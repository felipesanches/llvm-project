//===-- TLCS900BitTestOpt.cpp - BIT test peephole optimization ------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Replace the sequence:
//   AND32ri $reg, $reg, (1 << N)   ; 6 bytes — mask to single bit
//   CP32ri  $reg, 0                ; 6 bytes — compare with zero
//   JPcc    Z/NZ, target           ; 2-3 bytes — branch on result
// with:
//   BIT16   N, SubReg              ; 3 bytes — test bit, set Z flag
//   JPcc    Z/NZ, target           ; 2-3 bytes — unchanged
//
// Saves 9 bytes per pattern. BIT sets Z=1 if bit is 0, Z=0 if bit is 1 —
// same semantics as AND+CP.
//
// Safety checks:
// - CP32ri must compare with 0
// - JPcc condition must be Z or NZ (only uses Z flag)
// - CP32ri's register operand must have kill flag (AND result not needed later)
// - AND32ri immediate must be power-of-2 with bit < 16 (D8 prefix constraint)
// - AND32ri must define the same register that CP reads
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-bit-test-opt"

namespace {

class TLCS900BitTestOpt : public MachineFunctionPass {
public:
  static char ID;
  TLCS900BitTestOpt() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 BIT Test Peephole Optimization";
  }
};

} // end anonymous namespace

char TLCS900BitTestOpt::ID = 0;

bool TLCS900BitTestOpt::runOnMachineFunction(MachineFunction &MF) {
  const auto &STI = MF.getSubtarget<TLCS900Subtarget>();
  const auto *TII = STI.getInstrInfo();
  const auto *TRI = STI.getRegisterInfo();
  bool Changed = false;

  for (auto &MBB : MF) {
    // Look at the first terminator.
    auto TermI = MBB.getFirstTerminator();
    if (TermI == MBB.end())
      continue;

    // Match: JPcc Z/NZ, target
    if (TermI->getOpcode() != TLCS900::JPcc)
      continue;
    unsigned CC = TermI->getOperand(0).getImm();
    if (CC != TLCS900CC::COND_Z && CC != TLCS900CC::COND_NZ)
      continue;

    // Walk backward past debug instructions to find CP32ri.
    auto CmpI = TermI;
    if (CmpI == MBB.begin())
      continue;
    --CmpI;
    while (CmpI != MBB.begin() && CmpI->isDebugInstr())
      --CmpI;
    if (CmpI->isDebugInstr())
      continue;

    // Match: CP32ri $reg, 0
    if (CmpI->getOpcode() != TLCS900::CP32ri &&
        CmpI->getOpcode() != TLCS900::CP32_small)
      continue;
    if (CmpI->getOperand(1).getImm() != 0)
      continue;
    Register CmpReg = CmpI->getOperand(0).getReg();

    // CP must kill the register (AND result not used later).
    if (!CmpI->getOperand(0).isKill())
      continue;

    // Walk backward past debug instructions to find AND32ri.
    auto AndI = CmpI;
    if (AndI == MBB.begin())
      continue;
    --AndI;
    while (AndI != MBB.begin() && AndI->isDebugInstr())
      --AndI;
    if (AndI->isDebugInstr())
      continue;

    // Match: AND32ri $reg, $reg, pow2_imm
    if (AndI->getOpcode() != TLCS900::AND32ri)
      continue;
    Register AndDstReg = AndI->getOperand(0).getReg();
    if (AndDstReg != CmpReg)
      continue;

    int64_t Imm = AndI->getOperand(2).getImm();
    uint32_t UImm = static_cast<uint32_t>(Imm);
    if (!isPowerOf2_32(UImm))
      continue;
    unsigned BitNum = llvm::countr_zero(UImm);
    if (BitNum >= 16)
      continue;

    // Get the 16-bit sub-register.
    Register SubReg = TRI->getSubReg(AndDstReg, TLCS900::sub_16bit);
    if (!SubReg)
      continue;

    // Build BIT16: (outs), (ins i32imm:$bit, GR16:$rs)
    BuildMI(MBB, AndI, AndI->getDebugLoc(), TII->get(TLCS900::BIT16))
        .addImm(BitNum)
        .addReg(SubReg);

    // Remove old instructions.
    CmpI->eraseFromParent();
    AndI->eraseFromParent();

    Changed = true;
  }

  return Changed;
}

FunctionPass *llvm::createTLCS900BitTestOptPass() {
  return new TLCS900BitTestOpt();
}
