//===- TLCS900.cpp --------------------------------------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// The TLCS-900 is a 32-bit CISC microcontroller architecture by Toshiba.
// It features a 24-bit address bus, variable-length instructions (1-7 bytes),
// and little-endian byte ordering. This file handles TLCS-900 specific
// relocation processing for LLD.
//
//===----------------------------------------------------------------------===//

#include "Symbols.h"
#include "Target.h"
#include "lld/Common/ErrorHandler.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/Support/Endian.h"

using namespace llvm;
using namespace llvm::object;
using namespace llvm::support::endian;
using namespace llvm::ELF;
using namespace lld;
using namespace lld::elf;

namespace {
class TLCS900 final : public TargetInfo {
public:
  TLCS900(Ctx &);
  RelExpr getRelExpr(RelType type, const Symbol &s,
                     const uint8_t *loc) const override;
  void relocate(uint8_t *loc, const Relocation &rel,
                uint64_t val) const override;
};
} // namespace

TLCS900::TLCS900(Ctx &ctx) : TargetInfo(ctx) {
  // NOP (0x00) padding for executable sections.
  trapInstr = {0x00, 0x00, 0x00, 0x00};
}

RelExpr TLCS900::getRelExpr(RelType type, const Symbol &s,
                             const uint8_t *loc) const {
  switch (type) {
  case R_TLCS900_PC16:
  case R_TLCS900_PC24:
    return R_PC;
  default:
    return R_ABS;
  }
}

void TLCS900::relocate(uint8_t *loc, const Relocation &rel,
                        uint64_t val) const {
  switch (rel.type) {
  case R_TLCS900_NONE:
    break;
  case R_TLCS900_24: {
    checkUInt(ctx, loc, val, 24, rel);
    loc[0] = val;
    loc[1] = val >> 8;
    loc[2] = val >> 16;
    break;
  }
  case R_TLCS900_32:
    write32le(loc, val);
    break;
  case R_TLCS900_PC24: {
    loc[0] = val;
    loc[1] = val >> 8;
    loc[2] = val >> 16;
    break;
  }
  case R_TLCS900_LO16:
    write16le(loc, val);  // Truncate to low 16 bits, no range check
    break;
  case R_TLCS900_PC16:
    checkIntUInt(ctx, loc, val, 16, rel);
    write16le(loc, val);
    break;
  case R_TLCS900_HI16:
    write16le(loc, val >> 16);
    break;
  default:
    Err(ctx) << getErrorLoc(ctx, loc) << "unrecognized relocation " << rel.type;
  }
}

void elf::setTLCS900TargetInfo(Ctx &ctx) {
  ctx.target.reset(new TLCS900(ctx));
}
