//===-- TLCS900AsmBackend.cpp - TLCS900 Asm Backend -------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the TLCS900AsmBackend class.
//
//===----------------------------------------------------------------------===//

#include "TLCS900AsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCFixupKindInfo.h"
#include "llvm/MC/MCValue.h"

using namespace llvm;

std::unique_ptr<MCObjectTargetWriter>
TLCS900AsmBackend::createObjectTargetWriter() const {
  return createTLCS900ELFObjectWriter(
      MCELFObjectTargetWriter::getOSABI(OSType));
}

void TLCS900AsmBackend::applyFixup(const MCAssembler &Asm,
                                   const MCFixup &Fixup, const MCValue &Target,
                                   MutableArrayRef<char> Data, uint64_t Value,
                                   bool IsResolved,
                                   const MCSubtargetInfo *STI) const {
  unsigned Kind = Fixup.getKind();
  if (Kind >= FirstLiteralRelocationKind)
    return;

  unsigned Offset = Fixup.getOffset();
  unsigned NumBytes = (getFixupKindInfo(Fixup.getKind()).TargetSize + 7) / 8;

  assert(Offset + NumBytes <= Data.size() && "Invalid fixup offset!");

  // For each byte of the fragment that the fixup touches, mask in the bits
  // from the fixup value.
  for (unsigned i = 0; i < NumBytes; ++i) {
    Data[Offset + i] |= static_cast<uint8_t>((Value >> (i * 8)) & 0xff);
  }
}

const MCFixupKindInfo &
TLCS900AsmBackend::getFixupKindInfo(MCFixupKind Kind) const {
  // Use the default fixup kinds (FK_Data_1, FK_Data_2, FK_Data_4, etc.)
  // No target-specific fixups defined yet.
  return MCAsmBackend::getFixupKindInfo(Kind);
}

bool TLCS900AsmBackend::writeNopData(raw_ostream &OS, uint64_t Count,
                                     const MCSubtargetInfo *STI) const {
  // TLCS-900 NOP is a single byte: 0x00
  for (uint64_t i = 0; i < Count; ++i)
    OS.write('\0');
  return true;
}

MCAsmBackend *llvm::createTLCS900AsmBackend(const Target &T,
                                            const MCSubtargetInfo &STI,
                                            const MCRegisterInfo &MRI,
                                            const MCTargetOptions &Options) {
  return new TLCS900AsmBackend(STI.getTargetTriple().getOS());
}
