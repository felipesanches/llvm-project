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
// prefix-based encoding scheme. Encoding is driven by TSFlags metadata set
// in TableGen format classes. Each instruction's InstFormat field determines
// which encoding routine to use.
//
//===----------------------------------------------------------------------===//

#include "TLCS900MCCodeEmitter.h"
#include "TLCS900BaseInfo.h"
#include "TLCS900FixupKinds.h"
#include "TLCS900MCTargetDesc.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/MathExtras.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-mccodeemitter"

/// Check if an MCExpr tree contains a reference to the "." (dot/current PC)
/// symbol.  Dot symbols are temporary symbols starting with ".Ltmp" that the
/// assembler creates to represent the current location counter.
static bool exprContainsDot(const MCExpr *E) {
  switch (E->getKind()) {
  case MCExpr::Constant:
    return false;
  case MCExpr::SymbolRef: {
    const MCSymbolRefExpr *SR = static_cast<const MCSymbolRefExpr *>(E);
    // The assembler creates anonymous temporary symbols for "." (current
    // PC) references.  In text mode they're named ".Ltmp0" etc.; in
    // object mode they have empty names.  User-defined local labels
    // (like .Lloop) are also temporary but have non-empty names.
    const MCSymbol &Sym = SR->getSymbol();
    if (!Sym.isTemporary())
      return false;
    StringRef Name = Sym.getName();
    return Name.empty() || Name.starts_with(".Ltmp");
  }
  case MCExpr::Unary:
    return exprContainsDot(
        static_cast<const MCUnaryExpr *>(E)->getSubExpr());
  case MCExpr::Binary: {
    const MCBinaryExpr *BE = static_cast<const MCBinaryExpr *>(E);
    return exprContainsDot(BE->getLHS()) || exprContainsDot(BE->getRHS());
  }
  case MCExpr::Target:
    return false;
  }
  return false;
}

unsigned TLCS900MCCodeEmitter::getRegEncoding(const MCOperand &MO,
                                               unsigned OpSize) const {
  assert(MO.isReg() && "Expected register operand");
  MCRegister Reg = MO.getReg();
  const MCRegisterInfo *MRI = Ctx.getRegisterInfo();

  // For 8-bit operations, the register operand may be a 32-bit register
  // (from GPR_with_sub8 via RegisterOperand<GPR_lo8>), printed as its
  // low-byte sub-register name by printGPRAsLoByte.  We need the actual
  // 8-bit sub-register's HWEncoding (A=1, C=3, E=5, L=7), not the 32-bit
  // parent's (XWA=0, XBC=1, XDE=2, XHL=3).
  if (OpSize == TLCS900II::OpSize8) {
    if (MCRegister Sub = MRI->getSubReg(Reg, TLCS900::sub_8bit))
      Reg = Sub;
  } else if (OpSize == TLCS900II::OpSize16) {
    if (MCRegister Sub = MRI->getSubReg(Reg, TLCS900::sub_16bit))
      Reg = Sub;
  }

  return MRI->getEncodingValue(Reg) & 0x7;
}

void TLCS900MCCodeEmitter::emitImmediate(int64_t Value, unsigned NumBytes,
                                         SmallVectorImpl<char> &CB,
                                         const MCInst *MI) const {
  // An immediate that fits the field neither as a signed nor as an unsigned
  // number is a mistake, not a request to keep the low bytes: `push 0x1234`
  // used to emit [0x09,0x34] and point the program at 0x34.  Both readings
  // are accepted because the same field spells -1 and 0xFF.
  if (MI && NumBytes < 8 && !isUIntN(NumBytes * 8, uint64_t(Value)) &&
      !isIntN(NumBytes * 8, Value)) {
    std::string ErrMsg;
    raw_string_ostream OS(ErrMsg);
    OS << "immediate 0x";
    OS.write_hex(uint64_t(Value));
    OS << " does not fit in the " << (NumBytes * 8)
       << "-bit field of this instruction";
    Ctx.reportError(MI->getLoc(), ErrMsg);
    return;
  }
  for (unsigned i = 0; i < NumBytes; ++i) {
    CB.push_back(static_cast<char>(Value & 0xFF));
    Value >>= 8;
  }
}

void TLCS900MCCodeEmitter::emitFixup(const MCInst &MI, const MCOperand &MO,
                                     unsigned FixupOffset, MCFixupKind Kind,
                                     SmallVectorImpl<char> &CB,
                                     SmallVectorImpl<MCFixup> &Fixups) const {
  if (MO.isImm()) {
    // Immediate value — no fixup needed, just emit the bytes.
    unsigned NumBytes = 0;
    switch (unsigned(Kind)) {
    case FK_Data_1:
    case TLCS900::fixup_tlcs900_rel8:
    case TLCS900::fixup_tlcs900_disp8:
      NumBytes = 1;
      break;
    case FK_Data_2:
    case TLCS900::fixup_tlcs900_rel16:
    case TLCS900::fixup_tlcs900_disp16:
      NumBytes = 2;
      break;
    case TLCS900::fixup_tlcs900_24:
      NumBytes = 3;
      break;
    case FK_Data_4:
      NumBytes = 4;
      break;
    default:
      NumBytes = 3; // 24-bit
      break;
    }
    emitImmediate(MO.getImm(), NumBytes, CB);
  } else if (MO.isExpr()) {
    // Symbolic expression — emit placeholder zeros and create a fixup.
    unsigned NumBytes = 0;
    switch (unsigned(Kind)) {
    case FK_Data_1:
    case TLCS900::fixup_tlcs900_rel8:
    case TLCS900::fixup_tlcs900_disp8:
      NumBytes = 1;
      break;
    case FK_Data_2:
    case TLCS900::fixup_tlcs900_rel16:
    case TLCS900::fixup_tlcs900_disp16:
      NumBytes = 2;
      break;
    case TLCS900::fixup_tlcs900_24:
      NumBytes = 3;
      break;
    case FK_Data_4:
      NumBytes = 4;
      break;
    default:
      NumBytes = 3;
      break;
    }
    // For PC-relative fixups, adjust the expression to account for the
    // displacement being measured from the END of the instruction, not from
    // the displacement field. This ensures RELA addends are correct for
    // absolute symbols (e.g., .set labels).
    //
    // When the expression contains a "." (dot/current PC) reference (e.g.,
    // "calr (0xE00010 - . - 3)"), the user has already incorporated the PC
    // into the expression. Using a PC-relative fixup would double-subtract
    // the PC. In this case, use a plain data fixup (FK_Data_N) so the
    // expression value is emitted as-is.
    const MCExpr *Expr = MO.getExpr();
    MCFixupKind FixupKind = Kind;
    bool HasDotRef = exprContainsDot(Expr);
    if (Kind == (MCFixupKind)TLCS900::fixup_tlcs900_rel8) {
      if (HasDotRef) {
        FixupKind = (MCFixupKind)TLCS900::fixup_tlcs900_branch_expr8;
      } else {
        Expr = MCBinaryExpr::createAdd(
            Expr, MCConstantExpr::create(-1, Ctx), Ctx);
      }
    } else if (Kind == (MCFixupKind)TLCS900::fixup_tlcs900_rel16) {
      if (HasDotRef) {
        FixupKind = (MCFixupKind)TLCS900::fixup_tlcs900_branch_expr16;
      } else {
        Expr = MCBinaryExpr::createAdd(
            Expr, MCConstantExpr::create(-2, Ctx), Ctx);
      }
    }
    Fixups.push_back(MCFixup::create(FixupOffset, Expr, FixupKind));
    for (unsigned i = 0; i < NumBytes; ++i)
      CB.push_back(0);
  }
}

unsigned TLCS900MCCodeEmitter::emitMemPrefix(
    const MCInst &MI, unsigned BaseOpIdx, unsigned DispOpIdx, bool IsDstMem,
    unsigned OpSize, uint64_t StartByte, SmallVectorImpl<char> &CB,
    SmallVectorImpl<MCFixup> &Fixups) const {
  const MCOperand &BaseOp = MI.getOperand(BaseOpIdx);

  // Direct addressing: the base operand is the address expression.
  //
  // The prefix carries both the OPERAND SIZE and the ADDRESS WIDTH:
  //   source       C0/C1/C2 byte, D0/D1/D2 word, E0/E1/E2 long
  //   destination  F0/F1/F2, size-independent
  // with the low two bits selecting 1, 2 or 3 address bytes.  All three
  // source sizes are encodable; this used to emit 0xE2 unconditionally and
  // reject anything but a 32-bit operand, which is why byte/word direct
  // memory had to be written as raw bytes.
  //
  // The address WIDTH is not derivable from the address value -- firmware
  // routinely uses a wide form for a small address -- so it is requested
  // explicitly and carried in the displacement operand as a sentinel
  // (assembly syntax `(0x8a:24)`).  Operands that do not request one keep
  // the historical 24-bit default, which is also the only width a
  // relocation against an unresolved symbol can use.
  if (BaseOp.isExpr()) {
    const MCOperand &DispOp = MI.getOperand(DispOpIdx);
    int64_t DispVal = DispOp.isImm() ? DispOp.getImm() : 0;
    unsigned NumBytes = TLCS900II::getDirectAddrBytes(DispVal);

    CB.push_back(IsDstMem ? TLCS900II::getDstDirectPrefixN(NumBytes)
                          : TLCS900II::getSrcDirectPrefixN(OpSize, NumBytes));

    int64_t Addr;
    if (BaseOp.getExpr()->evaluateAsAbsolute(Addr)) {
      // A constant address is emitted here rather than through a fixup, so
      // that an address too wide for the requested form is REFUSED instead
      // of silently losing its high bytes.
      unsigned Bits = NumBytes * 8;
      if (!isUIntN(Bits, uint64_t(Addr)) && !isIntN(Bits, Addr)) {
        std::string ErrMsg;
        raw_string_ostream OS(ErrMsg);
        OS << "direct address 0x";
        OS.write_hex(uint64_t(Addr));
        OS << " does not fit in the " << Bits
           << "-bit form requested for this memory operand";
        Ctx.reportError(MI.getLoc(), ErrMsg);
        return 0;
      }
      emitImmediate(Addr, NumBytes, CB);
    } else {
      MCFixupKind Kind = NumBytes == 1   ? MCFixupKind(FK_Data_1)
                         : NumBytes == 2 ? MCFixupKind(FK_Data_2)
                                         : MCFixupKind(TLCS900::fixup_tlcs900_24);
      Fixups.push_back(
          MCFixup::create(CB.size() - StartByte, BaseOp.getExpr(), Kind));
      for (unsigned i = 0; i < NumBytes; ++i)
        CB.push_back(0);
    }
    return 1 + NumBytes;
  }

  // Register-indirect addressing.
  unsigned BaseReg = getRegEncoding(BaseOp);
  const MCOperand &DispOp = MI.getOperand(DispOpIdx);
  int64_t Disp = DispOp.isImm() ? DispOp.getImm() : 0;

  // Select prefix base: source or destination memory.
  // Destination memory always uses B0/B8 (size encoded in sub-opcode).
  // Source memory prefix depends on data size:
  //   8-bit:  0x80/0x88 → mnemonic_80 table
  //   16-bit: 0x90/0x98 → mnemonic_90 table
  //   32-bit: 0xA0/0xA8 → mnemonic_a0 table
  unsigned PrefixNoDisp, PrefixD8;
  if (IsDstMem) {
    PrefixNoDisp = 0xB0;
    PrefixD8 = 0xB8;
  } else {
    PrefixNoDisp = TLCS900II::getSrcMemPrefixBase(OpSize);
    PrefixD8 = PrefixNoDisp + 0x08;
  }

  // Sentinel: displacement of 256 means "force d8 form with displacement 0".
  // Used by the assembly converter to reproduce exact ROM encoding where
  // the original firmware used the 2-byte (Xrr+d8) prefix with d8=0x00
  // instead of the shorter 1-byte (Xrr) prefix.
  if (Disp == 256 && DispOp.isImm()) {
    CB.push_back(PrefixD8 + BaseReg);
    CB.push_back(0);
    return 2;
  }

  // Sentinel: displacement of 65536 means "force the 4-byte SRI (Xrr+d16)
  // form with a real displacement of 0" -- the same collapse as the 256
  // sentinel above, one width up (see decodeMemPrefix's PrefixSize==4
  // comment). 65536 is outside any real d16's -32768..32767 range, so it
  // can never be confused with a genuine displacement.
  if (Disp == 65536 && DispOp.isImm()) {
    uint8_t SRIPrefix0 = IsDstMem ? 0xF3 : (0xC3 + OpSize * 0x10);
    CB.push_back(SRIPrefix0);
    CB.push_back(0xE0 + (BaseReg << 2) + 0x01);
    CB.push_back(0);
    CB.push_back(0);
    return 4;
  }

  if (Disp == 0 && DispOp.isImm()) {
    // (Xrr) — no displacement, 1-byte prefix.
    CB.push_back(PrefixNoDisp + BaseReg);
    return 1;
  } else if (DispOp.isImm() && Disp >= -128 && Disp <= 127) {
    // (Xrr+d8) — 8-bit displacement, 2-byte prefix.
    CB.push_back(PrefixD8 + BaseReg);
    CB.push_back(static_cast<char>(Disp & 0xFF));
    return 2;
  } else {
    // (Xrr+d16) — 16-bit displacement, uses SRI prefix + mode byte + d16.
    // Destination memory uses F3 prefix (dispatches to B0/F0 table).
    // Source memory uses C3/D3/E3 prefix depending on data size:
    //   8-bit:  0xC3 → mnemonic_80 table
    //   16-bit: 0xD3 → mnemonic_90 table
    //   32-bit: 0xE3 → mnemonic_a0 table

    // Validate d16 range: must fit in signed 16-bit.
    if (DispOp.isImm() && (Disp < -32768 || Disp > 32767)) {
      std::string ErrMsg;
      raw_string_ostream OS(ErrMsg);
      OS << "displacement " << Disp
         << " too large for d16 encoding (-32768..32767) in: ";
      MI.print(OS);
      Ctx.reportError(MI.getLoc(), ErrMsg);
      return 0;
    }

    // ⚠ Silent spelling trap: `(Xrr+d8)` is SIGNED, so a raw disp8 byte
    // 0x80..0xFF written as its positive value (128..255) does not fit the
    // signed 8-bit field and falls through to this 5-byte (Xrr+d16) form
    // instead of the 2-byte (Xrr+d8) form -- with no error, because +N in
    // that range is *also* a perfectly legitimate d16 displacement (this
    // tree has hundreds of genuine ones). The two spellings are NOT
    // interchangeable -- +151 and -105 are different addresses, not the
    // same byte read two ways -- so this cannot be upgraded to an error or
    // silently re-encoded as d8 without changing what already-correct
    // spellings assemble to. It can only be flagged: if this was meant to
    // reproduce a raw disp8 byte from disassembly, the byte's signed decimal
    // form (Disp - 256) is the spelling that selects the 2-byte encoding.
    if (DispOp.isImm() && Disp >= 128 && Disp <= 255) {
      std::string WarnMsg;
      raw_string_ostream OS(WarnMsg);
      OS << "displacement +" << Disp << " (raw byte 0x" << utohexstr(Disp, true)
         << ") does not fit the signed (Xrr+d8) field and assembles to the "
            "5-byte (Xrr+d16) form; if you intended the raw disp8 byte "
            "0x" << utohexstr(Disp, true) << " (i.e. the 2-byte d8 encoding), "
            "write the signed displacement " << (Disp - 256) << " instead, in: ";
      MI.print(OS);
      Ctx.reportWarning(MI.getLoc(), WarnMsg);
    }

    uint8_t SRIPrefix = IsDstMem ? 0xF3 : (0xC3 + OpSize * 0x10);
    CB.push_back(SRIPrefix);
    // Mode byte: bits 1-0 = 01 (Xrr+d16), bits 7-2 = register file address >> 2.
    // Register file addresses: XWA=0xE0..XSP=0xFC, so (0xE0 >> 2) + BaseReg = 0x38+BaseReg.
    CB.push_back(0xE0 + (BaseReg << 2) + 0x01);
    if (DispOp.isImm()) {
      emitImmediate(Disp, 2, CB);
    } else if (DispOp.isExpr()) {
      Fixups.push_back(
          MCFixup::create(CB.size() - StartByte, DispOp.getExpr(), FK_Data_2));
      CB.push_back(0);
      CB.push_back(0);
    }
    return 4;
  }
}

void TLCS900MCCodeEmitter::emitDirectAddrPrefix(
    const MCOperand &AddrOp, bool IsDstMem, unsigned OpSize, bool Is24Bit,
    uint64_t StartByte, SmallVectorImpl<char> &CB,
    SmallVectorImpl<MCFixup> &Fixups) const {
  unsigned NumBytes = Is24Bit ? 3 : 2;
  uint8_t Prefix = Is24Bit
      ? (IsDstMem ? 0xF2 : (0xC2 + OpSize * 0x10))
      : (IsDstMem ? 0xF1 : (0xC1 + OpSize * 0x10));
  CB.push_back(Prefix);

  if (AddrOp.isExpr()) {
    MCFixupKind Kind = Is24Bit
        ? (MCFixupKind)TLCS900::fixup_tlcs900_24
        : FK_Data_2;
    Fixups.push_back(MCFixup::create(CB.size() - StartByte, AddrOp.getExpr(),
                                     Kind));
    for (unsigned i = 0; i < NumBytes; ++i)
      CB.push_back(0);
  } else {
    int64_t Addr = AddrOp.isImm() ? AddrOp.getImm() : 0;
    emitImmediate(Addr, NumBytes, CB);
  }
}

void TLCS900MCCodeEmitter::encodeInstruction(
    const MCInst &MI, SmallVectorImpl<char> &CB,
    SmallVectorImpl<MCFixup> &Fixups, const MCSubtargetInfo &STI) const {
  const MCInstrDesc &Desc = MCII.get(MI.getOpcode());

  // Pseudos and codegen-only instructions don't get encoded.
  if (Desc.isPseudo())
    return;

  // Record the start position so fixup offsets are instruction-relative.
  // MCELFStreamer::emitInstToData adjusts fixup offsets by adding the
  // instruction's start position in the fragment, so we must not include
  // that base in the offsets we create.
  uint64_t StartByte = CB.size();

  uint64_t TSFlags = Desc.TSFlags;
  unsigned Format = TLCS900II::getInstFormat(TSFlags);
  unsigned Opcode = TLCS900II::getOpcode(TSFlags);
  unsigned OpSize = TLCS900II::getOpSize(TSFlags);
  unsigned PrefixBase = TLCS900II::getRegPrefixBase(OpSize);
  bool Is24Bit = TLCS900II::getAddrWidth(TSFlags);

  // Immediate size in bytes based on operand size.
  unsigned ImmBytes = (OpSize == TLCS900II::OpSize8)    ? 1
                      : (OpSize == TLCS900II::OpSize16) ? 2
                                                        : 4;

  switch (Format) {
  default:
    LLVM_DEBUG(dbgs() << "TLCS900: unhandled InstFormat " << Format
                      << " for opcode " << MI.getOpcode() << "\n");
    // Fallback: emit NOP placeholder.
    CB.push_back(0x00);
    break;

  case TLCS900II::Pseudo:
    // Should have been caught above, but just in case.
    break;

  case TLCS900II::SingleByte:
    // 1-byte instruction, opcode only.
    CB.push_back(Opcode);
    break;

  case TLCS900II::SingleByteImm8: {
    // Opcode + 8-bit immediate.
    // For EI (0x06, level), the level is a separate byte after the opcode.
    // For SWI (0xF8+num), the immediate is embedded in the opcode byte.
    // For RETD (0x0F, d16), it's different.
    const MCOperand &ImmOp = MI.getOperand(0);
    if (Opcode == 0x06) {
      // EI level: opcode 0x06 followed by level byte.
      unsigned Imm = ImmOp.isImm() ? ImmOp.getImm() : 0;
      CB.push_back(0x06);
      CB.push_back(static_cast<char>(Imm & 0xFF));
    } else if (Opcode == 0xF8) {
      // SWI num: immediate encoded in opcode bits 0-2.
      unsigned Imm = ImmOp.isImm() ? ImmOp.getImm() : 0;
      CB.push_back(Opcode + (Imm & 0x7));
    } else if (Opcode == 0x0B || Opcode == 0x0F) {
      // PUSHW/RETD: opcode + 16-bit immediate.
      CB.push_back(Opcode);
      if (ImmOp.isImm())
        emitImmediate(ImmOp.getImm(), 2, CB, &MI);
      else
        emitFixup(MI, ImmOp, CB.size() - StartByte, FK_Data_2, CB, Fixups);
    } else {
      CB.push_back(Opcode);
      if (ImmOp.isImm())
        emitImmediate(ImmOp.getImm(), 1, CB, &MI);
      else
        emitFixup(MI, ImmOp, CB.size() - StartByte, FK_Data_1, CB, Fixups);
    }
    break;
  }

  case TLCS900II::SingleByteReg: {
    // Opcode + register in bits 0-2. No immediate.
    // PUSH32: operand 0 is the register to push.
    // POP32: operand 0 is the register to pop into.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(Opcode + RegEnc);
    break;
  }

  case TLCS900II::SingleByteRegImm: {
    // opcode+r, then N-byte immediate (N depends on OpSize).
    // LD r32, #imm32: 0x40+r, imm32 (5 bytes)
    // LDW r16, #imm16: 0x30+r, imm16 (3 bytes)
    // LDB r8, #imm8: 0x20+r, imm8 (2 bytes)
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(Opcode + RegEnc);
    const MCOperand &ImmOp = MI.getOperand(1);
    if (ImmOp.isImm()) {
      emitImmediate(ImmOp.getImm(), ImmBytes, CB, &MI);
    } else {
      MCFixupKind ImmFixupKind = (ImmBytes == 1)   ? FK_Data_1
                                 : (ImmBytes == 2) ? FK_Data_2
                                                    : FK_Data_4;
      emitFixup(MI, ImmOp, CB.size() - StartByte, ImmFixupKind, CB, Fixups);
    }
    break;
  }

  case TLCS900II::PrefixUnary: {
    // reg_prefix + opcode. Register is operand 0 (which is also the dest).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::PrefixRegImm: {
    // reg_prefix(dst) + opcode + immediate.
    // Two-address form: operand 0 = dst, operand 1 = src1 (tied), operand 2 = imm.
    // Compare form (CP32ri): operand 0 = rs1, operand 1 = imm.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    // Find the immediate operand (last operand).
    unsigned ImmIdx = Desc.getNumOperands() - 1;
    const MCOperand &ImmOp = MI.getOperand(ImmIdx);
    // Use instruction Size to compute immediate bytes (Size - 2 = prefix + opcode).
    // This handles cases like STCF16ri where OpSize is 16-bit but imm is 1 byte.
    unsigned PrefixRegImmBytes = Desc.getSize() - 2;
    MCFixupKind ImmFixupKind = (PrefixRegImmBytes == 1)   ? FK_Data_1
                               : (PrefixRegImmBytes == 2) ? FK_Data_2
                                                           : FK_Data_4;
    if (ImmOp.isImm()) {
      emitImmediate(ImmOp.getImm(), PrefixRegImmBytes, CB, &MI);
    } else {
      emitFixup(MI, ImmOp, CB.size() - StartByte, ImmFixupKind, CB, Fixups);
    }
    break;
  }

  case TLCS900II::PrefixRegReg: {
    // src_prefix + (opcode | dst_reg).
    // Two-address form: op 0 = dst, op 1 = src1 (tied to dst), op 2 = src2.
    // For LD32rr: op 0 = dst, op 1 = src. Prefix = src, second byte = opc+dst.
    // For CP32rr: op 0 = rs1, op 1 = rs2. Prefix = rs2, second byte = opc+rs1.
    unsigned DstEnc, SrcEnc;
    if (Desc.getNumOperands() >= 3) {
      // Two-address: dst=op0, src2=op2.
      DstEnc = getRegEncoding(MI.getOperand(0));
      SrcEnc = getRegEncoding(MI.getOperand(2));
    } else if (Desc.getNumOperands() == 2 && MI.getOperand(0).isReg() &&
               MI.getOperand(1).isReg()) {
      // Two-operand (LD rr, CP rr): dst=op0, src=op1.
      DstEnc = getRegEncoding(MI.getOperand(0));
      SrcEnc = getRegEncoding(MI.getOperand(1));
    } else {
      // Fallback for unusual operand counts.
      DstEnc = getRegEncoding(MI.getOperand(0));
      SrcEnc = 0;
    }
    CB.push_back(PrefixBase + SrcEnc);
    CB.push_back(Opcode + DstEnc);
    break;
  }

  case TLCS900II::PrefixShift: {
    // reg_prefix(rd) + shift_opcode + amount_byte.
    // Two-address: op 0 = dst, op 1 = src1 (tied), op 2 = imm.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    unsigned ImmIdx = Desc.getNumOperands() - 1;
    const MCOperand &ImmOp = MI.getOperand(ImmIdx);
    CB.push_back(static_cast<char>(ImmOp.isImm() ? ImmOp.getImm() : 1));
    break;
  }

  case TLCS900II::PrefixRotate: {
    // reg_prefix(rd) + rotate_opcode + count (always 1 for single rotate).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    CB.push_back(0x01); // Rotate by 1.
    break;
  }

  case TLCS900II::PrefixBit: {
    // reg_prefix(rd) + opcode + bit_number.
    // BIT32: op 0 = bit, op 1 = reg.
    // SET32/RES32/CHG32/TSET32: op 0 = dst, op 1 = bit, op 2 = src (tied).
    unsigned RegOpIdx, BitOpIdx;
    if (Desc.getNumDefs() > 0) {
      // Output instruction (SET, RES, CHG, TSET): op0=dst, op1=bit, op2=tied.
      RegOpIdx = 0;
      BitOpIdx = 1;
    } else {
      // No output (BIT): op0=bit, op1=reg.
      RegOpIdx = 1;
      BitOpIdx = 0;
    }
    unsigned RegEnc = getRegEncoding(MI.getOperand(RegOpIdx));
    unsigned BitNum =
        MI.getOperand(BitOpIdx).isImm() ? MI.getOperand(BitOpIdx).getImm() : 0;
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    CB.push_back(static_cast<char>(BitNum & 0x1F));
    break;
  }

  case TLCS900II::PrefixIncDec: {
    // reg_prefix(rd) + (opcode + I3).
    // INC32/DEC32: op 0 = dst, op 1 = src (tied), op 2 = count.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    unsigned Count =
        MI.getOperand(2).isImm() ? MI.getOperand(2).getImm() : 1;
    // Hardware I3 field: 001=1, 010=2, ..., 111=7, 000=8.
    unsigned EncodedCount = Count & 0x7;
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode + EncodedCount);
    break;
  }

  case TLCS900II::MemLoad: {
    // src_mem_prefix [+disp] + (opcode + dst_reg).
    // LD32rm: op 0 = dst, op 1 = base, op 2 = disp.
    // Uses source memory prefix (size-dependent) since data flows FROM memory.
    unsigned DstEnc = getRegEncoding(MI.getOperand(0), OpSize);
    emitMemPrefix(MI, 1, 2, /*IsDstMem=*/false, OpSize, StartByte, CB, Fixups);
    CB.push_back(Opcode + DstEnc);
    break;
  }

  case TLCS900II::MemLoadDst: {
    // dst_mem_prefix [+disp] + (opcode + dst_reg).
    // LDA32: op 0 = dst, op 1 = base, op 2 = disp.
    // Uses destination memory prefix (B0/B8) — LDA is in the B0 opcode table.
    unsigned DstEnc = getRegEncoding(MI.getOperand(0));
    emitMemPrefix(MI, 1, 2, /*IsDstMem=*/true, OpSize, StartByte, CB, Fixups);
    CB.push_back(Opcode + DstEnc);
    break;
  }

  case TLCS900II::MemStore: {
    // dst_mem_prefix [+disp] + (opcode + src_reg) or + imm.
    // LD32mr: op 0 = base, op 1 = disp, op 2 = src_reg.
    // LD32mi: op 0 = base, op 1 = disp, op 2 = imm.
    // Uses destination memory prefix (B0/B8/F2) since data flows TO memory.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/true, OpSize, StartByte, CB, Fixups);
    const MCOperand &SrcOp = MI.getOperand(2);
    if (SrcOp.isReg()) {
      unsigned SrcEnc = getRegEncoding(SrcOp, OpSize);
      CB.push_back(Opcode + SrcEnc);
    } else {
      // Store immediate: opcode + immediate bytes.
      CB.push_back(Opcode);
      if (SrcOp.isImm())
        emitImmediate(SrcOp.getImm(), ImmBytes, CB, &MI);
      else
        emitFixup(MI, SrcOp, CB.size() - StartByte, FK_Data_4, CB, Fixups);
    }
    break;
  }

  case TLCS900II::MemALU: {
    // src_mem_prefix [+disp] + (opcode + src_reg) or + opcode + imm.
    // ALU (mem), rs: op 0 = base, op 1 = disp, op 2 = reg_or_imm.
    // Uses source memory prefix (size-dependent) — ALU-with-memory opcodes
    // are in the source memory opcode table.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/false, OpSize, StartByte, CB, Fixups);
    const MCOperand &SrcOp = MI.getOperand(2);
    if (SrcOp.isReg()) {
      unsigned SrcEnc = getRegEncoding(SrcOp, OpSize);
      CB.push_back(Opcode + SrcEnc);
    } else {
      CB.push_back(Opcode);
      if (SrcOp.isImm())
        emitImmediate(SrcOp.getImm(), ImmBytes, CB, &MI);
      else
        emitFixup(MI, SrcOp, CB.size() - StartByte, FK_Data_4, CB, Fixups);
    }
    break;
  }

  case TLCS900II::MemStoreImm: {
    // dst_mem_prefix [+disp] + opcode + immediate.
    // LD (mem), #imm: op 0 = base, op 1 = disp, op 2 = imm.
    // Uses destination memory prefix (B0/B8) regardless of data size.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/true, OpSize, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    const MCOperand &ImmOp = MI.getOperand(2);
    if (ImmOp.isImm())
      emitImmediate(ImmOp.getImm(), ImmBytes, CB, &MI);
    else
      emitFixup(MI, ImmOp, CB.size() - StartByte,
                ImmBytes == 1 ? FK_Data_1 : FK_Data_2, CB, Fixups);
    break;
  }

  case TLCS900II::Branch16: {
    // 0x1A + 16-bit absolute address.
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(0);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 2, CB, &MI);
    } else {
      emitFixup(MI, Target, CB.size() - StartByte, FK_Data_2, CB, Fixups);
    }
    break;
  }

  case TLCS900II::Call16: {
    // 0x1C + 16-bit absolute address.
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(0);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 2, CB, &MI);
    } else {
      emitFixup(MI, Target, CB.size() - StartByte, FK_Data_2, CB, Fixups);
    }
    break;
  }

  case TLCS900II::Branch24: {
    // 0x1B + 24-bit absolute address.
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(0);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 3, CB, &MI);
    } else {
      emitFixup(MI, Target, CB.size() - StartByte,
                (MCFixupKind)TLCS900::fixup_tlcs900_24, CB, Fixups);
    }
    break;
  }

  case TLCS900II::BranchCond24: {
    // Emit as JRL cc, d16 (3 bytes): 0x70+cc, d16.
    // op 0 = cc, op 1 = target.
    unsigned CC =
        MI.getOperand(0).isImm() ? MI.getOperand(0).getImm() : 0;
    CB.push_back(0x70 + (CC & 0xF));
    const MCOperand &Target = MI.getOperand(1);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 2, CB, &MI);
    } else {
      emitFixup(MI, Target, CB.size() - StartByte,
                (MCFixupKind)TLCS900::fixup_tlcs900_rel16, CB, Fixups);
    }
    break;
  }

  case TLCS900II::BranchRel8: {
    // JR/JRcc: opcode(+cc) + d8.
    // Unconditional JR: op 0 = target (opcode already has T=8 baked in).
    // Conditional JRcc: op 0 = cc, op 1 = target.
    //
    // The operand is the RAW DISPLACEMENT FIELD, not a target address, so a
    // constant that fits it neither signed nor unsigned is a mistake and not a
    // request to keep the low byte -- emitImmediate refuses it.  JRL and CALR
    // have refused the same mistake since 95f7f2d40428 because they emit
    // through emitImmediate; JR masked with `& 0xFF` instead, so `jr 99832`
    // silently became [0x68,0xf8] and branched somewhere else entirely.  The
    // 36 sites in the kn5000-roms-disasm tree that hit this were displacements
    // the disassembly had SIGN-EXTENDED TO 24 BITS -- `jr c, 16777183` for
    // -33 -- exactly the shape 95f7f2d40428 found in 31 `jrl` operands.
    if (MI.getNumOperands() >= 2 && MI.getOperand(0).isImm()) {
      // Conditional: 0x60 + cc, d8.
      unsigned CC = MI.getOperand(0).getImm();
      CB.push_back(Opcode + (CC & 0xF));
      const MCOperand &Target = MI.getOperand(1);
      if (Target.isImm())
        emitImmediate(Target.getImm(), 1, CB, &MI);
      else
        emitFixup(MI, Target, CB.size() - StartByte,
                  (MCFixupKind)TLCS900::fixup_tlcs900_rel8, CB, Fixups);
    } else {
      // Unconditional: opcode already includes T condition.
      CB.push_back(Opcode);
      const MCOperand &Target = MI.getOperand(0);
      if (Target.isImm())
        emitImmediate(Target.getImm(), 1, CB, &MI);
      else
        emitFixup(MI, Target, CB.size() - StartByte,
                  (MCFixupKind)TLCS900::fixup_tlcs900_rel8, CB, Fixups);
    }
    break;
  }

  case TLCS900II::BranchRel16: {
    // JRL/JRLcc: opcode(+cc) + d16.
    if (MI.getNumOperands() >= 2 && MI.getOperand(0).isImm()) {
      unsigned CC = MI.getOperand(0).getImm();
      CB.push_back(Opcode + (CC & 0xF));
      const MCOperand &Target = MI.getOperand(1);
      if (Target.isImm())
        emitImmediate(Target.getImm(), 2, CB, &MI);
      else
        emitFixup(MI, Target, CB.size() - StartByte,
                  (MCFixupKind)TLCS900::fixup_tlcs900_rel16, CB, Fixups);
    } else {
      CB.push_back(Opcode);
      const MCOperand &Target = MI.getOperand(0);
      if (Target.isImm())
        emitImmediate(Target.getImm(), 2, CB, &MI);
      else
        emitFixup(MI, Target, CB.size() - StartByte,
                  (MCFixupKind)TLCS900::fixup_tlcs900_rel16, CB, Fixups);
    }
    break;
  }

  case TLCS900II::Call24: {
    // CALL nnn: 0x1D + 24-bit absolute address.
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(0);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 3, CB, &MI);
    } else {
      emitFixup(MI, Target, CB.size() - StartByte,
                (MCFixupKind)TLCS900::fixup_tlcs900_24, CB, Fixups);
    }
    break;
  }

  case TLCS900II::CallRel16: {
    // CALR d16: 0x1E + 16-bit relative displacement.
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(0);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 2, CB, &MI);
    } else {
      emitFixup(MI, Target, CB.size() - StartByte,
                (MCFixupKind)TLCS900::fixup_tlcs900_rel16, CB, Fixups);
    }
    break;
  }

  case TLCS900II::CallIndirect: {
    // CALL/JP (reg): B0+reg, opcode (0xE8=CALL T, 0xD8=JP T in B0 table).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(0xB0 + RegEnc);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::PrefixDJNZ: {
    // DJNZ: reg_prefix(rd) + 0x1C + d8.
    // op 0 = dst, op 1 = src (tied), op 2 = target.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(2);
    // Same displacement field, same refusal.  All 278 `djnz` sites in the
    // kn5000-roms-disasm tree take a label, so this one costs nothing today;
    // it is here so the branch group is consistent rather than because
    // anything was found wrong.
    if (Target.isImm())
      emitImmediate(Target.getImm(), 1, CB, &MI);
    else
      emitFixup(MI, Target, CB.size() - StartByte,
                (MCFixupKind)TLCS900::fixup_tlcs900_rel8, CB, Fixups);
    break;
  }

  case TLCS900II::PrefixLDImm: {
    // reg_prefix(rd) + 0x03 + immediate.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    const MCOperand &ImmOp = MI.getOperand(1);
    MCFixupKind LDImmFixupKind = (ImmBytes == 1)   ? FK_Data_1
                                 : (ImmBytes == 2) ? FK_Data_2
                                                    : FK_Data_4;
    if (ImmOp.isImm())
      emitImmediate(ImmOp.getImm(), ImmBytes, CB, &MI);
    else
      emitFixup(MI, ImmOp, CB.size() - StartByte, LDImmFixupKind, CB, Fixups);
    break;
  }

  case TLCS900II::PrefixPush: {
    // reg_prefix(rs) + 0x04.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::PrefixPop: {
    // reg_prefix(rd) + 0x05.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::BlockTransfer: {
    // 2-byte block transfer: prefix + sub-opcode.
    // Prefix = 0x80 + (OpSize * 16) + RegIdx
    // Default: OpSize=0, RegIdx=0 → 0x80 (byte-wide, register 0)
    unsigned RegIdx = TLCS900II::getRegIdx(TSFlags);
    CB.push_back(0x80 + (OpSize << 4) + RegIdx);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::SingleByteCondRet: {
    // RETcc: 0xB0, (Opcode + cc). Opcode = 0xF0 base.
    unsigned CC = MI.getOperand(0).isImm() ? MI.getOperand(0).getImm() : 0;
    CB.push_back(0xB0);
    CB.push_back(Opcode + (CC & 0xF));
    break;
  }

  case TLCS900II::PrefixCondCode: {
    // SCC: prefix(rd) + (Opcode + cc). Opcode = 0x70 base.
    // Operand 0 = rd (register), operand 1 = cc (condition code).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    unsigned CC = MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 0;
    CB.push_back(PrefixBase + RegEnc);
    CB.push_back(Opcode + (CC & 0xF));
    break;
  }

  case TLCS900II::PrefixSmallImm: {
    // reg_prefix(rd) + (opcode + imm3).
    // LD r, 0-7: prefix + (0xA8 + value). Value 0-7 in bits 0-2.
    // op 0 = rd, op 1 = imm(0-7).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(PrefixBase + RegEnc);
    unsigned Imm = MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 0;
    CB.push_back(Opcode + (Imm & 0x7));
    break;
  }

  case TLCS900II::MemIncDec: {
    // src_mem_prefix [+disp] + (opcode + count%8).
    // INC/DEC (mem): op 0 = base, op 1 = disp, op 2 = count.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/false, OpSize, StartByte, CB, Fixups);
    unsigned Count =
        MI.getOperand(2).isImm() ? MI.getOperand(2).getImm() : 1;
    unsigned EncodedCount = Count & 0x7;
    CB.push_back(Opcode + EncodedCount);
    break;
  }

  case TLCS900II::MemPush: {
    // src_mem_prefix [+disp] + opcode.
    // PUSH (mem): op 0 = base, op 1 = disp.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/false, OpSize, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::MemDstUnary: {
    // dst_mem_prefix [+disp] + opcode.
    // POP/POPW (mem), ANDCF/ORCF/XORCF/LDCF/STCF A,(mem): op 0 = base,
    // op 1 = disp.  These live in the destination sub-opcode table and take
    // neither a register nor a modifier in the opcode byte.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/true, OpSize, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::MemDstCC: {
    // dst_mem_prefix [+disp] + (opcode + cc).
    // JP cc,(mem) / CALL cc,(mem): op 0 = base, op 1 = disp, op 2 = cc.
    // The condition is four bits wide, unlike the three of a bit number.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/true, OpSize, StartByte, CB, Fixups);
    unsigned CC = MI.getOperand(2).isImm() ? MI.getOperand(2).getImm() : 0;
    CB.push_back(Opcode + (CC & 0xF));
    break;
  }

  case TLCS900II::MemDstBitOp: {
    // dst_mem_prefix [+disp] + (opcode + bit_number).
    // BIT/SET/RES/LDCF/STCF (mem): op 0 = base, op 1 = disp, op 2 = bit.
    emitMemPrefix(MI, 0, 1, /*IsDstMem=*/true, OpSize, StartByte, CB, Fixups);
    unsigned BitNum =
        MI.getOperand(2).isImm() ? MI.getOperand(2).getImm() : 0;
    CB.push_back(Opcode + (BitNum & 0x7));
    break;
  }

  //=== Direct addressing instructions ===

  case TLCS900II::DirectSrcReg: {
    // src_direct_prefix + addr + (opcode | reg_enc).
    // For loads/ALU-to-reg: op 0 = reg (dst), last op = addr.
    // For ALU-to-mem (store direction): op 0 = addr, op 1 = reg (src).
    unsigned RegIdx, AddrIdx;
    if (Desc.getNumDefs() > 0) {
      // Load or two-address ALU: register is op 0, addr is last operand.
      RegIdx = 0;
      AddrIdx = MI.getNumOperands() - 1;
    } else if (MI.getNumOperands() >= 2 && MI.getOperand(0).isImm()) {
      // Store direction (addr, reg): addr is op 0, reg is op 1.
      AddrIdx = 0;
      RegIdx = 1;
    } else {
      // Fallback: compare (reg, addr).
      RegIdx = 0;
      AddrIdx = MI.getNumOperands() - 1;
    }
    // NOT `OpSize` here for the ALU family (Opcode != 0x20): for the whole
    // ADD/SUB/AND/XOR/OR/CP-direct-address family, OpSize names the MEMORY
    // operand's width (it picks which of C0/D0/E0 direct-address prefix to
    // emit, below) and is UNRELATED to the register operand's width -- every
    // disassembler-produced instruction of this InstFormat (the DALUOps
    // table in TLCS900Disassembler.cpp) decodes the register with
    // decodeGPR() regardless of the "8"/"16"/"32" in its own mnemonic
    // (CP8_da16 prints "cpda8 xbc, (addr)", a 32-bit register, even though
    // its OpSize field is OpSize8). Passing that OpSize straight to
    // getRegEncoding() made it apply the GR8-sub-register substitution meant
    // for actual byte-sized register operands, silently re-encoding
    // XWA/XBC/XDE/XHL (the four GPRs with an 8-bit sub-register) as the
    // WRONG register -- confirmed on real ROM bytes (v7's
    // VoiceSlot_StatusRet: `c1 57 0d f1` decodes as "cpda8 xbc, (3415)" but
    // reassembled that text as `c1 57 0d f3`, silently swapping XBC for C).
    //
    // Opcode == 0x20 is the LD_da16/LD_da24 family instead, which this
    // InstFormat also serves -- and there, unlike the ALU family, at least
    // one already-committed spelling (hd-ae5000's
    // HDAE5000_HD_Read_Identify: "ldb_da xwa, (0x229d99)") relies on the
    // OLD OpSize8 substitution to reach the byte the ROM actually has (the
    // disassembler's OWN decode of this opcode, in decodeDirectAddr's
    // "0x20-0x27" branch, uses decodeRegForSize(enc, OpSize) -- genuinely
    // OpSize-dependent, not a fixed GPR like the ALU family). So the LD
    // family keeps the old, OpSize-dependent encoding untouched; confirmed
    // 2026-09-02 that widening this fix to Opcode==0x20 too regresses
    // hd-ae5000 by 30 B (`make gate` byte-identical check).
    unsigned RegEnc = getRegEncoding(
        MI.getOperand(RegIdx), Opcode == 0x20 ? OpSize : TLCS900II::OpSize32);
    emitDirectAddrPrefix(MI.getOperand(AddrIdx), /*IsDstMem=*/false, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    CB.push_back(Opcode + RegEnc);
    break;
  }

  case TLCS900II::DirectSrcImm: {
    // src_direct_prefix + addr + opcode + imm.
    // op 0 = addr, op 1 = imm.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    const MCOperand &ImmOp = MI.getOperand(1);
    if (ImmOp.isImm())
      emitImmediate(ImmOp.getImm(), ImmBytes, CB, &MI);
    else
      emitFixup(MI, ImmOp, CB.size() - StartByte,
                ImmBytes == 1 ? FK_Data_1 : FK_Data_2, CB, Fixups);
    break;
  }

  case TLCS900II::DirectSrcIncDec: {
    // src_direct_prefix + addr + (opcode + count%8).
    // op 0 = addr, op 1 = count.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    unsigned Count =
        MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 1;
    CB.push_back(Opcode + (Count & 0x7));
    break;
  }

  case TLCS900II::DirectSrcPush: {
    // src_direct_prefix + addr + opcode.
    // op 0 = addr (only operand).
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    break;
  }

  case TLCS900II::DirectDstReg: {
    // F1/F2 + addr + (opcode | reg_enc).
    // For LDA (output): op 0 = reg (dst), op 1 = addr.
    // For LD store (no output): op 0 = addr, op 1 = reg (src).
    unsigned RegIdx, AddrIdx;
    if (Desc.getNumDefs() > 0) {
      RegIdx = 0; AddrIdx = 1;
    } else {
      AddrIdx = 0; RegIdx = 1;
    }
    unsigned RegEnc = getRegEncoding(MI.getOperand(RegIdx), OpSize);
    emitDirectAddrPrefix(MI.getOperand(AddrIdx), /*IsDstMem=*/true, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    CB.push_back(Opcode + RegEnc);
    break;
  }

  case TLCS900II::DirectDstImm: {
    // F1/F2 + addr + opcode + imm.
    // op 0 = addr, op 1 = imm.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/true, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    const MCOperand &ImmOp = MI.getOperand(1);
    if (ImmOp.isImm())
      emitImmediate(ImmOp.getImm(), ImmBytes, CB, &MI);
    else
      emitFixup(MI, ImmOp, CB.size() - StartByte,
                ImmBytes == 1 ? FK_Data_1 : FK_Data_2, CB, Fixups);
    break;
  }

  case TLCS900II::DirectDstBitOp: {
    // F1/F2 + addr + (opcode + value).
    // op 0 = addr, op 1 = bit/count/cc.
    // Used for BIT/SET/RES (3-bit), INC/DEC (3-bit), and CALL cc (4-bit).
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/true, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    unsigned BitNum =
        MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 0;
    CB.push_back(Opcode + (BitNum & 0xF));
    break;
  }

  case TLCS900II::DirectMemToMem: {
    // src_direct_prefix + src_addr16 + opcode(0x19) + dst_addr16.
    // op 0 = src_addr, op 1 = dst_addr.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, StartByte, CB, Fixups);
    CB.push_back(Opcode);
    const MCOperand &DstAddr = MI.getOperand(1);
    if (DstAddr.isImm())
      emitImmediate(DstAddr.getImm(), Is24Bit ? 3 : 2, CB, &MI);
    break;
  }

  case TLCS900II::LdIoImm: {
    // 0x08 + addr8 + imm8. op 0 = addr, op 1 = imm.
    CB.push_back(Opcode);
    CB.push_back(MI.getOperand(0).isImm() ? MI.getOperand(0).getImm() : 0);
    CB.push_back(MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 0);
    break;
  }

  case TLCS900II::LdIoImm16: {
    // 0x0A + addr8 + imm16_LE. op 0 = addr, op 1 = imm.
    CB.push_back(Opcode);
    CB.push_back(MI.getOperand(0).isImm() ? MI.getOperand(0).getImm() : 0);
    if (MI.getOperand(1).isImm()) {
      int64_t Val = MI.getOperand(1).getImm();
      CB.push_back(static_cast<uint8_t>(Val & 0xFF));
      CB.push_back(static_cast<uint8_t>((Val >> 8) & 0xFF));
    } else {
      CB.push_back(0);
      CB.push_back(0);
    }
    break;
  }

  case TLCS900II::PrefixDisp16: {
    // reg_prefix(rs1) + Opcode + d16.  op 0 = register, op 1 = displacement.
    CB.push_back(0xE8 + getRegEncoding(MI.getOperand(0)));
    CB.push_back(Opcode);
    const MCOperand &D = MI.getOperand(1);
    if (D.isImm())
      emitImmediate(D.getImm(), 2, CB, &MI);
    else
      emitFixup(MI, D, CB.size() - StartByte, FK_Data_2, CB, Fixups);
    break;
  }

  case TLCS900II::ExtPrefix: {
    // Generic extended prefix: emit all operands as literal bytes.
    for (unsigned i = 0, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    break;
  }

  case TLCS900II::ExtAddrModeSuffix: {
    // Computed prefix + operand bytes + appended SubOpcode byte.
    // Encoding: [computed_prefix, operand_bytes..., SubOpcode]
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    for (unsigned i = 0, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::ExtAddrModeOpImm: {
    // Like ExtAddrModeSuffix but SubOpcode is inserted in the MIDDLE.
    // Encoding: [computed_prefix, pre_operands..., SubOpcode, post_operands...]
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    unsigned NumPre = TLCS900II::getNumPreOps(TSFlags);
    unsigned OpIdx = 0;
    // Emit pre-SubOpcode operands.
    for (unsigned i = 0; i < NumPre && OpIdx < MI.getNumOperands(); ++OpIdx) {
      const MCOperand &MO = MI.getOperand(OpIdx);
      if (MO.isImm()) {
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
        ++i;
      }
    }
    // Emit SubOpcode.
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    // Emit post-SubOpcode operands.
    for (; OpIdx < MI.getNumOperands(); ++OpIdx) {
      const MCOperand &MO = MI.getOperand(OpIdx);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    break;
  }

  //=== Extended addressing mode — native formats ===

  case TLCS900II::ERPReg: {
    // [prefix, bank_idx, SubOpc + reg_enc]
    // Operand 0: data register, Operand 1: bank index.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEnc = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpc + RegEnc));
    break;
  }

  case TLCS900II::ERPSmallImm: {
    // [prefix, bank_idx, SubOpc + imm3]
    // Operand 0: bank index, Operand 1: small immediate (0-7).
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(0).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned Imm = MI.getOperand(1).getImm() & 0x7;
    CB.push_back(static_cast<char>(SubOpc + Imm));
    break;
  }

  case TLCS900II::ERPUnary: {
    // [prefix, bank_idx, SubOpc]
    // Operand 0: bank index.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(0).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::ERPImmAfter: {
    // [prefix, bank_idx, SubOpc, imm_bytes...]
    // Operand 0: bank index, remaining operands: trailing immediate bytes.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(0).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    for (unsigned i = 1, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    break;
  }

  case TLCS900II::PIReg: {
    // [prefix, base_gpr_enc, SubOpc + data_reg_enc]
    // Operand 0: data register, Operand 1: base GPR.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(getRegEncoding(MI.getOperand(1))));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEnc = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpc + RegEnc));
    break;
  }

  case TLCS900II::PIUnary: {
    // [prefix, base_gpr_enc, SubOpc]
    // Operand 0: base GPR.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(getRegEncoding(MI.getOperand(0))));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::RIReg: {
    // [prefix, MEMsri_bytes..., SubOpc + reg_enc]
    // Operand 0: data register, Operand 1-3: MEMsri (mode, lo, hi).
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    // Emit MEMsri addressing mode bytes.
    unsigned Mode = MI.getOperand(1).getImm();
    CB.push_back(static_cast<char>(Mode & 0xFF));
    unsigned ModeType = Mode & 0x03;
    if (ModeType != 0) {
      // Modes 1 (Xrr+d16) and 3 (Xrr+Rn) and 0x13 (PC+d16) have 2 extra bytes.
      CB.push_back(static_cast<char>(MI.getOperand(2).getImm() & 0xFF));
      CB.push_back(static_cast<char>(MI.getOperand(3).getImm() & 0xFF));
    }
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEnc = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpc + RegEnc));
    break;
  }

  case TLCS900II::SriD16Reg: {
    // [prefix, mode_byte, d16_lo, d16_hi, SubOpc + reg_enc]
    // Operand 0: dest register, Operand 1: base GPR, Operand 2: d16 disp.
    // Mode byte = 0xE0 + (base_reg_enc * 4) + 1 (current bank, d16 mode).
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    unsigned BaseEnc = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(0xE0 + BaseEnc * 4 + 1));
    emitImmediate(MI.getOperand(2).getImm(), 2, CB, &MI);
    unsigned SubOpc2 = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEnc2 = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpc2 + RegEnc2));
    break;
  }

  //=== SRI Register+Register (R+R) addressing formats ===

  case TLCS900II::SriRRReg: {
    // [prefix, 0x07, base_addr, idx_addr, SubOpc + data_reg_enc]
    // Operand 0: data register, Operand 1: base GPR, Operand 2: index GR16.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(0x07)); // R+R 16-bit index mode
    unsigned BaseEnc = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(0xE0 + BaseEnc * 4));
    unsigned IdxEnc = getRegEncoding(MI.getOperand(2));
    CB.push_back(static_cast<char>(0xE0 + IdxEnc * 4));
    unsigned SubOpcRR = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEncRR = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpcRR + RegEncRR));
    break;
  }

  case TLCS900II::SriRRImm: {
    // [prefix, 0x07, base_addr, idx_addr, SubOpc, imm bytes...]
    // Operand 0: base GPR, Operand 1: index GR16, Operand 2..: immediate.
    unsigned PrefixI = Opcode;
    if (Opcode < 0xF0)
      PrefixI += OpSize * 0x10;
    CB.push_back(static_cast<char>(PrefixI));
    CB.push_back(static_cast<char>(0x07)); // R+R 16-bit index mode
    CB.push_back(static_cast<char>(0xE0 + getRegEncoding(MI.getOperand(0)) * 4));
    CB.push_back(static_cast<char>(0xE0 + getRegEncoding(MI.getOperand(1)) * 4));
    CB.push_back(static_cast<char>(TLCS900II::getSubOpcode(TSFlags)));
    unsigned ImmBytesRR = Desc.getSize() - 5;
    for (unsigned i = 0; i < ImmBytesRR; ++i)
      CB.push_back(static_cast<char>(MI.getOperand(2 + i).getImm() & 0xFF));
    break;
  }

  case TLCS900II::SriRRQReg: {
    // [prefix, 0x07, base_addr, idx_addr + 2, SubOpc + data_reg_enc]
    // Same as SriRRReg, but the index names a PREVIOUS-BANK register: the
    // register-file address of a previous-bank word register is the current
    // bank's plus 2, which is how `lda xiz,xbc+qwa` reaches idx byte 0xE2.
    unsigned PrefixQ = Opcode;
    if (Opcode < 0xF0)
      PrefixQ += OpSize * 0x10;
    CB.push_back(static_cast<char>(PrefixQ));
    CB.push_back(static_cast<char>(0x07)); // R+R 16-bit index mode
    CB.push_back(static_cast<char>(0xE0 + getRegEncoding(MI.getOperand(1)) * 4));
    CB.push_back(
        static_cast<char>(0xE0 + getRegEncoding(MI.getOperand(2)) * 4 + 2));
    CB.push_back(static_cast<char>(TLCS900II::getSubOpcode(TSFlags) +
                                   getRegEncoding(MI.getOperand(0), OpSize)));
    break;
  }

  case TLCS900II::SriRR8Reg: {
    // [prefix, 0x03, base_addr, idx_addr, SubOpc + data_reg_enc]
    // Same as SriRRReg but with 0x03 mode byte (8-bit index).
    unsigned Prefix8 = Opcode;
    if (Opcode < 0xF0)
      Prefix8 += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix8));
    CB.push_back(static_cast<char>(0x03)); // R+R 8-bit index mode
    unsigned BaseEnc8 = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(0xE0 + BaseEnc8 * 4));
    unsigned IdxEnc8 = getRegEncoding(MI.getOperand(2));
    // 8-bit register file address.  The file is byte-addressed and the parts
    // are little-endian, so the LOW half of a word register sits at offset 0
    // and the HIGH half at offset 1: A=0xE0, W=0xE1, C=0xE4, B=0xE5, E=0xE8,
    // D=0xE9, L=0xEC, H=0xED (offsets 2 and 3 are the previous bank, which is
    // why LDA_RRQ adds 2).  This was written the other way round, so `ld_rr8w
    // bc,xix,w` emitted 0xE0 -- the address of A -- and only the one call site
    // in the tree kept the byte gate green, by naming the wrong register.
    // GR8 HWEncoding is W=0,A=1,B=2,C=3,D=4,E=5,H=6,L=7, hence the 1 - lsb.
    CB.push_back(
        static_cast<char>(0xE0 + (IdxEnc8 >> 1) * 4 + (1 - (IdxEnc8 & 1))));
    unsigned SubOpcRR8 = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEncRR8 = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpcRR8 + RegEncRR8));
    break;
  }

  case TLCS900II::SriRRUnary: {
    // [prefix, 0x07, base_addr, idx_addr, SubOpc + cc]
    // Operand 0: condition code (imm), Operand 1: base GPR, Operand 2: index GR16.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(0x07)); // R+R 16-bit index mode
    unsigned BaseEnc = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(0xE0 + BaseEnc * 4));
    unsigned IdxEnc = getRegEncoding(MI.getOperand(2));
    CB.push_back(static_cast<char>(0xE0 + IdxEnc * 4));
    unsigned SubOpcRR = TLCS900II::getSubOpcode(TSFlags);
    unsigned CC = MI.getOperand(0).getImm() & 0xF;
    CB.push_back(static_cast<char>(SubOpcRR + CC));
    break;
  }

  //=== Previous register bank (PrevBank) formats ===

  case TLCS900II::PrevBankRR: {
    // [0xD7, mode_byte(QR), SubOpc + data_reg_enc]
    // Operand 0: data register (GR16), Operand 1: Q register (PrevGR16).
    CB.push_back(static_cast<char>(0xD7));
    unsigned QEnc = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(0xE0 + QEnc * 4 + 2));
    unsigned SubOpc3 = TLCS900II::getSubOpcode(TSFlags);
    unsigned DataEnc = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpc3 + DataEnc));
    break;
  }

  case TLCS900II::PrevBankUnary: {
    // [0xD7, mode_byte(QR), SubOpc]
    // Operand 0: Q register (PrevGR16).
    CB.push_back(static_cast<char>(0xD7));
    unsigned QEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(0xE0 + QEnc * 4 + 2));
    unsigned SubOpc3 = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc3));
    break;
  }

  case TLCS900II::PrevBankSmallImm: {
    // [0xD7, mode_byte(QR), SubOpc + imm3]
    // Operand 0: small immediate (0-7), Operand 1: Q register (PrevGR16).
    CB.push_back(static_cast<char>(0xD7));
    unsigned QEnc = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(0xE0 + QEnc * 4 + 2));
    unsigned SubOpc3 = TLCS900II::getSubOpcode(TSFlags);
    unsigned Imm = MI.getOperand(0).getImm() & 0x7;
    CB.push_back(static_cast<char>(SubOpc3 + Imm));
    break;
  }

  case TLCS900II::PrevBankImmAfter: {
    // [0xD7, mode_byte(QR), SubOpc, imm_bytes...]
    // Operand 0: Q register (PrevGR16), Operand 1: trailing immediate.
    CB.push_back(static_cast<char>(0xD7));
    unsigned QEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(0xE0 + QEnc * 4 + 2));
    unsigned SubOpc3 = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc3));
    unsigned TrailingBytes = Desc.getSize() - 3;
    emitImmediate(MI.getOperand(1).getImm(), TrailingBytes, CB, &MI);
    break;
  }

  case TLCS900II::RIUnary: {
    // [prefix, MEMsri_bytes..., SubOpc]
    // Operand 0-2: MEMsri (mode, lo, hi).
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    unsigned Mode = MI.getOperand(0).getImm();
    CB.push_back(static_cast<char>(Mode & 0xFF));
    unsigned ModeType = Mode & 0x03;
    if (ModeType != 0) {
      CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
      CB.push_back(static_cast<char>(MI.getOperand(2).getImm() & 0xFF));
    }
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::RIImmAfter: {
    // [prefix, MEMsri_bytes..., SubOpc, imm_bytes...]
    // Operand 0-2: MEMsri (mode, lo, hi), remaining: trailing imm.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    unsigned Mode = MI.getOperand(0).getImm();
    CB.push_back(static_cast<char>(Mode & 0xFF));
    unsigned ModeType = Mode & 0x03;
    unsigned NextOp = 1;
    if (ModeType != 0) {
      CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
      CB.push_back(static_cast<char>(MI.getOperand(2).getImm() & 0xFF));
      NextOp = 3;
    }
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    for (unsigned i = NextOp, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    break;
  }

  case TLCS900II::D8Reg: {
    // [prefix, addr8, SubOpc + reg_enc]
    // Operand 0: data register, Operand 1: addr8.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned RegEnc = getRegEncoding(MI.getOperand(0), OpSize);
    CB.push_back(static_cast<char>(SubOpc + RegEnc));
    break;
  }

  case TLCS900II::D8Unary: {
    // [prefix, addr8, SubOpc]
    // Operand 0: addr8.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(0).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::D8ImmAfter: {
    // [prefix, addr8, SubOpc, imm_bytes...]
    // Operand 0: addr8, remaining: trailing imm.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    CB.push_back(static_cast<char>(MI.getOperand(0).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    for (unsigned i = 1, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    break;
  }

  case TLCS900II::ExtImmMod: {
    // [prefix, raw_addr_bytes..., SubOpc + op0_mod]
    // Operand 0: modifier (immediate or register), remaining: raw address bytes.
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    for (unsigned i = 1, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
    }
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    const MCOperand &ModOp = MI.getOperand(0);
    unsigned Mod = ModOp.isReg() ? getRegEncoding(ModOp, OpSize)
                                 : (ModOp.getImm() & 0xFF);
    CB.push_back(static_cast<char>(SubOpc + Mod));
    break;
  }

  case TLCS900II::RIImmMod: {
    // [prefix, MEMsri_bytes..., SubOpc + op0_imm]
    // Operand 0: immediate modifier, Operands 1-3: MEMsri (mode, lo, hi).
    unsigned Prefix = Opcode;
    if (Opcode < 0xF0)
      Prefix += OpSize * 0x10;
    CB.push_back(static_cast<char>(Prefix));
    unsigned Mode = MI.getOperand(1).getImm();
    CB.push_back(static_cast<char>(Mode & 0xFF));
    unsigned ModeType = Mode & 0x03;
    if (ModeType != 0) {
      CB.push_back(static_cast<char>(MI.getOperand(2).getImm() & 0xFF));
      CB.push_back(static_cast<char>(MI.getOperand(3).getImm() & 0xFF));
    }
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned Mod = MI.getOperand(0).getImm() & 0xFF;
    CB.push_back(static_cast<char>(SubOpc + Mod));
    break;
  }

  case TLCS900II::MemRegSuffix: {
    // [PrefixBase + reg_enc, SubOpcode]
    // Operand 0: GPR register.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + RegEnc));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::MemRegDispSuffix: {
    // [PrefixBase + reg_enc, disp8, SubOpcode]
    // Operand 0: GPR register, Operand 1: displacement (i32imm).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + RegEnc));
    CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    break;
  }

  case TLCS900II::MemRegImmMod: {
    // [PrefixBase + reg_enc, SubOpcode + modifier]
    // Operand 0: GPR register, Operand 1: immediate modifier (bit#).
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + RegEnc));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned Mod = MI.getOperand(1).getImm() & 0xFF;
    CB.push_back(static_cast<char>(SubOpc + Mod));
    break;
  }

  case TLCS900II::MemRegRegSuffix: {
    // [PrefixBase + addr_reg_enc, SubOpcode | data_reg_enc]
    // Operand 0: address GPR, Operand 1: data register.
    unsigned AddrRegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + AddrRegEnc));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned DataRegEnc = getRegEncoding(MI.getOperand(1));
    CB.push_back(static_cast<char>(SubOpc | DataRegEnc));
    break;
  }

  case TLCS900II::MemRegRegDispSuffix: {
    // [PrefixBase + addr_reg_enc, disp8, SubOpcode | data_reg_enc]
    // Operand 0: address GPR, Operand 1: displacement, Operand 2: data register.
    unsigned AddrRegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + AddrRegEnc));
    CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    unsigned DataRegEnc = getRegEncoding(MI.getOperand(2));
    CB.push_back(static_cast<char>(SubOpc | DataRegEnc));
    break;
  }

  case TLCS900II::MemRegImmAfter: {
    // [PrefixBase + reg_enc, SubOpcode, imm_bytes...]
    // Operand 0: GPR register, remaining: immediate byte operands.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + RegEnc));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    unsigned ImmBytes = Desc.getSize() - 2;
    for (unsigned i = 0; i < ImmBytes; ++i) {
      CB.push_back(static_cast<char>(MI.getOperand(1 + i).getImm() & 0xFF));
    }
    break;
  }

  case TLCS900II::MemRegDispImmAfter: {
    // [PrefixBase + reg_enc, disp8, SubOpcode, imm_bytes...]
    // Operand 0: GPR register, Operand 1: displacement, remaining: imm bytes.
    unsigned RegEnc = getRegEncoding(MI.getOperand(0));
    CB.push_back(static_cast<char>(Opcode + RegEnc));
    CB.push_back(static_cast<char>(MI.getOperand(1).getImm() & 0xFF));
    unsigned SubOpc = TLCS900II::getSubOpcode(TSFlags);
    CB.push_back(static_cast<char>(SubOpc));
    unsigned ImmBytes = Desc.getSize() - 3;
    for (unsigned i = 0; i < ImmBytes; ++i) {
      CB.push_back(static_cast<char>(MI.getOperand(2 + i).getImm() & 0xFF));
    }
    break;
  }
  }
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
