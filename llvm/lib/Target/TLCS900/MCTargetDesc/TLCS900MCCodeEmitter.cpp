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
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/EndianStream.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-mccodeemitter"

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
                                         SmallVectorImpl<char> &CB) const {
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
    switch (Kind) {
    case FK_Data_1:
    case (MCFixupKind)TLCS900::fixup_tlcs900_rel8:
    case (MCFixupKind)TLCS900::fixup_tlcs900_disp8:
      NumBytes = 1;
      break;
    case FK_Data_2:
    case (MCFixupKind)TLCS900::fixup_tlcs900_rel16:
    case (MCFixupKind)TLCS900::fixup_tlcs900_disp16:
      NumBytes = 2;
      break;
    case (MCFixupKind)TLCS900::fixup_tlcs900_24:
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
    switch (Kind) {
    case FK_Data_1:
    case (MCFixupKind)TLCS900::fixup_tlcs900_rel8:
    case (MCFixupKind)TLCS900::fixup_tlcs900_disp8:
      NumBytes = 1;
      break;
    case FK_Data_2:
    case (MCFixupKind)TLCS900::fixup_tlcs900_rel16:
    case (MCFixupKind)TLCS900::fixup_tlcs900_disp16:
      NumBytes = 2;
      break;
    case (MCFixupKind)TLCS900::fixup_tlcs900_24:
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
    const MCExpr *Expr = MO.getExpr();
    if (Kind == (MCFixupKind)TLCS900::fixup_tlcs900_rel8) {
      Expr = MCBinaryExpr::createAdd(
          Expr, MCConstantExpr::create(-1, Ctx), Ctx);
    } else if (Kind == (MCFixupKind)TLCS900::fixup_tlcs900_rel16) {
      Expr = MCBinaryExpr::createAdd(
          Expr, MCConstantExpr::create(-2, Ctx), Ctx);
    }
    Fixups.push_back(MCFixup::create(FixupOffset, Expr, Kind));
    for (unsigned i = 0; i < NumBytes; ++i)
      CB.push_back(0);
  }
}

unsigned TLCS900MCCodeEmitter::emitMemPrefix(
    const MCInst &MI, unsigned BaseOpIdx, unsigned DispOpIdx, bool IsDstMem,
    unsigned OpSize, uint64_t StartByte, SmallVectorImpl<char> &CB,
    SmallVectorImpl<MCFixup> &Fixups) const {
  const MCOperand &BaseOp = MI.getOperand(BaseOpIdx);

  // Direct addressing: base is a symbol expression (global address).
  // Destination memory uses F2 prefix (dispatches to B0/F0 table — all sizes).
  // Source memory uses E2 prefix (dispatches to E0 table — 32-bit ONLY).
  // Byte/word source memory loads from globals must be lowered by ISel into
  // address materialization + register-indirect load, since the E0 table
  // has no 8/16-bit load sub-opcodes.
  if (BaseOp.isExpr()) {
    if (!IsDstMem && OpSize != TLCS900II::OpSize32) {
      Ctx.reportError(MI.getLoc(),
          "byte/word direct memory load not encodable; "
          "ISel should have materialized the address first");
      return 0;
    }
    const MCOperand &DispOp = MI.getOperand(DispOpIdx);
    int64_t Disp = DispOp.isImm() ? DispOp.getImm() : 0;
    CB.push_back(IsDstMem ? 0xF2 : 0xE2);
    // Emit 24-bit address with fixup.  If there's a displacement (e.g.
    // global+offset), we'd need to fold it into the symbol expression,
    // but in practice the ISel folds offsets into the symbol operand.
    Fixups.push_back(MCFixup::create(
        CB.size() - StartByte, BaseOp.getExpr(),
        (MCFixupKind)TLCS900::fixup_tlcs900_24));
    emitImmediate(Disp, 3, CB);
    return 4;
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
    // (Xrr+d16) — 16-bit displacement, uses F3 prefix + mode byte + d16.
    // F3 dispatches to the destination-memory opcode table (B0/F0), which
    // is correct for MemStore and MemLoadDst (LDA) but not for MemLoad
    // or MemALU. The register allocator's eliminateFrameIndex splits
    // MemLoad/MemALU with large offsets into LDA + register-indirect,
    // so we should only reach here for destination-memory formats.
    if (!IsDstMem) {
      Ctx.reportError(MI.getLoc(),
          "displacement too large for source memory; "
          "use LDA to compute the effective address first");
      return 0;
    }
    CB.push_back(0xF3);
    // Mode byte: bits 1-0 = 001 (Xrr+d16), bits 4-2 = base_reg.
    CB.push_back((BaseReg << 2) | 0x01);
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
    SmallVectorImpl<char> &CB) const {
  int64_t Addr = AddrOp.isImm() ? AddrOp.getImm() : 0;
  if (Is24Bit) {
    CB.push_back(IsDstMem ? 0xF2
                           : (0xC2 + OpSize * 0x10));
    emitImmediate(Addr, 3, CB);
  } else {
    CB.push_back(IsDstMem ? 0xF1
                           : (0xC1 + OpSize * 0x10));
    emitImmediate(Addr, 2, CB);
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
      CB.push_back(static_cast<char>(Imm & 0x7));
    } else if (Opcode == 0xF8) {
      // SWI num: immediate encoded in opcode bits 0-2.
      unsigned Imm = ImmOp.isImm() ? ImmOp.getImm() : 0;
      CB.push_back(Opcode + (Imm & 0x7));
    } else if (Opcode == 0x0B || Opcode == 0x0F) {
      // PUSHW/RETD: opcode + 16-bit immediate.
      CB.push_back(Opcode);
      if (ImmOp.isImm())
        emitImmediate(ImmOp.getImm(), 2, CB);
      else
        emitFixup(MI, ImmOp, CB.size() - StartByte, FK_Data_2, CB, Fixups);
    } else {
      CB.push_back(Opcode);
      if (ImmOp.isImm())
        CB.push_back(static_cast<char>(ImmOp.getImm() & 0xFF));
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
      emitImmediate(ImmOp.getImm(), ImmBytes, CB);
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
    MCFixupKind ImmFixupKind = (ImmBytes == 1)   ? FK_Data_1
                               : (ImmBytes == 2) ? FK_Data_2
                                                  : FK_Data_4;
    if (ImmOp.isImm()) {
      emitImmediate(ImmOp.getImm(), ImmBytes, CB);
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
        emitImmediate(SrcOp.getImm(), ImmBytes, CB);
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
        emitImmediate(SrcOp.getImm(), ImmBytes, CB);
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
      emitImmediate(ImmOp.getImm(), ImmBytes, CB);
    else
      emitFixup(MI, ImmOp, CB.size() - StartByte,
                ImmBytes == 1 ? FK_Data_1 : FK_Data_2, CB, Fixups);
    break;
  }

  case TLCS900II::Branch24: {
    // 0x1B + 24-bit absolute address.
    CB.push_back(Opcode);
    const MCOperand &Target = MI.getOperand(0);
    if (Target.isImm()) {
      emitImmediate(Target.getImm(), 3, CB);
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
      emitImmediate(Target.getImm(), 2, CB);
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
    if (MI.getNumOperands() >= 2 && MI.getOperand(0).isImm()) {
      // Conditional: 0x60 + cc, d8.
      unsigned CC = MI.getOperand(0).getImm();
      CB.push_back(Opcode + (CC & 0xF));
      const MCOperand &Target = MI.getOperand(1);
      if (Target.isImm())
        CB.push_back(static_cast<char>(Target.getImm() & 0xFF));
      else
        emitFixup(MI, Target, CB.size() - StartByte,
                  (MCFixupKind)TLCS900::fixup_tlcs900_rel8, CB, Fixups);
    } else {
      // Unconditional: opcode already includes T condition.
      CB.push_back(Opcode);
      const MCOperand &Target = MI.getOperand(0);
      if (Target.isImm())
        CB.push_back(static_cast<char>(Target.getImm() & 0xFF));
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
        emitImmediate(Target.getImm(), 2, CB);
      else
        emitFixup(MI, Target, CB.size() - StartByte,
                  (MCFixupKind)TLCS900::fixup_tlcs900_rel16, CB, Fixups);
    } else {
      CB.push_back(Opcode);
      const MCOperand &Target = MI.getOperand(0);
      if (Target.isImm())
        emitImmediate(Target.getImm(), 2, CB);
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
      emitImmediate(Target.getImm(), 3, CB);
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
      emitImmediate(Target.getImm(), 2, CB);
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
    if (Target.isImm())
      CB.push_back(static_cast<char>(Target.getImm() & 0xFF));
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
      emitImmediate(ImmOp.getImm(), ImmBytes, CB);
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
    unsigned RegEnc = getRegEncoding(MI.getOperand(RegIdx), OpSize);
    emitDirectAddrPrefix(MI.getOperand(AddrIdx), /*IsDstMem=*/false, OpSize,
                         Is24Bit, CB);
    CB.push_back(Opcode + RegEnc);
    break;
  }

  case TLCS900II::DirectSrcImm: {
    // src_direct_prefix + addr + opcode + imm.
    // op 0 = addr, op 1 = imm.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, CB);
    CB.push_back(Opcode);
    const MCOperand &ImmOp = MI.getOperand(1);
    if (ImmOp.isImm())
      emitImmediate(ImmOp.getImm(), ImmBytes, CB);
    else
      emitFixup(MI, ImmOp, CB.size() - StartByte,
                ImmBytes == 1 ? FK_Data_1 : FK_Data_2, CB, Fixups);
    break;
  }

  case TLCS900II::DirectSrcIncDec: {
    // src_direct_prefix + addr + (opcode + count%8).
    // op 0 = addr, op 1 = count.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, CB);
    unsigned Count =
        MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 1;
    CB.push_back(Opcode + (Count & 0x7));
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
                         Is24Bit, CB);
    CB.push_back(Opcode + RegEnc);
    break;
  }

  case TLCS900II::DirectDstImm: {
    // F1/F2 + addr + opcode + imm.
    // op 0 = addr, op 1 = imm.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/true, OpSize,
                         Is24Bit, CB);
    CB.push_back(Opcode);
    const MCOperand &ImmOp = MI.getOperand(1);
    if (ImmOp.isImm())
      emitImmediate(ImmOp.getImm(), ImmBytes, CB);
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
                         Is24Bit, CB);
    unsigned BitNum =
        MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 0;
    CB.push_back(Opcode + (BitNum & 0xF));
    break;
  }

  case TLCS900II::DirectMemToMem: {
    // src_direct_prefix + src_addr16 + opcode(0x19) + dst_addr16.
    // op 0 = src_addr, op 1 = dst_addr.
    emitDirectAddrPrefix(MI.getOperand(0), /*IsDstMem=*/false, OpSize,
                         Is24Bit, CB);
    CB.push_back(Opcode);
    const MCOperand &DstAddr = MI.getOperand(1);
    if (DstAddr.isImm())
      emitImmediate(DstAddr.getImm(), Is24Bit ? 3 : 2, CB);
    break;
  }

  case TLCS900II::LdIoImm: {
    // 0x08 + addr8 + imm8. op 0 = addr, op 1 = imm.
    CB.push_back(Opcode);
    CB.push_back(MI.getOperand(0).isImm() ? MI.getOperand(0).getImm() : 0);
    CB.push_back(MI.getOperand(1).isImm() ? MI.getOperand(1).getImm() : 0);
    break;
  }

  case TLCS900II::ExtPrefix: {
    // Generic extended prefix: emit all operands as literal bytes.
    // Used for C3/C5/C7/D3/D5/D7/E3/E5/E7/F0/F3/F5 prefix instructions
    // where the addressing mode is not yet fully modeled.
    for (unsigned i = 0, e = MI.getNumOperands(); i != e; ++i) {
      const MCOperand &MO = MI.getOperand(i);
      if (MO.isImm())
        CB.push_back(static_cast<char>(MO.getImm() & 0xFF));
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
