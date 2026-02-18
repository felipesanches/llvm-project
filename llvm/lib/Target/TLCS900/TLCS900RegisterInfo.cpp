//===-- TLCS900RegisterInfo.cpp - TLCS900 Register Information ----------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file contains the TLCS900 implementation of the TargetRegisterInfo class.
//
//===----------------------------------------------------------------------===//

#include "TLCS900RegisterInfo.h"
#include "TLCS900Subtarget.h"
#include "llvm/Support/Debug.h"

#define GET_REGINFO_TARGET_DESC
#include "TLCS900GenRegisterInfo.inc"

#define DEBUG_TYPE "tlcs900-reginfo"

using namespace llvm;

TLCS900RegisterInfo::TLCS900RegisterInfo(const TLCS900Subtarget &ST)
  : TLCS900GenRegisterInfo(/*RA=*/0, /*DwarfFlavour=*/0, /*EHFlavor=*/0,
                         /*PC=*/0), Subtarget(ST) {}

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

  markSuperRegs(Reserved, TLCS900::XSP); // sp

  return Reserved;
}

bool TLCS900RegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                              int SPAdj,
                                              unsigned FIOperandNum,
                                              RegScavenger *RS) const {
  llvm_unreachable("Unsupported eliminateFrameIndex");
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

