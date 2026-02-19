//===-- TLCS900ELFObjectWriter.cpp - TLCS900 ELF Writer -----------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/TLCS900FixupKinds.h"
#include "MCTargetDesc/TLCS900MCTargetDesc.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCValue.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

namespace {

class TLCS900ELFObjectWriter : public MCELFObjectTargetWriter {
public:
  TLCS900ELFObjectWriter(uint8_t OSABI);

  unsigned getRelocType(MCContext &Ctx, const MCValue &Target,
                        const MCFixup &Fixup, bool IsPCRel) const override;
};

} // end anonymous namespace

TLCS900ELFObjectWriter::TLCS900ELFObjectWriter(uint8_t OSABI)
    : MCELFObjectTargetWriter(/*Is64Bit=*/false, OSABI, ELF::EM_TLCS900,
                              /*HasRelocationAddend=*/true) {}

unsigned TLCS900ELFObjectWriter::getRelocType(MCContext &Ctx,
                                              const MCValue &Target,
                                              const MCFixup &Fixup,
                                              bool IsPCRel) const {
  unsigned Kind = Fixup.getKind();

  switch (Kind) {
  default:
    llvm_unreachable("Unimplemented fixup kind");
  case FK_Data_4:
    return IsPCRel ? ELF::R_TLCS900_PC24 : ELF::R_TLCS900_32;
  case FK_Data_2:
    return IsPCRel ? ELF::R_TLCS900_PC16 : ELF::R_TLCS900_LO16;
  case FK_Data_1:
    return ELF::R_TLCS900_NONE;
  case TLCS900::fixup_tlcs900_24:
    return ELF::R_TLCS900_24;
  case TLCS900::fixup_tlcs900_rel8:
    return ELF::R_TLCS900_PC16;
  case TLCS900::fixup_tlcs900_rel16:
    return ELF::R_TLCS900_PC16;
  case TLCS900::fixup_tlcs900_disp8:
    return ELF::R_TLCS900_NONE;
  case TLCS900::fixup_tlcs900_disp16:
    return ELF::R_TLCS900_LO16;
  }
}

std::unique_ptr<MCObjectTargetWriter>
llvm::createTLCS900ELFObjectWriter(uint8_t OSABI) {
  return std::make_unique<TLCS900ELFObjectWriter>(OSABI);
}
