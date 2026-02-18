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

/// Calculate the size of callee-saved register area (each GPR is 4 bytes).
static uint64_t getCSRSize(const MachineFrameInfo &MFI) {
  return MFI.getCalleeSavedInfo().size() * 4;
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

  // Local frame size = total stack size minus callee-saved register area
  // (PUSH instructions already allocated space for callee-saved registers)
  uint64_t StackSize = MFI.getStackSize() - getCSRSize(MFI);
  if (StackSize == 0)
    return;

  // Skip past PUSH instructions (marked FrameSetup)
  MachineBasicBlock::iterator MBBI = MBB.begin();
  while (MBBI != MBB.end() && MBBI->getFlag(MachineInstr::FrameSetup))
    ++MBBI;

  DebugLoc DL = MBBI != MBB.end() ? MBBI->getDebugLoc() : DebugLoc();

  // SUB XSP, StackSize (for local frame only)
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

  uint64_t StackSize = MFI.getStackSize() - getCSRSize(MFI);
  if (StackSize == 0)
    return;

  // Find insertion point: before POP instructions (marked FrameDestroy)
  MachineBasicBlock::iterator MBBI = MBB.getLastNonDebugInstr();
  while (MBBI != MBB.begin()) {
    MachineBasicBlock::iterator Prev = std::prev(MBBI);
    if (!Prev->getFlag(MachineInstr::FrameDestroy))
      break;
    MBBI = Prev;
  }

  DebugLoc DL = MBBI->getDebugLoc();

  // ADD XSP, StackSize (before POP instructions)
  BuildMI(MBB, MBBI, DL, TII.get(TLCS900::ADD32ri), TLCS900::XSP)
      .addReg(TLCS900::XSP)
      .addImm(StackSize)
      .setMIFlag(MachineInstr::FrameDestroy);
}

bool TLCS900FrameLowering::spillCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    ArrayRef<CalleeSavedInfo> CSI, const TargetRegisterInfo *TRI) const {
  if (CSI.empty())
    return false;

  const TargetInstrInfo &TII = *STI.getInstrInfo();
  DebugLoc DL = MI != MBB.end() ? MI->getDebugLoc() : DebugLoc();

  for (const CalleeSavedInfo &I : CSI) {
    Register Reg = I.getReg();
    BuildMI(MBB, MI, DL, TII.get(TLCS900::PUSH32))
        .addReg(Reg, RegState::Kill)
        .setMIFlag(MachineInstr::FrameSetup);
  }
  return true;
}

bool TLCS900FrameLowering::restoreCalleeSavedRegisters(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator MI,
    MutableArrayRef<CalleeSavedInfo> CSI,
    const TargetRegisterInfo *TRI) const {
  if (CSI.empty())
    return false;

  const TargetInstrInfo &TII = *STI.getInstrInfo();
  DebugLoc DL = MI != MBB.end() ? MI->getDebugLoc() : DebugLoc();

  // Restore in reverse order (POP is LIFO)
  for (auto I = CSI.rbegin(), E = CSI.rend(); I != E; ++I) {
    Register Reg = I->getReg();
    BuildMI(MBB, MI, DL, TII.get(TLCS900::POP32), Reg)
        .setMIFlag(MachineInstr::FrameDestroy);
  }
  return true;
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
