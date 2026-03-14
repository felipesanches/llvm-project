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
#include "TLCS900BaseInfo.h"
#include "TLCS900FrameLowering.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/RegisterScavenging.h"
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

  // When using a frame pointer, XIZ and its sub-registers are reserved.
  const auto *TFI = static_cast<const TLCS900FrameLowering *>(
      MF.getSubtarget().getFrameLowering());
  if (TFI->hasFP(MF))
    markSuperRegs(Reserved, TLCS900::XIZ);

  return Reserved;
}

bool TLCS900RegisterInfo::eliminateFrameIndex(MachineBasicBlock::iterator II,
                                              int SPAdj,
                                              unsigned FIOperandNum,
                                              RegScavenger *RS) const {
  MachineInstr &MI = *II;
  MachineBasicBlock &MBB = *MI.getParent();
  MachineFunction &MF = *MBB.getParent();
  const MachineFrameInfo &MFI = MF.getFrameInfo();
  const TLCS900InstrInfo &TII =
      *static_cast<const TLCS900InstrInfo *>(Subtarget.getInstrInfo());

  const auto *TFI = static_cast<const TLCS900FrameLowering *>(
      MF.getSubtarget().getFrameLowering());
  bool HasFP = TFI->hasFP(MF);

  int FrameIndex = MI.getOperand(FIOperandNum).getIndex();
  int Offset;

  if (HasFP) {
    // FP-relative: XIZ = entry_SP - CSRSize - 4 (after CSR pushes and PUSH XIZ).
    // Objects are at entry_SP + ObjectOffset (ObjectOffset is negative).
    // So FP-relative offset = ObjectOffset + CSRSize + 4.
    uint64_t CSRSize = MFI.getCalleeSavedInfo().size() * 4;
    Offset = MFI.getObjectOffset(FrameIndex) + CSRSize + 4;
  } else {
    Offset = MFI.getObjectOffset(FrameIndex) + MFI.getStackSize();
  }
  Offset += MI.getOperand(FIOperandNum + 1).getImm();
  Offset += SPAdj;

  Register BaseReg = HasFP ? TLCS900::XIZ : TLCS900::XSP;

  // Check if offset fits in 8-bit signed displacement (-128..127).
  bool FitsInD8 = (Offset >= -128 && Offset <= 127);

  if (FitsInD8 || Offset == 0) {
    // Simple case: offset fits in d8 or is zero — direct encoding.
    MI.getOperand(FIOperandNum).ChangeToRegister(BaseReg, false);
    MI.getOperand(FIOperandNum + 1).ChangeToImmediate(Offset);
    return false;
  }

  // Offset exceeds d8 range. All memory formats (MemLoad/MemALU/MemStore/
  // MemLoadDst) support d16 via the SRI prefix encoding:
  //   Source memory: C3/D3/E3 (size-dependent)
  //   Destination memory: F3
  if (Offset >= -32768 && Offset <= 32767) {
    MI.getOperand(FIOperandNum).ChangeToRegister(BaseReg, false);
    MI.getOperand(FIOperandNum + 1).ChangeToImmediate(Offset);
    return false;
  }

  // Offset exceeds d16 range. Split into address computation +
  // register-indirect access.
  assert(RS && "Register scavenger required for large frame offsets");
  Register ScratchReg = RS->scavengeRegisterBackwards(
      TLCS900::GPRRegClass, II, /*RestoreAfter=*/false, SPAdj);
  if (!ScratchReg)
    report_fatal_error("TLCS900: unable to scavenge register for "
                       "large stack frame offset");

  DebugLoc DL = MI.getDebugLoc();

  if (Offset >= -32768 && Offset <= 32767) {
    // Fits in d16: use LDA with F3+d16 prefix.
    BuildMI(MBB, II, DL, TII.get(TLCS900::LDA32), ScratchReg)
        .addReg(BaseReg)
        .addImm(Offset);
  } else {
    // Exceeds d16: use LD + ADD to compute effective address.
    BuildMI(MBB, II, DL, TII.get(TLCS900::LD32rr), ScratchReg)
        .addReg(BaseReg);
    BuildMI(MBB, II, DL, TII.get(TLCS900::ADD32ri), ScratchReg)
        .addReg(ScratchReg)
        .addImm(Offset);
  }

  // Rewrite original instruction to use (ScratchReg + 0).
  MI.getOperand(FIOperandNum).ChangeToRegister(ScratchReg, false,
                                               /*isImp=*/false,
                                               /*isKill=*/true);
  MI.getOperand(FIOperandNum + 1).ChangeToImmediate(0);

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
  const auto *TFI = static_cast<const TLCS900FrameLowering *>(
      MF.getSubtarget().getFrameLowering());
  return TFI->hasFP(MF) ? TLCS900::XIZ : TLCS900::XSP;
}
