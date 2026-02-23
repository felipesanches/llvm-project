//===-- TLCS900RedundantCmpElim.cpp - Remove redundant CP rd, 0 ------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Remove redundant "CP rd, 0" instructions when the preceding instruction
// already set the needed flags on the same register.
//
// Pattern:
//   <flag-setting-op> rd, ...   ; defines rd and SR
//   CP32ri rd, 0                ; redundant: Z/S already correct from above
//   JPcc {Z,NZ,MI,PL}, target  ; only uses Z or S flags
//
// After:
//   <flag-setting-op> rd, ...   ; defines rd and SR
//   JPcc {Z,NZ,MI,PL}, target  ; uses flags from the arithmetic op
//
// This is safe because all TLCS-900 arithmetic/logic instructions set the
// Z flag based on whether the result is zero, and the S flag based on the
// sign bit — exactly what "CP rd, 0" would produce for these conditions.
//
// This pass runs after DJNZ optimization (which handles the specific
// DEC+CP+JPcc NZ -> DJNZ case) and before branch shortening.
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFunctionPass.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-redundant-cmp-elim"

namespace {

class TLCS900RedundantCmpElim : public MachineFunctionPass {
public:
  static char ID;
  TLCS900RedundantCmpElim() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 Redundant Compare Elimination";
  }
};

} // end anonymous namespace

char TLCS900RedundantCmpElim::ID = 0;

/// Return true if the condition code only depends on Z and/or S flags,
/// which are set identically by arithmetic/logic ops and "CP rd, 0".
static bool isZeroCompareCondition(unsigned CC) {
  switch (CC) {
  case TLCS900CC::COND_Z:   // Zero (equal)
  case TLCS900CC::COND_NZ:  // Not zero (not equal)
  case TLCS900CC::COND_MI:  // Minus (sign bit set)
  case TLCS900CC::COND_PL:  // Plus (sign bit clear)
    return true;
  default:
    return false;
  }
}

/// Return true if the instruction sets flags (SR) based on its result
/// register (operand 0). This covers all two-address arithmetic/logic/shift
/// instructions and unary ops like NEG, CPL, INC, DEC.
static bool isFlagSettingDef(const MachineInstr &MI) {
  switch (MI.getOpcode()) {
  case TLCS900::ADD32rr:
  case TLCS900::ADD32ri:
  case TLCS900::SUB32rr:
  case TLCS900::SUB32ri:
  case TLCS900::ADC32rr:
  case TLCS900::ADC32ri:
  case TLCS900::SBC32rr:
  case TLCS900::SBC32ri:
  case TLCS900::AND32rr:
  case TLCS900::AND32ri:
  case TLCS900::OR32rr:
  case TLCS900::OR32ri:
  case TLCS900::XOR32rr:
  case TLCS900::XOR32ri:
  case TLCS900::INC32:
  case TLCS900::DEC32:
  case TLCS900::NEG32:
  case TLCS900::CPL32:
  case TLCS900::SLA32rr:
  case TLCS900::SLA32ri:
  case TLCS900::SRA32rr:
  case TLCS900::SRA32ri:
  case TLCS900::SRL32rr:
  case TLCS900::SRL32ri:
  case TLCS900::EXTS32:
  case TLCS900::EXTZ32:
    return true;
  default:
    return false;
  }
}

bool TLCS900RedundantCmpElim::runOnMachineFunction(MachineFunction &MF) {
  bool Changed = false;

  for (auto &MBB : MF) {
    // Find the first terminator (branch instruction).
    auto TermI = MBB.getFirstTerminator();
    if (TermI == MBB.end())
      continue;

    // Match: JPcc with Z/NZ/MI/PL condition.
    if (TermI->getOpcode() != TLCS900::JPcc)
      continue;
    unsigned CC = TermI->getOperand(0).getImm();
    if (!isZeroCompareCondition(CC))
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

    // Match: CP32ri reg, 0
    if (CmpI->getOpcode() != TLCS900::CP32ri &&
        CmpI->getOpcode() != TLCS900::CP32_small)
      continue;
    if (CmpI->getOperand(1).getImm() != 0)
      continue;
    Register CmpReg = CmpI->getOperand(0).getReg();

    // Walk backward past debug instructions to find the flag-setting def.
    auto DefI = CmpI;
    if (DefI == MBB.begin())
      continue;
    --DefI;
    while (DefI != MBB.begin() && DefI->isDebugInstr())
      --DefI;
    if (DefI->isDebugInstr())
      continue;

    // Check: must be a flag-setting instruction that defines the same reg.
    if (!isFlagSettingDef(*DefI))
      continue;
    if (DefI->getOperand(0).getReg() != CmpReg)
      continue;

    // Safe to remove the redundant compare.
    CmpI->eraseFromParent();
    Changed = true;
  }

  return Changed;
}

FunctionPass *llvm::createTLCS900RedundantCmpElimPass() {
  return new TLCS900RedundantCmpElim();
}
