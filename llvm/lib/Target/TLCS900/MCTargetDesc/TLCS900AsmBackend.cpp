//===-- TLCS900AsmBackend.cpp - TLCS900 Asm Backend -------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the TLCS900AsmBackend class, including branch relaxation
// (JR/JRcc -> JRL/JRLcc when 8-bit displacement is insufficient).
//
//===----------------------------------------------------------------------===//

#include "TLCS900AsmBackend.h"
#include "TLCS900FixupKinds.h"
#include "TLCS900MCTargetDesc.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCFixupKindInfo.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCValue.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/MathExtras.h"

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

  // TLCS-900 PC-relative branches measure displacement from the END of the
  // instruction, not from the displacement field itself. The MCCodeEmitter
  // embeds the adjustment (-1 for rel8, -2 for rel16) directly in the fixup
  // expression so that RELA relocation addends are correct for unresolved
  // symbols (e.g., absolute .set labels).

  // Range checking for PC-relative branch fixups.
  if (Kind == TLCS900::fixup_tlcs900_rel8 ||
      Kind == TLCS900::fixup_tlcs900_branch_expr8) {
    if (!isInt<8>(Value))
      Asm.getContext().reportError(
          Fixup.getLoc(),
          "fixup value out of range for 8-bit relative branch "
          "(displacement " +
              Twine((int64_t)Value) + " requires JRL instead of JR)");
  } else if (Kind == TLCS900::fixup_tlcs900_rel16 ||
             Kind == TLCS900::fixup_tlcs900_branch_expr16) {
    if (!isInt<16>(Value))
      Asm.getContext().reportError(
          Fixup.getLoc(),
          "fixup value out of range for 16-bit relative branch");
  }

  // For each byte of the fragment that the fixup touches, mask in the bits
  // from the fixup value (little-endian).
  for (unsigned i = 0; i < NumBytes; ++i) {
    Data[Offset + i] |= static_cast<uint8_t>((Value >> (i * 8)) & 0xff);
  }
}

bool TLCS900AsmBackend::evaluateTargetFixup(
    const MCAssembler &Asm, const MCFixup &Fixup, const MCFragment *DF,
    const MCValue &Target, const MCSubtargetInfo *STI, uint64_t &Value) {
  // Branch expression fixups (calr (addr - . - 3), etc.) use FKF_IsTarget
  // so we can manually resolve same-section symbol differences that the
  // generic ELF writer can't handle.
  const MCSymbol *Add = Target.getAddSym();
  const MCSymbol *Sub = Target.getSubSym();
  Value = Target.getConstant();
  if (Add && Add->isDefined())
    Value += Asm.getSymbolOffset(*Add);
  if (Sub && Sub->isDefined())
    Value -= Asm.getSymbolOffset(*Sub);
  // Always mark as resolved — these expressions should be fully evaluable
  // at assembly time since both sides are in the same section.
  return true;
}

std::optional<MCFixupKind>
TLCS900AsmBackend::getFixupKind(StringRef Name) const {
  unsigned Type = StringSwitch<unsigned>(Name)
      .Case("R_TLCS900_NONE", ELF::R_TLCS900_NONE)
      .Case("R_TLCS900_24", ELF::R_TLCS900_24)
      .Case("R_TLCS900_32", ELF::R_TLCS900_32)
      .Case("R_TLCS900_LO16", ELF::R_TLCS900_LO16)
      .Case("R_TLCS900_HI16", ELF::R_TLCS900_HI16)
      .Default(-1u);
  if (Type != -1u)
    return static_cast<MCFixupKind>(FirstLiteralRelocationKind + Type);
  return std::nullopt;
}

const MCFixupKindInfo &
TLCS900AsmBackend::getFixupKindInfo(MCFixupKind Kind) const {
  static const MCFixupKindInfo Infos[TLCS900::NumTargetFixupKinds] = {
      // name                offset  size  flags
      {"fixup_tlcs900_24", 0, 24, 0},
      {"fixup_tlcs900_rel8", 0, 8, MCFixupKindInfo::FKF_IsPCRel},
      {"fixup_tlcs900_rel16", 0, 16, MCFixupKindInfo::FKF_IsPCRel},
      {"fixup_tlcs900_disp8", 0, 8, 0},
      {"fixup_tlcs900_disp16", 0, 16, 0},
      {"fixup_tlcs900_branch_expr8", 0, 8,
       MCFixupKindInfo::FKF_IsTarget},
      {"fixup_tlcs900_branch_expr16", 0, 16,
       MCFixupKindInfo::FKF_IsTarget},
  };

  if (Kind >= FirstLiteralRelocationKind)
    return MCAsmBackend::getFixupKindInfo(FK_NONE);

  if (Kind < FirstTargetFixupKind)
    return MCAsmBackend::getFixupKindInfo(Kind);

  assert(unsigned(Kind - FirstTargetFixupKind) < TLCS900::NumTargetFixupKinds &&
         "Invalid kind!");
  return Infos[Kind - FirstTargetFixupKind];
}

bool TLCS900AsmBackend::writeNopData(raw_ostream &OS, uint64_t Count,
                                     const MCSubtargetInfo *STI) const {
  // TLCS-900 NOP is a single byte: 0x00
  for (uint64_t i = 0; i < Count; ++i)
    OS.write('\0');
  return true;
}

//===----------------------------------------------------------------------===//
// Branch Relaxation
//===----------------------------------------------------------------------===//

bool TLCS900AsmBackend::mayNeedRelaxation(const MCInst &Inst,
                                          const MCSubtargetInfo &STI) const {
  // JR (unconditional, 8-bit displacement) may need relaxation to JRL.
  // JRcc (conditional, 8-bit displacement) may need relaxation to JRLcc.
  unsigned Opc = Inst.getOpcode();
  return Opc == TLCS900::JR || Opc == TLCS900::JRcc;
}

bool TLCS900AsmBackend::fixupNeedsRelaxation(const MCFixup &Fixup,
                                             uint64_t Value) const {
  // If the 8-bit displacement doesn't fit, relax to 16-bit.
  if (Fixup.getKind() == (MCFixupKind)TLCS900::fixup_tlcs900_rel8)
    return !isInt<8>((int64_t)Value);
  return false;
}

void TLCS900AsmBackend::relaxInstruction(MCInst &Inst,
                                         const MCSubtargetInfo &STI) const {
  unsigned Opc = Inst.getOpcode();

  switch (Opc) {
  case TLCS900::JR:
    // JR target (2 bytes: 0x68 + d8) -> JRL target (3 bytes: 0x78 + d16)
    Inst.setOpcode(TLCS900::JRL);
    break;
  case TLCS900::JRcc:
    // JR cc, target (2 bytes: 0x60+cc + d8) -> JRL cc, target (3 bytes: 0x70+cc + d16)
    Inst.setOpcode(TLCS900::JRLcc);
    break;
  default:
    llvm_unreachable("Unexpected instruction to relax");
  }
}

MCAsmBackend *llvm::createTLCS900AsmBackend(const Target &T,
                                            const MCSubtargetInfo &STI,
                                            const MCRegisterInfo &MRI,
                                            const MCTargetOptions &Options) {
  return new TLCS900AsmBackend(STI.getTargetTriple().getOS());
}
