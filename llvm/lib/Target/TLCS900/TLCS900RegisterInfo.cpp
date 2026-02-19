//===-- TLCS900RegisterInfo.cpp - TLCS900 Register Information ----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the TLCS900 implementation of the TargetRegisterInfo class.
//
//===----------------------------------------------------------------------===//

#include "TLCS900RegisterInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/Support/Debug.h"

#define GET_REGINFO_TARGET_DESC
#include "TLCS900GenRegisterInfo.inc"

#define DEBUG_TYPE "tlcs900-reginfo"

using namespace llvm;

TLCS900RegisterInfo::TLCS900RegisterInfo(const TLCS900Subtarget &ST)
  : TLCS900GenRegisterInfo(TLCS900::PC, /*DwarfFlavour=*/0, /*EHFlavor=*/0,
                         TLCS900::PC), Subtarget(ST) {}

const MCPhysReg *
TLCS900RegisterInfo::getCalleeSavedRegs(const MachineFunction *MF) const {
  return TLCS900_CalleeSavedRegs_SaveList;
}

const TargetRegisterClass *TLCS900RegisterInfo::intRegClass(unsigned Size) const {
  return &TLCS900::GPRRegClass;
}

const uint32_t *
TLCS900RegisterInfo::getCallPreservedMask(const MachineFunction &MF,
                                        CallingConv::ID) const {
  return TLCS900_CalleeSavedRegs_RegMask;
}

BitVector TLCS900RegisterInfo::getReservedRegs(const MachineFunction &MF) const {
  BitVector Reserved(getNumRegs());

  markSuperRegs(Reserved, TLCS900::XSP); // Stack pointer
  Reserved.set(TLCS900::SR);             // Status register (flags)
  Reserved.set(TLCS900::PC);             // Program counter (DWARF only)

  return Reserved;
}

bool TLCS900RegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                              int SPAdj,
                                              unsigned FIOperandNum,
                                              RegScavenger *RS) const {
  MachineInstr &MI = *II;
  MachineFunction &MF = *MI.getParent()->getParent();
  const MachineFrameInfo &MFI = MF.getFrameInfo();

  int FrameIndex = MI.getOperand(FIOperandNum).getIndex();
  int Offset = MFI.getObjectOffset(FrameIndex) + MFI.getStackSize();
  Offset += MI.getOperand(FIOperandNum + 1).getImm();
  Offset += SPAdj;

  MI.getOperand(FIOperandNum).ChangeToRegister(TLCS900::XSP, false);
  MI.getOperand(FIOperandNum + 1).ChangeToImmediate(Offset);

  return false;
}

bool
TLCS900RegisterInfo::requiresRegisterScavenging(const MachineFunction &MF) const {
  return true;
}

bool
TLCS900RegisterInfo::requiresFrameIndexScavenging(
                                            const MachineFunction &MF) const {
  return true;
}

bool
TLCS900RegisterInfo::requiresFrameIndexReplacementScavenging(
                                            const MachineFunction &MF) const {
  return true;
}

bool
TLCS900RegisterInfo::trackLivenessAfterRegAlloc(const MachineFunction &MF) const {
  return true;
}

Register TLCS900RegisterInfo::getFrameRegister(const MachineFunction &MF) const {
  return TLCS900::XSP;
}
