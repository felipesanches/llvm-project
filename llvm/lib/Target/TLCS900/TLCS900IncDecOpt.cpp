//===-- TLCS900IncDecOpt.cpp - INC/DEC and small constant peephole ---------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Peephole optimization pass that replaces:
//
//   1. ADD32ri Reg, N  (6 bytes) →  INC32 Reg, N  (2 bytes)  where 1 <= N <= 8
//      SUB32ri Reg, N  (6 bytes) →  DEC32 Reg, N  (2 bytes)  where 1 <= N <= 8
//      Only when SR (status register) is dead after the instruction, because
//      INC/DEC do not affect the carry flag on hardware.
//
//   2. LD32ri Reg, N   (5 bytes) →  LD32ri_small Reg, N  (2 bytes) where 0 <= N <= 7
//      Always safe (no flags involved).
//
//   3. CP32ri Reg, N   (6 bytes) →  CP32_small Reg, N  (2 bytes) where 0 <= N <= 7
//      Always safe (both set all flags identically).
//
// This pass runs before DJNZ/BranchShortening since it changes instruction
// sizes.
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-incdec-opt"

namespace {

class TLCS900IncDecOpt : public MachineFunctionPass {
public:
  static char ID;
  TLCS900IncDecOpt() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 INC/DEC and Small Constant Peephole Optimization";
  }
};

} // end anonymous namespace

char TLCS900IncDecOpt::ID = 0;

bool TLCS900IncDecOpt::runOnMachineFunction(MachineFunction &MF) {
  const auto &STI = MF.getSubtarget<TLCS900Subtarget>();
  const auto *TII = STI.getInstrInfo();
  const auto *TRI = STI.getRegisterInfo();
  bool Changed = false;

  for (auto &MBB : MF) {
    for (auto I = MBB.begin(), E = MBB.end(); I != E;) {
      MachineInstr &MI = *I++;

      unsigned Opc = MI.getOpcode();

      // --- Optimization 1: ADD32ri/SUB32ri → INC32/DEC32 ---
      if (Opc == TLCS900::ADD32ri || Opc == TLCS900::SUB32ri) {
        // INC/DEC don't set carry, so only safe when SR is dead.
        if (!MI.registerDefIsDead(TLCS900::SR, TRI))
          continue;
        if (!MI.getOperand(2).isImm())
          continue;


        int64_t Imm = MI.getOperand(2).getImm();
        if (Imm < 1 || Imm > 8)
          continue;

        Register DstReg = MI.getOperand(0).getReg();
        unsigned NewOpc =
            (Opc == TLCS900::ADD32ri) ? TLCS900::INC32 : TLCS900::DEC32;

        BuildMI(MBB, MI, MI.getDebugLoc(), TII->get(NewOpc), DstReg)
            .addReg(DstReg)
            .addImm(Imm);

        MI.eraseFromParent();
        Changed = true;
        continue;
      }

      // --- Optimization 2: LD32ri → LD32ri_small ---
      if (Opc == TLCS900::LD32ri) {
        if (!MI.getOperand(1).isImm())
          continue;

        int64_t Imm = MI.getOperand(1).getImm();
        // LD32ri_small encodes immediates 0-7 in 2 bytes (vs 5 for LD32ri).
        if (Imm < 0 || Imm > 7)
          continue;

        Register DstReg = MI.getOperand(0).getReg();

        BuildMI(MBB, MI, MI.getDebugLoc(), TII->get(TLCS900::LD32ri_small),
                DstReg)
            .addImm(Imm);

        MI.eraseFromParent();
        Changed = true;
        continue;
      }

      // --- Optimization 3: CP32ri → CP32_small ---
      if (Opc == TLCS900::CP32ri) {
        if (!MI.getOperand(1).isImm())
          continue;

        int64_t Imm = MI.getOperand(1).getImm();
        if (Imm < 0 || Imm > 7)
          continue;

        Register SrcReg = MI.getOperand(0).getReg();
        bool IsKill = MI.getOperand(0).isKill();

        BuildMI(MBB, MI, MI.getDebugLoc(), TII->get(TLCS900::CP32_small))
            .addReg(SrcReg, getKillRegState(IsKill))
            .addImm(Imm);

        MI.eraseFromParent();
        Changed = true;
        continue;
      }
    }
  }

  return Changed;
}

FunctionPass *llvm::createTLCS900IncDecOptPass() {
  return new TLCS900IncDecOpt();
}
