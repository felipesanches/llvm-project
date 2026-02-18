//===-- TLCS900BranchShortening.cpp - Shorten branch instructions -----------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Replace long branch instructions (JP, JPcc) with shorter relative forms
// (JR/JRL, JRcc) when the target is within displacement range.
//
// ISel emits safe long-form branches:
//   JP target     -- 4 bytes (0x1C + 24-bit absolute address)
//   JPcc cc, tgt  -- 3 bytes (JRL cc, d16: 0x70+cc + 16-bit displacement)
//
// This pass shortens them to:
//   JR target     -- 2 bytes (0x68 + 8-bit signed displacement)
//   JRL target    -- 3 bytes (0x78 + 16-bit signed displacement)
//   JRcc cc, tgt  -- 2 bytes (0x60+cc + 8-bit signed displacement)
//
// The pass iterates until convergence since shortening one branch may bring
// other targets into range. Each iteration can only shrink (never grow)
// instruction sizes, guaranteeing monotone convergence.
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/CodeGen/MachineFunctionPass.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-branch-shortening"

namespace {

class TLCS900BranchShortening : public MachineFunctionPass {
public:
  static char ID;
  TLCS900BranchShortening() : MachineFunctionPass(ID) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  StringRef getPassName() const override {
    return "TLCS900 Branch Shortening";
  }
};

} // end anonymous namespace

char TLCS900BranchShortening::ID = 0;

bool TLCS900BranchShortening::runOnMachineFunction(MachineFunction &MF) {
  const auto *TII = MF.getSubtarget<TLCS900Subtarget>().getInstrInfo();
  bool Changed = false;
  bool MadeChange;

  do {
    MadeChange = false;

    // Compute block offsets from the start of the function.
    DenseMap<const MachineBasicBlock *, unsigned> BlockOffsets;
    unsigned Offset = 0;
    for (const auto &MBB : MF) {
      BlockOffsets[&MBB] = Offset;
      for (const auto &MI : MBB)
        Offset += MI.getDesc().getSize();
    }

    // Collect branches that can be shortened. We defer modifications to keep
    // offset computations consistent within a single scan.
    SmallVector<std::pair<MachineInstr *, unsigned>> Worklist;

    for (auto &MBB : MF) {
      unsigned InstOff = BlockOffsets[&MBB];
      for (auto &MI : MBB) {
        unsigned Opc = MI.getOpcode();

        if (Opc == TLCS900::JP) {
          // JP (4 bytes absolute) -> JR (2 bytes) or JRL (3 bytes).
          auto *Target = MI.getOperand(0).getMBB();
          unsigned TgtOff = BlockOffsets[Target];

          // Try JR first (shortest: 2 bytes, 8-bit signed displacement).
          int64_t DispJR = (int64_t)TgtOff - (int64_t)(InstOff + 2);
          if (isInt<8>(DispJR)) {
            Worklist.push_back({&MI, TLCS900::JR});
          } else {
            // Try JRL (3 bytes, 16-bit signed displacement).
            int64_t DispJRL = (int64_t)TgtOff - (int64_t)(InstOff + 3);
            if (isInt<16>(DispJRL))
              Worklist.push_back({&MI, TLCS900::JRL});
          }
        } else if (Opc == TLCS900::JPcc) {
          // JPcc (3 bytes, emitted as JRL cc) -> JRcc (2 bytes, JR cc).
          auto *Target = MI.getOperand(1).getMBB();
          unsigned TgtOff = BlockOffsets[Target];

          // JRcc: 2 bytes, 8-bit signed displacement.
          int64_t DispJR = (int64_t)TgtOff - (int64_t)(InstOff + 2);
          if (isInt<8>(DispJR))
            Worklist.push_back({&MI, TLCS900::JRcc});
        }

        InstOff += MI.getDesc().getSize();
      }
    }

    // Apply collected shortenings.
    for (auto &[MI, NewOpc] : Worklist) {
      MI->setDesc(TII->get(NewOpc));
      MadeChange = Changed = true;
    }
  } while (MadeChange);

  return Changed;
}

FunctionPass *llvm::createTLCS900BranchShorteningPass() {
  return new TLCS900BranchShortening();
}
