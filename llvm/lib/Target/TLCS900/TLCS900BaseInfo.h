//===-- TLCS900BaseInfo.h - Top level definitions for TLCS900 MC ----*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains small standalone enum definitions for the TLCS900 target
// useful for the compiler back-end and the MC libraries.
//
//===----------------------------------------------------------------------===//
#ifndef LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900BASEINFO_H
#define LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900BASEINFO_H

#include "llvm/MC/MCInstrDesc.h"

namespace llvm {

// TLCS900II - This namespace holds all of the target specific flags that
// instruction info tracks.
//
// TSFlags layout (32 bits used):
//   [6:0]   InstFormat   — encoding format class (7 bits, up to 128 formats)
//   [14:7]  Opcode       — second byte (operation code within prefix group)
//   [16:15] OperandSize  — 0=8bit, 1=16bit, 2=32bit
//   [17]    AddrWidth    — 0=16-bit address, 1=24-bit address (direct addressing)
//   [20:18] RegIdx       — register index for block transfer prefix byte
//   [28:21] SubOpcode    — sub-opcode byte (ExtAddrModeSuffix/OpImm formats)
//   [31:29] NumPreOps    — operands before SubOpcode (ExtAddrModeOpImm format)
namespace TLCS900II {

// Instruction encoding format classes.
enum InstFormat : uint8_t {
  Pseudo = 0,        // No encoding (pseudo-instructions)
  SingleByte,        // 1-byte instruction (NOP, RET, HALT, RETI)
  SingleByteImm8,    // 1-byte opcode + 8-bit immediate (EI, SWI)
  SingleByteReg,     // Opcode embeds register in bits 0-2 (PUSH r32, POP r32)
  SingleByteRegImm,  // Opcode+reg + immediate (LD r32, #imm32)
  PrefixUnary,       // Reg prefix + opcode (NEG, CPL, EXTS, EXTZ)
  PrefixRegImm,      // Reg prefix + opcode + immediate (ADD ri, SUB ri, etc.)
  PrefixRegReg,      // Src prefix + (opcode | dst_reg) (ADD rr, SUB rr, etc.)
  PrefixShift,       // Reg prefix + shift opcode + shift amount (SLA, SRA, SRL)
  PrefixRotate,      // Reg prefix + rotate opcode (RLC, RRC, RL, RR)
  PrefixBit,         // Reg prefix + bit opcode + bit number (SET, RES, CHG, BIT, TSET)
  PrefixIncDec,      // Reg prefix + inc/dec opcode with count in bits 0-2
  MemLoad,           // Mem prefix + opcode (LD rd, (mem)) — source mem (A0/A8)
  MemLoadDst,        // Mem prefix + opcode (LDA rd, mem) — dest mem (B0/B8)
  MemStore,          // Mem prefix + opcode (LD (mem), rs) — dest mem (B0/B8)
  MemALU,            // Mem prefix + opcode + operand (ADD/SUB/etc (mem), rs/#imm)
  Branch24,          // JP nnn (0x1B + 24-bit absolute)
  BranchCond24,      // JP cc, nnn (not a real HW encoding — uses JR/JRL for cond)
  BranchRel8,        // JR cc, d8 (0x60+cc + signed byte)
  BranchRel16,       // JRL cc, d16 (0x70+cc + signed word)
  Call24,            // CALL nnn (0x1D + 24-bit absolute)
  CallRel16,         // CALR d16 (0x1E + 16-bit relative)
  CallIndirect,      // Mem prefix + 0x1F (CALL (reg))
  PrefixDJNZ,        // Reg prefix + 0x1C + d8 (DJNZ)
  PrefixLDImm,       // Reg prefix + 0x03 + immediate (LD R, #imm via prefix)
  PrefixPush,        // Reg prefix + 0x04 (PUSH via prefix)
  PrefixPop,         // Reg prefix + 0x05 (POP via prefix)
  BlockTransfer,     // 2-byte block transfer: 0x80 prefix + sub-opcode (LDI, LDIR, etc.)
  PrefixSmallImm,    // Reg prefix + (opcode + imm3) — LD r, 0-7 (2 bytes)
  SingleByteCondRet, // 0xB0 + (opc+cc) — RETcc (2 bytes)
  PrefixCondCode,    // Reg prefix + (opc+cc) — SCC (2 bytes)
  MemStoreImm,       // Dst mem prefix + opc + immediate — LD (mem), #imm
  MemIncDec,         // Src mem prefix + (opc + count%8) — INC/DEC (mem)
  MemPush,           // Src mem prefix + 0x04 — PUSH (mem)
  MemDstBitOp,       // Dst mem prefix + (opc + bit%8) — BIT/SET/RES/LDCF/STCF (mem)
  DirectSrcReg,      // Src direct prefix + addr + (opc | reg) — LD/CP/ALU reg, (addr)
  DirectSrcImm,      // Src direct prefix + addr + opc + imm — CP/AND/OR (addr), #imm
  DirectSrcIncDec,   // Src direct prefix + addr + (opc + count) — INC/DEC (addr)
  DirectDstReg,      // Dst direct prefix + addr + (opc | reg) — LD (addr),reg / LDA reg,addr
  DirectDstImm,      // Dst direct prefix + addr + opc + imm — LD (addr), #imm
  DirectDstBitOp,    // Dst direct prefix + addr + (opc + bit) — BIT/SET/RES (addr)
  DirectMemToMem,    // Src direct prefix + src_addr + 0x19 + dst_addr — LD (dst),(src)
  LdIoImm,           // 0x08 + addr8 + imm8 — LD (n), #n (I/O register write)
  LdIoImm16,         // 0x0A + addr8 + imm16 — LDW (n), #nn (I/O register word write)
  ExtPrefix,          // Generic extended prefix: all operand bytes emitted literally
  ExtAddrModeSuffix,  // Computed prefix + literal bytes + appended SubOpcode byte
  ExtAddrModeOpImm,   // Computed prefix + pre-ops + SubOpcode + post-ops (middle insertion)

  // Extended addressing mode native formats (typed operands).
  // Prefix is computed as Opcode + (Opcode < 0xF0 ? OpSize*0x10 : 0).
  // ERP: Extended Register Prefix (C7/D7/E7 bank access)
  ERPReg,             // prefix + bank_imm + (SubOpc + reg_enc)
  ERPSmallImm,        // prefix + bank_imm + (SubOpc + small_imm3)
  ERPUnary,           // prefix + bank_imm + SubOpc (no data register)
  ERPImmAfter,        // prefix + bank_imm + SubOpc + trailing imm bytes
  // PI: Post-Increment/Pre-Decrement (C4/C5/D4/D5/E4/E5/F4/F5)
  PIReg,              // prefix + base_gpr_enc + (SubOpc + data_reg_enc)
  PIUnary,            // prefix + base_gpr_enc + SubOpc (no data register)
  // RI: Register-Indirect Complex (C3/D3/E3/F3 + MEMsri)
  RIReg,              // prefix + MEMsri_bytes + (SubOpc + reg_enc)
  RIUnary,            // prefix + MEMsri_bytes + SubOpc (no data register)
  RIImmAfter,         // prefix + MEMsri_bytes + SubOpc + trailing imm
  // D8: 8-bit Direct Address (C0/D0/E0/F0)
  D8Reg,              // prefix + addr8 + (SubOpc + reg_enc)
  D8Unary,            // prefix + addr8 + SubOpc (no data register)
  D8ImmAfter,         // prefix + addr8 + SubOpc + trailing imm
  // ImmMod: Sub-opcode + immediate modifier (bit#, cc, inc count)
  ExtImmMod,          // prefix + raw addr_bytes + (SubOpc + op0_imm)
  RIImmMod,           // prefix + MEMsri_bytes + (SubOpc + op0_imm)
  // SRI with computed mode byte from typed operands (base GPR + d16 disp)
  SriD16Reg,          // prefix + mode_byte + d16 + (SubOpc + reg_enc)
  // PrevBank: Previous register bank access (D7 prefix + computed mode byte)
  PrevBankRR,         // 0xD7 + mode_byte(QR) + (SubOpc + data_reg_enc)
  PrevBankUnary,      // 0xD7 + mode_byte(QR) + SubOpc
  PrevBankSmallImm,   // 0xD7 + mode_byte(QR) + (SubOpc + imm3)
  PrevBankImmAfter,   // 0xD7 + mode_byte(QR) + SubOpc + trailing_imm
  DirectSrcPush,      // Src direct prefix + addr + opcode — PUSH (addr)
};

// TSFlags bit field positions and masks.
enum : uint64_t {
  InstFormatShift = 0,
  InstFormatMask = 0x7F, // 7 bits [6:0]

  OpcodeShift = 7,
  OpcodeMask = 0xFF << OpcodeShift, // 8 bits [14:7]

  OpSizeShift = 15,
  OpSizeMask = 0x3 << OpSizeShift, // 2 bits [16:15]

  AddrWidthShift = 17,
  AddrWidthMask = 0x1 << AddrWidthShift, // 1 bit [17]

  RegIdxShift = 18,
  RegIdxMask = 0x7 << RegIdxShift, // 3 bits [20:18]

  SubOpcodeShift = 21,
  SubOpcodeMask = 0xFFULL << SubOpcodeShift, // 8 bits [28:21]

  NumPreOpsShift = 29,
  NumPreOpsMask = 0x7ULL << NumPreOpsShift, // 3 bits [31:29]
};

// Operand size encoding in TSFlags.
enum OpSize : uint8_t {
  OpSize8 = 0,
  OpSize16 = 1,
  OpSize32 = 2,
};

// Extract InstFormat from TSFlags.
inline unsigned getInstFormat(uint64_t TSFlags) {
  return TSFlags & InstFormatMask;
}

// Extract opcode from TSFlags.
inline unsigned getOpcode(uint64_t TSFlags) {
  return (TSFlags >> OpcodeShift) & 0xFF;
}

// Extract operand size from TSFlags.
inline unsigned getOpSize(uint64_t TSFlags) {
  return (TSFlags >> OpSizeShift) & 0x3;
}

// Get the register prefix base byte for a given operand size.
// 8-bit: 0xC8, 16-bit: 0xD8, 32-bit: 0xE8
inline unsigned getRegPrefixBase(unsigned OpSize) {
  return 0xC8 + (OpSize * 0x10);
}

// Extract address width from TSFlags. 0=16-bit, 1=24-bit.
inline unsigned getAddrWidth(uint64_t TSFlags) {
  return (TSFlags >> AddrWidthShift) & 0x1;
}

// Extract register index from TSFlags (block transfer prefix).
inline unsigned getRegIdx(uint64_t TSFlags) {
  return (TSFlags >> RegIdxShift) & 0x7;
}

// Extract sub-opcode from TSFlags (ExtAddrModeSuffix/OpImm format).
inline unsigned getSubOpcode(uint64_t TSFlags) {
  return (TSFlags >> SubOpcodeShift) & 0xFF;
}

// Extract NumPreOps from TSFlags (ExtAddrModeOpImm format).
// Number of operand bytes emitted before the SubOpcode byte.
inline unsigned getNumPreOps(uint64_t TSFlags) {
  return (TSFlags >> NumPreOpsShift) & 0x7;
}

// Get the source direct addressing prefix byte for a given operand size.
// 8-bit: 0xC1 (16-bit addr), 0xC2 (24-bit addr)
// 16-bit: 0xD1 / 0xD2
// 32-bit: 0xE1 / 0xE2
inline unsigned getSrcDirectPrefix(unsigned OpSize, bool Is24Bit) {
  return (Is24Bit ? 0xC2 : 0xC1) + (OpSize * 0x10);
}

// Get the destination direct addressing prefix byte.
// 0xF1 (16-bit addr), 0xF2 (24-bit addr) — size-independent.
inline unsigned getDstDirectPrefix(bool Is24Bit) {
  return Is24Bit ? 0xF2 : 0xF1;
}

// Get the source memory prefix base byte for a given operand size.
// The TLCS-900 ISA uses different prefix ranges per data size for source
// memory (loads/ALU from memory):
//   8-bit:  0x80 (no disp), 0x88 (+d8)  → mnemonic_80 table
//   16-bit: 0x90 (no disp), 0x98 (+d8)  → mnemonic_90 table
//   32-bit: 0xA0 (no disp), 0xA8 (+d8)  → mnemonic_a0 table
// Destination memory (stores, LDA) always uses 0xB0/0xB8 regardless of size.
inline unsigned getSrcMemPrefixBase(unsigned OpSize) {
  return 0x80 + (OpSize * 0x10);
}

} // namespace TLCS900II

} // namespace llvm

#endif
