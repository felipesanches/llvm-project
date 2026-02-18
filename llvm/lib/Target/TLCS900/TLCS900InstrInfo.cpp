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
