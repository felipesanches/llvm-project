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
// TSFlags layout (15 bits used):
//   [4:0]   InstFormat   — encoding format class
//   [12:5]  Opcode       — second byte (operation code within prefix group)
//   [14:13] OperandSize  — 0=8bit, 1=16bit, 2=32bit
namespace TLCS900II {

// Instruction encoding format classes.
enum InstFormat : uint8_t {
  Pseudo = 0,        // No encoding (pseudo-instructions)
  SingleByte,        // 1-byte instruction (NOP, RET, HALT, DI, RETI)
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
  Branch24,          // JP nnn (0x1C + 24-bit absolute)
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
  BlockTransfer,     // Single-byte block transfer (LDI, LDIR, LDD, LDDR, etc.)
};

// TSFlags bit field positions and masks.
enum : uint64_t {
  InstFormatShift = 0,
  InstFormatMask = 0x1F, // 5 bits [4:0]

  OpcodeShift = 5,
  OpcodeMask = 0xFF << OpcodeShift, // 8 bits [12:5]

  OpSizeShift = 13,
  OpSizeMask = 0x3 << OpSizeShift, // 2 bits [14:13]
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

} // namespace TLCS900II

} // namespace llvm

#endif
