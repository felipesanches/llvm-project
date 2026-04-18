//===-- TLCS900BitManipOpt.cpp - Bit manipulation peephole optimization ----===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Replace 6-byte OR32ri/AND32ri/XOR32ri with power-of-2 immediates (bits 0-15)
// with 3-byte SET16/RES16/CHG16 on the 16-bit sub-register.
//
//   OR32ri  Reg, (1 << N)   →  SET16 N, SubReg   (N < 16)
//   AND32ri Reg, ~(1 << N)  →  RES16 N, SubReg   (N < 16)
//   XOR32ri Reg, (1 << N)   →  CHG16 N, SubReg   (N < 16)
//
// SET/RES/CHG do not affect flags (SR), so the optimization is only safe
// when SR is dead after the instruction.
//
// This pass runs before DJNZ/RedundantCmpElim/BranchShortening since it
// changes instruction sizes.
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-bitmanip-opt"

namespace {

class TLCS900BitManipOpt : public MachineFunctionPass {
public:
  static char ID;
  TLCS900BitManipOpt() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 Bit Manipulation Peephole Optimization";
  }
};

} // end anonymous namespace

char TLCS900BitManipOpt::ID = 0;

bool TLCS900BitManipOpt::runOnMachineFunction(MachineFunction &MF) {
  const auto &STI = MF.getSubtarget<TLCS900Subtarget>();
  const auto *TII = STI.getInstrInfo();
  const auto *TRI = STI.getRegisterInfo();
  bool Changed = false;

  for (auto &MBB : MF) {
    for (auto I = MBB.begin(), E = MBB.end(); I != E;) {
      MachineInstr &MI = *I++;

      unsigned Opc = MI.getOpcode();
      unsigned NewOpc;
      bool IsAnd = false;

      switch (Opc) {
      default:
        continue;
      case TLCS900::OR32ri:
        NewOpc = TLCS900::SET16;
        break;
      case TLCS900::AND32ri:
        NewOpc = TLCS900::RES16;
        IsAnd = true;
        break;
      case TLCS900::XOR32ri:
        NewOpc = TLCS900::CHG16;
        break;
      }

      // SET/RES/CHG do not set flags. Skip if SR is live after this instruction.
      if (!MI.registerDefIsDead(TLCS900::SR, TRI))
        continue;

      // Extract the immediate operand.
      int64_t Imm = MI.getOperand(2).getImm();
      uint32_t UImm = static_cast<uint32_t>(Imm);

      // For AND, check that ~imm is a power of 2.
      // For OR/XOR, check that imm is a power of 2.
      unsigned BitNum;
      if (IsAnd) {
        uint32_t NotImm = ~UImm;
        if (!isPowerOf2_32(NotImm))
          continue;
        BitNum = llvm::countr_zero(NotImm);
      } else {
        if (!isPowerOf2_32(UImm))
          continue;
        BitNum = llvm::countr_zero(UImm);
      }

      // Only handle bits 0-15 (D8 prefix = 16-bit register).
      if (BitNum >= 16)
        continue;

      // Get the 16-bit sub-register.
      Register DstReg = MI.getOperand(0).getReg();
      Register SubReg = TRI->getSubReg(DstReg, TLCS900::sub_16bit);
      if (!SubReg)
        continue;

      // Build the replacement instruction.
      // SET16/RES16/CHG16: (outs GR16:$rd), (ins i32imm:$bit, GR16:$rs1)
      // with $rd = $rs1 constraint.
      BuildMI(MBB, MI, MI.getDebugLoc(), TII->get(NewOpc), SubReg)
          .addImm(BitNum)
          .addReg(SubReg)
          .addReg(DstReg, RegState::ImplicitDefine);

      MI.eraseFromParent();
      Changed = true;
    }
  }

  return Changed;
}

FunctionPass *llvm::createTLCS900BitManipOptPass() {
  return new TLCS900BitManipOpt();
}
