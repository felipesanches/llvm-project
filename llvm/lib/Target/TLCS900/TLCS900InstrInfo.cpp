//===-- TLCS900InstrInfo.cpp - TLCS900 Instruction Information ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the TLCS900 implementation of the TargetInstrInfo class.
//
//===----------------------------------------------------------------------===//

#include "TLCS900InstrInfo.h"

#include "TLCS900TargetMachine.h"
#include "TLCS900MachineFunction.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-instrinfo"

#define GET_INSTRINFO_CTOR_DTOR
#include "TLCS900GenInstrInfo.inc"

TLCS900InstrInfo::TLCS900InstrInfo(const TLCS900Subtarget &STI)
    : TLCS900GenInstrInfo(TLCS900::ADJCALLSTACKDOWN, TLCS900::ADJCALLSTACKUP),
      Subtarget(STI)
{
}

void TLCS900InstrInfo::copyPhysReg(MachineBasicBlock &MBB,
                                   MachineBasicBlock::iterator MBBI,
                                   const DebugLoc &DL, Register DstReg,
                                   Register SrcReg, bool KillSrc,
                                   bool RenamableDest,
                                   bool RenamableSrc) const {
  if (TLCS900::GPRRegClass.contains(DstReg, SrcReg)) {
    BuildMI(MBB, MBBI, DL, get(TLCS900::LD32rr), DstReg)
        .addReg(SrcReg, getKillRegState(KillSrc));
    return;
  }

  llvm_unreachable("Impossible reg-to-reg copy");
}

void TLCS900InstrInfo::storeRegToStackSlot(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI, Register SrcReg,
    bool isKill, int FrameIndex, const TargetRegisterClass *RC,
    const TargetRegisterInfo *TRI, Register VReg,
    MachineInstr::MIFlag Flags) const {
  DebugLoc DL;
  if (MI != MBB.end())
    DL = MI->getDebugLoc();

  if (TLCS900::GPRRegClass.hasSubClassEq(RC)) {
    BuildMI(MBB, MI, DL, get(TLCS900::LD32mr))
        .addFrameIndex(FrameIndex)
        .addImm(0)
        .addReg(SrcReg, getKillRegState(isKill))
        .setMIFlags(Flags);
  } else {
    llvm_unreachable("Cannot store this register to stack slot");
  }
}

void TLCS900InstrInfo::loadRegFromStackSlot(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI, Register DestReg,
    int FrameIndex, const TargetRegisterClass *RC,
    const TargetRegisterInfo *TRI, Register VReg,
    MachineInstr::MIFlag Flags) const {
  DebugLoc DL;
  if (MI != MBB.end())
    DL = MI->getDebugLoc();

  if (TLCS900::GPRRegClass.hasSubClassEq(RC)) {
    BuildMI(MBB, MI, DL, get(TLCS900::LD32rm), DestReg)
        .addFrameIndex(FrameIndex)
        .addImm(0)
        .setMIFlags(Flags);
  } else {
    llvm_unreachable("Cannot load this register from stack slot");
  }
}

unsigned TLCS900InstrInfo::removeBranch(MachineBasicBlock &MBB,
                                        int *BytesRemoved) const {
  assert(!BytesRemoved && "code size not handled");

  MachineBasicBlock::iterator I = MBB.end();
  unsigned Count = 0;

  while (I != MBB.begin()) {
    --I;
    if (I->isDebugInstr())
      continue;
    if (I->getOpcode() != TLCS900::JP && I->getOpcode() != TLCS900::JPcc)
      break;
    I->eraseFromParent();
    I = MBB.end();
    ++Count;
  }

  return Count;
}

bool TLCS900InstrInfo::analyzeBranch(MachineBasicBlock &MBB,
                                     MachineBasicBlock *&TBB,
                                     MachineBasicBlock *&FBB,
                                     SmallVectorImpl<MachineOperand> &Cond,
                                     bool AllowModify) const {
  MachineBasicBlock::iterator I = MBB.end();

  while (I != MBB.begin()) {
    --I;
    if (I->isDebugInstr())
      continue;

    if (!isUnpredicatedTerminator(*I))
      break;

    if (!I->isBranch())
      return true;

    // Handle unconditional branches.
    if (I->getOpcode() == TLCS900::JP) {
      if (!AllowModify) {
        TBB = I->getOperand(0).getMBB();
        continue;
      }

      // Delete dead code after unconditional branch.
      MBB.erase(std::next(I), MBB.end());
      Cond.clear();
      FBB = nullptr;

      // Remove JP if it's a fallthrough.
      if (MBB.isLayoutSuccessor(I->getOperand(0).getMBB())) {
        TBB = nullptr;
        I->eraseFromParent();
        I = MBB.end();
        continue;
      }

      TBB = I->getOperand(0).getMBB();
      continue;
    }

    // Handle conditional branches.
    if (I->getOpcode() != TLCS900::JPcc)
      return true; // Unknown branch type.

    unsigned BranchCC = I->getOperand(0).getImm();

    if (Cond.empty()) {
      FBB = TBB;
      TBB = I->getOperand(1).getMBB();
      Cond.push_back(MachineOperand::CreateImm(BranchCC));
      continue;
    }

    // Multiple conditional branches — only handle if same target.
    if (TBB != I->getOperand(1).getMBB())
      return true;

    if ((unsigned)Cond[0].getImm() == BranchCC)
      continue;

    return true;
  }

  return false;
}

unsigned TLCS900InstrInfo::insertBranch(MachineBasicBlock &MBB,
                                        MachineBasicBlock *TBB,
                                        MachineBasicBlock *FBB,
                                        ArrayRef<MachineOperand> Cond,
                                        const DebugLoc &DL,
                                        int *BytesAdded) const {
  assert(TBB && "insertBranch must not be told to insert a fallthrough");
  assert((Cond.size() == 1 || Cond.size() == 0) &&
         "TLCS900 branch conditions have one component!");
  assert(!BytesAdded && "code size not handled");

  if (Cond.empty()) {
    // Unconditional branch.
    assert(!FBB && "Unconditional branch with multiple successors!");
    BuildMI(&MBB, DL, get(TLCS900::JP)).addMBB(TBB);
    return 1;
  }

  // Conditional branch.
  unsigned Count = 0;
  BuildMI(&MBB, DL, get(TLCS900::JPcc))
      .addImm(Cond[0].getImm())
      .addMBB(TBB);
  ++Count;

  if (FBB) {
    BuildMI(&MBB, DL, get(TLCS900::JP)).addMBB(FBB);
    ++Count;
  }
  return Count;
}

bool TLCS900InstrInfo::reverseBranchCondition(
    SmallVectorImpl<MachineOperand> &Cond) const {
  assert(Cond.size() == 1 && "Invalid branch condition!");

  unsigned CC = Cond[0].getImm();

  // TLCS-900 condition codes come in complementary pairs: CC ^ 8
  // F(0)↔T(8), LT(1)↔GE(9), LE(2)↔GT(10), ULE(3)↔UGT(11),
  // OV(4)↔NOV(12), MI(5)↔PL(13), Z(6)↔NZ(14), C(7)↔NC(15)
  Cond[0].setImm(CC ^ 8);
  return false;
}
