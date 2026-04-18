//===-- TLCS900FixLargeDisp.cpp - Fix large displacements for source memory --===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// TLCS-900/H memory addressing supports up to 16-bit signed displacements
// (-32768..32767) via the SRI prefix encoding (C3/D3/E3 for source memory,
// F3 for destination memory).
//
// eliminateFrameIndex already splits instructions with large frame offsets.
// However, large displacements can also arise from other sources (global
// address folding with LTO, inlined functions, etc.) that bypass
// eliminateFrameIndex.
//
// This pass runs post-register-allocation and catches any remaining
// instructions with out-of-range displacements (exceeding d16 range).
// Splits them into:
//   LD ScratchReg, BaseReg + ADD ScratchReg, Offset
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
  case TLCS900II::MemStore:
  case TLCS900II::MemLoadDst:
    // op0 = base_reg, op1 = displacement, op2 = src_reg (or dst_reg for LDA)
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
  case TLCS900II::MemStore:
  case TLCS900II::MemLoadDst:
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
    // All memory formats (MemLoad/MemALU/MemStore/MemLoadDst) support d16
    // range (-32768..32767) via the SRI prefix (C3/D3/E3/F3).
    // Only need fixing if displacement exceeds d16 range.
    SmallVector<MachineInstr *, 8> Worklist;
    for (MachineInstr &MI : MBB) {
      int DispIdx = getDispOperandIndex(MI);
      if (DispIdx < 0)
        continue;
      MachineOperand &DispOp = MI.getOperand(DispIdx);
      if (!DispOp.isImm())
        continue;
      int64_t Disp = DispOp.getImm();
      if (Disp < -32768 || Disp > 32767)
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

      if (Disp >= -32768 && Disp <= 32767) {
        // Displacement fits in d16: use LDA with F3+d16 prefix.
        BuildMI(MBB, MBBI, DL, TII->get(TLCS900::LDA32), ScratchReg)
            .addReg(BaseReg)
            .addImm(Disp);
      } else {
        // Displacement exceeds d16: use LD + ADD to compute address.
        BuildMI(MBB, MBBI, DL, TII->get(TLCS900::LD32rr), ScratchReg)
            .addReg(BaseReg);
        BuildMI(MBB, MBBI, DL, TII->get(TLCS900::ADD32ri), ScratchReg)
            .addReg(ScratchReg)
            .addImm(Disp);
      }

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
