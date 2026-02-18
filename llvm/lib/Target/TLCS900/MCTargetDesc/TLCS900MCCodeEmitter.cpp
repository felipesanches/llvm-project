//===-- TLCS900MCCodeEmitter.cpp - Convert TLCS900 Code to Machine Code -------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the TLCS900MCCodeEmitter class.
//
// TLCS-900/H2 uses variable-length instructions (1-7 bytes) with a complex
// prefix-based encoding scheme. This is a skeleton implementation that emits
// placeholder bytes. Real encoding will be implemented once instruction format
// classes in the TableGen files include encoding bits.
//
//===----------------------------------------------------------------------===//

#include "TLCS900MCCodeEmitter.h"
#include "TLCS900MCTargetDesc.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-mccodeemitter"

void TLCS900MCCodeEmitter::encodeInstruction(
    const MCInst &MI, SmallVectorImpl<char> &CB,
    SmallVectorImpl<MCFixup> &Fixups, const MCSubtargetInfo &STI) const {
  const MCInstrDesc &Desc = MCII.get(MI.getOpcode());

  // Pseudos and codegen-only instructions don't get encoded.
  if (Desc.isPseudo())
    return;

  // Skeleton: emit a NOP placeholder (0x00) for each instruction.
  // TLCS-900 NOP is 0x00, a single byte. Real encoding TBD.
  //
  // This allows the MC infrastructure to function (assembly → object file)
  // while we implement proper encoding incrementally.
  CB.push_back(0x00);
}

unsigned TLCS900MCCodeEmitter::getMachineOpValue(
    const MCInst &MI, const MCOperand &MO, SmallVectorImpl<MCFixup> &Fixups,
    const MCSubtargetInfo &STI) const {
  if (MO.isReg())
    return Ctx.getRegisterInfo()->getEncodingValue(MO.getReg());
  if (MO.isImm())
    return static_cast<unsigned>(MO.getImm());

  llvm_unreachable("Unhandled expression!");
  return 0;
}

MCCodeEmitter *llvm::createTLCS900MCCodeEmitter(const MCInstrInfo &MCII,
                                                MCContext &Ctx) {
  return new TLCS900MCCodeEmitter(MCII, Ctx);
}
