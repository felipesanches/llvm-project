//===-- TLCS900DJNZOpt.cpp - DJNZ peephole optimization --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Replace the sequence:
//   DEC32 rd, rd, 1
//   CP32ri rd, 0
//   JPcc NZ, target
// with:
//   DJNZ32 rd, rd, target
//
// DJNZ (Decrement and Jump if Not Zero) is a 3-byte instruction that
// combines decrement, compare-with-zero, and conditional branch. It
// replaces 11 bytes (DEC=2 + CP=6 + JPcc=3) with a single 3-byte
// instruction.
//
// DJNZ has an 8-bit signed displacement, so the target must be within
// +127/-128 bytes of the end of the DJNZ instruction. The pass verifies
// this constraint before applying the optimization.
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-djnz-opt"

namespace {

class TLCS900DJNZOpt : public MachineFunctionPass {
public:
  static char ID;
  TLCS900DJNZOpt() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 DJNZ Peephole Optimization";
  }
};

} // end anonymous namespace

char TLCS900DJNZOpt::ID = 0;

bool TLCS900DJNZOpt::runOnMachineFunction(MachineFunction &MF) {
  const auto *TII = MF.getSubtarget<TLCS900Subtarget>().getInstrInfo();
  bool Changed = false;

  // Precompute block offsets for displacement checking.
  DenseMap<const MachineBasicBlock *, unsigned> BlockOffsets;
  unsigned Offset = 0;
  for (const auto &MBB : MF) {
    BlockOffsets[&MBB] = Offset;
    for (const auto &MI : MBB)
      Offset += MI.getDesc().getSize();
  }

  for (auto &MBB : MF) {
    // Look at the first terminator.
    auto TermI = MBB.getFirstTerminator();
    if (TermI == MBB.end())
      continue;

    // Match: JPcc NZ, target
    if (TermI->getOpcode() != TLCS900::JPcc)
      continue;
    if (TermI->getOperand(0).getImm() != TLCS900CC::COND_NZ)
      continue;

    auto *Target = TermI->getOperand(1).getMBB();

    // Walk backward past debug instructions to find CP32ri.
    auto CmpI = TermI;
    if (CmpI == MBB.begin())
      continue;
    --CmpI;
    while (CmpI != MBB.begin() && CmpI->isDebugInstr())
      --CmpI;
    if (CmpI->isDebugInstr())
      continue;

    // Match: CP32ri reg, 0
    if (CmpI->getOpcode() != TLCS900::CP32ri)
      continue;
    if (CmpI->getOperand(1).getImm() != 0)
      continue;
    Register CmpReg = CmpI->getOperand(0).getReg();

    // Walk backward past debug instructions to find DEC32.
    auto DecI = CmpI;
    if (DecI == MBB.begin())
      continue;
    --DecI;
    while (DecI != MBB.begin() && DecI->isDebugInstr())
      --DecI;
    if (DecI->isDebugInstr())
      continue;

    // Match: DEC32 reg, reg, 1
    if (DecI->getOpcode() != TLCS900::DEC32)
      continue;
    if (DecI->getOperand(2).getImm() != 1)
      continue;
    Register DecReg = DecI->getOperand(0).getReg();
    if (DecReg != CmpReg)
      continue;

    // Check 8-bit displacement constraint.
    // DJNZ will be placed at DEC's position (3 bytes: prefix + 0x1C + d8).
    // Displacement = target_offset - (djnz_offset + 3).
    unsigned DJNZOff = BlockOffsets[&MBB];
    for (auto It = MBB.begin(); It != MBB.end(); ++It) {
      if (&*It == &*DecI)
        break;
      DJNZOff += It->getDesc().getSize();
    }
    unsigned TgtOff = BlockOffsets[Target];
    int64_t Disp = (int64_t)TgtOff - (int64_t)(DJNZOff + 3);
    if (!isInt<8>(Disp))
      continue; // Target too far for DJNZ's 8-bit displacement.

    // Build DJNZ32: (outs GPR:$rd), (ins GPR:$rs1, brtarget:$target)
    BuildMI(MBB, DecI, DecI->getDebugLoc(), TII->get(TLCS900::DJNZ32), DecReg)
        .addReg(DecReg)
        .addMBB(Target);

    // Remove old instructions.
    TermI->eraseFromParent();
    CmpI->eraseFromParent();
    DecI->eraseFromParent();

    Changed = true;
  }

  return Changed;
}

FunctionPass *llvm::createTLCS900DJNZOptPass() {
  return new TLCS900DJNZOpt();
}
