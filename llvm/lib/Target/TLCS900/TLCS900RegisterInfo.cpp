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

  int FrameIndex = MI.getOperand(FIOperandNum).getIndex();
  int Offset = MFI.getObjectOffset(FrameIndex) + MFI.getStackSize();
  Offset += MI.getOperand(FIOperandNum + 1).getImm();
  Offset += SPAdj;

  // Check if offset fits in 8-bit signed displacement (-128..127).
  bool FitsInD8 = (Offset >= -128 && Offset <= 127);

  if (FitsInD8 || Offset == 0) {
    // Simple case: offset fits in d8 or is zero — direct encoding.
    MI.getOperand(FIOperandNum).ChangeToRegister(TLCS900::XSP, false);
    MI.getOperand(FIOperandNum + 1).ChangeToImmediate(Offset);
    return false;
  }

  // Offset exceeds d8 range. Check the instruction's encoding format.
  // The F3 prefix (used for d16 displacements) dispatches to the B0/F0
  // destination memory opcode table. This is correct for MemStore and
  // MemLoadDst (LDA), but WRONG for MemLoad and MemALU which need the
  // A0 source memory opcode table.
  uint64_t TSFlags = MI.getDesc().TSFlags;
  unsigned Format = TLCS900II::getInstFormat(TSFlags);

  bool NeedsSrcMemTable = (Format == TLCS900II::MemLoad ||
                           Format == TLCS900II::MemALU);

  if (!NeedsSrcMemTable) {
    // MemStore/MemLoadDst: F3+d16 dispatches to B0/F0 table — correct.
    MI.getOperand(FIOperandNum).ChangeToRegister(TLCS900::XSP, false);
    MI.getOperand(FIOperandNum + 1).ChangeToImmediate(Offset);
    return false;
  }

  // MemLoad/MemALU with d16: must split into LDA + register-indirect.
  // Scavenge a scratch register for the effective address.
  assert(RS && "Register scavenger required for large frame offsets");
  Register ScratchReg = RS->scavengeRegisterBackwards(
      TLCS900::GPRRegClass, II, /*RestoreAfter=*/false, SPAdj);
  if (!ScratchReg)
    report_fatal_error("TLCS900: unable to scavenge register for "
                       "large stack frame offset");

  DebugLoc DL = MI.getDebugLoc();

  // Emit: LDA ScratchReg, (XSP + Offset)
  BuildMI(MBB, II, DL, TII.get(TLCS900::LDA32), ScratchReg)
      .addReg(TLCS900::XSP)
      .addImm(Offset);

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
  return TLCS900::XSP;
}
