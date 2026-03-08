//===-- TLCS900FixLargeDisp.cpp - Fix large displacements for source memory --===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// TLCS-900/H source memory addressing (loads, ALU-from-memory) only supports
// 8-bit signed displacements (-128..127) in the prefix encoding. Destination
// memory (stores, LDA) supports 16-bit displacements via the F3 prefix.
//
// eliminateFrameIndex already splits MemLoad/MemALU instructions that have
// large frame offsets into LDA + register-indirect sequences. However, large
// displacements can also arise from other sources (global array accesses,
// inlined functions, etc.) that bypass eliminateFrameIndex.
//
// This pass runs post-register-allocation and catches any remaining MemLoad
// or MemALU instructions with displacements outside the d8 range, splitting
// them into:
//   LDA ScratchReg, (BaseReg + LargeOffset)
//   <original_instr> ... (ScratchReg + 0) ...
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900BaseInfo.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/RegisterScavenging.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-fix-large-disp"

namespace {

class TLCS900FixLargeDisp : public MachineFunctionPass {
public:
  static char ID;
  TLCS900FixLargeDisp() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 Fix Large Displacements";
  }
};

} // end anonymous namespace

char TLCS900FixLargeDisp::ID = 0;

/// Get the displacement operand index for an instruction based on its format.
/// Returns -1 if the instruction doesn't have a displacement operand.
static int getDispOperandIndex(const MachineInstr &MI) {
  uint64_t TSFlags = MI.getDesc().TSFlags;
  unsigned Format = TLCS900II::getInstFormat(TSFlags);

  switch (Format) {
  case TLCS900II::MemLoad:
    // op0 = dst_reg, op1 = base_reg, op2 = displacement
    return 2;
  case TLCS900II::MemALU:
    // op0 = base_reg, op1 = displacement, op2 = src_reg_or_imm
    return 1;
  default:
    return -1;
  }
}

/// Get the base register operand index for an instruction based on its format.
static int getBaseRegOperandIndex(const MachineInstr &MI) {
  uint64_t TSFlags = MI.getDesc().TSFlags;
  unsigned Format = TLCS900II::getInstFormat(TSFlags);

  switch (Format) {
  case TLCS900II::MemLoad:
    return 1; // op1 = base_reg
  case TLCS900II::MemALU:
    return 0; // op0 = base_reg
  default:
    return -1;
  }
}

bool TLCS900FixLargeDisp::runOnMachineFunction(MachineFunction &MF) {
  const auto *TII = MF.getSubtarget<TLCS900Subtarget>().getInstrInfo();
  bool Changed = false;

  // We need the RegScavenger to find scratch registers.
  // Use backward scanning since scavengeRegisterBackwards requires it.
  RegScavenger RS;

  for (MachineBasicBlock &MBB : MF) {
    // First pass: collect instructions that need fixing.
    SmallVector<MachineInstr *, 8> Worklist;
    for (MachineInstr &MI : MBB) {
      int DispIdx = getDispOperandIndex(MI);
      if (DispIdx < 0)
        continue;
      MachineOperand &DispOp = MI.getOperand(DispIdx);
      if (!DispOp.isImm())
        continue;
      int64_t Disp = DispOp.getImm();
      if (Disp < -128 || Disp > 127)
        Worklist.push_back(&MI);
    }

    if (Worklist.empty())
      continue;

    // Second pass: fix each instruction using backward scavenging.
    RS.enterBasicBlockEnd(MBB);

    // Process worklist in reverse order (back to front) to match
    // the scavenger's backward traversal direction.
    for (MachineInstr *MI : llvm::reverse(Worklist)) {
      int DispIdx = getDispOperandIndex(*MI);
      int BaseIdx = getBaseRegOperandIndex(*MI);
      assert(DispIdx >= 0 && BaseIdx >= 0);

      MachineOperand &DispOp = MI->getOperand(DispIdx);
      int64_t Disp = DispOp.getImm();
      Register BaseReg = MI->getOperand(BaseIdx).getReg();

      LLVM_DEBUG(dbgs() << "TLCS900FixLargeDisp: splitting large disp "
                        << Disp << " in: " << *MI);

      // Position scavenger just before this instruction (so liveness
      // reflects what's available at MI's position).
      MachineBasicBlock::iterator MBBI(MI);
      RS.backward(MBBI);

      // Find an unused GPR register at this point.
      Register ScratchReg = RS.FindUnusedReg(&TLCS900::GPRRegClass);
      if (!ScratchReg) {
        // If no register is free, try scavenging (may spill).
        MachineBasicBlock::iterator BeginIt = MBB.begin();
        ScratchReg = RS.scavengeRegisterBackwards(
            TLCS900::GPRRegClass, BeginIt, /*RestoreAfter=*/false,
            /*SPAdj=*/0);
      }
      if (!ScratchReg) {
        report_fatal_error("TLCS900FixLargeDisp: unable to find register "
                           "for large displacement");
      }

      DebugLoc DL = MI->getDebugLoc();

      // Insert: LDA ScratchReg, (BaseReg + Disp)
      // LDA uses destination memory prefix (F3+d16), which supports d16.
      BuildMI(MBB, MBBI, DL, TII->get(TLCS900::LDA32), ScratchReg)
          .addReg(BaseReg)
          .addImm(Disp);

      // Rewrite the original instruction to use (ScratchReg + 0).
      MI->getOperand(BaseIdx).ChangeToRegister(ScratchReg, false,
                                               /*isImp=*/false,
                                               /*isKill=*/true);
      DispOp.setImm(0);

      Changed = true;
    }
  }

  return Changed;
}

FunctionPass *llvm::createTLCS900FixLargeDispPass() {
  return new TLCS900FixLargeDisp();
}
