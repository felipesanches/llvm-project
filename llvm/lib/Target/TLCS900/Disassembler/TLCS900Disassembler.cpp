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
  /// Unified register prefix decoder for 8/16/32-bit operations.
  /// OpSize: 0=8-bit, 1=16-bit, 2=32-bit.
  DecodeStatus decodeGenericRegPrefix(MCInst &MI, uint64_t &Size,
                                      ArrayRef<uint8_t> Bytes,
                                      unsigned PrefixReg,
                                      unsigned OpSize) const;
  DecodeStatus decodeRegPrefix(MCInst &MI, uint64_t &Size,
                               ArrayRef<uint8_t> Bytes,
                               unsigned PrefixReg) const;
  DecodeStatus decodeGR16Prefix(MCInst &MI, uint64_t &Size,
                                    ArrayRef<uint8_t> Bytes,
                                    unsigned PrefixReg) const;
  DecodeStatus decodeGR8Prefix(MCInst &MI, uint64_t &Size,
                                   ArrayRef<uint8_t> Bytes,
                                   unsigned PrefixReg) const;
  /// Decode a source/destination memory-prefixed instruction.
  /// MemSize: 0=byte, 1=word, 2=long (selects sub-opcode interpretations).
  /// IsDstMem: true for B0/B8 destination table, false for source tables.
  DecodeStatus decodeMemPrefix(MCInst &MI, uint64_t &Size,
                               ArrayRef<uint8_t> Bytes, unsigned BaseReg,
                               int64_t Disp, unsigned PrefixSize,
                               unsigned MemSize = 2,
                               bool IsDstMem = false) const;
  /// Decode a direct-address-prefixed instruction.
  /// IsDst: true = F1/F2 (destination), false = C1..E2 (source).
  /// OpSize: 0=byte, 1=word, 2=long.  AddrBytes: 2 or 3.
  DecodeStatus decodeDirectAddr(MCInst &MI, uint64_t &Size,
                                ArrayRef<uint8_t> Bytes, bool IsDst,
                                unsigned OpSize, unsigned AddrBytes) const;
  /// Decode an 8-bit direct address (I/O) prefixed instruction.
  DecodeStatus decodeD8Prefix(MCInst &MI, uint64_t &Size,
                              ArrayRef<uint8_t> Bytes,
                              unsigned OpSize,
                              bool IsDst = false) const;
  /// Decode a register-indirect complex (SRI) prefixed instruction.
  DecodeStatus decodeSRIPrefix(MCInst &MI, uint64_t &Size,
                               ArrayRef<uint8_t> Bytes, bool IsDst,
                               unsigned OpSize) const;
  /// Decode a post-increment/pre-decrement prefixed instruction.
  /// IsPostInc: true for post-increment (R+), false for pre-decrement (-R).
  DecodeStatus decodePIPrefix(MCInst &MI, uint64_t &Size,
                              ArrayRef<uint8_t> Bytes, bool IsDst,
                              unsigned OpSize, bool IsPostInc) const;
  /// Decode an extended register prefix (ERP) instruction.
  DecodeStatus decodeERPPrefix(MCInst &MI, uint64_t &Size,
                               ArrayRef<uint8_t> Bytes,
                               unsigned OpSize) const;
  /// Decode a previous register bank (PrevBank/D7) instruction.
  DecodeStatus decodePrevBankPrefix(MCInst &MI, uint64_t &Size,
                                    ArrayRef<uint8_t> Bytes) const;
};

} // end anonymous namespace

// Map 3-bit register encoding to LLVM register number (32-bit GPR).
static unsigned decodeGPR(unsigned Enc) {
  static const unsigned GPRDecoderTable[] = {
      TLCS900::XWA, TLCS900::XBC, TLCS900::XDE, TLCS900::XHL,
      TLCS900::XIX, TLCS900::XIY, TLCS900::XIZ, TLCS900::XSP};
  assert(Enc < 8 && "Invalid register encoding");
  return GPRDecoderTable[Enc];
}

// Map 3-bit register encoding to 8-bit GR8 register.
static unsigned decodeGR8(unsigned Enc) {
  static const unsigned GR8DecoderTable[] = {
      TLCS900::W, TLCS900::A, TLCS900::B, TLCS900::C,
      TLCS900::D, TLCS900::E, TLCS900::H, TLCS900::L};
  assert(Enc < 8 && "Invalid register encoding");
  return GR8DecoderTable[Enc];
}

// Map 3-bit register encoding to 16-bit GR16 register.
static unsigned decodeGR16(unsigned Enc) {
  static const unsigned GR16DecoderTable[] = {
      TLCS900::WA, TLCS900::BC, TLCS900::DE, TLCS900::HL,
      TLCS900::IX, TLCS900::IY, TLCS900::IZ, TLCS900::SP};
  assert(Enc < 8 && "Invalid register encoding");
  return GR16DecoderTable[Enc];
}

// Decode a register based on operand size (0=8-bit, 1=16-bit, 2=32-bit).
static unsigned decodeRegForSize(unsigned Enc, unsigned OpSize) {
  switch (OpSize) {
  case 0: return decodeGR8(Enc);
  case 1: return decodeGR16(Enc);
  default: return decodeGPR(Enc);
  }
}

static uint16_t readU16LE(ArrayRef<uint8_t> Bytes, unsigned Offset) {
  return Bytes[Offset] | (static_cast<uint16_t>(Bytes[Offset + 1]) << 8);
}

static uint32_t readU24LE(ArrayRef<uint8_t> Bytes, unsigned Offset) {
  return Bytes[Offset] | (static_cast<uint32_t>(Bytes[Offset + 1]) << 8) |
         (static_cast<uint32_t>(Bytes[Offset + 2]) << 16);
}

static uint32_t readU32LE(ArrayRef<uint8_t> Bytes, unsigned Offset) {
  return Bytes[Offset] | (static_cast<uint32_t>(Bytes[Offset + 1]) << 8) |
         (static_cast<uint32_t>(Bytes[Offset + 2]) << 16) |
         (static_cast<uint32_t>(Bytes[Offset + 3]) << 24);
}

// Read an N-byte little-endian immediate.
static uint32_t readImmLE(ArrayRef<uint8_t> Bytes, unsigned Offset,
                          unsigned NumBytes) {
  switch (NumBytes) {
  case 1: return Bytes[Offset];
  case 2: return readU16LE(Bytes, Offset);
  case 3: return readU24LE(Bytes, Offset);
  case 4: return readU32LE(Bytes, Offset);
  default: return 0;
  }
}

// Get the immediate size in bytes for a given operand size.
static unsigned immBytesForSize(unsigned OpSize) {
  return (OpSize == 0) ? 1 : (OpSize == 1) ? 2 : 4;
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

//===----------------------------------------------------------------------===//
// Opcode tables indexed by OpSize (0=8-bit, 1=16-bit, 2=32-bit)
//===----------------------------------------------------------------------===//

// ALU register-immediate: 0xC8=ADD, 0xC9=ADC, 0xCA=SUB, 0xCB=SBC,
//                          0xCC=AND, 0xCD=XOR, 0xCE=OR, 0xCF=CP
static const unsigned ALUri[3][8] = {
  {TLCS900::ADD8ri, TLCS900::ADC8ri, TLCS900::SUB8ri, TLCS900::SBC8ri,
   TLCS900::AND8ri, TLCS900::XOR8ri, TLCS900::OR8ri, TLCS900::CP8ri},
  {TLCS900::ADD16ri, TLCS900::ADC16ri, TLCS900::SUB16ri, TLCS900::SBC16ri,
   TLCS900::AND16ri, TLCS900::XOR16ri, TLCS900::OR16ri, TLCS900::CP16ri},
  {TLCS900::ADD32ri, TLCS900::ADC32ri, TLCS900::SUB32ri, TLCS900::SBC32ri,
   TLCS900::AND32ri, TLCS900::XOR32ri, TLCS900::OR32ri, TLCS900::CP32ri},
};

// ALU register-register base opcodes: 0x80=ADD, 0x90=ADC, 0xA0=SUB, 0xB0=SBC,
//                                      0xC0=AND, 0xD0=XOR, 0xE0=OR, 0xF0=CP
// Map (SecondByte & 0xF8) >> 3 to index: 0x80→0, 0x90→2, 0xA0→4, ...
// Simpler: use (SecondByte >> 4) - 8 as first-level, and ((SecondByte>>3)&1) for alt.
// Actually, just use a direct map from (base >> 4) & 0x7:
static const unsigned ALUrr[3][8] = {
  {TLCS900::ADD8rr, TLCS900::ADC8rr, TLCS900::SUB8rr, TLCS900::SBC8rr,
   TLCS900::AND8rr, TLCS900::XOR8rr, TLCS900::OR8rr, TLCS900::CP8rr},
  {TLCS900::ADD16rr, TLCS900::ADC16rr, TLCS900::SUB16rr, TLCS900::SBC16rr,
   TLCS900::AND16rr, TLCS900::XOR16rr, TLCS900::OR16rr, TLCS900::CP16rr},
  {TLCS900::ADD32rr, TLCS900::ADC32rr, TLCS900::SUB32rr, TLCS900::SBC32rr,
   TLCS900::AND32rr, TLCS900::XOR32rr, TLCS900::OR32rr, TLCS900::CP32rr},
};

static const unsigned LDrr[3] = {
    TLCS900::LD8rr_asm, TLCS900::LD16rr_asm, TLCS900::LD32rr};

static const unsigned CPLops[3] = {TLCS900::CPL8, TLCS900::CPL16, TLCS900::CPL32};
static const unsigned NEGops[3] = {TLCS900::NEG8, TLCS900::NEG16, TLCS900::NEG32};
static const unsigned EXTSops[3] = {TLCS900::EXTS8, TLCS900::EXTS16, TLCS900::EXTS32};
static const unsigned EXTZops[3] = {TLCS900::EXTZ8, TLCS900::EXTZ16, TLCS900::EXTZ32};
static const unsigned INCops[3] = {TLCS900::INC8, TLCS900::INC16, TLCS900::INC32};
static const unsigned DECops[3] = {TLCS900::DEC8, TLCS900::DEC16, TLCS900::DEC32};
static const unsigned DJNZops[3] = {TLCS900::DJNZ8, TLCS900::DJNZ16, TLCS900::DJNZ32};

static const unsigned BITops[3] = {TLCS900::BIT8, TLCS900::BIT16, TLCS900::BIT32};
static const unsigned SETops[3] = {TLCS900::SET8, TLCS900::SET16, TLCS900::SET32};
static const unsigned RESops[3] = {TLCS900::RES8, TLCS900::RES16, TLCS900::RES32};
// CHG: no 8-bit variant
static const unsigned CHGops[3] = {0, TLCS900::CHG16, TLCS900::CHG32};
// TSET: 32-bit only
static const unsigned TSETops[3] = {0, 0, TLCS900::TSET32};

static const unsigned RLCops[3] = {TLCS900::RLC8, TLCS900::RLC16, TLCS900::RLC32};
static const unsigned RRCops[3] = {TLCS900::RRC8, TLCS900::RRC16, TLCS900::RRC32};
static const unsigned RLops[3] = {TLCS900::RL8, TLCS900::RL16, TLCS900::RL32};
static const unsigned RRops[3] = {TLCS900::RR8, TLCS900::RR16, TLCS900::RR32};

static const unsigned SLAops[3] = {TLCS900::SLA8ri, TLCS900::SLA16ri, TLCS900::SLA32ri};
static const unsigned SRAops[3] = {TLCS900::SRA8ri, TLCS900::SRA16ri, TLCS900::SRA32ri};
static const unsigned SRLops[3] = {TLCS900::SRL8ri, TLCS900::SRL16ri, TLCS900::SRL32ri};
static const unsigned SLLops[3] = {TLCS900::SLL8ri, TLCS900::SLL16ri, TLCS900::SLL32ri};

// MUL/MULS/DIV/DIVS: 8-bit and 16-bit only (32-bit = 0 = invalid)
static const unsigned MULrr[3] = {TLCS900::MUL8rr, TLCS900::MUL16rr, 0};
static const unsigned MULSrr[3] = {TLCS900::MULS8rr, TLCS900::MULS16rr, 0};
static const unsigned DIVrr[3] = {TLCS900::DIV8rr, TLCS900::DIV16rr, 0};
static const unsigned DIVSrr[3] = {TLCS900::DIVS8rr, TLCS900::DIVS16rr, 0};
static const unsigned MULri[3] = {TLCS900::MUL8ri, TLCS900::MUL16ri, 0};
static const unsigned MULSri[3] = {TLCS900::MULS8ri, TLCS900::MULS16ri, 0};
static const unsigned DIVri[3] = {TLCS900::DIV8ri, TLCS900::DIV16ri, 0};
static const unsigned DIVSri[3] = {TLCS900::DIVS8ri, TLCS900::DIVS16ri, 0};

static const unsigned EXops[3] = {TLCS900::EX8, TLCS900::EX16, TLCS900::EX32};
static const unsigned SCCops[3] = {TLCS900::SCC8, TLCS900::SCC16, TLCS900::SCC32};
static const unsigned LDsmall[3] = {
    TLCS900::LD8ri_small, TLCS900::LD16ri_small, TLCS900::LD32ri_small};
static const unsigned CPsmall[3] = {
    TLCS900::CP8_small, TLCS900::CP16_small, TLCS900::CP32_small};
static const unsigned PUSHops[3] = {TLCS900::PUSH8, TLCS900::PUSH16, TLCS900::PUSH32};
static const unsigned POPops[3] = {TLCS900::POP8, TLCS900::POP16, TLCS900::POP32};
static const unsigned LDriPrefix[3] = {
    TLCS900::LD8ri_asm, TLCS900::LD16ri_asm, TLCS900::LD32ri};

//===----------------------------------------------------------------------===//
// Unified register prefix decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeGenericRegPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, unsigned PrefixReg,
    unsigned OpSize) const {
  if (Bytes.size() < 2)
    return MCDisassembler::Fail;

  unsigned Reg = decodeRegForSize(PrefixReg, OpSize);
  uint8_t SB = Bytes[1]; // Second byte
  unsigned ImmBytes = immBytesForSize(OpSize);

  // --- Fixed second-byte opcodes (2 or 3+ bytes) ---
  switch (SB) {
  // LD via prefix: prefix(rd) + 0x03 + imm
  case 0x03: {
    unsigned TotalSize = 2 + ImmBytes;
    if (Bytes.size() < TotalSize)
      return MCDisassembler::Fail;
    uint32_t Imm = readImmLE(Bytes, 2, ImmBytes);
    MI.setOpcode(LDriPrefix[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = TotalSize;
    return MCDisassembler::Success;
  }

  // PUSH via prefix: prefix(rs) + 0x04
  case 0x04:
    MI.setOpcode(PUSHops[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 2;
    return MCDisassembler::Success;

  // POP via prefix: prefix(rd) + 0x05
  case 0x05:
    MI.setOpcode(POPops[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 2;
    return MCDisassembler::Success;

  case 0x06: // CPL
    return decodePrefixUnary(MI, Size, CPLops[OpSize], Reg);
  case 0x07: // NEG
    return decodePrefixUnary(MI, Size, NEGops[OpSize], Reg);

  // MUL/MULS/DIV/DIVS immediate: prefix(rd) + opcode + imm (8/16-bit only)
  case 0x08: case 0x09: case 0x0A: case 0x0B: {
    if (OpSize >= 2)
      return MCDisassembler::Fail; // No 32-bit MUL/DIV
    unsigned TotalSize = 2 + ImmBytes;
    if (Bytes.size() < TotalSize)
      return MCDisassembler::Fail;
    uint32_t Imm = readImmLE(Bytes, 2, ImmBytes);
    const unsigned *Table;
    switch (SB) {
    case 0x08: Table = MULri; break;
    case 0x09: Table = MULSri; break;
    case 0x0A: Table = DIVri; break;
    case 0x0B: Table = DIVSri; break;
    default: llvm_unreachable("handled above");
    }
    MI.setOpcode(Table[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg)); // tied
    MI.addOperand(MCOperand::createImm(Imm));
    Size = TotalSize;
    return MCDisassembler::Success;
  }

  // DAA: only valid for 32-bit
  case 0x10:
    if (OpSize != 2)
      return MCDisassembler::Fail;
    return decodePrefixUnary(MI, Size, TLCS900::DAA32, Reg);

  case 0x12: // EXTZ
    return decodePrefixUnary(MI, Size, EXTZops[OpSize], Reg);
  case 0x13: // EXTS
    return decodePrefixUnary(MI, Size, EXTSops[OpSize], Reg);

  // DJNZ: prefix(rd) + 0x1C + d8 — 3 bytes
  case 0x1C: {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    int8_t Disp = static_cast<int8_t>(Bytes[2]);
    MI.setOpcode(DJNZops[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = 3;
    return MCDisassembler::Success;
  }

  // Bit operations: prefix + opcode + bit_number — 3 bytes
  case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned BitNum = Bytes[2] & 0x1F;
    if (SB == 0x33) {
      // BIT: no output, operands are (bit, reg)
      MI.setOpcode(BITops[OpSize]);
      MI.addOperand(MCOperand::createImm(BitNum));
      MI.addOperand(MCOperand::createReg(Reg));
    } else {
      unsigned Opc;
      switch (SB) {
      case 0x30: Opc = RESops[OpSize]; break;
      case 0x31: Opc = SETops[OpSize]; break;
      case 0x32: Opc = CHGops[OpSize]; break;
      case 0x34: Opc = TSETops[OpSize]; break;
      default: llvm_unreachable("handled above");
      }
      if (Opc == 0)
        return MCDisassembler::Fail; // Unsupported size
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createImm(BitNum));
      MI.addOperand(MCOperand::createReg(Reg));
    }
    Size = 3;
    return MCDisassembler::Success;
  }

  // Rotate: prefix + opcode + count(1) — 3 bytes
  case 0xE8: case 0xE9: case 0xEA: case 0xEB: {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    const unsigned *Table;
    switch (SB) {
    case 0xE8: Table = RLCops; break;
    case 0xE9: Table = RRCops; break;
    case 0xEA: Table = RLops; break;
    case 0xEB: Table = RRops; break;
    default: llvm_unreachable("handled above");
    }
    MI.setOpcode(Table[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 3;
    return MCDisassembler::Success;
  }

  // Shift immediate: prefix + opcode + amount — 3 bytes
  case 0xEC: case 0xED: case 0xEE: case 0xEF: {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned Amount = Bytes[2];
    const unsigned *Table;
    switch (SB) {
    case 0xEC: Table = SLAops; break;
    case 0xED: Table = SRAops; break;
    case 0xEE: Table = SLLops; break;
    case 0xEF: Table = SRLops; break;
    default: llvm_unreachable("handled above");
    }
    MI.setOpcode(Table[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Amount));
    Size = 3;
    return MCDisassembler::Success;
  }

  default:
    break;
  }

  // --- MUL/MULS/DIV/DIVS register-register: 0x40-0x5F (8/16-bit only) ---
  if (SB >= 0x40 && SB <= 0x5F) {
    if (OpSize >= 2)
      return MCDisassembler::Fail;
    unsigned SecondReg;
    // MUL16rr/MULS16rr/DIV16rr/DIVS16rr use GPR operands;
    // MUL8rr etc. use GR8.
    if (OpSize == 1)
      SecondReg = decodeGPR(SB & 0x7);
    else
      SecondReg = decodeGR8(SB & 0x7);

    const unsigned *Table;
    unsigned SubGroup = (SB >> 3) & 0x3;
    switch (SubGroup) {
    case 0: Table = MULrr; break;  // 0x40-0x47
    case 1: Table = MULSrr; break; // 0x48-0x4F
    case 2: Table = DIVrr; break;  // 0x50-0x57
    case 3: Table = DIVSrr; break; // 0x58-0x5F
    default: return MCDisassembler::Fail;
    }
    unsigned Opc = Table[OpSize];
    if (Opc == 0)
      return MCDisassembler::Fail;

    // For 16-bit: operands are (GPR dst, GPR src1_tied, GPR src2)
    // For 8-bit: operands are (GR8 rs1, GR8 rs2) — no output
    if (OpSize == 1) {
      unsigned PrefixRegGPR = decodeGPR(PrefixReg);
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(SecondReg));
      MI.addOperand(MCOperand::createReg(SecondReg));
      MI.addOperand(MCOperand::createReg(PrefixRegGPR));
    } else {
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(SecondReg));
      MI.addOperand(MCOperand::createReg(Reg));
    }
    Size = 2;
    return MCDisassembler::Success;
  }

  // --- INC/DEC: prefix + (base_opcode | I3) — 2 bytes ---
  if (SB >= 0x60 && SB <= 0x67) {
    unsigned I3 = SB & 0x7;
    unsigned Count = (I3 == 0) ? 8 : I3;
    MI.setOpcode(INCops[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Count));
    Size = 2;
    return MCDisassembler::Success;
  }
  if (SB >= 0x68 && SB <= 0x6F) {
    unsigned I3 = SB & 0x7;
    unsigned Count = (I3 == 0) ? 8 : I3;
    MI.setOpcode(DECops[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Count));
    Size = 2;
    return MCDisassembler::Success;
  }

  // --- SCC: prefix(rd) + (0x70 + cc) — 2 bytes ---
  if (SB >= 0x70 && SB <= 0x7F) {
    unsigned CC = SB & 0xF;
    MI.setOpcode(SCCops[OpSize]);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(CC));
    MI.addOperand(MCOperand::createReg(Reg)); // tied
    Size = 2;
    return MCDisassembler::Success;
  }

  // --- Register-register ALU & special ops: 0x80+ ---
  if (SB >= 0x80) {
    unsigned DstEnc = SB & 0x7;
    unsigned AluBase = SB & 0xF8;

    // LD small immediate (0-7): prefix(rd) + (0xA8 + imm3)
    if (AluBase == 0xA8) {
      unsigned SmallImm = SB & 0x7;
      MI.setOpcode(LDsmall[OpSize]);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createImm(SmallImm));
      Size = 2;
      return MCDisassembler::Success;
    }

    // EX register-register: prefix(rs1) + (0xB8 + rs2_enc)
    if (AluBase == 0xB8) {
      unsigned SecondReg = decodeRegForSize(DstEnc, OpSize);
      MI.setOpcode(EXops[OpSize]);
      MI.addOperand(MCOperand::createReg(SecondReg)); // $rd (from sub-opcode)
      MI.addOperand(MCOperand::createReg(Reg));       // $rs (from prefix)
      Size = 2;
      return MCDisassembler::Success;
    }

    // CP small immediate (0-7): prefix(rs) + (0xD8 + imm3)
    if (AluBase == 0xD8) {
      unsigned SmallImm = SB & 0x7;
      MI.setOpcode(CPsmall[OpSize]);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createImm(SmallImm));
      Size = 2;
      return MCDisassembler::Success;
    }

    // Register-immediate ALU: prefix(rd) + (0xC8-0xCF) + imm
    if (SB >= 0xC8 && SB <= 0xCF) {
      unsigned TotalSize = 2 + ImmBytes;
      if (Bytes.size() < TotalSize)
        return MCDisassembler::Fail;
      uint32_t Imm = readImmLE(Bytes, 2, ImmBytes);
      unsigned Idx = SB & 0x7;
      if (Idx == 7) {
        // CP: no output
        MI.setOpcode(ALUri[OpSize][7]);
        MI.addOperand(MCOperand::createReg(Reg));
        MI.addOperand(MCOperand::createImm(Imm));
      } else {
        MI.setOpcode(ALUri[OpSize][Idx]);
        MI.addOperand(MCOperand::createReg(Reg));
        MI.addOperand(MCOperand::createReg(Reg));
        MI.addOperand(MCOperand::createImm(Imm));
      }
      Size = TotalSize;
      return MCDisassembler::Success;
    }

    // Map AluBase to ALU rr table index.
    // 0x80=ADD(0), 0x90=ADC(1), 0xA0=SUB(2), 0xB0=SBC(3),
    // 0xC0=AND(4), 0xD0=XOR(5), 0xE0=OR(6), 0xF0=CP(7)
    // Note: 0x88=LD, 0x98/0xA8/0xB8/0xC8/0xD8/0xE8 handled separately
    unsigned AluIdx;
    switch (AluBase) {
    case 0x80: AluIdx = 0; break; // ADD
    case 0x88: {
      // LD rr (no tied operand)
      unsigned DstReg = decodeRegForSize(DstEnc, OpSize);
      MI.setOpcode(LDrr[OpSize]);
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createReg(Reg));
      Size = 2;
      return MCDisassembler::Success;
    }
    case 0x90: AluIdx = 1; break; // ADC
    case 0xA0: AluIdx = 2; break; // SUB
    case 0xB0: AluIdx = 3; break; // SBC
    case 0xC0: AluIdx = 4; break; // AND
    case 0xD0: AluIdx = 5; break; // XOR
    case 0xE0: AluIdx = 6; break; // OR
    case 0xF0: AluIdx = 7; break; // CP
    default:
      return MCDisassembler::Fail;
    }

    unsigned DstReg = decodeRegForSize(DstEnc, OpSize);
    unsigned SrcReg = Reg; // prefix register

    if (AluIdx == 7) {
      // CP rr (no output, no tied)
      MI.setOpcode(ALUrr[OpSize][7]);
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createReg(SrcReg));
    } else {
      MI.setOpcode(ALUrr[OpSize][AluIdx]);
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createReg(SrcReg));
    }
    Size = 2;
    return MCDisassembler::Success;
  }

  return MCDisassembler::Fail;
}

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeRegPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes,
    unsigned PrefixReg) const {
  return decodeGenericRegPrefix(MI, Size, Bytes, PrefixReg, /*OpSize=*/2);
}

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeGR16Prefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes,
    unsigned PrefixReg) const {
  return decodeGenericRegPrefix(MI, Size, Bytes, PrefixReg, /*OpSize=*/1);
}

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeGR8Prefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes,
    unsigned PrefixReg) const {
  return decodeGenericRegPrefix(MI, Size, Bytes, PrefixReg, /*OpSize=*/0);
}

//===----------------------------------------------------------------------===//
// Memory prefix decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeMemPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, unsigned BaseReg,
    int64_t Disp, unsigned PrefixSize, unsigned MemSize,
    bool IsDstMem) const {
  unsigned OpByteIdx = PrefixSize;
  if (Bytes.size() <= OpByteIdx)
    return MCDisassembler::Fail;

  uint8_t OpByte = Bytes[OpByteIdx];
  unsigned Base = decodeGPR(BaseReg);

  // Block transfer instructions live in the byte source memory table (0x80).
  // Sub-opcodes 0x10-0x17 are block transfers (LDI, LDIR, LDD, LDDR, etc.)
  if (MemSize == 0 && OpByte >= 0x10 && OpByte <= 0x17) {
    switch (OpByte) {
    case 0x10: MI.setOpcode(TLCS900::LDI);  break;
    case 0x11: MI.setOpcode(TLCS900::LDIR); break;
    case 0x12: MI.setOpcode(TLCS900::LDD);  break;
    case 0x13: MI.setOpcode(TLCS900::LDDR); break;
    case 0x14: MI.setOpcode(TLCS900::CPI);  break;
    case 0x15: MI.setOpcode(TLCS900::CPIR); break;
    case 0x16: MI.setOpcode(TLCS900::CPD);  break;
    case 0x17: MI.setOpcode(TLCS900::CPDR); break;
    default:
      return MCDisassembler::Fail;
    }
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // MemLoad: 0x20-0x27 = LD rd, (mem) — size depends on MemSize
  if (OpByte >= 0x20 && OpByte <= 0x27) {
    unsigned RegEnc = OpByte & 0x7;
    unsigned DstReg;
    unsigned Opc;
    if (MemSize == 0) {
      DstReg = decodeGR8(RegEnc);
      Opc = TLCS900::LD8rm_asm;
    } else if (MemSize == 1) {
      DstReg = decodeGR16(RegEnc);
      Opc = TLCS900::LD16rm_asm;
    } else {
      DstReg = decodeGPR(RegEnc);
      Opc = TLCS900::LD32rm;
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(DstReg));
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // LDA rd, (mem): 0x30-0x37 — Load effective address (B0 destination table)
  if (IsDstMem && OpByte >= 0x30 && OpByte <= 0x37) {
    unsigned DstReg = decodeGPR(OpByte & 0x7);
    MI.setOpcode(TLCS900::LDA32);
    MI.addOperand(MCOperand::createReg(DstReg));
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // --- Destination memory table sub-opcodes ---
  // These are used when the memory is the destination (B0/B8 prefix, or F1/F2).

  // MemStore immediate: LD (mem), #imm
  // 0x00 + imm8 (byte), 0x02 + imm16 (word), 0x08 + imm32 (long)
  if (IsDstMem && OpByte == 0x00 && MemSize <= 2) {
    // LD (mem), #imm8
    if (Bytes.size() < OpByteIdx + 2)
      return MCDisassembler::Fail;
    uint8_t Imm = Bytes[OpByteIdx + 1];
    MI.setOpcode(TLCS900::LD8mi_dst);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = PrefixSize + 2;
    return MCDisassembler::Success;
  }
  if (IsDstMem && OpByte == 0x02 && MemSize <= 2) {
    // LD (mem), #imm16
    if (Bytes.size() < OpByteIdx + 3)
      return MCDisassembler::Fail;
    uint16_t Imm = readU16LE(Bytes, OpByteIdx + 1);
    MI.setOpcode(TLCS900::LD16mi_dst);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = PrefixSize + 3;
    return MCDisassembler::Success;
  }
  if (IsDstMem && OpByte == 0x08 && MemSize == 2) {
    // LD (mem), #imm32
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

  // MemStore register: sub-opcodes for LD (mem), rs (destination table only)
  //   0x40-0x47 = LD (mem), r8
  //   0x50-0x57 = LD (mem), r16
  //   0x60-0x67 = LD (mem), r32
  if (IsDstMem && OpByte >= 0x40 && OpByte <= 0x47) {
    unsigned SrcReg = decodeGR8(OpByte & 0x7);
    MI.setOpcode(TLCS900::LD8mr_asm);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }
  if (IsDstMem && OpByte >= 0x50 && OpByte <= 0x57) {
    unsigned SrcReg = decodeGR16(OpByte & 0x7);
    MI.setOpcode(TLCS900::LD16mr_asm);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }
  if (IsDstMem && OpByte >= 0x60 && OpByte <= 0x67) {
    unsigned SrcReg = decodeGPR(OpByte & 0x7);
    MI.setOpcode(TLCS900::LD32mr);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // PUSH (mem): sub-opcode 0x04 (byte/word source tables only)
  if (OpByte == 0x04 && MemSize <= 1) {
    unsigned Opc = (MemSize == 0) ? TLCS900::PUSH8 : TLCS900::PUSH16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(Base));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // INC/DEC (mem): source memory table, 0x60-0x6F
  if (MemSize <= 1 && OpByte >= 0x60 && OpByte <= 0x6F) {
    bool IsInc = (OpByte < 0x68);
    unsigned I3 = OpByte & 0x7;
    unsigned Count = (I3 == 0) ? 8 : I3;
    unsigned Opc;
    if (MemSize == 0)
      Opc = IsInc ? TLCS900::INC8m : TLCS900::DEC8m;
    else
      Opc = IsInc ? TLCS900::INC16m : TLCS900::DEC16m;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createImm(Count));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // RETcc: sub-opcode 0xF0-0xFF (B0 destination table only)
  if (IsDstMem && OpByte >= 0xF0) {
    unsigned CC = OpByte & 0xF;
    MI.setOpcode(TLCS900::RETcc);
    MI.addOperand(MCOperand::createImm(CC));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // JP cc, (mem): sub-opcode 0xD0-0xDF (B0 destination table only)
  if (IsDstMem && OpByte >= 0xD0 && OpByte <= 0xDF) {
    unsigned CC = OpByte & 0xF;
    MI.setOpcode(TLCS900::JPcc);
    MI.addOperand(MCOperand::createImm(CC));
    MI.addOperand(MCOperand::createReg(Base));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // CALL cc, (mem): sub-opcode 0xE0-0xEF (B0 destination table only)
  if (IsDstMem && OpByte >= 0xE0 && OpByte <= 0xEF) {
    unsigned CC = OpByte & 0xF;
    MI.setOpcode(TLCS900::CALLCC_24);
    MI.addOperand(MCOperand::createImm(CC));
    MI.addOperand(MCOperand::createReg(Base));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // MemALU register-source operations (all sizes)
  // Source memory table: ops that read from memory and combine with a register.
  {
    struct MemALURegEntry {
      uint8_t Base;
      unsigned Opcodes[3]; // [MemSize] = opcode
    };
    static const MemALURegEntry MemALURegOps[] = {
        {0x88, {TLCS900::ADD8mr, TLCS900::ADD16mr, TLCS900::ADD32mr}},
        {0xA8, {TLCS900::SUB8mr, TLCS900::SUB16mr, TLCS900::SUB32mr}},
        {0xC8, {TLCS900::AND8mr, TLCS900::AND16mr, TLCS900::AND32mr}},
        {0xD8, {TLCS900::XOR8mr, TLCS900::XOR16mr, TLCS900::XOR32mr}},
        {0xE8, {TLCS900::OR8mr, TLCS900::OR16mr, TLCS900::OR32mr}},
        {0xF8, {TLCS900::CP8mr, TLCS900::CP16mr, TLCS900::CP32mr}},
    };
    unsigned AluBase = OpByte & 0xF8;
    for (const auto &Op : MemALURegOps) {
      if (AluBase == Op.Base) {
        unsigned SrcReg = decodeRegForSize(OpByte & 0x7, MemSize);
        MI.setOpcode(Op.Opcodes[MemSize]);
        MI.addOperand(MCOperand::createReg(Base));
        MI.addOperand(MCOperand::createImm(Disp));
        MI.addOperand(MCOperand::createReg(SrcReg));
        Size = PrefixSize + 1;
        return MCDisassembler::Success;
      }
    }
  }

  return MCDisassembler::Fail;
}

//===----------------------------------------------------------------------===//
// Direct address prefix decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeDirectAddr(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, bool IsDst,
    unsigned OpSize, unsigned AddrBytes) const {
  // Prefix byte already consumed. Next: address bytes, then sub-opcode.
  unsigned AddrOffset = 1;
  if (Bytes.size() < AddrOffset + AddrBytes + 1)
    return MCDisassembler::Fail;

  uint32_t Addr = readImmLE(Bytes, AddrOffset, AddrBytes);
  unsigned SubOpIdx = AddrOffset + AddrBytes;
  uint8_t SubOp = Bytes[SubOpIdx];
  unsigned PrefixSize = 1 + AddrBytes;

  // LD rd, (addr): sub-opcode 0x20-0x27
  if (SubOp >= 0x20 && SubOp <= 0x27) {
    unsigned DstReg = decodeRegForSize(SubOp & 0x7, OpSize);
    bool Is24 = (AddrBytes == 3);
    unsigned Opc;
    if (OpSize == 0)
      Opc = Is24 ? TLCS900::LD8_da24 : TLCS900::LD8_da16;
    else if (OpSize == 1)
      Opc = Is24 ? TLCS900::LD16_da24 : TLCS900::LD16_da16;
    else
      Opc = Is24 ? TLCS900::LD32_da24 : TLCS900::LD32_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(DstReg));
    MI.addOperand(MCOperand::createImm(Addr));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // LDA rd, (addr): sub-opcode 0x30-0x37 (destination table only)
  if (IsDst && SubOp >= 0x30 && SubOp <= 0x37) {
    unsigned DstReg = decodeGPR(SubOp & 0x7);
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = Is24 ? TLCS900::LDA_da24 : TLCS900::LDA_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(DstReg));
    MI.addOperand(MCOperand::createImm(Addr));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // LD (addr), rs: destination table store operations
  // 0x40-0x47 = LD (addr), r8
  // 0x50-0x57 = LD (addr), r16
  // 0x60-0x67 = LD (addr), r32
  if (IsDst && SubOp >= 0x40 && SubOp <= 0x47) {
    unsigned SrcReg = decodeGR8(SubOp & 0x7);
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = Is24 ? TLCS900::LD8m_da24 : TLCS900::LD8m_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }
  if (IsDst && SubOp >= 0x50 && SubOp <= 0x57) {
    unsigned SrcReg = decodeGR16(SubOp & 0x7);
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = Is24 ? TLCS900::LD16m_da24 : TLCS900::LD16m_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }
  if (IsDst && SubOp >= 0x60 && SubOp <= 0x67) {
    unsigned SrcReg = decodeGPR(SubOp & 0x7);
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = Is24 ? TLCS900::LD32m_da24 : TLCS900::LD32m_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createReg(SrcReg));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // LD (addr), #imm: destination table immediate store
  if (IsDst && SubOp == 0x00) {
    if (Bytes.size() < SubOpIdx + 2)
      return MCDisassembler::Fail;
    uint8_t Imm = Bytes[SubOpIdx + 1];
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = Is24 ? TLCS900::LD8mi_da24 : TLCS900::LD8mi_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = PrefixSize + 2;
    return MCDisassembler::Success;
  }
  if (IsDst && SubOp == 0x02) {
    if (Bytes.size() < SubOpIdx + 3)
      return MCDisassembler::Fail;
    uint16_t Imm = readU16LE(Bytes, SubOpIdx + 1);
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = Is24 ? TLCS900::LD16mi_da24 : TLCS900::LD16mi_da16;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = PrefixSize + 3;
    return MCDisassembler::Success;
  }

  // INC/DEC (addr): source table, 0x60-0x6F
  if (!IsDst && SubOp >= 0x60 && SubOp <= 0x6F) {
    bool IsInc = (SubOp < 0x68);
    unsigned I3 = SubOp & 0x7;
    unsigned Count = (I3 == 0) ? 8 : I3;
    bool Is24 = (AddrBytes == 3);
    unsigned Opc;
    if (OpSize == 0)
      Opc = IsInc ? (Is24 ? TLCS900::INC8_da24 : TLCS900::INC8_da16)
                   : (Is24 ? TLCS900::DEC8_da24 : TLCS900::DEC8_da16);
    else if (OpSize == 1)
      Opc = IsInc ? (Is24 ? TLCS900::INC16_da24 : TLCS900::INC16_da16)
                   : (Is24 ? TLCS900::DEC16_da24 : TLCS900::DEC16_da16);
    else
      return MCDisassembler::Fail; // No 32-bit INC/DEC direct addressing
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(Count));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // ALU on direct address: source table
  // Two sub-opcode groups:
  //   0x80+reg: reg = reg op (addr) — "reg-destination" (3 ops: dst, src1_tied, addr)
  //   0x88+reg: (addr) = (addr) op reg — "mem-destination" (2 ops: addr, src)
  // CP variants have no output (2 ops: src/addr, addr/src)
  if (!IsDst) {
    struct DALUEntry {
      uint8_t Base;
      unsigned Opcodes8[2];  // [is24]
      unsigned Opcodes16[2];
      unsigned Opcodes32[2];
      bool IsRegDst;  // true = 3 operands (dst, src_tied, addr)
    };
    static const DALUEntry DALUOps[] = {
        // Reg-destination: reg = reg op (addr)
        {0x80, {TLCS900::ADD8_da16, TLCS900::ADD8_da24},
               {TLCS900::ADD16_da16, TLCS900::ADD16_da24},
               {TLCS900::ADD32_da16, TLCS900::ADD32_da24}, true},
        {0xA0, {TLCS900::SUB8_da16, TLCS900::SUB8_da24},
               {TLCS900::SUB16_da16, TLCS900::SUB16_da24},
               {TLCS900::SUB32_da16, TLCS900::SUB32_da24}, true},
        {0xC0, {TLCS900::AND8_da16, TLCS900::AND8_da24},
               {TLCS900::AND16_da16, TLCS900::AND16_da24},
               {0, 0}, true},
        {0xD0, {TLCS900::XOR8_da16, TLCS900::XOR8_da24},
               {0, 0}, {0, 0}, true},
        {0xE0, {TLCS900::OR8_da16, TLCS900::OR8_da24},
               {TLCS900::OR16_da16, TLCS900::OR16_da24},
               {0, 0}, true},
        {0xF0, {TLCS900::CP8_da16, TLCS900::CP8_da24},
               {TLCS900::CP16_da16, TLCS900::CP16_da24},
               {TLCS900::CP32_da16, TLCS900::CP32_da24}, false},
        // Mem-destination: (addr) = (addr) op reg
        {0x88, {TLCS900::ADD8m_da16, TLCS900::ADD8m_da24},
               {TLCS900::ADD16m_da16, TLCS900::ADD16m_da24},
               {TLCS900::ADD32m_da16, TLCS900::ADD32m_da24}, false},
        {0xA8, {TLCS900::SUB8m_da16, TLCS900::SUB8m_da24},
               {TLCS900::SUB16m_da16, TLCS900::SUB16m_da24},
               {TLCS900::SUB32m_da16, TLCS900::SUB32m_da24}, false},
        {0xC8, {TLCS900::AND8m_da16, TLCS900::AND8m_da24},
               {TLCS900::AND16m_da16, TLCS900::AND16m_da24},
               {0, 0}, false},
        {0xD8, {TLCS900::XOR8m_da16, TLCS900::XOR8m_da24},
               {TLCS900::XOR16m_da16, TLCS900::XOR16m_da24},
               {0, 0}, false},
        {0xE8, {TLCS900::OR8m_da16, TLCS900::OR8m_da24},
               {TLCS900::OR16m_da16, TLCS900::OR16m_da24},
               {0, 0}, false},
        {0xF8, {TLCS900::CP8m_da16, TLCS900::CP8m_da24},
               {TLCS900::CP16m_da16, TLCS900::CP16m_da24},
               {TLCS900::CP32m_da16, TLCS900::CP32m_da24}, false},
    };
    unsigned AluBase = SubOp & 0xF8;
    bool Is24 = (AddrBytes == 3);
    for (const auto &Op : DALUOps) {
      if (AluBase == Op.Base) {
        unsigned RegEnc = SubOp & 0x7;
        const unsigned *Opcodes;
        if (OpSize == 0) Opcodes = Op.Opcodes8;
        else if (OpSize == 1) Opcodes = Op.Opcodes16;
        else Opcodes = Op.Opcodes32;
        unsigned Opc = Opcodes[Is24 ? 1 : 0];
        if (Opc == 0)
          return MCDisassembler::Fail;
        MI.setOpcode(Opc);
        if (Op.IsRegDst) {
          // reg = reg op (addr): 3 operands (dst, src1_tied, addr)
          unsigned Reg = decodeRegForSize(RegEnc, OpSize);
          MI.addOperand(MCOperand::createReg(Reg));
          MI.addOperand(MCOperand::createReg(Reg));
          MI.addOperand(MCOperand::createImm(Addr));
        } else if (AluBase >= 0x88) {
          // (addr) = (addr) op reg: 2 operands (addr, src)
          unsigned Reg = decodeRegForSize(RegEnc, OpSize);
          MI.addOperand(MCOperand::createImm(Addr));
          MI.addOperand(MCOperand::createReg(Reg));
        } else {
          // CP reg, (addr): 2 operands (src, addr)
          unsigned Reg = decodeRegForSize(RegEnc, OpSize);
          MI.addOperand(MCOperand::createReg(Reg));
          MI.addOperand(MCOperand::createImm(Addr));
        }
        Size = PrefixSize + 1;
        return MCDisassembler::Success;
      }
    }
  }

  // BIT/SET/RES on direct address: destination table
  if (IsDst && SubOp >= 0xA0 && SubOp <= 0xBF) {
    unsigned BitGroup = (SubOp >> 3) & 0x3;
    unsigned BitNum = SubOp & 0x7;
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = 0;
    switch (BitGroup) {
    case 0: Opc = Is24 ? TLCS900::BIT_da24 : TLCS900::BIT_da16; break;  // 0xA0
    case 1: Opc = Is24 ? TLCS900::RES_da24 : TLCS900::RES_da16; break;  // 0xA8
    case 2: Opc = Is24 ? TLCS900::SET_da24 : TLCS900::SET_da16; break;  // 0xB0
    default: return MCDisassembler::Fail;
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(BitNum));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // RETcc in destination table: sub-opcode 0xF0-0xFF
  if (IsDst && SubOp >= 0xF0) {
    unsigned CC = SubOp & 0xF;
    MI.setOpcode(TLCS900::RETcc);
    MI.addOperand(MCOperand::createImm(CC));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  return MCDisassembler::Fail;
}

//===----------------------------------------------------------------------===//
// 8-bit direct (I/O) prefix decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeD8Prefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes,
    unsigned OpSize, bool IsDst) const {
  // Prefix byte already consumed. Next: addr8, then sub-opcode.
  if (Bytes.size() < 3)
    return MCDisassembler::Fail;

  uint8_t Addr8 = Bytes[1];
  uint8_t SubOp = Bytes[2];

  // All D8 instructions are at least 3 bytes (prefix + addr8 + sub-opcode).

  if (IsDst) {
    // === Destination 8-bit direct (F0 prefix) ===

    // LD (addr8), #imm8: sub-opcode 0x00, followed by 1 imm byte
    if (SubOp == 0x00) {
      if (Bytes.size() < 4)
        return MCDisassembler::Fail;
      MI.setOpcode(TLCS900::STIB_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      MI.addOperand(MCOperand::createImm(Bytes[3]));
      Size = 4;
      return MCDisassembler::Success;
    }

    // LD (addr8), #imm16: sub-opcode 0x02, followed by 2 imm bytes
    if (SubOp == 0x02) {
      if (Bytes.size() < 5)
        return MCDisassembler::Fail;
      MI.setOpcode(TLCS900::STIW_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      MI.addOperand(MCOperand::createImm(Bytes[3]));
      MI.addOperand(MCOperand::createImm(Bytes[4]));
      Size = 5;
      return MCDisassembler::Success;
    }

    // POP byte to (addr8): sub-opcode 0x04
    if (SubOp == 0x04) {
      MI.setOpcode(TLCS900::POPB_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // POP word to (addr8): sub-opcode 0x06
    if (SubOp == 0x06) {
      MI.setOpcode(TLCS900::POPW_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // CALL (addr8): sub-opcode 0x08
    if (SubOp == 0x08) {
      MI.setOpcode(TLCS900::CALL_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // ANDCF A, (addr8): sub-opcode 0x28
    if (SubOp == 0x28) {
      MI.setOpcode(TLCS900::ANDCF_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // ORCF A, (addr8): sub-opcode 0x29
    if (SubOp == 0x29) {
      MI.setOpcode(TLCS900::ORCF_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // XORCF A, (addr8): sub-opcode 0x2A
    if (SubOp == 0x2A) {
      MI.setOpcode(TLCS900::XORCF_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // STCF A, (addr8): sub-opcode 0x2C
    if (SubOp == 0x2C) {
      MI.setOpcode(TLCS900::STCFA_DD8);
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // LDA Rd, addr8: sub-opcode 0x30-0x37
    if (SubOp >= 0x30 && SubOp <= 0x37) {
      unsigned DstReg = decodeRegForSize(SubOp & 0x7, 2); // always 32-bit
      MI.setOpcode(TLCS900::LDA_DD8L);
      MI.addOperand(MCOperand::createReg(DstReg));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // LD (addr8), Rb: sub-opcode 0x40-0x47
    if (SubOp >= 0x40 && SubOp <= 0x47) {
      unsigned SrcReg = decodeRegForSize(SubOp & 0x7, 0); // 8-bit
      MI.setOpcode(TLCS900::ST_DD8B);
      MI.addOperand(MCOperand::createReg(SrcReg));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // LD (addr8), Rw: sub-opcode 0x50-0x57
    if (SubOp >= 0x50 && SubOp <= 0x57) {
      unsigned SrcReg = decodeRegForSize(SubOp & 0x7, 1); // 16-bit
      MI.setOpcode(TLCS900::ST_DD8W);
      MI.addOperand(MCOperand::createReg(SrcReg));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // LD (addr8), Rl: sub-opcode 0x60-0x67
    if (SubOp >= 0x60 && SubOp <= 0x67) {
      unsigned SrcReg = decodeRegForSize(SubOp & 0x7, 2); // 32-bit
      MI.setOpcode(TLCS900::ST_DD8L);
      MI.addOperand(MCOperand::createReg(SrcReg));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // LDCF bit, (addr8): sub-opcode 0x98-0x9F
    if (SubOp >= 0x98 && SubOp <= 0x9F) {
      MI.setOpcode(TLCS900::LDCF_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // STCF bit, (addr8): sub-opcode 0xA0-0xA7
    if (SubOp >= 0xA0 && SubOp <= 0xA7) {
      MI.setOpcode(TLCS900::STCF_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // TSET bit, (addr8): sub-opcode 0xA8-0xAF
    if (SubOp >= 0xA8 && SubOp <= 0xAF) {
      MI.setOpcode(TLCS900::TSET_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // RES bit, (addr8): sub-opcode 0xB0-0xB7
    if (SubOp >= 0xB0 && SubOp <= 0xB7) {
      MI.setOpcode(TLCS900::RES_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // SET bit, (addr8): sub-opcode 0xB8-0xBF
    if (SubOp >= 0xB8 && SubOp <= 0xBF) {
      MI.setOpcode(TLCS900::SET_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // CHG bit, (addr8): sub-opcode 0xC0-0xC7
    if (SubOp >= 0xC0 && SubOp <= 0xC7) {
      MI.setOpcode(TLCS900::CHG_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // BIT bit, (addr8): sub-opcode 0xC8-0xCF
    if (SubOp >= 0xC8 && SubOp <= 0xCF) {
      MI.setOpcode(TLCS900::BIT_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0x7));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    // JP cc, (addr8): sub-opcode 0xD0-0xDF
    if (SubOp >= 0xD0 && SubOp <= 0xDF) {
      MI.setOpcode(TLCS900::JP_DD8);
      MI.addOperand(MCOperand::createImm(SubOp & 0xF));
      MI.addOperand(MCOperand::createImm(Addr8));
      Size = 3;
      return MCDisassembler::Success;
    }

    return MCDisassembler::Fail;
  }

  // === Source 8-bit direct (C0/D0/E0 prefix) ===

  // LD rd, (addr8): sub-opcode 0x20-0x27
  if (SubOp >= 0x20 && SubOp <= 0x27) {
    unsigned DstReg = decodeRegForSize(SubOp & 0x7, OpSize);
    MI.setOpcode(TLCS900::LD_SD8B);
    MI.addOperand(MCOperand::createReg(DstReg));
    MI.addOperand(MCOperand::createImm(Addr8));
    Size = 3;
    return MCDisassembler::Success;
  }

  return MCDisassembler::Fail;
}

//===----------------------------------------------------------------------===//
// SRI (Register-Indirect Complex) prefix decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeSRIPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, bool IsDst,
    unsigned OpSize) const {
  // SRI prefix format: [C3/D3/E3/F3] [mode_byte] [d16_lo d16_hi]? [sub-opcode]
  // Mode byte: bits 7-2 = register file address >> 2, bits 1-0 = mode type.
  //   Mode type 00: (Xrr) — register indirect, no displacement
  //   Mode type 01: (Xrr+d16) — 16-bit displacement
  //   Mode type 11: (Xrr+Rn) — register index (not yet supported)
  // Register encoding: BaseReg = (ModeByte >> 2) - 0x38 = (ModeByte - 0xE0) >> 2

  if (Bytes.size() < 3)
    return MCDisassembler::Fail;

  uint8_t Mode = Bytes[1];
  unsigned ModeType = Mode & 0x03;

  // Decode the base register from the mode byte.
  // Encoder produces: 0xE0 + (BaseReg << 2) + ModeType
  // So BaseReg = (Mode - ModeType - 0xE0) >> 2
  if (Mode < 0xE0)
    return MCDisassembler::Fail;
  unsigned BaseReg = ((Mode - ModeType) - 0xE0) >> 2;
  if (BaseReg > 7)
    return MCDisassembler::Fail;

  int64_t Disp = 0;
  unsigned PrefixSize; // Total bytes consumed before the sub-opcode.

  if (ModeType == 0x00) {
    // (Xrr) — no displacement. Prefix = 2 bytes (SRI prefix + mode byte).
    PrefixSize = 2;
  } else if (ModeType == 0x01) {
    // (Xrr+d16) — 16-bit signed displacement.
    if (Bytes.size() < 5) // prefix + mode + d16(2) + sub-opcode(1)
      return MCDisassembler::Fail;
    Disp = static_cast<int16_t>(readU16LE(Bytes, 2));
    PrefixSize = 4; // prefix(1) + mode(1) + d16(2)
  } else {
    // Mode types 2 and 3 (register index, etc.) not yet supported.
    return MCDisassembler::Fail;
  }

  // Delegate to the unified memory prefix decoder with the extracted
  // base register, displacement, and prefix size.
  return decodeMemPrefix(MI, Size, Bytes, BaseReg, Disp, PrefixSize,
                         /*MemSize=*/OpSize, IsDst);
}

//===----------------------------------------------------------------------===//
// PI (Post-Increment / Pre-Decrement) prefix decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodePIPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, bool IsDst,
    unsigned OpSize, bool IsPostInc) const {
  // Prefix byte consumed. Next: base_gpr_enc (1 byte), then sub-opcode.
  if (Bytes.size() < 3)
    return MCDisassembler::Fail;

  uint8_t BaseRegByte = Bytes[1];
  uint8_t SubOpc = Bytes[2];

  // Helper to pick instruction based on IsDst, IsPostInc, and OpSize.
  // Source: C5/D5/E5 (post-inc), C4/D4/E4 (pre-dec)
  // Dest:   F5 (post-inc), F4 (pre-dec)

  // === Destination table (F5/F4) ===
  if (IsDst) {
    // ST r, (R+/-) — sub-opcodes 0x30-0x37 (byte), 0x50-0x57 (word), 0x60-0x67 (long)
    if (SubOpc >= 0x30 && SubOpc <= 0x37) {
      unsigned RegEnc = SubOpc & 0x7;
      unsigned Opc = IsPostInc ? TLCS900::ST_DPIB : TLCS900::ST_DPDB;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }
    if (SubOpc >= 0x50 && SubOpc <= 0x57) {
      unsigned RegEnc = SubOpc & 0x7;
      unsigned Opc = IsPostInc ? TLCS900::ST_DPIW : TLCS900::ST_DPDW;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGR16(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }
    if (SubOpc >= 0x60 && SubOpc <= 0x67) {
      unsigned RegEnc = SubOpc & 0x7;
      unsigned Opc = IsPostInc ? TLCS900::ST_DPIL : TLCS900::ST_DPDL;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGPR(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // LDA r32, (R+/-) — sub-opcodes 0x40-0x47
    if (SubOpc >= 0x40 && SubOpc <= 0x47) {
      unsigned RegEnc = SubOpc & 0x7;
      unsigned Opc = IsPostInc ? TLCS900::LDA_DPI : TLCS900::LDA_DPD;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGPR(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // Store immediate: LD (R+/-), #imm8 — sub-opcode 0x00
    if (SubOpc == 0x00) {
      if (Bytes.size() < 4)
        return MCDisassembler::Fail;
      unsigned Opc = IsPostInc ? TLCS900::STIB_DPI : TLCS900::STIB_DPD;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      MI.addOperand(MCOperand::createImm(Bytes[3]));
      Size = 4;
      return MCDisassembler::Success;
    }

    // Store immediate word: LD (R+/-), #imm16 — sub-opcode 0x02
    if (SubOpc == 0x02) {
      if (Bytes.size() < 5)
        return MCDisassembler::Fail;
      unsigned Opc = IsPostInc ? TLCS900::STIW_DPI : TLCS900::STIW_DPI; // TODO: STIW_DPD
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      MI.addOperand(MCOperand::createImm(Bytes[3]));
      MI.addOperand(MCOperand::createImm(Bytes[4]));
      Size = 5;
      return MCDisassembler::Success;
    }

    // POP to (R+/-) byte — sub-opcode 0x04
    if (SubOpc == 0x04) {
      unsigned Opc = IsPostInc ? TLCS900::POPB_DPI : TLCS900::POPB_DPD;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }
    // POP to (R+/-) word — sub-opcode 0x06
    if (SubOpc == 0x06) {
      unsigned Opc = IsPostInc ? TLCS900::POPW_DPI : TLCS900::POPW_DPD;
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    return MCDisassembler::Fail;
  }

  // === Source table (C5/D5/E5 post-inc, C4/D4/E4 pre-dec) ===

  // LD reg, (R+/-) — sub-opcodes 0x20-0x27
  if (SubOpc >= 0x20 && SubOpc <= 0x27) {
    unsigned RegEnc = SubOpc & 0x7;
    unsigned Opc;
    if (OpSize == 0) // byte
      Opc = IsPostInc ? TLCS900::LD_SPIB : TLCS900::LD_SPDB;
    else if (OpSize == 1) // word
      Opc = IsPostInc ? TLCS900::LD_SPIW : TLCS900::LD_SPDW;
    else // long
      Opc = IsPostInc ? TLCS900::LD_SPIL : TLCS900::LD_SPDL;
    MI.setOpcode(Opc);
    if (OpSize == 0)
      MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
    else if (OpSize == 1)
      MI.addOperand(MCOperand::createReg(decodeGR16(RegEnc)));
    else
      MI.addOperand(MCOperand::createReg(decodeGPR(RegEnc)));
    MI.addOperand(MCOperand::createImm(BaseRegByte));
    Size = 3;
    return MCDisassembler::Success;
  }

  // PUSH (R+/-) — sub-opcode 0x04
  if (SubOpc == 0x04) {
    if (!IsPostInc) {
      // Pre-dec
      if (OpSize == 0)
        MI.setOpcode(TLCS900::PUSH_SPDB);
      else if (OpSize == 1)
        return MCDisassembler::Fail; // TODO: add PUSH_SPDW
      else
        return MCDisassembler::Fail;
    } else {
      // Post-inc
      if (OpSize == 0)
        MI.setOpcode(TLCS900::PUSH_SPIB);
      else if (OpSize == 1)
        MI.setOpcode(TLCS900::PUSH_SPIW);
      else
        return MCDisassembler::Fail; // TODO: add PUSH_SPIL
    }
    MI.addOperand(MCOperand::createImm(BaseRegByte));
    Size = 3;
    return MCDisassembler::Success;
  }

  // INC n, (R+/-) — sub-opcodes 0x60-0x67
  if (SubOpc >= 0x60 && SubOpc <= 0x67) {
    unsigned Count = SubOpc & 0x7;
    unsigned Opc;
    if (OpSize == 0) // byte
      Opc = IsPostInc ? TLCS900::INC_SPIB : TLCS900::INC_SPDB;
    else if (OpSize == 1) // word
      Opc = IsPostInc ? TLCS900::INC_SPIW : TLCS900::INC_SPIW; // TODO: INC_SPDW
    else
      return MCDisassembler::Fail;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(BaseRegByte));
    MI.addOperand(MCOperand::createImm(Count));
    Size = 3;
    return MCDisassembler::Success;
  }

  // DEC n, (R+/-) — sub-opcodes 0x68-0x6F
  if (SubOpc >= 0x68 && SubOpc <= 0x6F) {
    unsigned Count = SubOpc & 0x7;
    unsigned Opc;
    if (OpSize == 0) // byte
      Opc = IsPostInc ? TLCS900::DEC_SPIB : TLCS900::DEC_SPDB;
    else if (OpSize == 1) // word
      Opc = IsPostInc ? TLCS900::DEC_SPIW : TLCS900::DEC_SPIW; // TODO: DEC_SPDW
    else
      return MCDisassembler::Fail;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(BaseRegByte));
    MI.addOperand(MCOperand::createImm(Count));
    Size = 3;
    return MCDisassembler::Success;
  }

  // ALU (mem), #imm — sub-opcodes 0x38-0x3F
  if (SubOpc >= 0x38 && SubOpc <= 0x3F) {
    unsigned ImmSize = (OpSize == 0) ? 1 : (OpSize == 1) ? 2 : 4;
    if (Bytes.size() < 3u + ImmSize)
      return MCDisassembler::Fail;

    // Select opcode based on ALU operation and OpSize
    unsigned AluOp = SubOpc & 0x07; // 0=ADD,1=ADC,2=SUB,3=SBC,4=AND,5=XOR,6=OR,7=CP
    unsigned Opc;
    if (OpSize == 0) {
      // Byte ALU immediate
      static const unsigned SpiByteImm[] = {
        TLCS900::ADD_SPIB_IM, TLCS900::ADC_SPIB_IM, TLCS900::SUB_SPIB_IM,
        TLCS900::SBC_SPIB_IM, TLCS900::AND_SPIB_IM, TLCS900::XOR_SPIB_IM,
        TLCS900::OR_SPIB_IM, TLCS900::CP_SPIB_IM
      };
      static const unsigned SpdByteImm[] = {
        0, 0, 0, 0, 0, 0, 0, TLCS900::CP_SPDB_IM
      };
      if (IsPostInc) {
        Opc = SpiByteImm[AluOp];
      } else {
        Opc = SpdByteImm[AluOp];
        if (!Opc) return MCDisassembler::Fail;
      }
    } else if (OpSize == 1) {
      // Word ALU immediate (only some defined)
      static const unsigned SpiWordImm[] = {
        TLCS900::ADD_SPIW_IM, 0, TLCS900::SUB_SPIW_IM, 0,
        TLCS900::AND_SPIW_IM, 0, TLCS900::OR_SPIW_IM, TLCS900::CP_SPIW_IM
      };
      if (!IsPostInc) return MCDisassembler::Fail;
      Opc = SpiWordImm[AluOp];
      if (!Opc) return MCDisassembler::Fail;
    } else {
      return MCDisassembler::Fail;
    }

    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(BaseRegByte));
    for (unsigned i = 0; i < ImmSize; i++)
      MI.addOperand(MCOperand::createImm(Bytes[3 + i]));
    Size = 3 + ImmSize;
    return MCDisassembler::Success;
  }

  // ALU reg, (mem) and ALU (mem), reg — sub-opcodes 0x80-0xFF
  if (SubOpc >= 0x80) {
    unsigned RegEnc = SubOpc & 0x7;
    unsigned AluBase = SubOpc & 0xF8;
    bool IsMemReg = (AluBase & 0x08) != 0; // 0x88,0x98,...,0xF8 = (mem),reg direction

    // Map AluBase to instruction opcode
    // reg,(mem): 0x80=ADD, 0x90=ADC, 0xA0=SUB, 0xB0=SBC, 0xC0=AND, 0xD0=XOR, 0xE0=OR, 0xF0=CP
    // (mem),reg: 0x88=ADD, 0x98=ADC, 0xA8=SUB, 0xB8=SBC, 0xC8=AND, 0xD8=XOR, 0xE8=OR, 0xF8=CP

    // Byte SPI reg,(mem)
    if (OpSize == 0 && IsPostInc && !IsMemReg) {
      static const unsigned SpiByteRM[] = {
        TLCS900::ADD_SPIB, 0, TLCS900::ADC_SPIB, 0,
        TLCS900::SUB_SPIB, 0, TLCS900::SBC_SPIB, 0,
        TLCS900::AND_SPIB, 0, TLCS900::XOR_SPIB, 0,
        TLCS900::OR_SPIB_RM, 0, TLCS900::CP_SPIB, 0
      };
      unsigned Idx = (AluBase - 0x80) >> 3;
      if (Idx >= 16 || !SpiByteRM[Idx]) return MCDisassembler::Fail;
      MI.setOpcode(SpiByteRM[Idx]);
      MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // Byte SPI (mem),reg
    if (OpSize == 0 && IsPostInc && IsMemReg) {
      static const unsigned SpiByteReg[] = {
        TLCS900::ADD_SPIB_MR, TLCS900::ADC_SPIB_MR,
        TLCS900::SUB_SPIB_MR, TLCS900::SBC_SPIB_MR,
        TLCS900::AND_SPIB_MR, TLCS900::XOR_SPIB_MR,
        TLCS900::OR_SPIB_MR, TLCS900::CP_SPIB_MR
      };
      unsigned Idx = (AluBase - 0x88) >> 4;
      MI.setOpcode(SpiByteReg[Idx]);
      MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // Byte SPD (pre-dec)
    if (OpSize == 0 && !IsPostInc) {
      // Only CP_SPDB defined for reg,(mem) direction
      if (!IsMemReg && AluBase == 0xF0) {
        MI.setOpcode(TLCS900::CP_SPDB);
        MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
        MI.addOperand(MCOperand::createImm(BaseRegByte));
        Size = 3;
        return MCDisassembler::Success;
      }
      if (IsMemReg && AluBase == 0xF8) {
        MI.setOpcode(TLCS900::CP_SPDB_MR);
        MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
        MI.addOperand(MCOperand::createImm(BaseRegByte));
        Size = 3;
        return MCDisassembler::Success;
      }
      // Other SPD byte ALU ops
      if (!IsMemReg) {
        unsigned Opc = 0;
        switch (AluBase) {
        case 0x80: Opc = TLCS900::ADD_SPDB; break;
        case 0xA0: Opc = TLCS900::SUB_SPDB; break;
        case 0xC0: Opc = TLCS900::AND_SPDB; break;
        case 0xE0: Opc = TLCS900::OR_SPDB; break;
        default: return MCDisassembler::Fail;
        }
        MI.setOpcode(Opc);
        MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
        MI.addOperand(MCOperand::createImm(BaseRegByte));
        Size = 3;
        return MCDisassembler::Success;
      }
      return MCDisassembler::Fail;
    }

    // Word SPI reg,(mem)
    if (OpSize == 1 && IsPostInc && !IsMemReg) {
      unsigned Opc = 0;
      switch (AluBase) {
      case 0x80: Opc = TLCS900::ADD_SPIW; break;
      case 0x90: Opc = TLCS900::ADC_SPIW; break;
      case 0xA0: Opc = TLCS900::SUB_SPIW; break;
      case 0xB0: Opc = TLCS900::SBC_SPIW; break;
      case 0xC0: Opc = TLCS900::AND_SPIW; break;
      case 0xD0: Opc = TLCS900::XOR_SPIW; break;
      case 0xE0: Opc = TLCS900::OR_SPIW; break;
      case 0xF0: Opc = TLCS900::CP_SPIW; break;
      default: return MCDisassembler::Fail;
      }
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGR16(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // Word SPI (mem),reg
    if (OpSize == 1 && IsPostInc && IsMemReg) {
      unsigned Opc = 0;
      switch (AluBase) {
      case 0x88: Opc = TLCS900::ADD_SPIW_MR; break;
      case 0xA8: Opc = TLCS900::SUB_SPIW_MR; break;
      case 0xC8: Opc = TLCS900::AND_SPIW_MR; break;
      case 0xE8: Opc = TLCS900::OR_SPIW_MR; break;
      case 0xF8: Opc = TLCS900::CPM_SPIW; break;
      default: return MCDisassembler::Fail;
      }
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGR16(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // Word SPD
    if (OpSize == 1 && !IsPostInc && !IsMemReg && AluBase == 0xF0) {
      MI.setOpcode(TLCS900::CP_SPDW);
      MI.addOperand(MCOperand::createReg(decodeGR16(RegEnc)));
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    // Long SPI
    if (OpSize == 2 && IsPostInc) {
      unsigned Opc = 0;
      if (!IsMemReg) {
        switch (AluBase) {
        case 0x80: Opc = TLCS900::ADD_SPIL; break;
        case 0xA0: Opc = TLCS900::SUB_SPIL; break;
        case 0xC0: Opc = TLCS900::AND_SPIL; break;
        case 0xE0: Opc = TLCS900::OR_SPIL; break;
        case 0xF0: Opc = TLCS900::CP_SPIL; break;
        default: return MCDisassembler::Fail;
        }
        MI.setOpcode(Opc);
        MI.addOperand(MCOperand::createReg(decodeGPR(RegEnc)));
      } else {
        switch (AluBase) {
        case 0x88: Opc = TLCS900::ADD_SPIL_MR; break;
        case 0xA8: Opc = TLCS900::SUB_SPIL_MR; break;
        case 0xF8: Opc = TLCS900::CP_SPIL_MR; break;
        default: return MCDisassembler::Fail;
        }
        MI.setOpcode(Opc);
        MI.addOperand(MCOperand::createReg(decodeGPR(RegEnc)));
      }
      MI.addOperand(MCOperand::createImm(BaseRegByte));
      Size = 3;
      return MCDisassembler::Success;
    }

    return MCDisassembler::Fail;
  }

  return MCDisassembler::Fail;
}

//===----------------------------------------------------------------------===//
// ERP (Extended Register Prefix) decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodeERPPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes,
    unsigned OpSize) const {
  // Prefix byte consumed. Next: bank_idx (1 byte), then sub-opcode.
  if (Bytes.size() < 3)
    return MCDisassembler::Fail;

  // Emit as raw bytes for now.
  // TODO: Map sub-opcodes to appropriate ERP instructions.
  return MCDisassembler::Fail;
}

// Map 3-bit register encoding to PrevGR16 (Q) register.
static unsigned decodeQReg(unsigned Enc) {
  static const unsigned QRegDecoderTable[] = {
      TLCS900::QWA, TLCS900::QBC, TLCS900::QDE, TLCS900::QHL,
      TLCS900::QIX, TLCS900::QIY, TLCS900::QIZ, TLCS900::QSP};
  assert(Enc < 8 && "Invalid Q register encoding");
  return QRegDecoderTable[Enc];
}

//===----------------------------------------------------------------------===//
// Previous register bank (PrevBank / D7 prefix) decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::decodePrevBankPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes) const {
  // Format: 0xD7 + mode_byte + sub-opcode [+ operand bytes]
  // mode_byte = 0xE0 + QR_enc * 4 + 2 (register direct mode)
  if (Bytes.size() < 3)
    return MCDisassembler::Fail;

  uint8_t ModeByte = Bytes[1];
  // Validate mode byte: must be 0xE2, 0xE6, 0xEA, ..., 0xFE
  // i.e., (ModeByte - 0xE2) must be divisible by 4 and in range 0..28
  if (ModeByte < 0xE2 || ((ModeByte - 0xE2) & 0x3) != 0)
    return MCDisassembler::Fail;
  unsigned QEnc = (ModeByte - 0xE2) >> 2;
  if (QEnc > 7)
    return MCDisassembler::Fail;
  unsigned QReg = decodeQReg(QEnc);

  uint8_t SubOpc = Bytes[2];

  // --- Unary operations (3 bytes: D7 + mode + sub) ---
  switch (SubOpc) {
  case 0x04: // PUSH qR
    MI.setOpcode(TLCS900::PUSH_PBW);
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  case 0x05: // POP qR
    MI.setOpcode(TLCS900::POP_PBW);
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  case 0x06: // CPL qR
    MI.setOpcode(TLCS900::CPL_PBW);
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  case 0x07: // NEG qR
    MI.setOpcode(TLCS900::NEG_PBW);
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  case 0x0F: // BS1B a, qR
    MI.setOpcode(TLCS900::BS1B_PBW);
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  default:
    break;
  }

  // --- LD qR, #imm16 (sub-opcode 0x03 + 2 bytes imm) ---
  if (SubOpc == 0x03) {
    if (Bytes.size() < 5)
      return MCDisassembler::Fail;
    uint16_t Imm = readU16LE(Bytes, 3);
    MI.setOpcode(TLCS900::LD_PBW_IMM);
    MI.addOperand(MCOperand::createReg(QReg));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = 5;
    return MCDisassembler::Success;
  }

  // --- CP qR, #imm16 (sub-opcode 0xCF + 2 bytes imm) ---
  if (SubOpc == 0xCF) {
    if (Bytes.size() < 5)
      return MCDisassembler::Fail;
    uint16_t Imm = readU16LE(Bytes, 3);
    MI.setOpcode(TLCS900::CP_PBW_IMM);
    MI.addOperand(MCOperand::createReg(QReg));
    MI.addOperand(MCOperand::createImm(Imm));
    Size = 5;
    return MCDisassembler::Success;
  }

  // --- Bit operations with trailing byte (4 bytes: D7 + mode + sub + bit) ---
  // 0x23=LDCF, 0x24=STCF, 0x30=RES, 0x31=SET, 0x33=BIT
  if (SubOpc == 0x23 || SubOpc == 0x24 ||
      SubOpc == 0x30 || SubOpc == 0x31 || SubOpc == 0x33) {
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    unsigned BitNum = Bytes[3];
    unsigned Opc;
    switch (SubOpc) {
    case 0x23: Opc = TLCS900::LDCF_PBW; break;
    case 0x24: Opc = TLCS900::STCF_PBW; break;
    case 0x30: Opc = TLCS900::RES_PBW; break;
    case 0x31: Opc = TLCS900::SET_PBW; break;
    case 0x33: Opc = TLCS900::BIT_PBW; break;
    default: llvm_unreachable("handled above");
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(QReg));
    MI.addOperand(MCOperand::createImm(BitNum));
    Size = 4;
    return MCDisassembler::Success;
  }

  // --- INC n, qR (0x60-0x67) and DEC n, qR (0x68-0x6F) ---
  if (SubOpc >= 0x60 && SubOpc <= 0x6F) {
    bool IsInc = (SubOpc < 0x68);
    unsigned I3 = SubOpc & 0x7;
    unsigned Count = (I3 == 0) ? 8 : I3;
    MI.setOpcode(IsInc ? TLCS900::INC_PBW : TLCS900::DEC_PBW);
    MI.addOperand(MCOperand::createImm(Count));
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  }

  // --- LD small immediate: 0xA8-0xAF = LD qR, #small (0-7) ---
  if ((SubOpc & 0xF8) == 0xA8) {
    unsigned SmallImm = SubOpc & 0x7;
    MI.setOpcode(TLCS900::LD_PBW_SI);
    MI.addOperand(MCOperand::createImm(SmallImm));
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  }

  // --- CP small immediate: 0xD8-0xDF = CP qR, #small (0-7) ---
  if ((SubOpc & 0xF8) == 0xD8) {
    unsigned SmallImm = SubOpc & 0x7;
    MI.setOpcode(TLCS900::CP_PBW_SI);
    MI.addOperand(MCOperand::createImm(SmallImm));
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  }

  // --- Register-register ALU operations: sub-opcode = base + rd_enc ---
  // 0x80=ADD, 0x88=LD(to), 0x90=ADC, 0x98=LD(from), 0xA0=SUB, 0xB0=SBC,
  // 0xC0=AND, 0xD0=XOR, 0xE0=OR, 0xF0=CP
  // Also 0x40=MUL
  if (SubOpc >= 0x80) {
    unsigned DstEnc = SubOpc & 0x7;
    unsigned AluBase = SubOpc & 0xF8;
    unsigned DataReg = decodeGR16(DstEnc);

    switch (AluBase) {
    case 0x80: // ADD rd, qR
      MI.setOpcode(TLCS900::ADD_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0x88: // LD rd, qR (load from Q to current)
      MI.setOpcode(TLCS900::LD_PBW_TO);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0x90: // ADC rd, qR
      MI.setOpcode(TLCS900::ADC_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0x98: // LD qR, rd (store current to Q)
      MI.setOpcode(TLCS900::LD_PBW_FR);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0xA0: // SUB rd, qR
      MI.setOpcode(TLCS900::SUB_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0xB0: // SBC rd, qR
      MI.setOpcode(TLCS900::SBC_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0xC0: // AND rd, qR
      MI.setOpcode(TLCS900::AND_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0xD0: // XOR rd, qR
      MI.setOpcode(TLCS900::XOR_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0xE0: // OR rd, qR
      MI.setOpcode(TLCS900::OR_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    case 0xF0: // CP rd, qR
      MI.setOpcode(TLCS900::CP_PBW);
      MI.addOperand(MCOperand::createReg(DataReg));
      MI.addOperand(MCOperand::createReg(QReg));
      Size = 3;
      return MCDisassembler::Success;
    default:
      break;
    }
  }

  // --- MUL rd, qR: 0x40-0x47 ---
  if (SubOpc >= 0x40 && SubOpc <= 0x47) {
    unsigned DstEnc = SubOpc & 0x7;
    unsigned DataReg = decodeGR16(DstEnc);
    MI.setOpcode(TLCS900::MUL_PBW);
    MI.addOperand(MCOperand::createReg(DataReg));
    MI.addOperand(MCOperand::createReg(QReg));
    Size = 3;
    return MCDisassembler::Success;
  }

  return MCDisassembler::Fail;
}

//===----------------------------------------------------------------------===//
// Main instruction decoder
//===----------------------------------------------------------------------===//

MCDisassembler::DecodeStatus TLCS900Disassembler::getInstruction(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, uint64_t Address,
    raw_ostream &CStream) const {
  Size = 0;

  if (Bytes.empty())
    return MCDisassembler::Fail;

  uint8_t FirstByte = Bytes[0];

  // === Single-byte instructions ===
  switch (FirstByte) {
  case 0x00: // NOP
    return decodeSingleByte(MI, Size, TLCS900::NOP);
  case 0x02: // PUSH SR
    return decodeSingleByte(MI, Size, TLCS900::PUSH_SR);
  case 0x03: // POP SR
    return decodeSingleByte(MI, Size, TLCS900::POP_SR);
  case 0x05: // HALT
    return decodeSingleByte(MI, Size, TLCS900::HALT);
  case 0x07: // RETI
    return decodeSingleByte(MI, Size, TLCS900::RETI);
  case 0x0C: // INCF
    return decodeSingleByte(MI, Size, TLCS900::INCF);
  case 0x0D: // DECF
    return decodeSingleByte(MI, Size, TLCS900::DECF);
  case 0x0E: // RET
    return decodeSingleByte(MI, Size, TLCS900::RET);
  case 0x10: // RCF
    return decodeSingleByte(MI, Size, TLCS900::RCF);
  case 0x11: // SCF
    return decodeSingleByte(MI, Size, TLCS900::SCF);
  case 0x12: // CCF
    return decodeSingleByte(MI, Size, TLCS900::CCF);
  case 0x13: // ZCF
    return decodeSingleByte(MI, Size, TLCS900::ZCF);
  case 0x14: // PUSH A
    return decodeSingleByte(MI, Size, TLCS900::PUSH_A);
  case 0x15: // POP A
    return decodeSingleByte(MI, Size, TLCS900::POP_A);
  case 0x16: // EX F, F'
    return decodeSingleByte(MI, Size, TLCS900::EX_FF);
  case 0x18: // PUSH F
    return decodeSingleByte(MI, Size, TLCS900::PUSH_F);
  case 0x19: // POP F
    return decodeSingleByte(MI, Size, TLCS900::POP_F);

  // EI level: 0x06, level_byte — 2 bytes
  case 0x06:
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::EI);
    MI.addOperand(MCOperand::createImm(Bytes[1] & 0x7));
    Size = 2;
    return MCDisassembler::Success;

  // LDIO: 0x08 + addr8 + imm8 — 3 bytes
  case 0x08:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::LDIO);
    MI.addOperand(MCOperand::createImm(Bytes[1]));
    MI.addOperand(MCOperand::createImm(Bytes[2]));
    Size = 3;
    return MCDisassembler::Success;

  // PUSH imm8: 0x09 + imm8 — 2 bytes
  case 0x09:
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::PUSH_imm8);
    MI.addOperand(MCOperand::createImm(Bytes[1]));
    Size = 2;
    return MCDisassembler::Success;

  // LDWIO: 0x0A + addr8 + imm16 — 4 bytes
  case 0x0A:
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::LDWIO);
    MI.addOperand(MCOperand::createImm(Bytes[1]));
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 2)));
    Size = 4;
    return MCDisassembler::Success;

  // PUSHW imm16: 0x0B + imm16 — 3 bytes
  case 0x0B:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::PUSHW_imm);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1)));
    Size = 3;
    return MCDisassembler::Success;

  // RETD: 0x0F + d16 — 3 bytes
  case 0x0F:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::RETD);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1)));
    Size = 3;
    return MCDisassembler::Success;

  // === JP absolute: 0x1B + addr24 — 4 bytes ===
  case 0x1B:
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::JP);
    MI.addOperand(MCOperand::createImm(readU24LE(Bytes, 1)));
    Size = 4;
    return MCDisassembler::Success;

  // === CALL absolute: 0x1D + addr24 — 4 bytes ===
  case 0x1D:
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::CALL);
    MI.addOperand(MCOperand::createImm(readU24LE(Bytes, 1)));
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

  // === SWI: 0xF8-0xFF ===
  case 0xF8: case 0xF9: case 0xFA: case 0xFB:
  case 0xFC: case 0xFD: case 0xFE: case 0xFF:
    MI.setOpcode(TLCS900::SWI);
    MI.addOperand(MCOperand::createImm(FirstByte - 0xF8));
    Size = 1;
    return MCDisassembler::Success;

  default:
    break;
  }

  // === LD r8, #imm8 (short): 0x20+r, imm8 — 2 bytes ===
  if (FirstByte >= 0x20 && FirstByte <= 0x27) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned Reg = decodeGR8(FirstByte & 0x7);
    MI.setOpcode(TLCS900::LD8ri_short);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(Bytes[1]));
    Size = 2;
    return MCDisassembler::Success;
  }

  // === PUSH r16 (short): 0x28+r — 1 byte ===
  if (FirstByte >= 0x28 && FirstByte <= 0x2F) {
    unsigned Reg = decodeGR16(FirstByte & 0x7);
    MI.setOpcode(TLCS900::PUSH16_short);
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 1;
    return MCDisassembler::Success;
  }

  // === LD r16, #imm16 (short): 0x30+r, imm16 — 3 bytes ===
  if (FirstByte >= 0x30 && FirstByte <= 0x37) {
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    unsigned Reg = decodeGR16(FirstByte & 0x7);
    MI.setOpcode(TLCS900::LD16ri_short);
    MI.addOperand(MCOperand::createReg(Reg));
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1)));
    Size = 3;
    return MCDisassembler::Success;
  }

  // === PUSH r32: 0x38+r — 1 byte ===
  if (FirstByte >= 0x38 && FirstByte <= 0x3F) {
    unsigned Reg = decodeGPR(FirstByte & 0x7);
    MI.setOpcode(TLCS900::PUSH32);
    MI.addOperand(MCOperand::createReg(Reg));
    Size = 1;
    return MCDisassembler::Success;
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

  // === POP r16 (short): 0x48+r — 1 byte ===
  if (FirstByte >= 0x48 && FirstByte <= 0x4F) {
    unsigned Reg = decodeGR16(FirstByte & 0x7);
    MI.setOpcode(TLCS900::POP16_short);
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

  // === Byte source memory prefix (no disp): 0x80-0x87 ===
  if (FirstByte >= 0x80 && FirstByte <= 0x87) {
    unsigned BaseReg = FirstByte & 0x7;
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, 0, 1, /*MemSize=*/0);
  }

  // === Byte source memory prefix (d8 disp): 0x88-0x8F ===
  if (FirstByte >= 0x88 && FirstByte <= 0x8F) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned BaseReg = FirstByte & 0x7;
    int8_t Disp = static_cast<int8_t>(Bytes[1]);
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, Disp, 2, /*MemSize=*/0);
  }

  // === Word source memory prefix (no disp): 0x90-0x97 ===
  if (FirstByte >= 0x90 && FirstByte <= 0x97) {
    unsigned BaseReg = FirstByte & 0x7;
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, 0, 1, /*MemSize=*/1);
  }

  // === Word source memory prefix (d8 disp): 0x98-0x9F ===
  if (FirstByte >= 0x98 && FirstByte <= 0x9F) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned BaseReg = FirstByte & 0x7;
    int8_t Disp = static_cast<int8_t>(Bytes[1]);
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, Disp, 2, /*MemSize=*/1);
  }

  // === Long source memory prefix (no disp): 0xA0-0xA7 ===
  if (FirstByte >= 0xA0 && FirstByte <= 0xA7) {
    unsigned BaseReg = FirstByte & 0x7;
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, 0, 1, /*MemSize=*/2);
  }

  // === Long source memory prefix (d8 disp): 0xA8-0xAF ===
  if (FirstByte >= 0xA8 && FirstByte <= 0xAF) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned BaseReg = FirstByte & 0x7;
    int8_t Disp = static_cast<int8_t>(Bytes[1]);
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, Disp, 2, /*MemSize=*/2);
  }

  // === Destination memory prefix (no disp): 0xB0-0xB7 ===
  if (FirstByte >= 0xB0 && FirstByte <= 0xB7) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned BaseReg = FirstByte & 0x7;
    uint8_t SubOp = Bytes[1];

    // CALL (reg): sub-opcode 0xE8
    if (SubOp == 0xE8) {
      MI.setOpcode(TLCS900::CALL_r);
      MI.addOperand(MCOperand::createReg(decodeGPR(BaseReg)));
      Size = 2;
      return MCDisassembler::Success;
    }
    // JP (reg): sub-opcode 0xD8
    if (SubOp == 0xD8) {
      MI.setOpcode(TLCS900::JP_r);
      MI.addOperand(MCOperand::createReg(decodeGPR(BaseReg)));
      Size = 2;
      return MCDisassembler::Success;
    }
    // Delegate stores, LDA, RETcc, JP cc, CALL cc, and store-immediate
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, 0, 1, /*MemSize=*/2,
                           /*IsDstMem=*/true);
  }

  // === Destination memory prefix (d8 disp): 0xB8-0xBF ===
  if (FirstByte >= 0xB8 && FirstByte <= 0xBF) {
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    unsigned BaseReg = FirstByte & 0x7;
    int8_t Disp = static_cast<int8_t>(Bytes[1]);
    return decodeMemPrefix(MI, Size, Bytes, BaseReg, Disp, 2, /*MemSize=*/2,
                           /*IsDstMem=*/true);
  }

  // === 8-bit direct / I/O: C0/D0/E0/F0 ===
  // === Direct addressing: C1/D1/E1/F1 (16-bit addr), C2/D2/E2/F2 (24-bit addr) ===
  // === SRI: C3/D3/E3/F3 ===
  // === SPI (post-inc): C4/D4/E4/F4 ===
  // === SPD (pre-dec): C5/D5/E5/F5 ===
  // === ERP: C7/D7/E7 ===
  if (FirstByte >= 0xC0 && FirstByte <= 0xC7) {
    unsigned SubType = FirstByte & 0x7;
    switch (SubType) {
    case 0: return decodeD8Prefix(MI, Size, Bytes, /*OpSize=*/0);
    case 1: return decodeDirectAddr(MI, Size, Bytes, false, 0, 2);
    case 2: return decodeDirectAddr(MI, Size, Bytes, false, 0, 3);
    case 3: return decodeSRIPrefix(MI, Size, Bytes, false, 0);
    case 4: return decodePIPrefix(MI, Size, Bytes, false, 0, false);
    case 5: return decodePIPrefix(MI, Size, Bytes, false, 0, true);
    case 7: return decodeERPPrefix(MI, Size, Bytes, 0);
    default: return MCDisassembler::Fail;
    }
  }

  // === 8-bit register prefix: 0xC8-0xCF ===
  if (FirstByte >= 0xC8 && FirstByte <= 0xCF) {
    return decodeGR8Prefix(MI, Size, Bytes, FirstByte & 0x7);
  }

  if (FirstByte >= 0xD0 && FirstByte <= 0xD7) {
    unsigned SubType = FirstByte & 0x7;
    switch (SubType) {
    case 0: return decodeD8Prefix(MI, Size, Bytes, /*OpSize=*/1);
    case 1: return decodeDirectAddr(MI, Size, Bytes, false, 1, 2);
    case 2: return decodeDirectAddr(MI, Size, Bytes, false, 1, 3);
    case 3: return decodeSRIPrefix(MI, Size, Bytes, false, 1);
    case 4: return decodePIPrefix(MI, Size, Bytes, false, 1, false);
    case 5: return decodePIPrefix(MI, Size, Bytes, false, 1, true);
    case 7: return decodePrevBankPrefix(MI, Size, Bytes);
    default: return MCDisassembler::Fail;
    }
  }

  // === 16-bit register prefix: 0xD8-0xDF ===
  if (FirstByte >= 0xD8 && FirstByte <= 0xDF) {
    return decodeGR16Prefix(MI, Size, Bytes, FirstByte & 0x7);
  }

  if (FirstByte >= 0xE0 && FirstByte <= 0xE7) {
    unsigned SubType = FirstByte & 0x7;
    switch (SubType) {
    case 0: return decodeD8Prefix(MI, Size, Bytes, /*OpSize=*/2);
    case 1: return decodeDirectAddr(MI, Size, Bytes, false, 2, 2);
    case 2: return decodeDirectAddr(MI, Size, Bytes, false, 2, 3);
    case 3: return decodeSRIPrefix(MI, Size, Bytes, false, 2);
    case 4: return decodePIPrefix(MI, Size, Bytes, false, 2, false);
    case 5: return decodePIPrefix(MI, Size, Bytes, false, 2, true);
    case 7: return decodeERPPrefix(MI, Size, Bytes, 2);
    default: return MCDisassembler::Fail;
    }
  }

  // === 32-bit register prefix: 0xE8-0xEF ===
  if (FirstByte >= 0xE8 && FirstByte <= 0xEF) {
    return decodeRegPrefix(MI, Size, Bytes, FirstByte & 0x7);
  }

  // === Destination prefixes: F0-F7 ===
  if (FirstByte >= 0xF0 && FirstByte <= 0xF7) {
    unsigned SubType = FirstByte & 0x7;
    switch (SubType) {
    case 0: return decodeD8Prefix(MI, Size, Bytes, /*OpSize=*/2, /*IsDst=*/true);
    case 1: return decodeDirectAddr(MI, Size, Bytes, true, 2, 2);
    case 2: return decodeDirectAddr(MI, Size, Bytes, true, 2, 3);
    case 3: return decodeSRIPrefix(MI, Size, Bytes, true, 2);
    case 4: return decodePIPrefix(MI, Size, Bytes, true, 2, false);
    case 5: return decodePIPrefix(MI, Size, Bytes, true, 2, true);
    case 7: // 0xF7 = LDX (block transfer exchange)
      MI.setOpcode(TLCS900::LDX);
      Size = 1;
      return MCDisassembler::Success;
    default: return MCDisassembler::Fail;
    }
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
