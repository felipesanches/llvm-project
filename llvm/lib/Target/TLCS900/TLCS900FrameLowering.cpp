//===-- TLCS900FrameLowering.cpp - TLCS900 Frame Information ------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the TLCS900TargetFrameLowering class.
//
//===----------------------------------------------------------------------===//

#include "TLCS900FrameLowering.h"
#include "TLCS900InstrInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/RegisterScavenging.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

bool TLCS900FrameLowering::hasFPImpl(const MachineFunction &MF) const {
  return false;
}

MachineBasicBlock::iterator TLCS900FrameLowering::eliminateCallFramePseudoInstr(
                                        MachineFunction &MF,
                                        MachineBasicBlock &MBB,
                                        MachineBasicBlock::iterator I) const {
  return MBB.erase(I);
}

void TLCS900FrameLowering::emitPrologue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  const TLCS900InstrInfo &TII =
      *static_cast<const TLCS900InstrInfo *>(STI.getInstrInfo());

  uint64_t StackSize = MFI.getStackSize();
  if (StackSize == 0)
    return;

  MachineBasicBlock::iterator MBBI = MBB.begin();
  DebugLoc DL = MBBI != MBB.end() ? MBBI->getDebugLoc() : DebugLoc();

  // SUB XSP, StackSize
  BuildMI(MBB, MBBI, DL, TII.get(TLCS900::SUB32ri), TLCS900::XSP)
      .addReg(TLCS900::XSP)
      .addImm(StackSize)
      .setMIFlag(MachineInstr::FrameSetup);
}

void TLCS900FrameLowering::emitEpilogue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineFrameInfo &MFI = MF.getFrameInfo();
  const TLCS900InstrInfo &TII =
      *static_cast<const TLCS900InstrInfo *>(STI.getInstrInfo());

  uint64_t StackSize = MFI.getStackSize();
  if (StackSize == 0)
    return;

  MachineBasicBlock::iterator MBBI = MBB.getLastNonDebugInstr();
  DebugLoc DL = MBBI->getDebugLoc();

  // ADD XSP, StackSize (before the return instruction)
  BuildMI(MBB, MBBI, DL, TII.get(TLCS900::ADD32ri), TLCS900::XSP)
      .addReg(TLCS900::XSP)
      .addImm(StackSize)
      .setMIFlag(MachineInstr::FrameDestroy);
}

bool
TLCS900FrameLowering::hasReservedCallFrame(const MachineFunction &MF) const {
  return true;
}

void TLCS900FrameLowering::determineCalleeSaves(MachineFunction &MF,
                                              BitVector &SavedRegs,
                                              RegScavenger *RS) const {
  TargetFrameLowering::determineCalleeSaves(MF, SavedRegs, RS);
}
