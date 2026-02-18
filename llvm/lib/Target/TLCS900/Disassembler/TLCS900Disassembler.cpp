//===-- TLCS900Disassembler.cpp - Disassembler for TLCS900 --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the TLCS900Disassembler class. The TLCS-900/H2 uses
// variable-length instructions (1-7 bytes) with a prefix-based encoding that
// cannot be auto-generated from TableGen Inst{} fields, so all decoding is
// done manually in C++.
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/TLCS900MCTargetDesc.h"
#include "TargetInfo/TLCS900TargetInfo.h"
#include "llvm/MC/MCDecoderOps.h"
#include "llvm/MC/MCDisassembler/MCDisassembler.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-disassembler"

namespace {

class TLCS900Disassembler : public MCDisassembler {
public:
  TLCS900Disassembler(const MCSubtargetInfo &STI, MCContext &Ctx)
      : MCDisassembler(STI, Ctx) {}
  ~TLCS900Disassembler() override = default;

  DecodeStatus getInstruction(MCInst &Instr, uint64_t &Size,
                              ArrayRef<uint8_t> Bytes, uint64_t Address,
                              raw_ostream &CStream) const override;

private:
  DecodeStatus decodeRegPrefix(MCInst &MI, uint64_t &Size,
                               ArrayRef<uint8_t> Bytes,
                               unsigned PrefixReg) const;
  DecodeStatus decodeMemPrefix(MCInst &MI, uint64_t &Size,
                               ArrayRef<uint8_t> Bytes, unsigned BaseReg,
                               int64_t Disp, unsigned PrefixSize) const;
};

} // end anonymous namespace

// Map 3-bit register encoding to LLVM register number.
static unsigned decodeGPR(unsigned Enc) {
  static const unsigned GPRDecoderTable[] = {
      TLCS900::XWA, TLCS900::XBC, TLCS900::XDE, TLCS900::XHL,
      TLCS900::XIX, TLCS900::XIY, TLCS900::XIZ, TLCS900::XSP};
  assert(Enc < 8 && "Invalid register encoding");
  return GPRDecoderTable[Enc];
}

static uint16_t readU16LE(ArrayRef<uint8_t> Bytes, unsigned Offset) {
  return Bytes[Offset] | (static_cast<uint16_t>(Bytes[Offset + 1]) << 8);
}

static uint32_t readU32LE(ArrayRef<uint8_t> Bytes, unsigned Offset) {
  return Bytes[Offset] | (static_cast<uint32_t>(Bytes[Offset + 1]) << 8) |
         (static_cast<uint32_t>(Bytes[Offset + 2]) << 16) |
         (static_cast<uint32_t>(Bytes[Offset + 3]) << 24);
}

// Helper: emit a simple instruction with no operands.
static MCDisassembler::DecodeStatus
decodeSingleByte(MCInst &MI, uint64_t &Size, unsigned Opcode) {
  MI.setOpcode(Opcode);
  Size = 1;
  return MCDisassembler::Success;
}

// Helper: emit a unary prefix instruction (rd = rd, tied input).
static MCDisassembler::DecodeStatus
decodePrefixUnary(MCInst &MI, uint64_t &Size, unsigned Opcode, unsigned Reg) {
  MI.setOpcode(Opcode);
  MI.addOperand(MCOperand::createReg(Reg));
  MI.addOperand(MCOperand::createReg(Reg));
  Size = 2;
  return MCDisassembler::Success;
}

// Helper: emit a two-address reg-reg ALU instruction (rd = rd op rs2).
static MCDisassembler::DecodeStatus decodePrefixRegReg(MCInst &MI,
                                                       uint64_t &Size,
                                                       unsigned Opcode,
                                                       unsigned DstReg,
                                                       unsigned SrcReg) {
  MI.setOpcode(Opcode);
  MI.addOperand(MCOperand::createReg(DstReg));
  MI.addOperand(MCOperand::createReg(DstReg));
  MI.addOperand(MCOperand::createReg(SrcReg));
  Size = 2;
  return MCDisassembler::Success;
}

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeRegPrefix(MCInst &MI, uint64_t &Size,
                                                  ArrayRef<uint8_t> Bytes,
                                                  unsigned PrefixReg) const {
  if (Bytes.size() < 2)
    return MCDisassembler::Fail;

  unsigned Reg = decodeGPR(PrefixReg);
  uint8_t SecondByte = Bytes[1];

  // --- Fixed second-byte opcodes ---
  switch (SecondByte) {
  case 0x06: // CPL
    return decodePrefixUnary(MI, Size, TLCS900::CPL32, Reg);
  case 0x07: // NEG
    return decodePrefixUnary(MI, Size, TLCS900::NEG32, Reg);
  case 0x10: // DAA
    return decodePrefixUnary(MI, Size, TLCS900::DAA32, Reg);
  case 0x12: // EXTZ
    return decodePrefixUnary(MI, Size, TLCS900::EXTZ32, Reg);
  case 0x13: // EXTS
    return decodePrefixUnary(MI, Size, TLCS900::EXTS32, Reg);

  // DJNZ: prefix(rd) + 0x1C + d8 — 3 bytes
  case 0x1C: {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    int8_t Disp = static_cast<int8_t>(Bytes[2]);
    MI.setOpcode(TLCS900::DJNZ32);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = 3;
    return MCDisassembler::Success;
  }

  // Bit operations: prefix + opcode + bit_number — 3 bytes
  case 0x30: // RES
  case 0x31: // SET
  case 0x32: // CHG
  case 0x33: // BIT
  case 0x34: // TSET
  {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned BitNum = Bytes[2] & 0x1F;
    if (SecondByte == 0x33) {
      // BIT: no output, operands are (bit, reg)
      MI.setOpcode(TLCS900::BIT32);
      MI.addOperand(MCOperand::createImm(BitNum));
      MI.addOperand(MCOperand::createReg(Reg));
    } else {
      // SET/RES/CHG/TSET: output, operands are (rd, bit, rs1_tied)
      unsigned Opc;
      switch (SecondByte) {
      case 0x30:
        Opc = TLCS900::RES32;
        break;
      case 0x31:
        Opc = TLCS900::SET32;
        break;
      case 0x32:
        Opc = TLCS900::CHG32;
        break;
      case 0x34:
        Opc = TLCS900::TSET32;
        break;
      default:
        llvm_unreachable("handled above");
      }
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createImm(BitNum));
      MI.addOperand(MCOperand::createReg(Reg));
    }
    Size = 3;
    return MCDisassembler::Success;
  }

  // Rotate: prefix + opcode + count(1) — 3 bytes
  case 0xE8: // RLC
  case 0xE9: // RRC
  case 0xEA: // RL
  case 0xEB: // RR
  {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned Opc;
    switch (SecondByte) {
    case 0xE8:
      Opc = TLCS900::RLC32;
      break;
    case 0xE9:
      Opc = TLCS900::RRC32;
      break;
    case 0xEA:
      Opc = TLCS900::RL32;
      break;
    case 0xEB:
      Opc = TLCS900::RR32;
      break;
    default:
      llvm_unreachable("handled above");
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 3;
    return MCDisassembler::Success;
  }

  // Shift immediate: prefix + opcode + amount — 3 bytes
  case 0xEC: // SLA
  case 0xED: // SRA
  case 0xEF: // SRL
  {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned Amount = Bytes[2];
    unsigned Opc;
    switch (SecondByte) {
    case 0xEC:
      Opc = TLCS900::SLA32ri;
      break;
    case 0xED:
      Opc = TLCS900::SRA32ri;
      break;
    case 0xEF:
      Opc = TLCS900::SRL32ri;
      break;
    default:
      llvm_unreachable("handled above");
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Amount));
    Size = 3;
    return MCDisassembler::Success;
  }

  default:
    break;
  }

  // --- INC/DEC: prefix + (base_opcode | count-1) — 2 bytes ---
  if (SecondByte >= 0x60 && SecondByte <= 0x67) {
    unsigned Count = (SecondByte & 0x7) + 1;
    MI.setOpcode(TLCS900::INC32);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Count));
    Size = 2;
    return MCDisassembler::Success;
  }
  if (SecondByte >= 0x68 && SecondByte <= 0x6F) {
    unsigned Count = (SecondByte & 0x7) + 1;
    MI.setOpcode(TLCS900::DEC32);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Count));
    Size = 2;
    return MCDisassembler::Success;
  }

  // --- Register-immediate ALU: prefix(rd) + opcode + imm32 — 6 bytes ---
  if (SecondByte >= 0xC8 && SecondByte <= 0xCF) {
    if (Bytes.size() < 6)
      return MCDisassembler::Fail;
    uint32_t Imm = readU32LE(Bytes, 2);
    if (SecondByte == 0xCF) {
      // CP: no output, operands are (rs1, imm)
      MI.setOpcode(TLCS900::CP32ri);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createImm(Imm));
    } else {
      unsigned Opc;
      switch (SecondByte) {
      case 0xC8:
        Opc = TLCS900::ADD32ri;
        break;
      case 0xC9:
        Opc = TLCS900::ADC32ri;
        break;
      case 0xCA:
        Opc = TLCS900::SUB32ri;
        break;
      case 0xCB:
        Opc = TLCS900::SBC32ri;
        break;
      case 0xCC:
        Opc = TLCS900::AND32ri;
        break;
      case 0xCD:
        Opc = TLCS900::XOR32ri;
        break;
      case 0xCE:
        Opc = TLCS900::OR32ri;
        break;
      default:
        return MCDisassembler::Fail;
      }
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createImm(Imm));
    }
    Size = 6;
    return MCDisassembler::Success;
  }

  // --- Register-register ALU: src_prefix + (opcode | dst) — 2 bytes ---
  // PrefixReg is the SOURCE register for these operations.
  if (SecondByte >= 0x80) {
    unsigned DstEnc = SecondByte & 0x7;
    unsigned AluOpc = SecondByte & 0xF8;
    unsigned DstReg = decodeGPR(DstEnc);
    unsigned SrcReg = decodeGPR(PrefixReg);

    switch (AluOpc) {
    case 0x80: // ADD rr
      return decodePrefixRegReg(MI, Size, TLCS900::ADD32rr, DstReg, SrcReg);
    case 0x88: // LD rr (no tied operand)
      MI.setOpcode(TLCS900::LD32rr);
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createReg(SrcReg));
      Size = 2;
      return MCDisassembler::Success;
    case 0x90: // ADC rr
      return decodePrefixRegReg(MI, Size, TLCS900::ADC32rr, DstReg, SrcReg);
    case 0xA0: // SUB rr
      return decodePrefixRegReg(MI, Size, TLCS900::SUB32rr, DstReg, SrcReg);
    case 0xB0: // SBC rr
      return decodePrefixRegReg(MI, Size, TLCS900::SBC32rr, DstReg, SrcReg);
    case 0xC0: // AND rr
      return decodePrefixRegReg(MI, Size, TLCS900::AND32rr, DstReg, SrcReg);
    case 0xD0: // XOR rr
      return decodePrefixRegReg(MI, Size, TLCS900::XOR32rr, DstReg, SrcReg);
    case 0xE0: // OR rr
      return decodePrefixRegReg(MI, Size, TLCS900::OR32rr, DstReg, SrcReg);
    case 0xF0: // CP rr (no output, no tied)
      MI.setOpcode(TLCS900::CP32rr);
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createReg(SrcReg));
      Size = 2;
      return MCDisassembler::Success;
    default:
      break;
    }
  }

  return MCDisassembler::Fail;
}

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeMemPrefix(MCInst &MI, uint64_t &Size,
                                                  ArrayRef<uint8_t> Bytes,
                                                  unsigned BaseReg,
                                                  int64_t Disp,
                                                  unsigned PrefixSize) const {
  unsigned OpByteIdx = PrefixSize;
  if (Bytes.size() <= OpByteIdx)
    return MCDisassembler::Fail;

  uint8_t OpByte = Bytes[OpByteIdx];
  unsigned Base = decodeGPR(BaseReg);

  // MemLoad: 0x20-0x27 = LD rd, (mem)
  if (OpByte >= 0x20 && OpByte <= 0x27) {
    unsigned DstReg = decodeGPR(OpByte & 0x7);
    MI.setOpcode(TLCS900::LD32rm);
    MI.addOperand(MCOperand::createReg(DstReg));
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // MemStore immediate: 0x08 = LD (mem), #imm32
  if (OpByte == 0x08) {
    if (Bytes.size() < OpByteIdx + 5)
      return MCDisassembler::Fail;
    uint32_t Imm = readU32LE(Bytes, OpByteIdx + 1);
    MI.setOpcode(TLCS900::LD32mi);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = PrefixSize + 5;
    return MCDisassembler::Success;
  }

  // MemStore register: 0x40-0x47 = LD (mem), rs
  if (OpByte >= 0x40 && OpByte <= 0x47) {
    unsigned SrcReg = decodeGPR(OpByte & 0x7);
    MI.setOpcode(TLCS900::LD32mr);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // MemALU register-source operations
  struct MemALURegEntry {
    uint8_t Base;
    unsigned Opcode;
  };
  static const MemALURegEntry MemALURegOps[] = {
      {0x80, TLCS900::ADD32mr}, {0xA0, TLCS900::SUB32mr},
      {0xC0, TLCS900::AND32mr}, {0xD0, TLCS900::XOR32mr},
      {0xE0, TLCS900::OR32mr},  {0xF0, TLCS900::CP32mr},
  };
  unsigned AluBase = OpByte & 0xF8;
  for (const auto &Op : MemALURegOps) {
    if (AluBase == Op.Base) {
      unsigned SrcReg = decodeGPR(OpByte & 0x7);
      MI.setOpcode(Op.Opcode);
      MI.addOperand(MCOperand::createReg(Base));
      MI.addOperand(MCOperand::createImm(Disp));
      MI.addOperand(MCOperand::createReg(SrcReg));
      Size = PrefixSize + 1;
      return MCDisassembler::Success;
    }
  }

  // MemALU immediate-source operations
  struct MemALUImmEntry {
    uint8_t Opc;
    unsigned Opcode;
  };
  static const MemALUImmEntry MemALUImmOps[] = {
      {0xC8, TLCS900::ADD32mi},
      {0xCA, TLCS900::SUB32mi},
      {0xCF, TLCS900::CP32mi},
  };
  for (const auto &Op : MemALUImmOps) {
    if (OpByte == Op.Opc) {
      if (Bytes.size() < OpByteIdx + 5)
        return MCDisassembler::Fail;
      uint32_t Imm = readU32LE(Bytes, OpByteIdx + 1);
      MI.setOpcode(Op.Opcode);
      MI.addOperand(MCOperand::createReg(Base));
      MI.addOperand(MCOperand::createImm(Disp));
      MI.addOperand(MCOperand::createImm(Imm));
      Size = PrefixSize + 5;
      return MCDisassembler::Success;
    }
  }

  return MCDisassembler::Fail;
}

MCDisassembler::DecodeStatus TLCS900Disassembler::getInstruction(MCInst &MI, uint64_t &Size,
                                                 ArrayRef<uint8_t> Bytes,
                                                 uint64_t Address,
                                                 raw_ostream &CStream) const {
  Size = 0;

  if (Bytes.empty())
    return MCDisassembler::Fail;

  uint8_t FirstByte = Bytes[0];

  // === Single-byte instructions ===
  switch (FirstByte) {
  case 0x00: // NOP
    return decodeSingleByte(MI, Size, TLCS900::NOP);
  case 0x06: // HALT
    return decodeSingleByte(MI, Size, TLCS900::HALT);
  case 0x07: // DI
    return decodeSingleByte(MI, Size, TLCS900::DI);
  case 0x0B: // RETI
    return decodeSingleByte(MI, Size, TLCS900::RETI);
  case 0x0E: // RET
    return decodeSingleByte(MI, Size, TLCS900::RET);

  // EI level: 0x08 + level (levels 0-2, 4-5; 3/6/7 conflict with RETI/RET/RETD)
  case 0x08:
  case 0x09:
  case 0x0A:
  case 0x0C:
  case 0x0D:
    MI.setOpcode(TLCS900::EI);
    MI.addOperand(MCOperand::createImm(FirstByte - 0x08));
    Size = 1;
    return MCDisassembler::Success;

  // RETD: 0x0F + d16 — 3 bytes
  case 0x0F:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::RETD);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1)));
    Size = 3;
    return MCDisassembler::Success;

  // === Block transfer instructions (single byte) ===
  case 0x10: // LDI
    return decodeSingleByte(MI, Size, TLCS900::LDI);
  case 0x11: // LDIR
    return decodeSingleByte(MI, Size, TLCS900::LDIR);
  case 0x12: // LDD
    return decodeSingleByte(MI, Size, TLCS900::LDD);
  case 0x13: // LDDR
    return decodeSingleByte(MI, Size, TLCS900::LDDR);
  case 0x14: // CPI
    return decodeSingleByte(MI, Size, TLCS900::CPI);
  case 0x15: // CPIR
    return decodeSingleByte(MI, Size, TLCS900::CPIR);
  case 0x16: // CPD
    return decodeSingleByte(MI, Size, TLCS900::CPD);
  case 0x17: // CPDR
    return decodeSingleByte(MI, Size, TLCS900::CPDR);

  // === JP absolute: 0x1C + addr24 — 4 bytes ===
  case 0x1C:
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::JP);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1) |
                                       (static_cast<uint32_t>(Bytes[3]) << 16)));
    Size = 4;
    return MCDisassembler::Success;

  // === CALL absolute: 0x1D + addr24 — 4 bytes ===
  case 0x1D:
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::CALL);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1) |
                                       (static_cast<uint32_t>(Bytes[3]) << 16)));
    Size = 4;
    return MCDisassembler::Success;

  // === CALR relative: 0x1E + d16 — 3 bytes ===
  case 0x1E:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::CALR);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1)));
    Size = 3;
    return MCDisassembler::Success;

  // === SWI: 0xF8 + num — 1 byte ===
  case 0xF8:
  case 0xF9:
  case 0xFA:
  case 0xFB:
  case 0xFC:
  case 0xFD:
  case 0xFE:
  case 0xFF:
    MI.setOpcode(TLCS900::SWI);
    MI.addOperand(MCOperand::createImm(FirstByte - 0xF8));
    Size = 1;
    return MCDisassembler::Success;

  default:
    break;
  }

  // === LD r32, #imm32: 0x40+r, imm32 — 5 bytes ===
  if (FirstByte >= 0x40 && FirstByte <= 0x47) {
    if (Bytes.size() < 5)
      return MCDisassembler::Fail;
    unsigned Reg = decodeGPR(FirstByte & 0x7);
    MI.setOpcode(TLCS900::LD32ri);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(readU32LE(Bytes, 1)));
    Size = 5;
    return MCDisassembler::Success;
  }

  // === PUSH r32: 0x48+r — 1 byte ===
  if (FirstByte >= 0x48 && FirstByte <= 0x4F) {
    unsigned Reg = decodeGPR(FirstByte & 0x7);
    MI.setOpcode(TLCS900::PUSH32);
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 1;
    return MCDisassembler::Success;
  }

  // === POP r32: 0x58+r — 1 byte ===
  if (FirstByte >= 0x58 && FirstByte <= 0x5F) {
    unsigned Reg = decodeGPR(FirstByte & 0x7);
    MI.setOpcode(TLCS900::POP32);
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 1;
    return MCDisassembler::Success;
  }

  // === JR / JRcc: 0x60+cc, d8 — 2 bytes ===
  if (FirstByte >= 0x60 && FirstByte <= 0x6F) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned CC = FirstByte & 0xF;
    int8_t Disp = static_cast<int8_t>(Bytes[1]);
    if (CC == 8) {
      // cc=T (always true) → unconditional JR
      MI.setOpcode(TLCS900::JR);
      MI.addOperand(MCOperand::createImm(Disp));
    } else {
      MI.setOpcode(TLCS900::JRcc);
      MI.addOperand(MCOperand::createImm(CC));
      MI.addOperand(MCOperand::createImm(Disp));
    }
    Size = 2;
    return MCDisassembler::Success;
  }

  // === JRL / JRLcc: 0x70+cc, d16 — 3 bytes ===
  if (FirstByte >= 0x70 && FirstByte <= 0x7F) {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned CC = FirstByte & 0xF;
    int16_t Disp = static_cast<int16_t>(readU16LE(Bytes, 1));
    if (CC == 8) {
      // cc=T → unconditional JRL
      MI.setOpcode(TLCS900::JRL);
      MI.addOperand(MCOperand::createImm(Disp));
    } else {
      MI.setOpcode(TLCS900::JRLcc);
      MI.addOperand(MCOperand::createImm(CC));
      MI.addOperand(MCOperand::createImm(Disp));
    }
    Size = 3;
    return MCDisassembler::Success;
  }

  // === Memory prefix (no displacement): 0xA0-0xA7 ===
  if (FirstByte >= 0xA0 && FirstByte <= 0xA7) {
    unsigned BaseReg = FirstByte & 0x7;
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, 0, 1);
  }

  // === Memory prefix (d8 displacement): 0xA8-0xAF ===
  if (FirstByte >= 0xA8 && FirstByte <= 0xAF) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned BaseReg = FirstByte & 0x7;
    int8_t Disp = static_cast<int8_t>(Bytes[1]);
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, Disp, 2);
  }

  // === CALL/JP indirect: 0xB0+reg, opcode — 2 bytes ===
  if (FirstByte >= 0xB0 && FirstByte <= 0xB7) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned Reg = decodeGPR(FirstByte & 0x7);
    if (Bytes[1] == 0x1F) {
      MI.setOpcode(TLCS900::CALL_r);
      MI.addOperand(MCOperand::createReg(Reg));
      Size = 2;
      return MCDisassembler::Success;
    }
    if (Bytes[1] == 0x1C) {
      MI.setOpcode(TLCS900::JP_r);
      MI.addOperand(MCOperand::createReg(Reg));
      Size = 2;
      return MCDisassembler::Success;
    }
    return MCDisassembler::Fail;
  }

  // === 32-bit register prefix: 0xE8-0xEF ===
  if (FirstByte >= 0xE8 && FirstByte <= 0xEF) {
    return decodeRegPrefix(MI, Size, Bytes, FirstByte & 0x7);
  }

  // Unrecognized first byte
  return MCDisassembler::Fail;
}

static MCDisassembler *createTLCS900Disassembler(const Target &T,
                                                 const MCSubtargetInfo &STI,
                                                 MCContext &Ctx) {
  return new TLCS900Disassembler(STI, Ctx);
}

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900Disassembler() {
  TargetRegistry::RegisterMCDisassembler(getTheTLCS900Target(),
                                         createTLCS900Disassembler);
}
