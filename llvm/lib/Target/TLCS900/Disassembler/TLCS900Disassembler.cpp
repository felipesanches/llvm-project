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
  /// Decode the SRI register+register indexed forms: mode byte 0x07 (16-bit
  /// index register) or 0x03 (8-bit index register). Called from
  /// decodeSRIPrefix once it recognises one of those two fixed mode bytes.
  DecodeStatus decodeSriRRPrefix(MCInst &MI, uint64_t &Size,
                                 ArrayRef<uint8_t> Bytes, bool IsDst,
                                 unsigned OpSize, bool Is8BitIndex) const;
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

// Map 3-bit register encoding to PrevGR16 (Q) register. Defined further
// below, alongside the PrevBank (D7) decoder that is its main user.
static unsigned decodeQReg(unsigned Enc);

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
// Source-memory-prefix ALU sub-opcode tables
//===----------------------------------------------------------------------===//
// The 0x80/0x90/0xA0 prefixes (byte/word/long source memory) share one
// sub-opcode table whose upper half is the ALU family.  Each operation owns a
// pair of adjacent 8-entry rows -- the register-destination direction first,
// the memory-destination direction second:
//
//   0x80 ADD r,(mem)   0x88 ADD (mem),r      0xC0 AND r,(mem)   0xC8 AND (mem),r
//   0x90 ADC r,(mem)   0x98 ADC (mem),r      0xD0 XOR r,(mem)   0xD8 XOR (mem),r
//   0xA0 SUB r,(mem)   0xA8 SUB (mem),r      0xE0 OR  r,(mem)   0xE8 OR  (mem),r
//   0xB0 SBC r,(mem)   0xB8 SBC (mem),r      0xF0 CP  r,(mem)   0xF8 CP  (mem),r
//
// so bits 4-6 of the sub-opcode select the operation, bit 3 the direction and
// bits 0-2 the register.  Indexed [MemSize][op] with op in that 0..7 order.
// ⚠ These rows are the ORDER THE HARDWARE USES, which is not the order of
// ALUri/ALUrr above (ADD, ADC, SUB, SBC, AND, XOR, OR, CP): there AND/XOR/OR
// are 0xCC/0xCD/0xCE, here they are 0xC0/0xD0/0xE0.  Same eight operations,
// different table.
static const unsigned ALUrm[3][8] = {
  {TLCS900::ADD8rm, TLCS900::ADC8rm, TLCS900::SUB8rm, TLCS900::SBC8rm,
   TLCS900::AND8rm, TLCS900::XOR8rm, TLCS900::OR8rm, TLCS900::CP8rm},
  {TLCS900::ADD16rm, TLCS900::ADC16rm, TLCS900::SUB16rm, TLCS900::SBC16rm,
   TLCS900::AND16rm, TLCS900::XOR16rm, TLCS900::OR16rm, TLCS900::CP16rm},
  {TLCS900::ADD32rm, TLCS900::ADC32rm, TLCS900::SUB32rm, TLCS900::SBC32rm,
   TLCS900::AND32rm, TLCS900::XOR32rm, TLCS900::OR32rm, TLCS900::CP32rm},
};

static const unsigned ALUmr[3][8] = {
  {TLCS900::ADD8mr, TLCS900::ADC8mr, TLCS900::SUB8mr, TLCS900::SBC8mr,
   TLCS900::AND8mr, TLCS900::XOR8mr, TLCS900::OR8mr, TLCS900::CP8mr},
  {TLCS900::ADD16mr, TLCS900::ADC16mr, TLCS900::SUB16mr, TLCS900::SBC16mr,
   TLCS900::AND16mr, TLCS900::XOR16mr, TLCS900::OR16mr, TLCS900::CP16mr},
  {TLCS900::ADD32mr, TLCS900::ADC32mr, TLCS900::SUB32mr, TLCS900::SBC32mr,
   TLCS900::AND32mr, TLCS900::XOR32mr, TLCS900::OR32mr, TLCS900::CP32mr},
};

// ALU (mem), #imm -- sub-opcodes 0x38-0x3F, in the SAME operation order as
// the rows above.  There is no 32-bit row: the long source table (0xA0) has
// no memory-immediate ALU, which is why the .td's ADD32mi/SUB32mi/CP32mi are
// isCodeGenOnly with opcodes borrowed from the register-immediate table.  A
// third row here would decode 0xA?/0x3F bytes into text that re-encodes to
// something else entirely, so the table stops at two and MemSize == 2 falls
// through to the ordinary refusal.
static const unsigned ALUmi[2][8] = {
  {TLCS900::ADD8mi, TLCS900::ADC8mi, TLCS900::SUB8mi, TLCS900::SBC8mi,
   TLCS900::AND8mi, TLCS900::XOR8mi, TLCS900::OR8mi, TLCS900::CP8mi},
  {TLCS900::ADD16mi, TLCS900::ADC16mi, TLCS900::SUB16mi, TLCS900::SBC16mi,
   TLCS900::AND16mi, TLCS900::XOR16mi, TLCS900::OR16mi, TLCS900::CP16mi},
};

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

    // EX register-register: prefix(rs1) + (0xB8 + rs2_enc) -- 8/16-bit only.
    // EXops[2] is TLCS900::EX32, which TLCS900InstrInfo.td documents itself
    // as codegen-only and "NOT E8 (32-bit)": it is a 4-operand tied pseudo
    // (2 outs + 2 ins) kept for a future ISel pattern, not a real 2-operand
    // asm form like EX8/EX16. Handing it only 2 decoded operands (as this
    // branch used to, for every OpSize) left encodeInstruction reading past
    // the end of the MCInst's operand list whenever OpSize==2 was reached --
    // confirmed 2026-09-02: raw bytes `ee bf` (E8-prefix + 0xB8 sub-opcode)
    // aborts with "SmallVector idx < size()" in
    // TLCS900MCCodeEmitter::encodeInstruction, found in v7's
    // AccTone_InlineBytecodeData. No committed source can depend on the old
    // behaviour: it never once returned to a caller without crashing the
    // process. Refuse the 32-bit case outright rather than invent an
    // encoding nobody has confirmed exists on real hardware.
    if (AluBase == 0xB8 && OpSize < 2) {
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
  // The 3-byte (Xrr+d8) encoding and the 2-byte (Xrr) encoding print
  // IDENTICALLY through printMemOperand when the true displacement is zero
  // -- both show "(reg)" -- so an instruction actually decoded from the
  // longer, explicit-d8=0 form could not be told apart from the shorter
  // form, and re-assembling the disassembler's own output always picked the
  // shorter encoding. emitMemPrefix already reserves a sentinel for this
  // (Disp == 256 means "force the d8 form with displacement 0"); nothing
  // upstream ever produced it. PrefixSize == 2 means a disp8 byte was
  // actually consumed, so a real zero there is exactly that case.
  if (PrefixSize == 2 && Disp == 0)
    Disp = 256;

  // The SAME collision exists one width up: the SRI-prefixed 4-byte
  // (Xrr+d16) encoding with an explicit d16 of 0x0000 prints identically to
  // the 1-byte (Xrr) form (both "(reg)"), and reassembly always re-picks the
  // shortest encoding. Confirmed 2026-09-02 on v7's
  // PanelEvt_Handler_4_DualValueCheck: raw bytes `c3 f9 00 00` (SRI prefix +
  // mode 0xF9 = Xrr+d16, base=xiz + d16=0x0000) decode to a bare "(xiz)"
  // that reassembles two bytes shorter than the original four -- the same
  // print/encode collapse `975a2c17d683` fixed for PrefixSize==2, just never
  // extended to PrefixSize==4. Mirrors that fix exactly: emitMemPrefix
  // reserves 65536 (outside any real d16's -32768..32767 range, so it can
  // never collide with a genuine displacement) to force this 4-byte form
  // with a real displacement of 0; PrefixSize == 4 means a real d16 pair was
  // actually consumed, so a real zero there is exactly that case.
  if (PrefixSize == 4 && Disp == 0)
    Disp = 65536;

  unsigned OpByteIdx = PrefixSize;
  if (Bytes.size() <= OpByteIdx)
    return MCDisassembler::Fail;

  uint8_t OpByte = Bytes[OpByteIdx];
  unsigned Base = decodeGPR(BaseReg);

  // Block transfer instructions: sub-opcodes 0x10-0x17 of the byte (0x80) and
  // word (0x90) source memory tables.
  //
  // ⚠ The base-register field of the prefix is part of the encoding even
  // though the hardware ignores it for these, and the firmware does not always
  // write 0: v10 has `83 11`, `85 10`, `85 13`, `93 11`, `95 10`.  Each such
  // combination has its OWN instruction definition carrying the index (LDIR83,
  // LDI85, LDIRW93, ...), because the plain LDI/LDIR/... always encode the
  // field as 0.  Decoding every index to the plain spelling therefore lost the
  // byte -- `83 11` printed "ldir" and re-assembled to `80 11`.
  //
  // Only the (size, index, sub-opcode) combinations that have a definition are
  // decoded.  An index with no spelling is REFUSED rather than rounded to the
  // nearest one: this tree has no source for it, and a decode that
  // re-assembles to different bytes is worse than none.
  if (MemSize <= 1 && OpByte >= 0x10 && OpByte <= 0x17 && PrefixSize == 1) {
    struct BlockXferEntry {
      uint8_t MemSize, RegIdx, Sub;
      unsigned Opc;
    };
    static const BlockXferEntry BlockXferOps[] = {
        {0, 0, 0x10, TLCS900::LDI},     {0, 0, 0x11, TLCS900::LDIR},
        {0, 0, 0x12, TLCS900::LDD},     {0, 0, 0x13, TLCS900::LDDR},
        {0, 0, 0x14, TLCS900::CPI},     {0, 0, 0x15, TLCS900::CPIR},
        {0, 0, 0x16, TLCS900::CPD},     {0, 0, 0x17, TLCS900::CPDR},
        {0, 3, 0x11, TLCS900::LDIR83},  {0, 3, 0x13, TLCS900::LDDR83},
        {0, 3, 0x15, TLCS900::CPIR83},
        {0, 5, 0x10, TLCS900::LDI85},   {0, 5, 0x11, TLCS900::LDIR85},
        {0, 5, 0x13, TLCS900::LDDR85},
        {1, 3, 0x11, TLCS900::LDIRW93},
        {1, 5, 0x10, TLCS900::LDIW},    {1, 5, 0x11, TLCS900::LDIRW},
    };
    for (const auto &E : BlockXferOps) {
      if (E.MemSize == MemSize && E.RegIdx == BaseReg && E.Sub == OpByte) {
        MI.setOpcode(E.Opc);
        Size = PrefixSize + 1;
        return MCDisassembler::Success;
      }
    }
    return MCDisassembler::Fail;
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
    // LDW (mem), #imm16 -- sub-opcode 0x02, distinct from the redundant
    // 0x14 hardware encoding (TLCS900::LD16mi_dst, mnemonic "ldmi16").
    // Both produce identical 16-bit stores, but they are NOT the same
    // instruction definition: LD16mi_dst's declared opcode is 0x14, so
    // setting it here for 0x02 bytes made the disassembler print text
    // ("ldmi16 (mem), #imm") whose own encoder emits the WRONG sub-opcode
    // (0x14) when re-assembled -- a decode/encode asymmetry caught by the
    // subcpu v142 DSP_Bytecode round-trip (bf 04 02 01 00 -> "ldmi16
    // (xsp+4), 1" -> re-encoded as bf 04 14 01 00). Use the matching
    // LD16mi_dst_02 definition (mnemonic "ldw") instead, already proven at
    // ~30 real ROM sites (e.g. v142/subcpu/kn5000_subprogram_v142.s).
    if (Bytes.size() < OpByteIdx + 3)
      return MCDisassembler::Fail;
    uint16_t Imm = readU16LE(Bytes, OpByteIdx + 1);
    MI.setOpcode(TLCS900::LD16mi_dst_02);
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

  // PUSH (mem): sub-opcode 0x04 (byte/word source tables only).
  // ⚠ PUSHB_m/PUSHW_m, NOT PUSH8/PUSH16.  The latter are the one-byte
  // register pushes (0x38+r); decoding to them threw the memory prefix away,
  // so `92 04` ("pushm (xde)") printed as "push xde" and re-assembled to the
  // single byte 0x3a -- a three-to-one byte loss that nothing reported.
  if (OpByte == 0x04 && MemSize <= 1) {
    MI.setOpcode(MemSize == 0 ? TLCS900::PUSHB_m : TLCS900::PUSHW_m);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
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

  // RETcc: sub-opcode 0xF0-0xFF (B0 destination table only).
  //
  // The condition is all RETcc carries, but the prefix byte still holds a
  // base-register field the instruction does not use, and the hardware
  // ignores it.  RETcc's own encoding writes that field as 0, so decoding
  // every prefix to RETcc loses it: v7/v9's `b6 f9` came back as "ret ge" and
  // re-assembled to `b0 f9`.  RET_CC_RI is the spelling that keeps the
  // register, so use it whenever the field is not 0.
  //
  // A d8 prefix (0xB8-0xBF) has no spelling at all here -- RET_CC_RI is a
  // two-byte form -- and no source in this tree writes one, so it is refused
  // rather than decoded to something that re-assembles two bytes shorter.
  if (IsDstMem && OpByte >= 0xF0) {
    if (PrefixSize != 1)
      return MCDisassembler::Fail;
    unsigned CC = OpByte & 0xF;
    if (BaseReg == 0) {
      MI.setOpcode(TLCS900::RETcc);
      MI.addOperand(MCOperand::createImm(CC));
    } else {
      MI.setOpcode(TLCS900::RET_CC_RI);
      MI.addOperand(MCOperand::createReg(Base));
      MI.addOperand(MCOperand::createImm(CC));
    }
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // JP cc, (mem) and CALL cc, (mem) -- destination table sub-opcodes
  // 0xD0-0xDF and 0xE0-0xEF, condition in the low four bits.  Built from
  // JPCC_m/CALLCC_m (MemDstCCInst), whose emitter case reads its operands as
  // base, disp, cc; MAME's independent TLCS-900 disassembler reads `b1 d1` the
  // same way ("jp NZ,(XBC)").
  //
  // ⚠ This branch used to repurpose JPcc and CALLCC_24 -- the unrelated
  // 0x70-prefixed short-branch and F2 direct-address encodings -- passing a
  // Reg where their `brtarget`/`directaddr` operand is printed with an
  // unconditional MCOperand::getImm(), so ANY byte reaching here aborted the
  // process ("This is not an immediate", MCInst.h:82).  It was then made to
  // Fail outright for want of a ground truth.  Do not reintroduce an operand
  // order taken from anywhere but the instruction's own declared list.
  if (IsDstMem && OpByte >= 0xD0 && OpByte <= 0xEF) {
    MI.setOpcode(OpByte < 0xE0 ? TLCS900::JPCC_m : TLCS900::CALLCC_m);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createImm(OpByte & 0xF));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // --- Destination memory table: the forms with no register in the opcode ---
  //
  // These occupy sub-opcodes the SOURCE table gives to ALU operations, so they
  // must be settled before the ALU tables below are consulted -- and the ALU
  // tables must not be consulted for a destination prefix at all.  Reading
  // them there is not a missing decode but a WRONG one: `b3 c8` is
  // "bit 0, (xhl)" and used to come back as "and (xhl), xwa", which
  // re-assembles to `a3 c8` -- different bytes, silently.
  if (IsDstMem) {
    // POP/POPW (mem) and the carry-flag group ANDCF/ORCF/XORCF/LDCF/STCF
    // A,(mem): fixed opcode byte, no register and no bit number.
    struct DstUnaryEntry { uint8_t Sub; unsigned Opc; };
    static const DstUnaryEntry DstUnaryOps[] = {
        {0x04, TLCS900::POPB_m},   {0x06, TLCS900::POPW_m},
        {0x28, TLCS900::ANDCFA_m}, {0x29, TLCS900::ORCFA_m},
        {0x2A, TLCS900::XORCFA_m}, {0x2B, TLCS900::LDCFA_m},
        {0x2C, TLCS900::STCFA_m},
    };
    for (const auto &E : DstUnaryOps) {
      if (OpByte == E.Sub) {
        MI.setOpcode(E.Opc);
        MI.addOperand(MCOperand::createReg(Base));
        MI.addOperand(MCOperand::createImm(Disp));
        Size = PrefixSize + 1;
        return MCDisassembler::Success;
      }
    }

    // Bit operations: base sub-opcode + bit number in bits 0-2.
    struct DstBitEntry { uint8_t Base; unsigned Opc; };
    static const DstBitEntry DstBitOps[] = {
        {0x98, TLCS900::LDCFm}, {0xA0, TLCS900::STCFm},
        {0xA8, TLCS900::TSETm}, {0xB0, TLCS900::RESm},
        {0xB8, TLCS900::SETm},  {0xC0, TLCS900::CHGm},
        {0xC8, TLCS900::BITm},
    };
    for (const auto &E : DstBitOps) {
      if ((OpByte & 0xF8) == E.Base) {
        MI.setOpcode(E.Opc);
        MI.addOperand(MCOperand::createReg(Base));
        MI.addOperand(MCOperand::createImm(Disp));
        MI.addOperand(MCOperand::createImm(OpByte & 0x7));
        Size = PrefixSize + 1;
        return MCDisassembler::Success;
      }
    }

    // Nothing else in the destination table has a decode yet.  Refusing here
    // rather than falling into the source table's ALU rows is the point of
    // this whole block.
    return MCDisassembler::Fail;
  }

  // ⚠ NO decode for source-table sub-opcodes 0x28-0x2F.  LD8mr_src /
  // LD16mr_src / LD32mr_src claim that range for "LD (mem), rs", but MAME's
  // TLCS-900 disassembler renders `80 28`, `90 28` and `a0 28` as `db` -- not
  // an instruction -- and no committed source in the kn5000-roms-disasm tree
  // contains a single statement with that sub-opcode in a source memory
  // prefix (censused over v7, v9 and v10 by
  // scripts/analysis/mem_subopcode_gap_census.py).  A decode with no ground
  // truth in either direction is exactly what this file refuses to guess.

  // --- Source memory table: EX (mem), r at 0x30-0x37 ---
  // Byte and word only; the long source table does not carry these.
  if (OpByte >= 0x30 && OpByte <= 0x37 && MemSize <= 1) {
    MI.setOpcode(MemSize == 0 ? TLCS900::EX8m : TLCS900::EX16m);
    MI.addOperand(MCOperand::createReg(decodeRegForSize(OpByte & 0x7, MemSize)));
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // --- Source memory table: MUL/MULS/DIV/DIVS rd, (mem) at 0x40-0x5F ---
  if (OpByte >= 0x40 && OpByte <= 0x5F && MemSize <= 1) {
    static const unsigned MULDIVm[4][2] = {
        {TLCS900::MUL8m, TLCS900::MUL16m},
        {TLCS900::MULS8m, TLCS900::MULS16m},
        {TLCS900::DIV8m, TLCS900::DIV16m},
        {TLCS900::DIVS8m, TLCS900::DIVS16m},
    };
    MI.setOpcode(MULDIVm[(OpByte >> 3) & 0x3][MemSize]);
    MI.addOperand(MCOperand::createReg(decodeRegForSize(OpByte & 0x7, MemSize)));
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // --- Source memory table: shift/rotate (mem) at 0x78-0x7F ---
  // ⚠ The sub-opcode order is rlc rrc rl rr sla sra sll srl -- not
  // alphabetical, and sla/sll have been transposed once already in this
  // project.  It matches the def order in TLCS900InstrInfo.td exactly.
  if (OpByte >= 0x78 && OpByte <= 0x7F && MemSize <= 1) {
    static const unsigned SHIFTm[8][2] = {
        {TLCS900::RLC8m, TLCS900::RLC16m}, {TLCS900::RRC8m, TLCS900::RRC16m},
        {TLCS900::RL8m, TLCS900::RL16m},   {TLCS900::RR8m, TLCS900::RR16m},
        {TLCS900::SLA8m, TLCS900::SLA16m}, {TLCS900::SRA8m, TLCS900::SRA16m},
        {TLCS900::SLL8m, TLCS900::SLL16m}, {TLCS900::SRL8m, TLCS900::SRL16m},
    };
    MI.setOpcode(SHIFTm[OpByte & 0x7][MemSize]);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // --- Source memory table: ALU (mem), #imm at 0x38-0x3F ---
  // Byte and word only; see ALUmi's comment for why there is no long row.
  if (OpByte >= 0x38 && OpByte <= 0x3F && MemSize <= 1) {
    unsigned NumImm = immBytesForSize(MemSize);
    if (Bytes.size() < OpByteIdx + 1 + NumImm)
      return MCDisassembler::Fail;
    MI.setOpcode(ALUmi[MemSize][OpByte & 0x7]);
    MI.addOperand(MCOperand::createReg(Base));
    MI.addOperand(MCOperand::createImm(Disp));
    MI.addOperand(MCOperand::createImm(readImmLE(Bytes, OpByteIdx + 1, NumImm)));
    Size = PrefixSize + 1 + NumImm;
    return MCDisassembler::Success;
  }

  // --- Source memory table: the ALU family at 0x80-0xFF ---
  // Bits 4-6 pick the operation, bit 3 the direction, bits 0-2 the register.
  if (OpByte >= 0x80) {
    unsigned AluIdx = (OpByte >> 4) & 0x7;
    unsigned Reg = decodeRegForSize(OpByte & 0x7, MemSize);
    if (OpByte & 0x08) {
      // OP (mem), r -- memory is the destination, register the source.
      MI.setOpcode(ALUmr[MemSize][AluIdx]);
      MI.addOperand(MCOperand::createReg(Base));
      MI.addOperand(MCOperand::createImm(Disp));
      MI.addOperand(MCOperand::createReg(Reg));
    } else {
      // OP r, (mem) -- register is the destination.
      MI.setOpcode(ALUrm[MemSize][AluIdx]);
      MI.addOperand(MCOperand::createReg(Reg));
      MI.addOperand(MCOperand::createReg(Base));
      MI.addOperand(MCOperand::createImm(Disp));
    }
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
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
        // Reg-destination: reg = reg op (addr). The is24 (second) slot below
        // is always the "_gpr"-suffixed TLCS900InstrInfo.td sibling, not the
        // plain "_da24" one: this table always builds the register operand
        // with decodeGPR() a few lines down, and the plain "_da24" names are
        // declared GR8 to match existing hand-written source that spells
        // them with a GR8 letter ("cpda8_24 a, (addr)") -- see that
        // TableGen block's comment. Using the plain name here would hand a
        // GPR-enum register to a GR8-typed operand and silently produce
        // text that cannot reassemble, exactly the bug this table's own
        // comment above already documents for the is16 slot.
        {0x80, {TLCS900::ADD8_da16, TLCS900::ADD8_da24_gpr},
               {TLCS900::ADD16_da16, TLCS900::ADD16_da24},
               {TLCS900::ADD32_da16, TLCS900::ADD32_da24}, true},
        {0xA0, {TLCS900::SUB8_da16, TLCS900::SUB8_da24_gpr},
               {TLCS900::SUB16_da16, TLCS900::SUB16_da24},
               {TLCS900::SUB32_da16, TLCS900::SUB32_da24}, true},
        {0xC0, {TLCS900::AND8_da16, TLCS900::AND8_da24_gpr},
               {TLCS900::AND16_da16, TLCS900::AND16_da24},
               {0, 0}, true},
        {0xD0, {TLCS900::XOR8_da16, TLCS900::XOR8_da24_gpr},
               {0, 0}, {0, 0}, true},
        {0xE0, {TLCS900::OR8_da16, TLCS900::OR8_da24_gpr},
               {TLCS900::OR16_da16, TLCS900::OR16_da24},
               {0, 0}, true},
        {0xF0, {TLCS900::CP8_da16, TLCS900::CP8_da24_gpr},
               {TLCS900::CP16_da16, TLCS900::CP16_da24},
               {TLCS900::CP32_da16, TLCS900::CP32_da24}, false},
        // Mem-destination: (addr) = (addr) op reg
        {0x88, {TLCS900::ADD8m_da16, TLCS900::ADD8m_da24_gpr},
               {TLCS900::ADD16m_da16, TLCS900::ADD16m_da24},
               {TLCS900::ADD32m_da16, TLCS900::ADD32m_da24}, false},
        {0xA8, {TLCS900::SUB8m_da16, TLCS900::SUB8m_da24_gpr},
               {TLCS900::SUB16m_da16, TLCS900::SUB16m_da24},
               {TLCS900::SUB32m_da16, TLCS900::SUB32m_da24}, false},
        {0xC8, {TLCS900::AND8m_da16, TLCS900::AND8m_da24_gpr},
               {TLCS900::AND16m_da16, TLCS900::AND16m_da24},
               {0, 0}, false},
        {0xD8, {TLCS900::XOR8m_da16, TLCS900::XOR8m_da24_gpr},
               {TLCS900::XOR16m_da16, TLCS900::XOR16m_da24},
               {0, 0}, false},
        {0xE8, {TLCS900::OR8m_da16, TLCS900::OR8m_da24_gpr},
               {TLCS900::OR16m_da16, TLCS900::OR16m_da24},
               {0, 0}, false},
        {0xF8, {TLCS900::CP8m_da16, TLCS900::CP8m_da24_gpr},
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
        // Every entry in DALUOps (reg-dst ADD/SUB/AND/XOR/OR/CP *and*
        // mem-dst ADDm/SUBm/...) declares its register operand as plain
        // GPR (the 32-bit xNN class) in TLCS900InstrInfo.td, at every data
        // width (8/16/32) -- confirmed by ~20 already-shipped ROM sites
        // that spell it "cpda16_24 xhl, (addr)", never "hl, (addr)". There
        // is no GR8/GR16-class overload for this family (unlike the plain
        // `ld reg,(addr)` forms just above, which have one). So the
        // register here must always decode as GPR regardless of OpSize;
        // decodeRegForSize(RegEnc, OpSize) produced an 8/16-bit register
        // name (e.g. "wa") that the sole matching definition's GPR operand
        // class then rejects on re-assembly -- caught by round-tripping
        // subcpu v142's TaskSched/TaskEvent .byte runs (bytes d1 40 10 80
        // decoded as "addda16 wa, (4160)", which does not re-encode; the
        // correct, encodable spelling is "addda16 xwa, (4160)").
        unsigned Reg = decodeGPR(RegEnc);
        if (Op.IsRegDst) {
          // reg = reg op (addr): 3 operands (dst, src1_tied, addr)
          MI.addOperand(MCOperand::createReg(Reg));
          MI.addOperand(MCOperand::createReg(Reg));
          MI.addOperand(MCOperand::createImm(Addr));
        } else if (AluBase & 0x08) {
          // (addr) = (addr) op reg: 2 operands (addr, src).
          // The mem-dst sub-opcodes are 0x88/0xA8/0xC8/0xD8/0xE8/0xF8 --
          // bit 3 set -- versus the reg-dst/CP family 0x80/0xA0/.../0xF0
          // with bit 3 clear.  The previous `AluBase >= 0x88` test does
          // not distinguish them: CP's base 0xF0 (240) is numerically
          // >= 0x88 (136) too, so `cpda16`/`cpda16_24` were wrongly routed
          // into this branch with (addr, src) operand order -- printed
          // backwards, e.g. "cpda16 4160, (wa)" instead of "cpda16 xwa,
          // (4160)" -- while CP16_da16's declared operand order is
          // (src, addr), so the wrong-order MCOperands never matched the
          // instruction actually selected by MI.setOpcode(Opc) above.
          MI.addOperand(MCOperand::createImm(Addr));
          MI.addOperand(MCOperand::createReg(Reg));
        } else {
          // CP reg, (addr): 2 operands (src, addr)
          MI.addOperand(MCOperand::createReg(Reg));
          MI.addOperand(MCOperand::createImm(Addr));
        }
        Size = PrefixSize + 1;
        return MCDisassembler::Success;
      }
    }
  }

  // ALU (addr), #imm: source table sub-opcodes 0x38-0x3F, immediate width from
  // the prefix (byte prefix -> imm8, word prefix -> imm16).  This is the same
  // family, and the same operation order, as ALUmi in the register-indirect
  // decoder; the long tables have none, and the entries the .td does not
  // define are 0 here and refused rather than rounded to a neighbour.
  if (!IsDst && SubOp >= 0x38 && SubOp <= 0x3F && OpSize <= 1) {
    //                    ADD    ADC    SUB    SBC    AND    XOR    OR     CP
    static const unsigned DALUmi[2][2][8] = {
      { // 8-bit operand
        {TLCS900::ADD8i_da16, 0, TLCS900::SUB8i_da16, 0,
         TLCS900::AND8i_da16, TLCS900::XOR8i_da16, TLCS900::OR8i_da16,
         TLCS900::CP8i_da16},
        {TLCS900::ADD8i_da24, TLCS900::ADC8i_da24, TLCS900::SUB8i_da24,
         TLCS900::SBC8i_da24, TLCS900::AND8i_da24, TLCS900::XOR8i_da24,
         TLCS900::OR8i_da24, TLCS900::CP8i_da24},
      },
      { // 16-bit operand
        {TLCS900::ADD16i_da16, 0, TLCS900::SUB16i_da16, 0,
         TLCS900::AND16i_da16, 0, TLCS900::OR16i_da16, TLCS900::CP16i_da16},
        {TLCS900::ADD16i_da24, 0, TLCS900::SUB16i_da24, 0,
         TLCS900::AND16i_da24, 0, TLCS900::OR16i_da24, TLCS900::CP16i_da24},
      },
    };
    unsigned Opc = DALUmi[OpSize][AddrBytes == 3][SubOp & 0x7];
    if (!Opc)
      return MCDisassembler::Fail;
    unsigned NumImm = immBytesForSize(OpSize);
    if (Bytes.size() < SubOpIdx + 1 + NumImm)
      return MCDisassembler::Fail;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(readImmLE(Bytes, SubOpIdx + 1, NumImm)));
    Size = PrefixSize + 1 + NumImm;
    return MCDisassembler::Success;
  }

  // LD (addr), (addr): source table sub-opcode 0x19, memory to memory.  The
  // prefix's address is the SOURCE and a second 16-bit address follows the
  // sub-opcode; LDmm8_da16/LDmm16_da16 take them in that order and print them
  // the other way round.  16-bit source addresses only -- there is no 24-bit
  // definition, and the register-indirect spelling of this instruction has no
  // definition at all (see mem_subopcode_gap_census.py).
  if (!IsDst && SubOp == 0x19 && OpSize <= 1 && AddrBytes == 2) {
    if (Bytes.size() < SubOpIdx + 3)
      return MCDisassembler::Fail;
    MI.setOpcode(OpSize == 0 ? TLCS900::LDmm8_da16 : TLCS900::LDmm16_da16);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, SubOpIdx + 1)));
    Size = PrefixSize + 3;
    return MCDisassembler::Success;
  }

  // Bit operations on a direct address: destination table.
  //
  // ⚠ THE SUB-OPCODES ARE THE SAME AS THE REGISTER-INDIRECT DESTINATION
  // TABLE'S -- 0x98 LDCF, 0xA0 STCF, 0xA8 TSET, 0xB0 RES, 0xB8 SET, 0xC0 CHG,
  // 0xC8 BIT -- and this branch used to map 0xA0/0xA8/0xB0 to BIT/RES/SET,
  // one whole group out of step.  It was not a refusal but a WRONG decode
  // that no round-trip test then existed to catch: v10's `f1 13 04 b0`
  // ("res 0, (1043)") came back as "setda 0, (1043)" and re-assembled to
  // `f1 13 04 b8`.  157 distinct v10 samples were affected.  Confirmed
  // against MAME unidasm on all seven sub-opcodes.
  //
  // Only the four with a matching definition are decoded.  ⚠ TSET_da16 and
  // TSET_da24 are declared with opcode 0xA0, which is STCF; decoding 0xA0 to
  // them would round-trip and still be the wrong instruction, so 0x98/0xA0/
  // 0xA8 are refused until correctly-named definitions exist.  Fixing those
  // two opcodes is an ENCODING change and deliberately not made here.
  if (IsDst && SubOp >= 0x98 && SubOp <= 0xCF) {
    bool Is24 = (AddrBytes == 3);
    unsigned Opc = 0;
    switch (SubOp & 0xF8) {
    case 0xB0: Opc = Is24 ? TLCS900::RES_da24 : TLCS900::RES_da16; break;
    case 0xB8: Opc = Is24 ? TLCS900::SET_da24 : TLCS900::SET_da16; break;
    case 0xC0: Opc = Is24 ? TLCS900::CHG_da24 : 0; break;
    case 0xC8: Opc = Is24 ? TLCS900::BIT_da24 : TLCS900::BIT_da16; break;
    default: break;
    }
    if (!Opc)
      return MCDisassembler::Fail;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(SubOp & 0x7));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // JP cc, (addr) / CALL cc, (addr): destination sub-opcodes 0xD0-0xEF,
  // 24-bit address only (JPCC_24/CALLCC_24 are the only definitions).
  if (IsDst && SubOp >= 0xD0 && SubOp <= 0xEF && AddrBytes == 3) {
    MI.setOpcode(SubOp < 0xE0 ? TLCS900::JPCC_24 : TLCS900::CALLCC_24);
    MI.addOperand(MCOperand::createImm(Addr));
    MI.addOperand(MCOperand::createImm(SubOp & 0xF));
    Size = PrefixSize + 1;
    return MCDisassembler::Success;
  }

  // ⚠ NO RETcc here.  Sub-opcodes 0xF0-0xFF after a direct-address prefix
  // used to decode to plain RETcc, whose own encoding is the two bytes
  // `B0, F0+cc` -- so `f1 aa 28 f9` printed "ret ge" and re-assembled four
  // bytes shorter, into a different instruction.  There is no direct-address
  // RET definition, and no source in this tree writes one.

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

  // Register+register indexed addressing: mode byte is the fixed marker
  // 0x07 (16-bit index register) or 0x03 (8-bit index register), not a
  // base-register-encoded mode byte -- both values are far below 0xE0, so
  // they must be recognised here before the `Mode < 0xE0` rejection below.
  if (Mode == 0x07 || Mode == 0x03)
    return decodeSriRRPrefix(MI, Size, Bytes, IsDst, OpSize, Mode == 0x03);

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
// SRI Register+Register (R+R) indexed addressing decoder
//===----------------------------------------------------------------------===//
//
// Format: [prefix, 0x07 or 0x03, base_addr, idx_addr, SubOpc(+reg|+cc|+imm3)
//          [, trailing imm bytes]]
// base_addr = 0xE0 + base_enc*4 (always a 32-bit GPR, current bank).
// mode 0x07 (16-bit index): idx_addr = 0xE0 + idx_enc*4 (current-bank GR16),
//   or +2 for a PREVIOUS-BANK (Q) register -- only LDA_RRQ uses that form.
// mode 0x03 (8-bit index): idx_addr addresses a GR8 sub-byte of WA/BC/DE/HL
//   only, using the byte-addressed register file (low half at +0, high half
//   at +1 -- see TLCS900MCCodeEmitter.cpp's SriRR8Reg case for the encoder
//   side of this same formula).
//
// The encoder for this whole family only applies the OpSize-based prefix
// bump (C3->D3->E3) when Opcode < 0xF0 (see TLCS900MCCodeEmitter.cpp): the
// source loads (LD_RR*, prefix C3/D3/E3) size themselves via the PREFIX, so
// OpSize here is reliable and comes straight from the outer dispatch. The
// destination forms (ST_RR*, LDA_RR, JP_RR, CALL_RR; fixed prefix F3) size
// themselves via the SUB-OPCODE instead (0x40/0x50/0x60 for byte/word/long)
// -- confirmed by direct ROM evidence, not guessed: `f3 07 e4 e0 31`
// disassembles as `lda XBC,XBC+WA` in the KN5000 v7 ROM, and 0x31 = 0x30 |
// reg, settling 0x30=LDA / 0x40=STB, with 0x50=STW / 0x60=STL following the
// same fixed-width-per-range pattern every other 0xF3 sub-table in this
// backend already uses (see commit 1b9432474daa). So despite the passed-in
// OpSize parameter being fixed at 2 for every dest-side call, this function
// never trusts it for STx/LDA sizing -- only the sub-opcode is.
MCDisassembler::DecodeStatus TLCS900Disassembler::decodeSriRRPrefix(
    MCInst &MI, uint64_t &Size, ArrayRef<uint8_t> Bytes, bool IsDst,
    unsigned OpSize, bool Is8BitIndex) const {
  if (Bytes.size() < 5)
    return MCDisassembler::Fail;

  uint8_t BaseAddr = Bytes[2];
  uint8_t IdxAddr = Bytes[3];
  uint8_t SubOpc = Bytes[4];

  if (BaseAddr < 0xE0 || ((BaseAddr - 0xE0) & 0x3) != 0)
    return MCDisassembler::Fail;
  unsigned BaseEnc = (BaseAddr - 0xE0) >> 2;
  if (BaseEnc > 7)
    return MCDisassembler::Fail;
  unsigned BaseReg = decodeGPR(BaseEnc);

  if (Is8BitIndex) {
    // --- 8-bit index register: LD_RR8{B,W,L} (source) / ST_RR8{B,W,L} (dst)
    // idx_addr = 0xE0 + (idx_enc>>1)*4 + (1 - (idx_enc&1)); idx_enc is the
    // GR8 hardware encoding W=0,A=1,B=2,C=3,D=4,E=5,H=6,L=7 -- i.e. only the
    // 8 byte-halves of WA/BC/DE/HL are reachable this way.
    if (IdxAddr < 0xE0)
      return MCDisassembler::Fail;
    unsigned X = IdxAddr - 0xE0;
    unsigned PairIdx = X >> 2;
    unsigned Low2 = X & 0x3;
    if (PairIdx > 3 || (Low2 != 0 && Low2 != 1))
      return MCDisassembler::Fail;
    unsigned IdxEnc = (Low2 == 1) ? (PairIdx * 2) : (PairIdx * 2 + 1);
    unsigned IdxReg = decodeGR8(IdxEnc);

    if (!IsDst) {
      if ((SubOpc & 0xF8) != 0x20)
        return MCDisassembler::Fail;
      unsigned DataEnc = SubOpc & 0x7;
      unsigned Opc;
      switch (OpSize) {
      case 0: Opc = TLCS900::LD_RR8B; break;
      case 1: Opc = TLCS900::LD_RR8W; break;
      case 2: Opc = TLCS900::LD_RR8L; break;
      default: return MCDisassembler::Fail;
      }
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeRegForSize(DataEnc, OpSize)));
      MI.addOperand(MCOperand::createReg(BaseReg));
      MI.addOperand(MCOperand::createReg(IdxReg));
      Size = 5;
      return MCDisassembler::Success;
    }
    // Destination: ST_RR8{B,W,L}, sized by the sub-opcode range.
    unsigned Base = SubOpc & 0xF8;
    unsigned DataEnc = SubOpc & 0x7;
    unsigned Opc = 0, DataOpSize = 0;
    switch (Base) {
    case 0x40: Opc = TLCS900::ST_RR8B; DataOpSize = 0; break;
    case 0x50: Opc = TLCS900::ST_RR8W; DataOpSize = 1; break;
    case 0x60: Opc = TLCS900::ST_RR8L; DataOpSize = 2; break;
    default: return MCDisassembler::Fail;
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(decodeRegForSize(DataEnc, DataOpSize)));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(IdxReg));
    Size = 5;
    return MCDisassembler::Success;
  }

  // --- 16-bit index register (mode byte 0x07) ---
  if (IdxAddr < 0xE0)
    return MCDisassembler::Fail;
  unsigned IdxX = IdxAddr - 0xE0;
  unsigned IdxBankOffset = IdxX & 0x3; // 0 = current bank, 2 = previous bank
  unsigned IdxEnc16 = IdxX >> 2;
  if (IdxEnc16 > 7 || (IdxBankOffset != 0 && IdxBankOffset != 2))
    return MCDisassembler::Fail;

  if (!IsDst) {
    // Source: LD_RR{B,W,L} (sized by OpSize, from the prefix) or the one
    // word-only immediate form OR_RRW_IM (fixed sub-opcode 0x3E, no bank).
    if (IdxBankOffset != 0)
      return MCDisassembler::Fail; // no previous-bank source form exists
    unsigned IdxReg = decodeGR16(IdxEnc16);
    if (SubOpc == 0x3E) {
      if (OpSize != 1 || Bytes.size() < 7)
        return MCDisassembler::Fail;
      MI.setOpcode(TLCS900::OR_RRW_IM);
      MI.addOperand(MCOperand::createReg(BaseReg));
      MI.addOperand(MCOperand::createReg(IdxReg));
      MI.addOperand(MCOperand::createImm(Bytes[5]));
      MI.addOperand(MCOperand::createImm(Bytes[6]));
      Size = 7;
      return MCDisassembler::Success;
    }
    if ((SubOpc & 0xF8) != 0x20)
      return MCDisassembler::Fail;
    unsigned DataEnc = SubOpc & 0x7;
    unsigned Opc;
    switch (OpSize) {
    case 0: Opc = TLCS900::LD_RRB; break;
    case 1: Opc = TLCS900::LD_RRW; break;
    case 2: Opc = TLCS900::LD_RRL; break;
    default: return MCDisassembler::Fail;
    }
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(decodeRegForSize(DataEnc, OpSize)));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(IdxReg));
    Size = 5;
    return MCDisassembler::Success;
  }

  // Destination (F3 prefix): CALL_RR, LDA_RR/LDA_RRQ, ST_RR{B,W,L}, JP_RR.
  // None of these ranges overlap (0x08-0x17, 0x30-0x37, 0x40-0x47, 0x50-0x57,
  // 0x60-0x67, 0xD0-0xDF), so they are checked as plain sub-ranges.
  if (SubOpc >= 0x08 && SubOpc <= 0x17) {
    if (IdxBankOffset != 0)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::CALL_RR);
    MI.addOperand(MCOperand::createImm(SubOpc - 0x08));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(decodeGR16(IdxEnc16)));
    Size = 5;
    return MCDisassembler::Success;
  }
  if (SubOpc >= 0x30 && SubOpc <= 0x37) {
    unsigned DataEnc = SubOpc & 0x7;
    if (IdxBankOffset == 0) {
      MI.setOpcode(TLCS900::LDA_RR);
      MI.addOperand(MCOperand::createReg(decodeGPR(DataEnc)));
      MI.addOperand(MCOperand::createReg(BaseReg));
      MI.addOperand(MCOperand::createReg(decodeGR16(IdxEnc16)));
    } else {
      MI.setOpcode(TLCS900::LDA_RRQ);
      MI.addOperand(MCOperand::createReg(decodeGPR(DataEnc)));
      MI.addOperand(MCOperand::createReg(BaseReg));
      MI.addOperand(MCOperand::createReg(decodeQReg(IdxEnc16)));
    }
    Size = 5;
    return MCDisassembler::Success;
  }
  if (IdxBankOffset != 0)
    return MCDisassembler::Fail; // no previous-bank form below this point
  if (SubOpc >= 0x40 && SubOpc <= 0x47) {
    MI.setOpcode(TLCS900::ST_RRB);
    MI.addOperand(MCOperand::createReg(decodeGR8(SubOpc & 0x7)));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(decodeGR16(IdxEnc16)));
    Size = 5;
    return MCDisassembler::Success;
  }
  if (SubOpc >= 0x50 && SubOpc <= 0x57) {
    MI.setOpcode(TLCS900::ST_RRW);
    MI.addOperand(MCOperand::createReg(decodeGR16(SubOpc & 0x7)));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(decodeGR16(IdxEnc16)));
    Size = 5;
    return MCDisassembler::Success;
  }
  if (SubOpc >= 0x60 && SubOpc <= 0x67) {
    MI.setOpcode(TLCS900::ST_RRL);
    MI.addOperand(MCOperand::createReg(decodeGPR(SubOpc & 0x7)));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(decodeGR16(IdxEnc16)));
    Size = 5;
    return MCDisassembler::Success;
  }
  if (SubOpc >= 0xD0 && SubOpc <= 0xDF) {
    MI.setOpcode(TLCS900::JP_RR);
    MI.addOperand(MCOperand::createImm(SubOpc - 0xD0));
    MI.addOperand(MCOperand::createReg(BaseReg));
    MI.addOperand(MCOperand::createReg(decodeGR16(IdxEnc16)));
    Size = 5;
    return MCDisassembler::Success;
  }

  return MCDisassembler::Fail;
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
  // Format: [0xC7 (byte, OpSize==0) | 0xE7 (long, OpSize==2)] + bank byte +
  // SubOpc [+ trailing operand bytes]. OpSize==1 (word, 0xD7) never reaches
  // here -- the caller routes it to decodePrevBankPrefix instead, because
  // every real ROM word-sized use of this prefix addresses a previous-bank
  // register (0xE2 + n*4) and that decoder already produces a typed,
  // round-trip-correct mnemonic for it (e.g. `push QIZ` for what the
  // assembler also accepts as `pushw_erp 0xFA`).
  //
  // Unlike decodePrevBankPrefix's Q-register decode, the "bank" byte here is
  // kept as a raw immediate, never turned into a register operand: real ROM
  // sites reference sub-byte fields (e.g. 0xFB, the high byte of the
  // previous-bank IZ register) that have no typed register class in this
  // backend, which is exactly why the raw `..._erp bank, ...` spellings
  // exist and are the dominant convention already committed across the tree
  // (`stb_erp`/`ldb_erp`/`ldib_erp`/`cpib_erp`/... -- thousands of sites in
  // v7, v142 and the subcpu boot ROM).
  if (Bytes.size() < 3)
    return MCDisassembler::Fail;
  if (OpSize != 0 && OpSize != 2)
    return MCDisassembler::Fail;

  uint8_t Bank = Bytes[1];
  uint8_t SubOpc = Bytes[2];

  if (OpSize == 2) {
    // === Long-sized ERP (prefix 0xE7) ===
    switch (SubOpc) {
    case 0x04:
      MI.setOpcode(TLCS900::PUSH_LERP);
      MI.addOperand(MCOperand::createImm(Bank));
      Size = 3;
      return MCDisassembler::Success;
    case 0x05:
      MI.setOpcode(TLCS900::POP_LERP);
      MI.addOperand(MCOperand::createImm(Bank));
      Size = 3;
      return MCDisassembler::Success;
    case 0x64:
      MI.setOpcode(TLCS900::INC4_LERP);
      MI.addOperand(MCOperand::createImm(Bank));
      Size = 3;
      return MCDisassembler::Success;
    case 0xC8: {
      // ADD_ERPL: [bank, 0xC8, b0, b1, b2, b3] -- 4 trailing bytes.
      if (Bytes.size() < 7)
        return MCDisassembler::Fail;
      MI.setOpcode(TLCS900::ADD_ERPL);
      MI.addOperand(MCOperand::createImm(Bank));
      for (unsigned I = 0; I < 4; ++I)
        MI.addOperand(MCOperand::createImm(Bytes[3 + I]));
      Size = 7;
      return MCDisassembler::Success;
    }
    default:
      break;
    }
    // ERPRegInst: [bank, SubOpcBase + reg_enc(0-7)], GPR (32-bit) operand.
    unsigned RegEnc = SubOpc & 0x7;
    unsigned Base = SubOpc & 0xF8;
    unsigned Opc = 0;
    switch (Base) {
    case 0x88: Opc = TLCS900::LDTO_LERP; break; // ldto_lerp
    case 0x98: Opc = TLCS900::LDFR_LERP; break; // ldfr_lerp
    default: break;
    }
    if (!Opc)
      return MCDisassembler::Fail;
    MI.setOpcode(Opc);
    MI.addOperand(MCOperand::createReg(decodeGPR(RegEnc)));
    MI.addOperand(MCOperand::createImm(Bank));
    Size = 3;
    return MCDisassembler::Success;
  }

  // === Byte-sized ERP (prefix 0xC7) ===

  // --- Fixed-subopcode unary forms, checked first: 0x61 and 0x69 sit inside
  // the general small-immediate ranges handled further below (0x60-0x67,
  // 0x68-0x6F) but every real ROM site that hits exactly those two byte
  // values uses the dedicated "increment/decrement by 1" spelling
  // (inc1b_erp: 258 sites: incb_erp with imm=1: 15, all of which also land on
  // 0x61) -- so the specific form must win the dispatch, matching how
  // decodePrevBankPrefix's own unary switch is checked before its INC/DEC
  // range below. ---
  switch (SubOpc) {
  case 0x2A:
    MI.setOpcode(TLCS900::XORCF_A_BERP); // xorcfb_erp
    MI.addOperand(MCOperand::createImm(Bank));
    Size = 3;
    return MCDisassembler::Success;
  case 0x61:
    MI.setOpcode(TLCS900::INC1_BERP); // inc1b_erp
    MI.addOperand(MCOperand::createImm(Bank));
    Size = 3;
    return MCDisassembler::Success;
  case 0x69:
    MI.setOpcode(TLCS900::DEC1_BERP); // dec1b_erp
    MI.addOperand(MCOperand::createImm(Bank));
    Size = 3;
    return MCDisassembler::Success;
  case 0xFE:
    MI.setOpcode(TLCS900::SLL_A_BERP); // sllb_erp
    MI.addOperand(MCOperand::createImm(Bank));
    Size = 3;
    return MCDisassembler::Success;
  default:
    break;
  }

  // --- ERPImmAfterInst: [bank, SubOpc, 1 trailing byte] ---
  // ⚠ NOTE: XORCF_ERPB (0xE2) and LDCF_ERPB (0xE6) are DELIBERATELY not
  // decoded here. Both are unverified (zero uses anywhere in the disasm
  // tree, unlike every other mnemonic below) and both COLLIDE with the
  // OR_BERP register range (0xE0 + reg_enc spans 0xE0-0xE7): the word-sized
  // analogues of XORCF/LDCF use sub-opcodes 0x22/0x23 (see XORCF_ERPW /
  // LDCF_ERPW), so 0xE2/0xE6 for the byte form look like a copy-paste guess
  // rather than attested hardware behaviour. Treating that range as OR_BERP
  // instead matches the fully-populated, ROM-attested 8-register pattern
  // that every other ALU op in this family follows (ADD/SUB/AND/XOR/CP all
  // span their own contiguous 8-value block).
  struct ImmAfterEntry {
    uint8_t SubOpc;
    unsigned Opc;
  };
  static const ImmAfterEntry ImmAfterTable[] = {
      {0x03, TLCS900::LDI_ERPB},  {0x09, TLCS900::MULS_ERPB},
      {0x30, TLCS900::RES_ERPB},  {0x31, TLCS900::SET_ERPB},
      {0x33, TLCS900::BIT_ERPB},  {0xC8, TLCS900::ADD_ERPB},
      {0xCA, TLCS900::SUB_ERPB},  {0xCC, TLCS900::AND_ERPB},
      {0xCD, TLCS900::XOR_ERPB},  {0xCE, TLCS900::OR_ERPB},
      {0xCF, TLCS900::CP_ERPB},   {0xEE, TLCS900::SLL_ERPB},
      {0xEF, TLCS900::SRL_ERPB},
  };
  for (const auto &E : ImmAfterTable) {
    if (SubOpc != E.SubOpc)
      continue;
    if (Bytes.size() < 4)
      return MCDisassembler::Fail;
    MI.setOpcode(E.Opc);
    MI.addOperand(MCOperand::createImm(Bank));
    MI.addOperand(MCOperand::createImm(Bytes[3]));
    Size = 4;
    return MCDisassembler::Success;
  }

  // --- ERPRegInst: [bank, SubOpcBase + reg_enc(0-7)], GR8 operand.
  // 0x90 (ADC) and 0xB0 (SBC) are not defined for byte size and fall through
  // to Fail. The colliding 0x88/0x98/0xE0/0xF0 bases each have a byte-for-
  // byte-identical "mirror" definition (LD_ERPB_RR/ST_ERPB_RR/OR_ERPB_RR/
  // CP_ERPB_RR); this picks the pre-existing, far more common spelling
  // already used across the tree (stb_erp/ldb_erp/orb_erp/cpb_erp). ---
  {
    unsigned RegEnc = SubOpc & 0x7;
    unsigned Base = SubOpc & 0xF8;
    unsigned Opc = 0;
    switch (Base) {
    case 0x80: Opc = TLCS900::ADD_BERP; break;  // addb_erp
    case 0x88: Opc = TLCS900::LDTO_BERP; break; // stb_erp
    case 0x98: Opc = TLCS900::LDFR_BERP; break; // ldb_erp
    case 0xA0: Opc = TLCS900::SUB_BERP; break;  // subb_erp
    case 0xC0: Opc = TLCS900::AND_BERP; break;  // andb_erp
    case 0xD0: Opc = TLCS900::XOR_BERP; break;  // xorb_erp
    case 0xE0: Opc = TLCS900::OR_BERP; break;   // orb_erp
    case 0xF0: Opc = TLCS900::CP_BERP; break;   // cpb_erp
    default: break;
    }
    if (Opc) {
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createReg(decodeGR8(RegEnc)));
      MI.addOperand(MCOperand::createImm(Bank));
      Size = 3;
      return MCDisassembler::Success;
    }
  }

  // --- ERPSmallImmInst: [bank, SubOpcBase + imm3(0-7)].
  // LDI_BERP/CPI_BERP each have a byte-identical mirror (LDS_ERPB/CPS_ERPB);
  // pick the pre-existing dominant spelling (ldib_erp: 444 sites, cpib_erp:
  // 254, vs lds_erpb: 23, cps_erpb: 7). ---
  {
    unsigned Imm3 = SubOpc & 0x7;
    unsigned Base = SubOpc & 0xF8;
    unsigned Opc = 0;
    switch (Base) {
    case 0x60: Opc = TLCS900::INC_BERP; break; // incb_erp
    case 0x68: Opc = TLCS900::DEC_BERP; break; // decb_erp
    case 0xA8: Opc = TLCS900::LDI_BERP; break; // ldib_erp
    case 0xD8: Opc = TLCS900::CPI_BERP; break; // cpib_erp
    default: break;
    }
    if (Opc) {
      MI.setOpcode(Opc);
      MI.addOperand(MCOperand::createImm(Bank));
      MI.addOperand(MCOperand::createImm(Imm3));
      Size = 3;
      return MCDisassembler::Success;
    }
  }

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

  // === NORMAL: 0x01 — 1 byte ===
  case 0x01: // NORMAL
    return decodeSingleByte(MI, Size, TLCS900::NORMAL);

  // === MAX: 0x04 — 1 byte ===
  case 0x04: // MAX
    return decodeSingleByte(MI, Size, TLCS900::MAX);

  // === LDF #bank: 0x17 + bank — 2 bytes ===
  // ⚠ The operand byte is passed through UNMASKED.  Only the low 2 bits are
  // architecturally meaningful, but the encoder writes the immediate verbatim
  // (`ldf 0x05` -> [0x17,0x05]), so masking here would make bytes with a
  // non-zero upper nibble reassemble to a DIFFERENT byte.  unidasm also prints
  // the raw byte.
  case 0x17:
    if (Bytes.size() < 2)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::LDF);
    MI.addOperand(MCOperand::createImm(Bytes[1]));
    Size = 2;
    return MCDisassembler::Success;

  // === JP absolute 16-bit: 0x1A + addr16 — 3 bytes ===
  // A DIFFERENT instruction from the 0x1B addr24 form below, not a narrower
  // spelling of it: the width is part of the encoding the source requests.
  case 0x1A:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::JP16);
    MI.addOperand(MCOperand::createImm(readU16LE(Bytes, 1)));
    Size = 3;
    return MCDisassembler::Success;

  // === CALL absolute 16-bit: 0x1C + addr16 — 3 bytes ===
  case 0x1C:
    if (Bytes.size() < 3)
      return MCDisassembler::Fail;
    MI.setOpcode(TLCS900::CALL16);
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
    unsigned RegEnc = FirstByte & 0x7;
    unsigned Reg = decodeGR16(RegEnc);
    // r=7 is SP, which LD16ri_short's codegen-facing GR16 class excludes
    // (see LD16ri_short_sp's comment in TLCS900InstrInfo.td) -- use the
    // asm-only sibling so this reassembles instead of erroring.
    MI.setOpcode(RegEnc == 7 ? TLCS900::LD16ri_short_sp
                              : TLCS900::LD16ri_short);
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
