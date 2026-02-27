//== TLCS900InstrInfo.td - TLCS900 Instruction Definitions ---*- tablegen -*-=//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// TLCS900 instruction definitions for the TMP94C241 (TLCS-900/H2).
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// TLCS900-specific SDNodes
//===----------------------------------------------------------------------===//

// Procedure return
def tlcs900_ret : SDNode<"TLCS900ISD::Ret", SDTNone,
                       [SDNPHasChain, SDNPOptInGlue, SDNPVariadic]>;

// Function call
def SDT_TLCS900Call : SDTypeProfile<0, -1, [SDTCisVT<0, iPTR>]>;
def tlcs900_call : SDNode<"TLCS900ISD::Call", SDT_TLCS900Call,
                          [SDNPHasChain, SDNPOutGlue, SDNPOptInGlue,
                           SDNPVariadic]>;

// Tail call (jump instead of call+ret)
def tlcs900_tail_call : SDNode<"TLCS900ISD::TailCall", SDT_TLCS900Call,
                               [SDNPHasChain, SDNPOptInGlue,
                                SDNPVariadic]>;

// Compare (sets flags, produces glue)
def SDT_TLCS900Cmp : SDTypeProfile<0, 2, [SDTCisSameAs<0, 1>,
                                           SDTCisInt<0>]>;
def tlcs900_cmp : SDNode<"TLCS900ISD::CMP", SDT_TLCS900Cmp, [SDNPOutGlue]>;

// Conditional branch (reads flags via glue)
def SDT_TLCS900BrCond : SDTypeProfile<0, 2, [SDTCisVT<0, i32>,
                                              SDTCisVT<1, OtherVT>]>;
def tlcs900_brcond : SDNode<"TLCS900ISD::BRCOND", SDT_TLCS900BrCond,
                            [SDNPHasChain, SDNPInGlue]>;

// Conditional select (reads flags via glue)
def SDT_TLCS900SelectCC : SDTypeProfile<1, 3, [SDTCisSameAs<0, 1>,
                                                SDTCisSameAs<1, 2>]>;
def tlcs900_select_cc : SDNode<"TLCS900ISD::SELECT_CC", SDT_TLCS900SelectCC,
                               [SDNPInGlue]>;

// Set condition code (reads flags via glue, produces 0 or 1)
def SDT_TLCS900SCC : SDTypeProfile<1, 1, [SDTCisVT<0, i32>,
                                           SDTCisVT<1, i32>]>;
def tlcs900_scc : SDNode<"TLCS900ISD::SCC", SDT_TLCS900SCC,
                          [SDNPInGlue]>;

// 16x16→32 unsigned multiply (hardware MUL instruction)
def SDT_TLCS900Mul16 : SDTypeProfile<1, 2, [SDTCisVT<0, i32>,
                                              SDTCisVT<1, i32>,
                                              SDTCisVT<2, i32>]>;
def tlcs900_mul16 : SDNode<"TLCS900ISD::MUL16", SDT_TLCS900Mul16>;

// Wrapper for materializing target-specific addresses into registers
def tlcs900_wrapper : SDNode<"TLCS900ISD::Wrapper", SDTIntUnaryOp>;

// Call sequence markers
def SDT_CallSeqStart : SDCallSeqStart<[SDTCisVT<0, i32>,
                                       SDTCisVT<1, i32>]>;
def SDT_CallSeqEnd   : SDCallSeqEnd<[SDTCisVT<0, i32>,
                                    SDTCisVT<1, i32>]>;

def callseq_start : SDNode<"ISD::CALLSEQ_START", SDT_CallSeqStart,
                           [SDNPHasChain, SDNPOutGlue]>;
def callseq_end   : SDNode<"ISD::CALLSEQ_END", SDT_CallSeqEnd,
                           [SDNPHasChain, SDNPOptInGlue, SDNPOutGlue]>;

//===----------------------------------------------------------------------===//
// Instruction format includes
//===----------------------------------------------------------------------===//

include "TLCS900InstrFormats.td"

//===----------------------------------------------------------------------===//
// Operand definitions
//===----------------------------------------------------------------------===//

// AsmOperandClass for condition codes (used by AsmParser)
def CCOperand : AsmOperandClass {
  let Name = "CondCode";
  let ParserMethod = "parseCondCodeOperand";
}

// Condition code operand for conditional branches
def cc : Operand<i32> {
  let PrintMethod = "printCondCode";
  let ParserMatchClass = CCOperand;
}

// Branch target (basic block reference)
def brtarget : Operand<OtherVT>;

// AsmOperandClass for memory operands (used by AsmParser)
def MEMriAsmOperand : AsmOperandClass {
  let Name = "Memri";
  let ParserMethod = "parseMemriOperand";
}

// Memory operand: base register + 16-bit displacement
def MEMri : Operand<i32> {
  let MIOperandInfo = (ops GPR:$base, i32imm:$disp);
  let PrintMethod = "printMemOperand";
  let ParserMatchClass = MEMriAsmOperand;
}

// Address pattern: matches base+offset and frame indices
def addr : ComplexPattern<iPTR, 2, "SelectAddr", [frameindex], []>;

// Register operands that print as sub-register names (for 8/16-bit ops)
// GPR_lo8 uses the restricted GPR_with_sub8 class (only XWA/XBC/XDE/XHL
// have 8-bit sub-registers on TLCS-900).
def GPR_lo8 : RegisterOperand<GPR_with_sub8> {
  let PrintMethod = "printGPRAsLoByte";
}

def GPR_lo16 : RegisterOperand<GPR> {
  let PrintMethod = "printGPRAsLoWord";
}

//===----------------------------------------------------------------------===//
// Data Transfer Instructions
//===----------------------------------------------------------------------===//

// LD rd, #imm32 — Load 32-bit immediate into register
// Encoding: 0x40+r, imm32 (5 bytes)
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD32ri : SingleByteRegImmInst<0x40, 5, (outs GPR:$rd), (ins i32imm:$imm),
                                  "ld", "$rd, $imm",
                                  [(set GPR:$rd, (imm):$imm)]>,
             Sched<[WriteIALU]>;

// LD rd, rs — Copy register to register (no side effects, pure move)
// Encoding: E8+src, 0x88+dst (2 bytes) — LD C, R form
let isAsCheapAsAMove = 1, hasSideEffects = 0 in
def LD32rr : PrefixRegRegInst<0x88, (outs GPR:$rd), (ins GPR:$rs),
                              "ld", "$rd, $rs", []>,
             Sched<[WriteIALU]>;

// LD rd, (base+disp) — Load 32-bit from memory
// Encoding: mem_prefix + opcode(0x20+rd) — size varies by addressing mode
def LD32rm : MemLoadInst<0x20, 4, (outs GPR:$rd), (ins MEMri:$addr),
                         "ld", "$rd, $addr",
                         [(set GPR:$rd, (load addr:$addr))]>,
             Sched<[WriteLDW, ReadMemBase]>;

// LD (base+disp), rs — Store 32-bit to memory
// Encoding: dst_mem_prefix + 0x60+rs (LDLMR in B0/F0 table)
def LD32mr : MemStoreInst<0x60, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                          "ld", "$addr, $rs",
                          [(store GPR:$rs, addr:$addr)]>,
             Sched<[WriteSTW, ReadMemBase]>;

// Note: TLCS-900/H has no 32-bit immediate-to-memory store instruction
// in hardware. The B0 table only has LDBMI (0x00, byte) and LDWMI (0x02,
// word). ISel lowers 32-bit immediate stores as: LD reg, #imm;
// LD (mem), reg. Kept as codegen-only placeholder; not exposed to the
// assembler since opcode 0x08 is invalid for 32-bit stores.
let isCodeGenOnly = 1 in
def LD32mi : MemStoreInst<0x08, 8, (outs), (ins MEMri:$addr, i32imm:$val),
                          "ld", "$addr, $val", []>,
             Sched<[WriteSTW, ReadMemBase]>;

// LD (mem), #imm8/16 — Store immediate to memory via B0/B8 prefix
// The B0/B8 table has multiple sub-opcodes for immediate stores:
//   0x00 = LD (mem), #imm8    0x02 = LDW (mem), #imm16
//   0x14 = LD (mem), #imm8    0x16 = LDW (mem), #imm16
// Both 0x00/0x14 produce identical 8-bit stores; 0x02/0x16 identical 16-bit.
let OpSize = OpSize8.Value in
def LD8mi_dst : MemStoreImmInst<0x00, 4, (outs), (ins MEMri:$addr, i8imm:$val),
                                 "ld", "$addr, $val", []>,
                Sched<[WriteSTW, ReadMemBase]>;
let OpSize = OpSize16.Value in {
def LD16mi_dst : MemStoreImmInst<0x14, 5, (outs), (ins MEMri:$addr, i16imm:$val),
                                  "ldmi16", "$addr, $val", []>,
                 Sched<[WriteSTW, ReadMemBase]>;
def LD16mi_dst_02 : MemStoreImmInst<0x02, 4, (outs), (ins MEMri:$addr, i16imm:$val),
                                     "ldw", "$addr, $val", []>,
                    Sched<[WriteSTW, ReadMemBase]>;
def LD16mi_dst_16 : MemStoreImmInst<0x16, 5, (outs), (ins MEMri:$addr, i16imm:$val),
                                     "ldmw2", "$addr, $val", []>,
                    Sched<[WriteSTW, ReadMemBase]>;
} // OpSize16

// LD rd:lo16, (base+disp) — Load 16-bit from memory into low word of GPR
// Note: upper 16 bits of the 32-bit register are UNCHANGED by hardware.
// This is used internally; zextloadi16/sextloadi16 patterns add explicit
// EXTZ/EXTS to clear/sign-extend the upper bits.
// isCodeGenOnly: prevents asm matcher from preferring this over LD32rm
// (GPR_with_sub8 ⊂ GPR causes ambiguous matching otherwise).
let mayLoad = 1, OpSize = OpSize16.Value, isCodeGenOnly = 1 in
def LD16rm : MemLoadInst<0x20, 4, (outs GPR_lo16:$rd), (ins MEMri:$addr),
                         "ld", "$rd, $addr", []>,
             Sched<[WriteLDW, ReadMemBase]>;

// LD rd:lo8, (base+disp) — Load 8-bit from memory into low byte of GPR
// Note: other bytes of the register are UNCHANGED by hardware.
// isCodeGenOnly: same reason as LD16rm.
let mayLoad = 1, OpSize = OpSize8.Value, isCodeGenOnly = 1 in
def LD8rm : MemLoadInst<0x20, 3, (outs GPR_lo8:$rd), (ins MEMri:$addr),
                        "ld", "$rd, $addr", []>,
            Sched<[WriteLDW, ReadMemBase]>;

// (Extending load patterns are after the instruction definitions below.)

// LD (base+disp), rs:lo16 — Truncating store: writes low 16 bits to memory
// Pattern is separate (below) because the RegisterOperand GPR_lo16 doesn't
// match bare GPR in inline patterns.
// isCodeGenOnly: prevents asm matcher ambiguity with LD32mr.
let OpSize = OpSize16.Value, isCodeGenOnly = 1 in
def LD16mr : MemStoreInst<0x50, 4, (outs), (ins MEMri:$addr, GPR_lo16:$rs),
                          "ld", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase]>;

// LD (base+disp), rs:lo8 — Truncating store: writes low 8 bits to memory
// isCodeGenOnly: prevents asm matcher ambiguity with LD32mr.
let OpSize = OpSize8.Value, isCodeGenOnly = 1 in
def LD8mr : MemStoreInst<0x40, 3, (outs), (ins MEMri:$addr, GPR_lo8:$rs),
                         "ld", "$addr, $rs", []>,
            Sched<[WriteSTW, ReadMemBase]>;

// Patterns for address materialization — all go through TLCS900ISD::Wrapper
def : Pat<(tlcs900_wrapper tglobaladdr:$addr), (LD32ri tglobaladdr:$addr)>;
def : Pat<(tlcs900_wrapper texternalsym:$addr), (LD32ri texternalsym:$addr)>;
def : Pat<(tlcs900_wrapper tblockaddress:$addr), (LD32ri tblockaddress:$addr)>;
def : Pat<(tlcs900_wrapper tjumptable:$addr), (LD32ri tjumptable:$addr)>;

//===----------------------------------------------------------------------===//
// Arithmetic Instructions (two-address: rd = rd op rs)
// All arithmetic instructions modify the Status Register (flags).
//===----------------------------------------------------------------------===//

let Constraints = "$rd = $rs1", Defs = [SR] in {

// ADD rd, rs — rd = rd + rs (affects S, Z, H, V, N, C)
// Encoding: E8+src, 0x80+dst (2 bytes)
let isCommutable = 1 in
def ADD32rr : PrefixRegRegInst<0x80, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "add", "$rd, $rs2",
                               [(set GPR:$rd, (add GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// ADD rd, #imm — rd = rd + imm
// Encoding: E8+dst, 0xC8, imm32 (6 bytes)
def ADD32ri : PrefixRegImmInst<0xC8, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                               "add", "$rd, $imm",
                               [(set GPR:$rd, (add GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// SUB rd, rs — rd = rd - rs (affects S, Z, H, V, N, C)
// Encoding: E8+src, 0xA0+dst (2 bytes)
def SUB32rr : PrefixRegRegInst<0xA0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "sub", "$rd, $rs2",
                               [(set GPR:$rd, (sub GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// SUB rd, #imm — rd = rd - imm
// Encoding: E8+dst, 0xCA, imm32 (6 bytes)
def SUB32ri : PrefixRegImmInst<0xCA, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                               "sub", "$rd, $imm",
                               [(set GPR:$rd, (sub GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// ADC rd, rs — rd = rd + rs + carry (also reads carry from SR)
// Encoding: E8+src, 0x90+dst (2 bytes)
let Uses = [SR] in {
def ADC32rr : PrefixRegRegInst<0x90, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "adc", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// ADC rd, #imm — rd = rd + imm + carry
// Encoding: E8+dst, 0xC9, imm32 (6 bytes)
def ADC32ri : PrefixRegImmInst<0xC9, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                               "adc", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

// SBC rd, rs — rd = rd - rs - carry (also reads carry from SR)
// Encoding: E8+src, 0xB0+dst (2 bytes)
def SBC32rr : PrefixRegRegInst<0xB0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "sbc", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// SBC rd, #imm — rd = rd - imm - carry
// Encoding: E8+dst, 0xCB, imm32 (6 bytes)
def SBC32ri : PrefixRegImmInst<0xCB, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                               "sbc", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;
} // Uses = [SR]

//===----------------------------------------------------------------------===//
// Logic Instructions (two-address, all modify SR flags)
//===----------------------------------------------------------------------===//

// AND rd, rs (affects S, Z, H=1, V=parity, N=0, C=0)
// Encoding: E8+src, 0xC0+dst (2 bytes)
let isCommutable = 1 in
def AND32rr : PrefixRegRegInst<0xC0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "and", "$rd, $rs2",
                               [(set GPR:$rd, (and GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// AND rd, #imm
// Encoding: E8+dst, 0xCC, imm32 (6 bytes)
def AND32ri : PrefixRegImmInst<0xCC, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                               "and", "$rd, $imm",
                               [(set GPR:$rd, (and GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// OR rd, rs (affects S, Z, H=0, V=parity, N=0, C=0)
// Encoding: E8+src, 0xE0+dst (2 bytes)
let isCommutable = 1 in
def OR32rr : PrefixRegRegInst<0xE0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                              "or", "$rd, $rs2",
                              [(set GPR:$rd, (or GPR:$rs1, GPR:$rs2))]>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// OR rd, #imm
// Encoding: E8+dst, 0xCE, imm32 (6 bytes)
def OR32ri : PrefixRegImmInst<0xCE, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "or", "$rd, $imm",
                              [(set GPR:$rd, (or GPR:$rs1, (imm):$imm))]>,
             Sched<[WriteIALU, ReadIALU]>;

// XOR rd, rs (affects S, Z, H=0, V=parity, N=0, C=0)
// Encoding: E8+src, 0xD0+dst (2 bytes)
let isCommutable = 1 in
def XOR32rr : PrefixRegRegInst<0xD0, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "xor", "$rd, $rs2",
                               [(set GPR:$rd, (xor GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// XOR rd, #imm
// Encoding: E8+dst, 0xCD, imm32 (6 bytes)
def XOR32ri : PrefixRegImmInst<0xCD, 6, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                               "xor", "$rd, $imm",
                               [(set GPR:$rd, (xor GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Shift Instructions (two-address, all modify SR flags)
//===----------------------------------------------------------------------===//

// SLA rd, rs — Shift Left Arithmetic (affects S, Z, H=0, V, N=0, C)
// Encoding: E8+rd, 0xFC (SLA A,R form — shift amount in A register)
def SLA32rr : PrefixRegRegInst<0xFC, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "sla", "$rd, $rs2",
                               [(set GPR:$rd, (shl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SLA rd, #imm
// Encoding: E8+rd, 0xEC, amt (3 bytes)
def SLA32ri : PrefixShiftInst<0xEC, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "sla", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// SRA rd, rs — Shift Right Arithmetic (affects S, Z, H=0, V, N=0, C)
// Encoding: E8+rd, 0xFD (SRA A,R form)
def SRA32rr : PrefixRegRegInst<0xFD, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "sra", "$rd, $rs2",
                               [(set GPR:$rd, (sra GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRA rd, #imm
// Encoding: E8+rd, 0xED, amt (3 bytes)
def SRA32ri : PrefixShiftInst<0xED, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "sra", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// SLL rd, #imm — Shift Left Logical (same result as SLA, different flags)
// Encoding: E8+rd, 0xEE, amt (3 bytes)
def SLL32ri : PrefixShiftInst<0xEE, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "sll", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// SRL rd, rs — Shift Right Logical (affects S, Z, H=0, V, N=0, C)
// Encoding: E8+rd, 0xFF (SRL A,R form)
def SRL32rr : PrefixRegRegInst<0xFF, (outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                               "srl", "$rd, $rs2",
                               [(set GPR:$rd, (srl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRL rd, #imm
// Encoding: E8+rd, 0xEF, amt (3 bytes)
def SRL32ri : PrefixShiftInst<0xEF, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "srl", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

} // Constraints = "$rd = $rs1", Defs = [SR]

// Carry-flag arithmetic patterns for multi-precision (i64) add/sub.
// ADDC/SUBC produce carry output (SR); ADDE/SUBE consume carry input (SR).
def : Pat<(addc GPR:$rs1, GPR:$rs2), (ADD32rr GPR:$rs1, GPR:$rs2)>;
def : Pat<(addc GPR:$rs1, (imm):$imm), (ADD32ri GPR:$rs1, (imm):$imm)>;
def : Pat<(adde GPR:$rs1, GPR:$rs2), (ADC32rr GPR:$rs1, GPR:$rs2)>;
def : Pat<(adde GPR:$rs1, (imm):$imm), (ADC32ri GPR:$rs1, (imm):$imm)>;
def : Pat<(subc GPR:$rs1, GPR:$rs2), (SUB32rr GPR:$rs1, GPR:$rs2)>;
def : Pat<(subc GPR:$rs1, (imm):$imm), (SUB32ri GPR:$rs1, (imm):$imm)>;
def : Pat<(sube GPR:$rs1, GPR:$rs2), (SBC32rr GPR:$rs1, GPR:$rs2)>;
def : Pat<(sube GPR:$rs1, (imm):$imm), (SBC32ri GPR:$rs1, (imm):$imm)>;

//===----------------------------------------------------------------------===//
// Unary Instructions (single-operand, in-place, all modify SR flags)
//===----------------------------------------------------------------------===//

let Constraints = "$rd = $rs1", Defs = [SR] in {

// NEG rd — Negate: rd = 0 - rd (affects all flags)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
// isCodeGenOnly: 32-bit NEG is expanded to XOR + INC by ISel patterns.
let isCodeGenOnly = 1 in
def NEG32 : PrefixUnaryInst<0x07, (outs GPR:$rd), (ins GPR:$rs1),
                            "neg", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// CPL rd — Complement (bitwise NOT): rd = ~rd (affects H=1, N=1)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
// isCodeGenOnly: 32-bit CPL is expanded to XOR with -1 by ISel patterns.
let isCodeGenOnly = 1 in
def CPL32 : PrefixUnaryInst<0x06, (outs GPR:$rd), (ins GPR:$rs1),
                            "cpl", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// EXTS rd — Sign extend: low 16 bits sign-extended to 32 bits (affects S, Z)
// Encoding: E8+rd, 0x13 (2 bytes)
def EXTS32 : PrefixUnaryInst<0x13, (outs GPR:$rd), (ins GPR:$rs1),
                             "exts", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

// EXTZ rd — Zero extend: low 16 bits zero-extended to 32 bits (affects S, Z)
// Encoding: E8+rd, 0x12 (2 bytes)
def EXTZ32 : PrefixUnaryInst<0x12, (outs GPR:$rd), (ins GPR:$rs1),
                             "extz", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

} // Constraints = "$rd = $rs1", Defs = [SR]

// INC #n, rd — Increment by n (n = 1..8)
// Encoding: E8+rd, 0x60+(n-1) (2 bytes)
// NOTE: On TLCS-900/H, 32-bit INC does NOT set any flags (S, Z, H, V).
// Only 8-bit INC sets flags. The compiler must not rely on flag output.
let Constraints = "$rd = $rs1" in {
def INC32 : PrefixIncDecInst<0x60, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$n),
                             "inc", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// DEC #n, rd — Decrement by n (n = 1..8)
// Encoding: E8+rd, 0x68+(n-1) (2 bytes)
// Same: 32-bit DEC does NOT set flags on TLCS-900/H.
def DEC32 : PrefixIncDecInst<0x68, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$n),
                             "dec", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;
} // Constraints = "$rd = $rs1" (no Defs=[SR]: 32-bit INC/DEC don't set flags)

// DAA rd — Decimal Adjust after Addition (BCD) (affects all flags)
// Reads N and H flags from prior arithmetic to determine BCD correction.
// Only valid in C8 (8-bit) prefix table, NOT D8 (16-bit) or E8 (32-bit).
// isCodeGenOnly: DAA is only meaningful for 8-bit BCD operations.
let Constraints = "$rd = $rs1", Defs = [SR], Uses = [SR], isCodeGenOnly = 1 in
def DAA32 : PrefixUnaryInst<0x10, (outs GPR:$rd), (ins GPR:$rs1),
                            "daa", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// Patterns for NEG and CPL
// NEG32 and CPL32 are invalid in the E8 (32-bit) prefix table.
// Expand NEG (0 - x) to: XOR x, -1 (bitwise NOT) then INC 1 (two's complement).
def : Pat<(sub 0, GPR:$rs), (INC32 (XOR32ri GPR:$rs, -1), 1)>;
// Expand CPL (bitwise NOT) to: XOR x, -1 (all ones).
def : Pat<(not GPR:$rs), (XOR32ri GPR:$rs, -1)>;

// Pattern for EXTS: sign extend from i16 to i32
def : Pat<(sext_inreg GPR:$rs, i16), (EXTS32 GPR:$rs)>;

// Pattern for sign extend i8 to i32 (shift pair)
def : Pat<(sext_inreg GPR:$rs, i8), (SRA32ri (SLA32ri GPR:$rs, 24), 24)>;

// Pattern for EXTZ: zero extend low 16 bits (AND with 0xFFFF)
def : Pat<(and GPR:$rs, 65535), (EXTZ32 GPR:$rs)>;

// Patterns for truncating stores (separate Pat because RegisterOperand
// GPR_lo16/GPR_lo8 can't be used directly in inline instruction patterns)
def : Pat<(truncstorei16 GPR:$rs, addr:$addr), (LD16mr addr:$addr, GPR:$rs)>;
def : Pat<(truncstorei8  GPR:$rs, addr:$addr), (LD8mr  addr:$addr, GPR:$rs)>;

// Patterns for byte/word extending loads from globals/externals.
// Direct memory (E2 prefix) only supports 32-bit loads, so byte/word loads
// from globals must materialize the address into a register first, then use
// register-indirect addressing.  AddedComplexity ensures these are tried
// before the generic addr:$addr patterns (whose ComplexPattern has high
// implicit complexity).
let AddedComplexity = 20 in {

// 16-bit loads from globals
def : Pat<(i32 (zextloadi16 (tlcs900_wrapper tglobaladdr:$addr))),
          (EXTZ32 (LD16rm (LD32ri tglobaladdr:$addr), 0))>;
def : Pat<(i32 (sextloadi16 (tlcs900_wrapper tglobaladdr:$addr))),
          (EXTS32 (LD16rm (LD32ri tglobaladdr:$addr), 0))>;
def : Pat<(i32 (extloadi16 (tlcs900_wrapper tglobaladdr:$addr))),
          (EXTZ32 (LD16rm (LD32ri tglobaladdr:$addr), 0))>;
def : Pat<(i32 (zextloadi16 (tlcs900_wrapper texternalsym:$addr))),
          (EXTZ32 (LD16rm (LD32ri texternalsym:$addr), 0))>;
def : Pat<(i32 (sextloadi16 (tlcs900_wrapper texternalsym:$addr))),
          (EXTS32 (LD16rm (LD32ri texternalsym:$addr), 0))>;
def : Pat<(i32 (extloadi16 (tlcs900_wrapper texternalsym:$addr))),
          (EXTZ32 (LD16rm (LD32ri texternalsym:$addr), 0))>;

// 8-bit loads from globals
def : Pat<(i32 (zextloadi8 (tlcs900_wrapper tglobaladdr:$addr))),
          (AND32ri (LD8rm (LD32ri tglobaladdr:$addr), 0), 255)>;
def : Pat<(i32 (sextloadi8 (tlcs900_wrapper tglobaladdr:$addr))),
          (SRA32ri (SLA32ri (LD8rm (LD32ri tglobaladdr:$addr), 0), 24), 24)>;
def : Pat<(i32 (extloadi8 (tlcs900_wrapper tglobaladdr:$addr))),
          (AND32ri (LD8rm (LD32ri tglobaladdr:$addr), 0), 255)>;
def : Pat<(i32 (zextloadi8 (tlcs900_wrapper texternalsym:$addr))),
          (AND32ri (LD8rm (LD32ri texternalsym:$addr), 0), 255)>;
def : Pat<(i32 (sextloadi8 (tlcs900_wrapper texternalsym:$addr))),
          (SRA32ri (SLA32ri (LD8rm (LD32ri texternalsym:$addr), 0), 24), 24)>;
def : Pat<(i32 (extloadi8 (tlcs900_wrapper texternalsym:$addr))),
          (AND32ri (LD8rm (LD32ri texternalsym:$addr), 0), 255)>;

} // AddedComplexity = 20

// Patterns for 16-bit extending loads (generic — register-indirect)
def : Pat<(i32 (zextloadi16 addr:$addr)), (EXTZ32 (LD16rm addr:$addr))>;
def : Pat<(i32 (sextloadi16 addr:$addr)), (EXTS32 (LD16rm addr:$addr))>;
def : Pat<(i32 (extloadi16 addr:$addr)),  (EXTZ32 (LD16rm addr:$addr))>;

// Patterns for 8-bit extending loads (generic — register-indirect)
// Zero-extend: load byte, then AND with 0xFF
def : Pat<(i32 (zextloadi8 addr:$addr)),
          (AND32ri (LD8rm addr:$addr), 255)>;
// Sign-extend: load byte, shift left 24, shift right arithmetic 24
def : Pat<(i32 (sextloadi8 addr:$addr)),
          (SRA32ri (SLA32ri (LD8rm addr:$addr), 24), 24)>;
// Any-extend: just load (upper bits don't matter)
def : Pat<(i32 (extloadi8 addr:$addr)),
          (AND32ri (LD8rm addr:$addr), 255)>;

// Patterns for shift-by-immediate (more efficient than loading count into reg)
def : Pat<(shl GPR:$rs, (i32 imm:$amt)), (SLA32ri GPR:$rs, imm:$amt)>;
def : Pat<(sra GPR:$rs, (i32 imm:$amt)), (SRA32ri GPR:$rs, imm:$amt)>;
def : Pat<(srl GPR:$rs, (i32 imm:$amt)), (SRL32ri GPR:$rs, imm:$amt)>;

// Patterns for INC: add by small constant (1-8) uses INC instruction
// INC doesn't affect Carry flag (unlike ADD), useful for loop counters
def : Pat<(add GPR:$rs, 1), (INC32 GPR:$rs, 1)>;
def : Pat<(add GPR:$rs, 2), (INC32 GPR:$rs, 2)>;
def : Pat<(add GPR:$rs, 3), (INC32 GPR:$rs, 3)>;
def : Pat<(add GPR:$rs, 4), (INC32 GPR:$rs, 4)>;
def : Pat<(add GPR:$rs, 5), (INC32 GPR:$rs, 5)>;
def : Pat<(add GPR:$rs, 6), (INC32 GPR:$rs, 6)>;
def : Pat<(add GPR:$rs, 7), (INC32 GPR:$rs, 7)>;
def : Pat<(add GPR:$rs, 8), (INC32 GPR:$rs, 8)>;

// Patterns for DEC: subtract small constant (1-8) uses DEC instruction
def : Pat<(add GPR:$rs, -1), (DEC32 GPR:$rs, 1)>;
def : Pat<(add GPR:$rs, -2), (DEC32 GPR:$rs, 2)>;
def : Pat<(add GPR:$rs, -3), (DEC32 GPR:$rs, 3)>;
def : Pat<(add GPR:$rs, -4), (DEC32 GPR:$rs, 4)>;
def : Pat<(add GPR:$rs, -5), (DEC32 GPR:$rs, 5)>;
def : Pat<(add GPR:$rs, -6), (DEC32 GPR:$rs, 6)>;
def : Pat<(add GPR:$rs, -7), (DEC32 GPR:$rs, 7)>;
def : Pat<(add GPR:$rs, -8), (DEC32 GPR:$rs, 8)>;

//===----------------------------------------------------------------------===//
// Compare Instructions (set flags in SR)
//===----------------------------------------------------------------------===//

let Defs = [SR], isCompare = 1 in {

// CP rd, rs — Compare registers (rd - rs, set flags, discard result)
// Encoding: E8+rs2, 0xF0+rs1 (2 bytes)
def CP32rr : PrefixRegRegInst<0xF0, (outs), (ins GPR:$rs1, GPR:$rs2),
                              "cp", "$rs1, $rs2",
                              [(tlcs900_cmp GPR:$rs1, GPR:$rs2)]>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// CP rd, #imm — Compare register with immediate
// Encoding: E8+rs1, 0xCF, imm32 (6 bytes)
def CP32ri : PrefixRegImmInst<0xCF, 6, (outs), (ins GPR:$rs1, i32imm:$imm),
                              "cp", "$rs1, $imm",
                              [(tlcs900_cmp GPR:$rs1, (imm):$imm)]>,
             Sched<[WriteIALU, ReadIALU]>;

// CP rd, #(0-7) — Compare with small immediate: E8+r, 0xD8+val (2 bytes)
def CP32_small : PrefixSmallImmInst<0xD8, (outs), (ins GPR:$rs1, i32imm:$imm),
                                     "cps", "$rs1, $imm", []>,
                 Sched<[WriteIALU, ReadIALU]>;

} // Defs = [SR]

//===----------------------------------------------------------------------===//
// Branch Instructions
//===----------------------------------------------------------------------===//

// JP target — Unconditional branch (absolute address)
// Encoding: 0x1B, addr24 (4 bytes)
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JP : Branch24Inst<0x1B, (outs), (ins brtarget:$target),
                      "jp", "$target",
                      [(br bb:$target)]>,
         Sched<[WriteJmp]>;

// JP (rs) — Indirect jump through register
// Encoding: B0+rs, 0xD8 (2 bytes) — JP T,(mem) in B0 table (0xD0+cc, cc=T=8)
let isBranch = 1, isTerminator = 1, isBarrier = 1, isIndirectBranch = 1 in
def JP_r : CallIndirectInst<0xD8, (outs), (ins GPR:$target),
                            "jp", "(${target})",
                            [(brind GPR:$target)]>,
           Sched<[WriteJmp]>;

// JP cc, target — Conditional branch (emits as JRL cc, d16)
// Encoding: 0x70+cc, d16 (3 bytes)
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JPcc : BranchCond24Inst<0x70, (outs), (ins cc:$cc, brtarget:$target),
                            "jp", "$cc, $target",
                            [(tlcs900_brcond (i32 imm:$cc), bb:$target)]>,
           Sched<[WriteJmp]>;

// JR target — Relative jump (8-bit signed offset, shorter encoding)
// Encoding: 0x68 (JR T), d8 (2 bytes) — T=always=8, so 0x60+8=0x68
// No isel patterns; used by linker relaxation JP→JR when target is near.
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JR : BranchRel8Inst<0x68, (outs), (ins brtarget:$target),
                        "jr", "$target", []>,
         Sched<[WriteJmp]>;

// JR cc, target — Conditional relative jump (8-bit signed offset)
// Encoding: 0x60+cc, d8 (2 bytes)
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JRcc : BranchRel8Inst<0x60, (outs), (ins cc:$cc, brtarget:$target),
                          "jr", "$cc, $target", []>,
           Sched<[WriteJmp]>;

// JRL target — Relative jump (16-bit signed offset)
// Encoding: 0x78 (JRL T), d16 (3 bytes) — T=always=8, so 0x70+8=0x78
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JRL : BranchRel16Inst<0x78, (outs), (ins brtarget:$target),
                          "jrl", "$target", []>,
          Sched<[WriteJmp]>;

// JRL cc, target — Conditional relative jump (16-bit signed offset)
// Encoding: 0x70+cc, d16 (3 bytes)
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JRLcc : BranchRel16Inst<0x70, (outs), (ins cc:$cc, brtarget:$target),
                            "jrl", "$cc, $target", []>,
            Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Call Instructions
//===----------------------------------------------------------------------===//

let isCall = 1 in {

// CALL target — Direct function call
// Encoding: 0x1D, addr24 (4 bytes)
def CALL : Call24Inst<0x1D, (outs), (ins i32imm:$target),
                      "call", "$target",
                      [(tlcs900_call tglobaladdr:$target)]>,
           Sched<[WriteJmp]>;

// CALL (rs) — Indirect function call through register
// Encoding: B0+rs, 0xE8 (2 bytes) — CALL T,(mem) in B0 table (0xE0+cc, cc=T=8)
def CALL_r : CallIndirectInst<0xE8, (outs), (ins GPR:$target),
                              "call", "(${target})",
                              [(tlcs900_call GPR:$target)]>,
             Sched<[WriteJmp]>;

// CALR target — Relative call (16-bit signed offset, shorter encoding)
// Encoding: 0x1E, d16 (3 bytes)
// No isel patterns; used by linker relaxation CALL→CALR when target is near.
def CALR : CallRel16Inst<0x1E, (outs), (ins i32imm:$target),
                         "calr", "$target", []>,
           Sched<[WriteJmp]>;

} // isCall = 1

def : Pat<(tlcs900_call texternalsym:$target), (CALL texternalsym:$target)>;

// Tail call pseudo-instructions — expanded to JP in AsmPrinter
// after prologue/epilogue insertion has restored the frame.
let isCall = 1, isReturn = 1, isBarrier = 1, isTerminator = 1 in {

def TAIL_CALL : Pseudo<(outs), (ins i32imm:$target),
                        [(tlcs900_tail_call tglobaladdr:$target)]>;

def TAIL_CALL_r : Pseudo<(outs), (ins GPR:$target),
                          [(tlcs900_tail_call GPR:$target)]>;

} // isCall, isReturn, isBarrier, isTerminator

def : Pat<(tlcs900_tail_call texternalsym:$target),
          (TAIL_CALL texternalsym:$target)>;

//===----------------------------------------------------------------------===//
// Return
//===----------------------------------------------------------------------===//

// RET — Return from subroutine
// Encoding: 0x0E (1 byte)
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RET : SingleByteInst<0x0E, (outs), (ins),
                         "ret", "",
                         [(tlcs900_ret)]>,
          Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Stack Instructions
//===----------------------------------------------------------------------===//

// Stack effects fully captured by Defs/Uses=[XSP] and mayLoad/mayStore.
let Defs = [XSP], Uses = [XSP], hasSideEffects = 0 in {

// PUSH rs — Push 32-bit register to stack (pre-decrement SP, store)
// Encoding: 0x38+r (1 byte)
let mayStore = 1 in
def PUSH32 : SingleByteRegInst<0x38, (outs), (ins GPR:$rs),
                               "push", "$rs", []>,
             Sched<[WritePush]>;

// POP rd — Pop 32-bit register from stack (load, post-increment SP)
// Encoding: 0x58+r (1 byte)
let mayLoad = 1 in
def POP32 : SingleByteRegInst<0x58, (outs GPR:$rd), (ins),
                              "pop", "$rd", []>,
            Sched<[WritePop]>;

// PUSH rs8 — Push 8-bit register (prefix C8+r, opcode 0x04)
let mayStore = 1, OpSize = OpSize8.Value in
def PUSH8 : PrefixPushInst<0x04, (outs), (ins GR8:$rs),
                            "push", "$rs", []>,
            Sched<[WritePush]>;

// POP rd8 — Pop 8-bit register (prefix C8+r, opcode 0x05)
let mayLoad = 1, OpSize = OpSize8.Value in
def POP8 : PrefixPopInst<0x05, (outs GR8:$rd), (ins),
                          "pop", "$rd", []>,
           Sched<[WritePop]>;

// PUSH rs16 — Push 16-bit register (prefix D8+r, opcode 0x04)
let mayStore = 1, OpSize = OpSize16.Value in
def PUSH16 : PrefixPushInst<0x04, (outs), (ins GR16:$rs),
                             "push", "$rs", []>,
             Sched<[WritePush]>;

// POP rd16 — Pop 16-bit register (prefix D8+r, opcode 0x05)
let mayLoad = 1, OpSize = OpSize16.Value in
def POP16 : PrefixPopInst<0x05, (outs GR16:$rd), (ins),
                           "pop", "$rd", []>,
            Sched<[WritePop]>;

// PUSH rs16 — Short form: 0x28+r (1 byte)
let mayStore = 1 in
def PUSH16_short : SingleByteRegInst<0x28, (outs), (ins GR16:$rs),
                                      "pushw", "$rs", []>,
                   Sched<[WritePush]>;

// POP rd16 — Short form: 0x48+r (1 byte)
let mayLoad = 1 in
def POP16_short : SingleByteRegInst<0x48, (outs GR16:$rd), (ins),
                                     "popw", "$rd", []>,
                  Sched<[WritePop]>;

// PUSHW #imm16 — Push 16-bit immediate to stack
// Encoding: 0x0B, imm16_LE (3 bytes)
let mayStore = 1 in
def PUSHW_imm : SingleByteImm8Inst<0x0B, (outs), (ins i16imm:$imm),
                                     "pushw", "$imm", []>,
                Sched<[WritePush]>;

} // Defs = [XSP], Uses = [XSP], hasSideEffects

// PUSH SR — Push status register (0x02, 1 byte)
let Defs = [XSP], Uses = [XSP, SR], hasSideEffects = 0, mayStore = 1 in
def PUSH_SR : SingleByteInst<0x02, (outs), (ins),
                              "push_sr", "", []>,
              Sched<[WritePush]>;

// POP SR — Pop status register (0x03, 1 byte)
let Defs = [XSP, SR], Uses = [XSP], hasSideEffects = 0, mayLoad = 1 in
def POP_SR : SingleByteInst<0x03, (outs), (ins),
                             "pop_sr", "", []>,
             Sched<[WritePop]>;

//===----------------------------------------------------------------------===//
// Pseudo Instructions
//===----------------------------------------------------------------------===//

let Defs = [XSP], Uses = [XSP] in {
def ADJCALLSTACKDOWN : Pseudo<(outs), (ins i32imm:$amt1, i32imm:$amt2),
                              [(callseq_start timm:$amt1, timm:$amt2)]>;
def ADJCALLSTACKUP   : Pseudo<(outs), (ins i32imm:$amt1, i32imm:$amt2),
                              [(callseq_end timm:$amt1, timm:$amt2)]>;
} // Defs = [XSP], Uses = [XSP]

// TRAP — maps to SWI 0 for __builtin_trap() / unreachable
let isBarrier = 1, isTerminator = 1 in
def TRAP : Pseudo<(outs), (ins), [(trap)]>;

// SELECT_CC pseudo — Expanded to branch diamond by custom inserter.
// Operands: trueVal, falseVal, condition code. Reads flags from SR.
let usesCustomInserter = 1, Uses = [SR] in
def Select32 : Pseudo<(outs GPR:$rd),
                      (ins GPR:$trueVal, GPR:$falseVal, i32imm:$cc),
                      [(set GPR:$rd,
                        (tlcs900_select_cc GPR:$trueVal, GPR:$falseVal,
                                           (i32 imm:$cc)))]>;

//===----------------------------------------------------------------------===//
// Set Condition Code
//===----------------------------------------------------------------------===//

// SCC cc, rd — Set register to 1 if condition true, 0 otherwise
// Used by SETCC lowering: CMP → SCC produces branchless boolean result.
let Uses = [SR], hasSideEffects = 0, usesCustomInserter = 1 in
def SCC32 : TLCS900Inst<(outs GPR:$rd), (ins cc:$cc),
                         "scc", "$cc, $rd",
                         [(set GPR:$rd, (tlcs900_scc (i32 imm:$cc)))]>,
            Sched<[WriteIALU]>;

// SCC real encodable forms (for inline assembly / converter use)
// Encoding: reg_prefix + 0x70+cc (2 bytes)
let Uses = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def SCC8 : PrefixCondCodeInst<0x70, (outs GR8:$rd), (ins cc:$cc, GR8:$rs),
                               "scc8", "$cc, $rd", []>,
           Sched<[WriteIALU]> {
  let Constraints = "$rd = $rs";
}
let OpSize = OpSize16.Value in
def SCC16 : PrefixCondCodeInst<0x70, (outs GR16:$rd), (ins cc:$cc, GR16:$rs),
                                "scc16", "$cc, $rd", []>,
            Sched<[WriteIALU]> {
  let Constraints = "$rd = $rs";
}
} // Uses = [SR]

//===----------------------------------------------------------------------===//
// System Instructions
//===----------------------------------------------------------------------===//

// NOP — No operation (safe to remove)
// Encoding: 0x00 (1 byte)
let hasSideEffects = 0 in
def NOP : SingleByteInst<0x00, (outs), (ins), "nop", "", []>,
          Sched<[WriteNop]>;

// HALT — Halt CPU until interrupt
// Encoding: 0x05 (1 byte)
def HALT : SingleByteInst<0x05, (outs), (ins), "halt", "", []>,
           Sched<[WriteNop]>;

// EX F, F' — Exchange flag registers
// Encoding: 0x16 (1 byte)
let Defs = [SR], Uses = [SR], hasSideEffects = 1 in
def EX_FF : SingleByteInst<0x16, (outs), (ins), "ex_ff", "", []>,
            Sched<[WriteNop]>;

// RCF — Reset carry flag (0x10)
let Defs = [SR], hasSideEffects = 0 in
def RCF : SingleByteInst<0x10, (outs), (ins), "rcf", "", []>,
          Sched<[WriteNop]>;

// SCF — Set carry flag (0x11)
let Defs = [SR], hasSideEffects = 0 in
def SCF : SingleByteInst<0x11, (outs), (ins), "scf", "", []>,
          Sched<[WriteNop]>;

// CCF — Complement carry flag (0x12)
let Defs = [SR], hasSideEffects = 0 in
def CCF : SingleByteInst<0x12, (outs), (ins), "ccf", "", []>,
          Sched<[WriteNop]>;

// ZCF — Zero carry flag (set C=!Z) (0x13)
let Defs = [SR], Uses = [SR], hasSideEffects = 0 in
def ZCF : SingleByteInst<0x13, (outs), (ins), "zcf", "", []>,
          Sched<[WriteNop]>;

// INCF — Increment register bank (0x0C)
let hasSideEffects = 1 in
def INCF : SingleByteInst<0x0C, (outs), (ins), "incf", "", []>,
           Sched<[WriteNop]>;

// DECF — Decrement register bank (0x0D)
let hasSideEffects = 1 in
def DECF : SingleByteInst<0x0D, (outs), (ins), "decf", "", []>,
           Sched<[WriteNop]>;

// PUSH A (0x14), POP A (0x15) — Push/pop accumulator byte
let mayStore = 1 in
def PUSH_A : SingleByteInst<0x14, (outs), (ins), "push_a", "", []>,
             Sched<[WritePush]>;
let mayLoad = 1 in
def POP_A : SingleByteInst<0x15, (outs), (ins), "pop_a", "", []>,
            Sched<[WritePop]>;

// PUSH F (0x18), POP F (0x19) — Push/pop flags
let mayStore = 1, Uses = [SR] in
def PUSH_F : SingleByteInst<0x18, (outs), (ins), "push_f", "", []>,
             Sched<[WritePush]>;
let mayLoad = 1, Defs = [SR] in
def POP_F : SingleByteInst<0x19, (outs), (ins), "pop_f", "", []>,
            Sched<[WritePop]>;

// EI — Enable/disable interrupts (with level)
// Encoding: 0x06, level (2 bytes — opcode then level byte)
def EI : SingleByteImm8Inst<0x06, (outs), (ins i32imm:$level),
                            "ei", "$level", []>,
         Sched<[WriteNop]>;

// DI is an alias for EI 0 (setting interrupt level to 0 disables interrupts).
// There is no separate DI opcode in the TLCS-900/H instruction set.
def : InstAlias<"di", (EI 0)>;

// SWI — Software interrupt (with vector number)
// Encoding: 0xF8+num (1 byte, num in bits 0-2)
// Using SingleByteImm8 as approximation; encoder emits 0xF8+num as 1 byte.
def SWI : SingleByteImm8Inst<0xF8, (outs), (ins i32imm:$num),
                             "swi", "$num", []>,
          Sched<[WriteJmp]>;

// LD (n), #n — I/O register write (3-byte: 0x08 + addr8 + imm8)
let mayStore = 1, hasSideEffects = 1 in
def LDIO : LdIoImmInst<0x08, (outs), (ins i32imm:$addr, i32imm:$val),
                         "ldio", "$addr, $val", []>,
           Sched<[WriteSTW]>;

// LDW (n), #nn — I/O register word write (4-byte: 0x0A + addr8 + imm16)
let mayStore = 1, hasSideEffects = 1 in
def LDWIO : LdIoImm16Inst<0x0A, (outs), (ins i32imm:$addr, i32imm:$val),
                            "ldwio", "$addr, $val", []>,
            Sched<[WriteSTW]>;

// RETI — Return from interrupt (pops SR then PC from stack)
// Encoding: 0x07 (1 byte)
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RETI : SingleByteInst<0x07, (outs), (ins), "reti", "", []>,
           Sched<[WriteJmp]>;

// RETD — Return and deallocate stack space
// Encoding: 0x0F, d16 (3 bytes)
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RETD : SingleByteImm8Inst<0x0F, (outs), (ins i32imm:$imm),
                              "retd", "$imm", []>,
           Sched<[WriteJmp]>;

// RETcc — Conditional return
// Encoding: 0xB0, 0xF0+cc (2 bytes)
let isReturn = 1, isTerminator = 1, Uses = [SR] in
def RETcc : SingleByteCondRetInst<0xF0, (outs), (ins cc:$cc),
                                   "ret", "$cc", []>,
            Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Rotate Instructions (single-operand, in-place)
//===----------------------------------------------------------------------===//

// Rotate instructions read AND write carry flag (33-bit rotates through carry).
let Constraints = "$rd = $rs1", Defs = [SR], Uses = [SR], hasSideEffects = 0 in {

// RLC rd — Rotate left through carry (1 bit)
// Encoding: E8+rd, 0xE8, 0x01 (3 bytes)
def RLC32 : PrefixRotateInst<0xE8, (outs GPR:$rd), (ins GPR:$rs1),
                             "rlc", "$rd", []>,
            Sched<[WriteShift, ReadIALU]>;

// RRC rd — Rotate right through carry (1 bit)
// Encoding: E8+rd, 0xE9, 0x01 (3 bytes)
def RRC32 : PrefixRotateInst<0xE9, (outs GPR:$rd), (ins GPR:$rs1),
                             "rrc", "$rd", []>,
            Sched<[WriteShift, ReadIALU]>;

// RL rd — Rotate left (9-bit rotation through carry)
// Encoding: E8+rd, 0xEA, 0x01 (3 bytes)
def RL32 : PrefixRotateInst<0xEA, (outs GPR:$rd), (ins GPR:$rs1),
                            "rl", "$rd", []>,
           Sched<[WriteShift, ReadIALU]>;

// RR rd — Rotate right (9-bit rotation through carry)
// Encoding: E8+rd, 0xEB, 0x01 (3 bytes)
def RR32 : PrefixRotateInst<0xEB, (outs GPR:$rd), (ins GPR:$rs1),
                            "rr", "$rd", []>,
           Sched<[WriteShift, ReadIALU]>;

} // Constraints, Defs, Uses

//===----------------------------------------------------------------------===//
// Shift-by-A Instructions (2-byte: prefix + sub_opcode, count from register A)
// Sub-opcodes: 0xF8=RLC, 0xF9=RRC, 0xFA=RL, 0xFB=RR, 0xFC=SLA, 0xFD=SRA,
//              0xFE=SLL, 0xFF=SRL
// Uses PrefixUnary format (2-byte encoding: prefix + opcode)
//===----------------------------------------------------------------------===//

let Constraints = "$rd = $rs1", Defs = [SR], Uses = [XWA], hasSideEffects = 0 in {

// 32-bit shift-by-A
def SLA_A_32 : PrefixUnaryInst<0xFC, (outs GPR:$rd), (ins GPR:$rs1),
                                "slaa", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
def SRA_A_32 : PrefixUnaryInst<0xFD, (outs GPR:$rd), (ins GPR:$rs1),
                                "sraa", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
def SLL_A_32 : PrefixUnaryInst<0xFE, (outs GPR:$rd), (ins GPR:$rs1),
                                "slla", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
def SRL_A_32 : PrefixUnaryInst<0xFF, (outs GPR:$rd), (ins GPR:$rs1),
                                "srla", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;

// 16-bit shift-by-A
let OpSize = OpSize16.Value in {
def SLA_A_16 : PrefixUnaryInst<0xFC, (outs GR16:$rd), (ins GR16:$rs1),
                                "slaa", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
def SRA_A_16 : PrefixUnaryInst<0xFD, (outs GR16:$rd), (ins GR16:$rs1),
                                "sraa", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
def SLL_A_16 : PrefixUnaryInst<0xFE, (outs GR16:$rd), (ins GR16:$rs1),
                                "slla", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
def SRL_A_16 : PrefixUnaryInst<0xFF, (outs GR16:$rd), (ins GR16:$rs1),
                                "srla", "$rd", []>,
               Sched<[WriteShift, ReadIALU]>;
} // OpSize16

// 8-bit shift-by-A
let OpSize = OpSize8.Value in {
def SLA_A_8 : PrefixUnaryInst<0xFC, (outs GR8:$rd), (ins GR8:$rs1),
                               "slaa", "$rd", []>,
              Sched<[WriteShift, ReadIALU]>;
def SRA_A_8 : PrefixUnaryInst<0xFD, (outs GR8:$rd), (ins GR8:$rs1),
                               "sraa", "$rd", []>,
              Sched<[WriteShift, ReadIALU]>;
def SLL_A_8 : PrefixUnaryInst<0xFE, (outs GR8:$rd), (ins GR8:$rs1),
                               "slla", "$rd", []>,
              Sched<[WriteShift, ReadIALU]>;
def SRL_A_8 : PrefixUnaryInst<0xFF, (outs GR8:$rd), (ins GR8:$rs1),
                               "srla", "$rd", []>,
              Sched<[WriteShift, ReadIALU]>;
} // OpSize8

} // Constraints, Defs, Uses

//===----------------------------------------------------------------------===//
// Bit Manipulation Instructions
//===----------------------------------------------------------------------===//

// BIT #bit, rd — Test bit (set Z flag; effect captured by Defs)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
let Defs = [SR], hasSideEffects = 0, isCodeGenOnly = 1 in
def BIT32 : PrefixBitInst<0x33, (outs), (ins i32imm:$bit, GPR:$rs),
                          "bit", "$bit, $rs", []>,
            Sched<[WriteIALU, ReadIALU]>;

// SET #bit, rd — Set bit (pure computation on register)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
let Constraints = "$rd = $rs1", hasSideEffects = 0, isCodeGenOnly = 1 in
def SET32 : PrefixBitInst<0x31, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "set", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// RES #bit, rd — Reset (clear) bit (pure computation on register)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
let Constraints = "$rd = $rs1", hasSideEffects = 0, isCodeGenOnly = 1 in
def RES32 : PrefixBitInst<0x30, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "res", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// CHG #bit, rd — Change (toggle) bit (pure computation on register)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
let Constraints = "$rd = $rs1", hasSideEffects = 0, isCodeGenOnly = 1 in
def CHG32 : PrefixBitInst<0x32, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "chg", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// TSET #bit, rd — Test and set bit (set Z flag, then set the bit)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
let Constraints = "$rd = $rs1", Defs = [SR], hasSideEffects = 0, isCodeGenOnly = 1 in
def TSET32 : PrefixBitInst<0x34, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                           "tset", "$bit, $rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Exchange Instructions
//===----------------------------------------------------------------------===//

// EX rd, rs — Exchange contents of two registers (no side effects)
// Only valid in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
// isCodeGenOnly: no ISel patterns use this; kept for future pseudo expansion.
let Constraints = "$rd_out = $rd_in, $rs_out = $rs_in", hasSideEffects = 0,
    isCodeGenOnly = 1 in
def EX32 : PrefixRegRegInst<0xB8, (outs GPR:$rd_out, GPR:$rs_out),
                            (ins GPR:$rd_in, GPR:$rs_in),
                            "ex", "$rd_out, $rs_out", []>,
           Sched<[WriteIALU]>;

//===----------------------------------------------------------------------===//
// Load Effective Address
//===----------------------------------------------------------------------===//

// LDA rd, (base+disp) — Load effective address into register (pure computation)
// Encoding: dst_mem_prefix + 0x30+rd (LDA is in B0 opcode table at 0x30)
let hasSideEffects = 0, isReMaterializable = 1 in
def LDA32 : MemLoadDstInst<0x30, 4, (outs GPR:$rd), (ins MEMri:$addr),
                           "lda", "$rd, $addr", []>,
            Sched<[WriteIALU]>;

//===----------------------------------------------------------------------===//
// Loop Instruction
//===----------------------------------------------------------------------===//

// DJNZ rd, target — Decrement and jump if not zero (modifies flags)
// Encoding: D8+rd, 0x1C, d8 (3 bytes) — uses 16-bit prefix (D8)
// DJNZ only exists in C8 (8-bit) and D8 (16-bit) prefix tables, NOT E8 (32-bit).
// We use OpSize16 so the encoder emits a D8 prefix, decrementing the low 16 bits.
let Constraints = "$rd = $rs1", isBranch = 1, isTerminator = 1, Defs = [SR],
    OpSize = OpSize16.Value in
def DJNZ32 : PrefixDJNZInst<0x1C, (outs GPR:$rd), (ins GPR:$rs1, brtarget:$target),
                             "djnz", "$rd, $target", []>,
             Sched<[WriteIALU, WriteJmp]>;

// DJNZ8 rd, target — 8-bit decrement and jump if not zero
// Encoding: C8+rd, 0x1C, d8 (3 bytes) — uses 8-bit prefix (C8)
let Constraints = "$rd = $rs1", isBranch = 1, isTerminator = 1, Defs = [SR],
    OpSize = OpSize8.Value in
def DJNZ8 : PrefixDJNZInst<0x1C, (outs GR8:$rd), (ins GR8:$rs1, brtarget:$target),
                            "djnz8", "$rd, $target", []>,
            Sched<[WriteIALU, WriteJmp]>;

//===----------------------------------------------------------------------===//
// Memory-register arithmetic (CISC: operates directly on memory)
// All modify SR flags.
//===----------------------------------------------------------------------===//

let Defs = [SR], mayLoad = 1, mayStore = 1 in {

// ADD (mem), rs — Add register to memory location (read-modify-write)
// Opcode 0x88: ADDLMR in A0 table (0x80 = ADDLRM is register direction)
def ADD32mr : MemALUInst<0x88, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                         "add", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// SUB (mem), rs — Subtract register from memory location (read-modify-write)
// Opcode 0xA8: SUBLMR in A0 table (0xA0 = SUBLRM is register direction)
def SUB32mr : MemALUInst<0xA8, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                         "sub", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// AND (mem), rs — AND register with memory location (read-modify-write)
// Opcode 0xC8: ANDLMR in A0 table (0xC0 = ANDLRM is register direction)
def AND32mr : MemALUInst<0xC8, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                         "and", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// OR (mem), rs — OR register with memory location (read-modify-write)
// Opcode 0xE8: ORLMR in A0 table (0xE0 = ORLRM is register direction)
def OR32mr : MemALUInst<0xE8, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                        "or", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// XOR (mem), rs — XOR register with memory location (read-modify-write)
// Opcode 0xD8: XORLMR in A0 table (0xD0 = XORLRM is register direction)
def XOR32mr : MemALUInst<0xD8, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                         "xor", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

} // Defs = [SR], mayLoad, mayStore

// CP only reads memory (no write-back), and has patterns so mayLoad is inferred.
let Defs = [SR], isCompare = 1 in {

// CP (mem), rs — Compare memory with register (folds load into compare)
// Opcode 0xF8: CPLMR in A0 table — (mem) - r32 flags (0xF0 = CPLRM is reg direction)
def CP32mr : MemALUInst<0xF8, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                        "cp", "$addr, $rs",
                        [(tlcs900_cmp (load addr:$addr), GPR:$rs)]>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

// CP (mem), #imm — Compare memory with immediate
// Invalid for 32-bit: A0 table has no memory-immediate ALU (0x38-0x3F are DB).
// isCodeGenOnly: ISel will generate LD tmp,(mem); CP tmp,#imm instead.
let isCodeGenOnly = 1 in
def CP32mi : MemALUInst<0xCF, 8, (outs), (ins MEMri:$addr, i32imm:$imm),
                        "cp", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;

} // Defs = [SR]

// ADD/SUB memory-immediate: invalid for 32-bit (A0 table has no mem-imm ALU).
// isCodeGenOnly: ISel will generate LD tmp,(mem); ADD/SUB tmp,#imm; ST (mem),tmp.
let Defs = [SR], mayLoad = 1, mayStore = 1, isCodeGenOnly = 1 in {

def ADD32mi : MemALUInst<0xC8, 8, (outs), (ins MEMri:$addr, i32imm:$imm),
                         "add", "$addr, $imm", []>,
              Sched<[WriteSTW, ReadMemBase]>;

def SUB32mi : MemALUInst<0xCA, 8, (outs), (ins MEMri:$addr, i32imm:$imm),
                         "sub", "$addr, $imm", []>,
              Sched<[WriteSTW, ReadMemBase]>;

} // Defs = [SR], mayLoad, mayStore, isCodeGenOnly

// Memory-immediate ALU (8-bit and 16-bit) — valid in 0x80/0x90 prefix tables.
// Sub-opcodes: ADD=0x38, ADC=0x39, SUB=0x3A, SBC=0x3B,
//              AND=0x3C, XOR=0x3D, OR=0x3E, CP=0x3F.
let Defs = [SR], mayLoad = 1, hasSideEffects = 0 in {

let OpSize = OpSize8.Value in {
def CP8mi  : MemALUInst<0x3F, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "cp", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def AND8mi : MemALUInst<0x3C, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "andmi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def OR8mi  : MemALUInst<0x3E, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "ormi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def ADD8mi : MemALUInst<0x38, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "addmi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def SUB8mi : MemALUInst<0x3A, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "submi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def ADC8mi : MemALUInst<0x39, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "adcmi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def SBC8mi : MemALUInst<0x3B, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "sbcmi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
def XOR8mi : MemALUInst<0x3D, 4, (outs), (ins MEMri:$addr, i8imm:$imm),
                         "xormi8", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;
}

let OpSize = OpSize16.Value in {
def CP16mi  : MemALUInst<0x3F, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "cpw", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def AND16mi : MemALUInst<0x3C, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "andmi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def OR16mi  : MemALUInst<0x3E, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "ormi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def ADD16mi : MemALUInst<0x38, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "addmi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def SUB16mi : MemALUInst<0x3A, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "submi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def ADC16mi : MemALUInst<0x39, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "adcmi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def SBC16mi : MemALUInst<0x3B, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "sbcmi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def XOR16mi : MemALUInst<0x3D, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "xormi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
}

} // Defs = [SR], mayLoad, hasSideEffects

// Memory-ALU isel patterns: fold load+op+store into CISC read-modify-write.
// Matches (store (op (load addr), val), addr) → OP32mr addr, val.
// Commutative ops (add, and, or, xor) auto-match both operand orderings.
def : Pat<(store (add (load addr:$a), GPR:$v), addr:$a),
          (ADD32mr addr:$a, GPR:$v)>;
def : Pat<(store (sub (load addr:$a), GPR:$v), addr:$a),
          (SUB32mr addr:$a, GPR:$v)>;
def : Pat<(store (and (load addr:$a), GPR:$v), addr:$a),
          (AND32mr addr:$a, GPR:$v)>;
def : Pat<(store (or (load addr:$a), GPR:$v), addr:$a),
          (OR32mr addr:$a, GPR:$v)>;
def : Pat<(store (xor (load addr:$a), GPR:$v), addr:$a),
          (XOR32mr addr:$a, GPR:$v)>;

// Note: Memory-immediate ADD/SUB patterns removed because these instructions
// are invalid in the A0 (32-bit source memory) table. ISel will naturally
// decompose these as: LD tmp,(mem); ADD/SUB tmp,#imm; ST (mem),tmp.

// Memory ALU (reg, mem) direction — OP r32, (mem).
// Uses MemLoad encoding: src_prefix + (opcode + reg_enc).
let Defs = [SR], mayLoad = 1 in {
def ADD32rm : MemLoadInst<0x80, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                          "add", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def ADC32rm : MemLoadInst<0x90, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                          "adc", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def SUB32rm : MemLoadInst<0xA0, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                          "sub", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def SBC32rm : MemLoadInst<0xB0, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                          "sbc", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def AND32rm : MemLoadInst<0xC0, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                          "and", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def XOR32rm : MemLoadInst<0xD0, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                          "xor", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def OR32rm : MemLoadInst<0xE0, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                         "or", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
} // Defs = [SR], mayLoad

let Defs = [SR], isCompare = 1 in
def CP32rm : MemLoadInst<0xF0, 4, (outs), (ins GPR:$rs, MEMri:$addr),
                         "cp", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

// Memory ALU 32-bit: (mem), reg — ADC/SBC forms.
let Defs = [SR], Uses = [SR], mayLoad = 1, mayStore = 1 in {
def ADC32mr : MemALUInst<0x98, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                          "adc", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def SBC32mr : MemALUInst<0xB8, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                          "sbc", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
} // Defs, Uses, mayLoad, mayStore

// LD (mem), rs — Source-prefix store (alternative encoding).
// The TLCS-900 ISA has two valid encodings for register-to-memory stores:
//   1. Destination prefix (B0/B8): LD32mr/LD16mr/LD8mr use sub-opcodes 0x60/0x50/0x40
//   2. Source prefix (80-AF):      sub-opcode 0x28+reg_enc in the source memory table
// Both are semantically identical but produce different byte sequences.
// The source-prefix form uses MemALU encoding (IsDstMem=false) since
// the sub-opcode 0x28 lives in the source memory opcode table.
// Mnemonic: ld_s (source-prefix LD store) to disambiguate from ld.
let mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize32.Value in
def LD32mr_src : MemALUInst<0x28, 4, (outs), (ins MEMri:$addr, GPR:$rs),
                              "ld_s", "$addr, $rs", []>,
                 Sched<[WriteSTW, ReadMemBase]>;
let OpSize = OpSize16.Value in
def LD16mr_src : MemALUInst<0x28, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                              "ld_s", "$addr, $rs", []>,
                 Sched<[WriteSTW, ReadMemBase]>;
let OpSize = OpSize8.Value in
def LD8mr_src : MemALUInst<0x28, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                             "ld_s", "$addr, $rs", []>,
                Sched<[WriteSTW, ReadMemBase]>;
} // mayStore, hasSideEffects

// Memory INC/DEC — register-indirect addressing.
// Encoding: src_mem_prefix(base [+disp]) + (0x60 + count%8) for INC
//           src_mem_prefix(base [+disp]) + (0x68 + count%8) for DEC
// Count 1-8 encoded in sub-opcode bits 0-2 (8 wraps to 0).
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def INC8m : MemIncDecInst<0x60, 2, (outs),
                           (ins MEMri:$addr, i32imm:$count),
                           "incm8", "$count, $addr", []>,
            Sched<[WriteSTW, ReadMemBase]>;
def DEC8m : MemIncDecInst<0x68, 2, (outs),
                           (ins MEMri:$addr, i32imm:$count),
                           "decm8", "$count, $addr", []>,
            Sched<[WriteSTW, ReadMemBase]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16m : MemIncDecInst<0x60, 2, (outs),
                            (ins MEMri:$addr, i32imm:$count),
                            "incm", "$count, $addr", []>,
             Sched<[WriteSTW, ReadMemBase]>;
def DEC16m : MemIncDecInst<0x68, 2, (outs),
                            (ins MEMri:$addr, i32imm:$count),
                            "decm", "$count, $addr", []>,
             Sched<[WriteSTW, ReadMemBase]>;
} // OpSize16
} // Defs, mayLoad, mayStore, hasSideEffects

// Memory BIT/SET/RES/LDCF/STCF — bit operations on memory via B0/B8 prefix.
// Encoding: dst_mem_prefix(base [+disp]) + (base_opcode + bit_number)
// BIT: 0xC8+n  SET: 0xB8+n  RES: 0xB0+n  LDCF: 0x98+n  STCF: 0xA0+n
let mayLoad = 1, hasSideEffects = 0 in {
def BITm : MemDstBitOpInst<0xC8, 2, (outs),
                            (ins MEMri:$addr, i32imm:$bit),
                            "bitm", "$bit, $addr", []>,
           Sched<[WriteIALU, ReadMemBase]>;
let Defs = [SR] in
def LDCFm : MemDstBitOpInst<0x98, 2, (outs),
                              (ins MEMri:$addr, i32imm:$bit),
                              "ldcfm", "$bit, $addr", []>,
            Sched<[WriteIALU, ReadMemBase]>;
} // mayLoad, hasSideEffects
let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
def SETm : MemDstBitOpInst<0xB8, 2, (outs),
                            (ins MEMri:$addr, i32imm:$bit),
                            "setm", "$bit, $addr", []>,
           Sched<[WriteSTW, ReadMemBase]>;
def RESm : MemDstBitOpInst<0xB0, 2, (outs),
                            (ins MEMri:$addr, i32imm:$bit),
                            "resm", "$bit, $addr", []>,
           Sched<[WriteSTW, ReadMemBase]>;
let Uses = [SR] in
def STCFm : MemDstBitOpInst<0xA0, 2, (outs),
                              (ins MEMri:$addr, i32imm:$bit),
                              "stcfm", "$bit, $addr", []>,
            Sched<[WriteSTW, ReadMemBase]>;
} // mayLoad, mayStore, hasSideEffects

// Memory PUSH — read from memory and push to stack.
// Encoding: src_mem_prefix(base [+disp]) + 0x04
// 16-bit (PUSHW): uses 0x90-0x9F source memory prefix.
let mayLoad = 1, mayStore = 1, hasSideEffects = 0, Uses = [XSP] in {
let OpSize = OpSize16.Value in
def PUSHW_m : MemPushInst<0x04, 2, (outs), (ins MEMri:$addr),
                           "pushm", "$addr", []>,
              Sched<[WritePush, ReadMemBase]>;
} // mayLoad, mayStore, hasSideEffects, Uses

// Compare memory with immediate: expand to LD + CP since CP32mi is invalid
// in the 32-bit A0 table.
def : Pat<(tlcs900_cmp (i32 (load addr:$a)), (i32 (imm):$v)),
          (CP32ri (LD32rm addr:$a), imm:$v)>;

//===----------------------------------------------------------------------===//
// Multiply / Divide
//===----------------------------------------------------------------------===//
// The TLCS-900/H hardware provides 16×16→32 MUL/MULS under the 16-bit
// register prefix (0xD8-0xDF). i32 MUL is custom-lowered to three MUL16
// operations. DIV/DIVS (32÷16→16+16r) still use libcalls.

// MUL16rr: unsigned 16×16→32 multiply.
// Reads low 16 bits of $src1, multiplies by low 16 bits of $rs2,
// writes full 32-bit result to $rd (destructive on $src1).
// Encoding: D8+src2, 0x40+dst (2 bytes) — 16-bit register prefix
let Constraints = "$rd = $src1", Defs = [SR], OpSize = OpSize16.Value in
def MUL16rr : PrefixRegRegInst<0x40, (outs GPR:$rd),
                                (ins GPR:$src1, GPR:$rs2),
                                "mul", "$rd, $rs2",
                                [(set GPR:$rd,
                                  (tlcs900_mul16 GPR:$src1, GPR:$rs2))]>,
              Sched<[WriteIMul, ReadIALU, ReadIALU]>;

// MULS16rr: signed 16×16→32 multiply (same encoding with opcode 0x48).
// No isel pattern — for future use / inline asm.
let Constraints = "$rd = $src1", Defs = [SR], OpSize = OpSize16.Value in
def MULS16rr : PrefixRegRegInst<0x48, (outs GPR:$rd),
                                 (ins GPR:$src1, GPR:$rs2),
                                 "muls", "$rd, $rs2", []>,
               Sched<[WriteIMul, ReadIALU, ReadIALU]>;

// DIV16rr: unsigned 32÷16→16q+16r.
// Reads full 32-bit $src1 as dividend, divides by low 16 bits of $rs2.
// Result in $rd: low 16 = quotient, high 16 = remainder.
// Encoding: D8+src2, 0x50+dst (2 bytes) — 16-bit register prefix
let Constraints = "$rd = $src1", Defs = [SR], OpSize = OpSize16.Value in
def DIV16rr : PrefixRegRegInst<0x50, (outs GPR:$rd),
                                (ins GPR:$src1, GPR:$rs2),
                                "div", "$rd, $rs2", []>,
              Sched<[WriteIMul, ReadIALU, ReadIALU]>;

// DIVS16rr: signed 32÷16→16q+16r.
let Constraints = "$rd = $src1", Defs = [SR], OpSize = OpSize16.Value in
def DIVS16rr : PrefixRegRegInst<0x58, (outs GPR:$rd),
                                 (ins GPR:$src1, GPR:$rs2),
                                 "divs", "$rd, $rs2", []>,
               Sched<[WriteIMul, ReadIALU, ReadIALU]>;

// MUL/MULS/DIV/DIVS with 8-bit immediate (C8+r prefix, opc, imm8)
let Constraints = "$rd = $src1", Defs = [SR], OpSize = OpSize8.Value in {
def MUL8ri : PrefixRegImmInst<0x08, 3, (outs GR8:$rd),
                               (ins GR8:$src1, i8imm:$imm),
                               "mul", "$rd, $imm", []>,
             Sched<[WriteIMul, ReadIALU]>;
def MULS8ri : PrefixRegImmInst<0x09, 3, (outs GR8:$rd),
                                (ins GR8:$src1, i8imm:$imm),
                                "muls", "$rd, $imm", []>,
              Sched<[WriteIMul, ReadIALU]>;
def DIV8ri : PrefixRegImmInst<0x0A, 3, (outs GR8:$rd),
                               (ins GR8:$src1, i8imm:$imm),
                               "div", "$rd, $imm", []>,
             Sched<[WriteIMul, ReadIALU]>;
def DIVS8ri : PrefixRegImmInst<0x0B, 3, (outs GR8:$rd),
                                (ins GR8:$src1, i8imm:$imm),
                                "divs", "$rd, $imm", []>,
              Sched<[WriteIMul, ReadIALU]>;
}

// MUL/MULS/DIV/DIVS with 16-bit immediate (D8+r prefix, opc, imm16)
let Constraints = "$rd = $src1", Defs = [SR], OpSize = OpSize16.Value in {
def MUL16ri : PrefixRegImmInst<0x08, 4, (outs GR16:$rd),
                                (ins GR16:$src1, i16imm:$imm),
                                "mul", "$rd, $imm", []>,
              Sched<[WriteIMul, ReadIALU]>;
def MULS16ri : PrefixRegImmInst<0x09, 4, (outs GR16:$rd),
                                 (ins GR16:$src1, i16imm:$imm),
                                 "muls", "$rd, $imm", []>,
               Sched<[WriteIMul, ReadIALU]>;
def DIV16ri : PrefixRegImmInst<0x0A, 4, (outs GR16:$rd),
                                (ins GR16:$src1, i16imm:$imm),
                                "div", "$rd, $imm", []>,
              Sched<[WriteIMul, ReadIALU]>;
def DIVS16ri : PrefixRegImmInst<0x0B, 4, (outs GR16:$rd),
                                 (ins GR16:$src1, i16imm:$imm),
                                 "divs", "$rd, $imm", []>,
               Sched<[WriteIMul, ReadIALU]>;
}

//===----------------------------------------------------------------------===//
// Block Transfer Instructions (no isel patterns — for inline asm / builtins)
//===----------------------------------------------------------------------===//

// LDI — Load and increment: (XDE) ← (XHL), XDE++, XHL++, XBC--
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize8.Value in
def LDI : BlockTransferInst<0x10, (outs), (ins), "ldi", "", []>,
          Sched<[WriteSTW]>;

// LDIR — Load, increment, repeat: LDI until XBC == 0
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize8.Value in
def LDIR : BlockTransferInst<0x11, (outs), (ins), "ldir", "", []>,
           Sched<[WriteSTW]>;

// LDD — Load and decrement: (XDE) ← (XHL), XDE--, XHL--, XBC--
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize8.Value in
def LDD : BlockTransferInst<0x12, (outs), (ins), "ldd", "", []>,
          Sched<[WriteSTW]>;

// LDDR — Load, decrement, repeat: LDD until XBC == 0
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize8.Value in
def LDDR : BlockTransferInst<0x13, (outs), (ins), "lddr", "", []>,
           Sched<[WriteSTW]>;

// --- Block transfer variants with non-zero register index ---
// The TLCS-900 hardware ignores the register index for block transfers,
// but the ROM uses specific indices that we must byte-match.

// Prefix 0x85 (8-bit, reg_idx=5): ldi85, ldir85, lddr85
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize8.Value in {
def LDI85 : BlockTransferInst<0x10, (outs), (ins), "ldi85", "", [], 5>,
            Sched<[WriteSTW]>;
def LDIR85 : BlockTransferInst<0x11, (outs), (ins), "ldir85", "", [], 5>,
             Sched<[WriteSTW]>;
def LDDR85 : BlockTransferInst<0x13, (outs), (ins), "lddr85", "", [], 5>,
             Sched<[WriteSTW]>;
}

// Prefix 0x83 (8-bit, reg_idx=3): ldir83, lddr83, cpir83
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize8.Value in {
def LDIR83 : BlockTransferInst<0x11, (outs), (ins), "ldir83", "", [], 3>,
             Sched<[WriteSTW]>;
def LDDR83 : BlockTransferInst<0x13, (outs), (ins), "lddr83", "", [], 3>,
             Sched<[WriteSTW]>;
}
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1,
    OpSize = OpSize8.Value in
def CPIR83 : BlockTransferInst<0x15, (outs), (ins), "cpir83", "", [], 3>,
             Sched<[WriteIALU]>;

// --- 16-bit wide block transfers (prefix 0x90+ridx) ---
// LDIW — Word-size LDI (prefix 0x95, reg_idx=5)
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize16.Value in {
def LDIW : BlockTransferInst<0x10, (outs), (ins), "ldiw", "", [], 5>,
           Sched<[WriteSTW]>;
def LDIRW : BlockTransferInst<0x11, (outs), (ins), "ldirw", "", [], 5>,
            Sched<[WriteSTW]>;
}

// LDIRW with reg_idx=3 (prefix 0x93)
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    OpSize = OpSize16.Value in
def LDIRW93 : BlockTransferInst<0x11, (outs), (ins), "ldirw93", "", [], 3>,
              Sched<[WriteSTW]>;

//===----------------------------------------------------------------------===//
// Bit manipulation isel patterns
//===----------------------------------------------------------------------===//

// Predicate: immediate is a power of 2 (exactly one bit set)
def IsPow2_32 : PatLeaf<(i32 imm), [{
  return N->getAPIntValue().isPowerOf2();
}]>;

// Predicate: immediate has exactly one zero bit (~imm is power of 2)
def IsNotPow2_32 : PatLeaf<(i32 imm), [{
  return (~N->getAPIntValue()).isPowerOf2();
}]>;

// Transform: extract bit number from a power-of-2 constant
def Log2_32 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(
    N->getAPIntValue().exactLogBase2(), SDLoc(N), MVT::i32);
}]>;

// Transform: extract bit number from a ~power-of-2 constant (one zero bit)
def Log2Not_32 : SDNodeXForm<imm, [{
  return CurDAG->getTargetConstant(
    (~N->getAPIntValue()).exactLogBase2(), SDLoc(N), MVT::i32);
}]>;

// Note: SET32/RES32/CHG32 are invalid in the E8 (32-bit) prefix table.
// Power-of-2 OR/AND/XOR patterns will naturally select OR32ri/AND32ri/XOR32ri
// which are valid 32-bit instructions.

//===----------------------------------------------------------------------===//
// Block Transfer ISel: LDIR for memcpy
//===----------------------------------------------------------------------===//

// LDIR SDNode: no explicit operands; XDE/XHL/XBC set via CopyToReg + glue.
def tlcs900_ldir : SDNode<"TLCS900ISD::LDIR", SDTNone,
                           [SDNPHasChain, SDNPInGlue, SDNPOutGlue,
                            SDNPMayStore, SDNPMayLoad]>;
def : Pat<(tlcs900_ldir), (LDIR)>;

// MEMMOVE SDNode: runtime direction check + LDIR or LDDR.
def tlcs900_memmove : SDNode<"TLCS900ISD::MEMMOVE", SDTNone,
                              [SDNPHasChain, SDNPInGlue, SDNPOutGlue,
                               SDNPMayStore, SDNPMayLoad]>;

// MEMMOVE_PSEUDO: expanded by custom inserter into CP+branch+LDIR/LDDR.
let usesCustomInserter = 1, Defs = [XDE, XHL, XBC, SR],
    Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def MEMMOVE_PSEUDO : Pseudo<(outs), (ins), [(tlcs900_memmove)]>;

//===----------------------------------------------------------------------===//
// Compare/Search Block Instructions
//===----------------------------------------------------------------------===//

// CPI — Compare and increment: compare A with (XHL), XHL++, XBC--
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1,
    OpSize = OpSize8.Value in
def CPI : BlockTransferInst<0x14, (outs), (ins), "cpi", "", []>,
          Sched<[WriteIALU]>;

// CPIR — Compare, increment, repeat: CPI until match or XBC == 0
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1,
    OpSize = OpSize8.Value in
def CPIR : BlockTransferInst<0x15, (outs), (ins), "cpir", "", []>,
           Sched<[WriteIALU]>;

// CPD — Compare and decrement: compare A with (XHL), XHL--, XBC--
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1,
    OpSize = OpSize8.Value in
def CPD : BlockTransferInst<0x16, (outs), (ins), "cpd", "", []>,
          Sched<[WriteIALU]>;

// CPDR — Compare, decrement, repeat: CPD until match or XBC == 0
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1,
    OpSize = OpSize8.Value in
def CPDR : BlockTransferInst<0x17, (outs), (ins), "cpdr", "", []>,
           Sched<[WriteIALU]>;

//===----------------------------------------------------------------------===//
// 16-bit Sub-register Instructions (assembler-only, no codegen patterns)
//
// These use the D8-DF register prefix (16-bit) with the same opcodes as
// their 32-bit counterparts. The encoder selects the prefix automatically
// based on OpSize. Register class GR16 (WA, BC, DE, HL, IX, IY, IZ).
//===----------------------------------------------------------------------===//

let OpSize = OpSize16.Value in {

// --- Data transfer ---

// LD rd16, rs16: D8+src, 0x88+dst
let isAsCheapAsAMove = 1, hasSideEffects = 0 in
def LD16rr_asm : PrefixRegRegInst<0x88, (outs GR16:$rd), (ins GR16:$rs),
                                   "ld", "$rd, $rs", []>,
                 Sched<[WriteIALU]>;

// LD rd16, #imm16: D8+rd, 0x03, imm16 (prefix form, 4 bytes)
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD16ri_asm : PrefixLDImmInst<0x03, 4, (outs GR16:$rd), (ins i16imm:$imm),
                                  "ld", "$rd, $imm", []>,
                 Sched<[WriteIALU]>;

// LD rd16, #imm16 — Short form: 0x30+r, imm16 (3 bytes)
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD16ri_short : SingleByteRegImmInst<0x30, 3, (outs GR16:$rd),
                                         (ins i16imm:$imm),
                                         "ldw", "$rd, $imm", []>,
                   Sched<[WriteIALU]>;

// LD rd, #(0-7) — Small immediate form: prefix+r, 0xA8+val (2 bytes)
let isReMaterializable = 1, isAsCheapAsAMove = 1 in {
let OpSize = OpSize8.Value in
def LD8ri_small : PrefixSmallImmInst<0xA8, (outs GR8:$rd),
                                      (ins i8imm:$imm),
                                      "lds8", "$rd, $imm", []>,
                  Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def LD16ri_small : PrefixSmallImmInst<0xA8, (outs GR16:$rd),
                                       (ins i16imm:$imm),
                                       "lds", "$rd, $imm", []>,
                   Sched<[WriteIALU]>;
let OpSize = OpSize32.Value in
def LD32ri_small : PrefixSmallImmInst<0xA8, (outs GPR:$rd),
                                       (ins i32imm:$imm),
                                       "lds32", "$rd, $imm", []>,
                   Sched<[WriteIALU]>;
}

// --- Arithmetic (two-address: rd = rd op rs) ---
let Constraints = "$rd = $rs1", Defs = [SR] in {

let isCommutable = 1 in
def ADD16rr : PrefixRegRegInst<0x80, (outs GR16:$rd),
                                (ins GR16:$rs1, GR16:$rs2),
                                "add", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def ADD16ri : PrefixRegImmInst<0xC8, 4, (outs GR16:$rd),
                                (ins GR16:$rs1, i16imm:$imm),
                                "add", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

def SUB16rr : PrefixRegRegInst<0xA0, (outs GR16:$rd),
                                (ins GR16:$rs1, GR16:$rs2),
                                "sub", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def SUB16ri : PrefixRegImmInst<0xCA, 4, (outs GR16:$rd),
                                (ins GR16:$rs1, i16imm:$imm),
                                "sub", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

// --- Carry arithmetic ---
let Uses = [SR] in {

def ADC16rr : PrefixRegRegInst<0x90, (outs GR16:$rd),
                                (ins GR16:$rs1, GR16:$rs2),
                                "adc", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def ADC16ri : PrefixRegImmInst<0xC9, 4, (outs GR16:$rd),
                                (ins GR16:$rs1, i16imm:$imm),
                                "adc", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

def SBC16rr : PrefixRegRegInst<0xB0, (outs GR16:$rd),
                                (ins GR16:$rs1, GR16:$rs2),
                                "sbc", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def SBC16ri : PrefixRegImmInst<0xCB, 4, (outs GR16:$rd),
                                (ins GR16:$rs1, i16imm:$imm),
                                "sbc", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

} // Uses = [SR]

// --- Logic ---

let isCommutable = 1 in
def AND16rr : PrefixRegRegInst<0xC0, (outs GR16:$rd),
                                (ins GR16:$rs1, GR16:$rs2),
                                "and", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def AND16ri : PrefixRegImmInst<0xCC, 4, (outs GR16:$rd),
                                (ins GR16:$rs1, i16imm:$imm),
                                "and", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

let isCommutable = 1 in
def OR16rr : PrefixRegRegInst<0xE0, (outs GR16:$rd),
                               (ins GR16:$rs1, GR16:$rs2),
                               "or", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def OR16ri : PrefixRegImmInst<0xCE, 4, (outs GR16:$rd),
                               (ins GR16:$rs1, i16imm:$imm),
                               "or", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

let isCommutable = 1 in
def XOR16rr : PrefixRegRegInst<0xD0, (outs GR16:$rd),
                                (ins GR16:$rs1, GR16:$rs2),
                                "xor", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def XOR16ri : PrefixRegImmInst<0xCD, 4, (outs GR16:$rd),
                                (ins GR16:$rs1, i16imm:$imm),
                                "xor", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

// --- Shifts ---

def SLA16ri : PrefixShiftInst<0xEC, (outs GR16:$rd),
                               (ins GR16:$rs1, i16imm:$imm),
                               "sla", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

def SRA16ri : PrefixShiftInst<0xED, (outs GR16:$rd),
                               (ins GR16:$rs1, i16imm:$imm),
                               "sra", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

def SLL16ri : PrefixShiftInst<0xEE, (outs GR16:$rd),
                               (ins GR16:$rs1, i16imm:$imm),
                               "sll", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

def SRL16ri : PrefixShiftInst<0xEF, (outs GR16:$rd),
                               (ins GR16:$rs1, i16imm:$imm),
                               "srl", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// --- Unary ---

def NEG16 : PrefixUnaryInst<0x07, (outs GR16:$rd), (ins GR16:$rs1),
                             "neg", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

def CPL16 : PrefixUnaryInst<0x06, (outs GR16:$rd), (ins GR16:$rs1),
                             "cpl", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// --- Extend ---

def EXTS16 : PrefixUnaryInst<0x13, (outs GR16:$rd), (ins GR16:$rs1),
                              "exts", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

def EXTZ16 : PrefixUnaryInst<0x12, (outs GR16:$rd), (ins GR16:$rs1),
                              "extz", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

} // Constraints = "$rd = $rs1", Defs = [SR]

// --- INC/DEC ---
// NOTE: On TLCS-900/H, 16-bit INC/DEC do NOT set any flags (S, Z, H, V).
// Only 8-bit INC/DEC set flags. Must be outside the Defs=[SR] block.
let Constraints = "$rd = $rs1" in {
def INC16 : PrefixIncDecInst<0x60, (outs GR16:$rd),
                              (ins GR16:$rs1, i16imm:$n),
                              "inc", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

def DEC16 : PrefixIncDecInst<0x68, (outs GR16:$rd),
                              (ins GR16:$rs1, i16imm:$n),
                              "dec", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;
} // Constraints = "$rd = $rs1" (no Defs=[SR]: 16-bit INC/DEC don't set flags)

// --- Compare (no output register) ---
let Defs = [SR], isCompare = 1 in {

def CP16rr : PrefixRegRegInst<0xF0, (outs), (ins GR16:$rs1, GR16:$rs2),
                               "cp", "$rs1, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def CP16ri : PrefixRegImmInst<0xCF, 4, (outs), (ins GR16:$rs1, i16imm:$imm),
                               "cp", "$rs1, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

// CP rd16, #(0-7) — Compare with small immediate: D8+r, 0xD8+val (2 bytes)
def CP16_small : PrefixSmallImmInst<0xD8, (outs), (ins GR16:$rs1, i16imm:$imm),
                                     "cps", "$rs1, $imm", []>,
                 Sched<[WriteIALU, ReadIALU]>;

} // Defs = [SR]

// --- Rotates (read AND write carry) ---
let Constraints = "$rd = $rs1", Defs = [SR], Uses = [SR], hasSideEffects = 0 in {

def RLC16 : PrefixRotateInst<0xE8, (outs GR16:$rd), (ins GR16:$rs1),
                              "rlc", "$rd", []>,
            Sched<[WriteShift, ReadIALU]>;

def RRC16 : PrefixRotateInst<0xE9, (outs GR16:$rd), (ins GR16:$rs1),
                              "rrc", "$rd", []>,
            Sched<[WriteShift, ReadIALU]>;

def RL16 : PrefixRotateInst<0xEA, (outs GR16:$rd), (ins GR16:$rs1),
                             "rl", "$rd", []>,
           Sched<[WriteShift, ReadIALU]>;

def RR16 : PrefixRotateInst<0xEB, (outs GR16:$rd), (ins GR16:$rs1),
                             "rr", "$rd", []>,
           Sched<[WriteShift, ReadIALU]>;

} // Constraints, Defs, Uses

// --- Bit manipulation (for peephole optimization pass) ---

// 16-bit SET/RES/CHG used by TLCS900BitManipOpt to replace 6-byte OR32ri/
// AND32ri/XOR32ri with power-of-2 immediates with 3-byte bit instructions.
// These do NOT set flags (no Defs = [SR]).
let Constraints = "$rd = $rs1", hasSideEffects = 0 in {
def SET16 : PrefixBitInst<0x31, (outs GR16:$rd), (ins i32imm:$bit, GR16:$rs1),
                           "set", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

def RES16 : PrefixBitInst<0x30, (outs GR16:$rd), (ins i32imm:$bit, GR16:$rs1),
                           "res", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

def CHG16 : PrefixBitInst<0x32, (outs GR16:$rd), (ins i32imm:$bit, GR16:$rs1),
                           "chg", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;
} // Constraints, hasSideEffects

// BIT16: test bit in 16-bit subreg, set Z flag
let Defs = [SR], hasSideEffects = 0 in
def BIT16 : PrefixBitInst<0x33, (outs), (ins i32imm:$bit, GR16:$rs),
                           "bit", "$bit, $rs", []>,
            Sched<[WriteIALU, ReadIALU]>;

// --- Memory load/store (16-bit data, register-indirect addressing) ---

// LD rd:16, (base+disp) — Load 16-bit from memory into 16-bit register.
// Assembler-visible: uses GR16 register class directly.
let mayLoad = 1 in
def LD16rm_asm : MemLoadInst<0x20, 4, (outs GR16:$rd), (ins MEMri:$addr),
                              "ld", "$rd, $addr", []>,
                 Sched<[WriteLDW, ReadMemBase]>;

// LD (base+disp), rs:16 — Store 16-bit register to memory.
// Assembler-visible: uses GR16 register class directly.
def LD16mr_asm : MemStoreInst<0x50, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                               "ld", "$addr, $rs", []>,
                 Sched<[WriteSTW, ReadMemBase]>;

// --- Memory ALU (16-bit data, register-indirect addressing) ---

// OP (mem), r16 — Read-modify-write memory with 16-bit register.
let Defs = [SR], mayLoad = 1, mayStore = 1 in {
def ADD16mr : MemALUInst<0x88, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                          "add", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def SUB16mr : MemALUInst<0xA8, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                          "sub", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def AND16mr : MemALUInst<0xC8, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                          "and", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def OR16mr : MemALUInst<0xE8, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                         "or", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def XOR16mr : MemALUInst<0xD8, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                          "xor", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
} // Defs, mayLoad, mayStore

let Defs = [SR], Uses = [SR], mayLoad = 1, mayStore = 1 in {
def ADC16mr : MemALUInst<0x98, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                          "adc", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def SBC16mr : MemALUInst<0xB8, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                          "sbc", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
} // Defs, Uses, mayLoad, mayStore

let Defs = [SR], isCompare = 1 in
def CP16mr : MemALUInst<0xF8, 4, (outs), (ins MEMri:$addr, GR16:$rs),
                         "cp", "$addr, $rs", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

// OP r16, (mem) — ALU with register destination, memory source.
let Defs = [SR], mayLoad = 1 in {
def ADD16rm : MemLoadInst<0x80, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                           "add", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def SUB16rm : MemLoadInst<0xA0, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                           "sub", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def AND16rm : MemLoadInst<0xC0, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                           "and", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def OR16rm : MemLoadInst<0xE0, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                          "or", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def XOR16rm : MemLoadInst<0xD0, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                           "xor", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
} // Defs, mayLoad

let Defs = [SR], Uses = [SR], mayLoad = 1 in {
def ADC16rm : MemLoadInst<0x90, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                           "adc", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def SBC16rm : MemLoadInst<0xB0, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                           "sbc", "$rs, $addr", []>,
              Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
} // Defs, Uses, mayLoad

let Defs = [SR], isCompare = 1 in
def CP16rm : MemLoadInst<0xF0, 4, (outs), (ins GR16:$rs, MEMri:$addr),
                          "cp", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

} // OpSize = OpSize16.Value

//===----------------------------------------------------------------------===//
// 8-bit Sub-register Instructions (assembler-only, no codegen patterns)
//
// These use the C8-CF register prefix (8-bit) with the same opcodes as
// their 32-bit counterparts. Register class GR8 (W, A, B, C, D, E, H, L).
//===----------------------------------------------------------------------===//

let OpSize = OpSize8.Value in {

// --- Data transfer ---

let isAsCheapAsAMove = 1, hasSideEffects = 0 in
def LD8rr_asm : PrefixRegRegInst<0x88, (outs GR8:$rd), (ins GR8:$rs),
                                  "ld", "$rd, $rs", []>,
                Sched<[WriteIALU]>;

let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD8ri_asm : PrefixLDImmInst<0x03, 3, (outs GR8:$rd), (ins i8imm:$imm),
                                 "ld", "$rd, $imm", []>,
                Sched<[WriteIALU]>;

// LD rd8, #imm8 — Short form: 0x20+r, imm8 (2 bytes)
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD8ri_short : SingleByteRegImmInst<0x20, 2, (outs GR8:$rd),
                                        (ins i8imm:$imm),
                                        "ldb", "$rd, $imm", []>,
                  Sched<[WriteIALU]>;

// --- Arithmetic ---
let Constraints = "$rd = $rs1", Defs = [SR] in {

let isCommutable = 1 in
def ADD8rr : PrefixRegRegInst<0x80, (outs GR8:$rd),
                               (ins GR8:$rs1, GR8:$rs2),
                               "add", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def ADD8ri : PrefixRegImmInst<0xC8, 3, (outs GR8:$rd),
                               (ins GR8:$rs1, i8imm:$imm),
                               "add", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

def SUB8rr : PrefixRegRegInst<0xA0, (outs GR8:$rd),
                               (ins GR8:$rs1, GR8:$rs2),
                               "sub", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def SUB8ri : PrefixRegImmInst<0xCA, 3, (outs GR8:$rd),
                               (ins GR8:$rs1, i8imm:$imm),
                               "sub", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

let Uses = [SR] in {

def ADC8rr : PrefixRegRegInst<0x90, (outs GR8:$rd),
                               (ins GR8:$rs1, GR8:$rs2),
                               "adc", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def ADC8ri : PrefixRegImmInst<0xC9, 3, (outs GR8:$rd),
                               (ins GR8:$rs1, i8imm:$imm),
                               "adc", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

def SBC8rr : PrefixRegRegInst<0xB0, (outs GR8:$rd),
                               (ins GR8:$rs1, GR8:$rs2),
                               "sbc", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def SBC8ri : PrefixRegImmInst<0xCB, 3, (outs GR8:$rd),
                               (ins GR8:$rs1, i8imm:$imm),
                               "sbc", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

} // Uses = [SR]

// --- Logic ---

let isCommutable = 1 in
def AND8rr : PrefixRegRegInst<0xC0, (outs GR8:$rd),
                               (ins GR8:$rs1, GR8:$rs2),
                               "and", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def AND8ri : PrefixRegImmInst<0xCC, 3, (outs GR8:$rd),
                               (ins GR8:$rs1, i8imm:$imm),
                               "and", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

let isCommutable = 1 in
def OR8rr : PrefixRegRegInst<0xE0, (outs GR8:$rd),
                              (ins GR8:$rs1, GR8:$rs2),
                              "or", "$rd, $rs2", []>,
            Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def OR8ri : PrefixRegImmInst<0xCE, 3, (outs GR8:$rd),
                              (ins GR8:$rs1, i8imm:$imm),
                              "or", "$rd, $imm", []>,
            Sched<[WriteIALU, ReadIALU]>;

let isCommutable = 1 in
def XOR8rr : PrefixRegRegInst<0xD0, (outs GR8:$rd),
                               (ins GR8:$rs1, GR8:$rs2),
                               "xor", "$rd, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def XOR8ri : PrefixRegImmInst<0xCD, 3, (outs GR8:$rd),
                               (ins GR8:$rs1, i8imm:$imm),
                               "xor", "$rd, $imm", []>,
             Sched<[WriteIALU, ReadIALU]>;

// --- Shifts ---

def SLA8ri : PrefixShiftInst<0xEC, (outs GR8:$rd),
                              (ins GR8:$rs1, i8imm:$imm),
                              "sla", "$rd, $imm", []>,
             Sched<[WriteShift, ReadIALU]>;

def SRA8ri : PrefixShiftInst<0xED, (outs GR8:$rd),
                              (ins GR8:$rs1, i8imm:$imm),
                              "sra", "$rd, $imm", []>,
             Sched<[WriteShift, ReadIALU]>;

def SLL8ri : PrefixShiftInst<0xEE, (outs GR8:$rd),
                              (ins GR8:$rs1, i8imm:$imm),
                              "sll", "$rd, $imm", []>,
             Sched<[WriteShift, ReadIALU]>;

def SRL8ri : PrefixShiftInst<0xEF, (outs GR8:$rd),
                              (ins GR8:$rs1, i8imm:$imm),
                              "srl", "$rd, $imm", []>,
             Sched<[WriteShift, ReadIALU]>;

// --- Unary ---

def NEG8 : PrefixUnaryInst<0x07, (outs GR8:$rd), (ins GR8:$rs1),
                            "neg", "$rd", []>,
           Sched<[WriteIALU, ReadIALU]>;

def CPL8 : PrefixUnaryInst<0x06, (outs GR8:$rd), (ins GR8:$rs1),
                            "cpl", "$rd", []>,
           Sched<[WriteIALU, ReadIALU]>;

// --- Extend (8→16 within 16-bit register) ---

def EXTS8 : PrefixUnaryInst<0x13, (outs GR8:$rd), (ins GR8:$rs1),
                             "exts", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

def EXTZ8 : PrefixUnaryInst<0x12, (outs GR8:$rd), (ins GR8:$rs1),
                             "extz", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// --- INC/DEC ---

def INC8 : PrefixIncDecInst<0x60, (outs GR8:$rd),
                             (ins GR8:$rs1, i8imm:$n),
                             "inc", "$n, $rd", []>,
           Sched<[WriteIALU, ReadIALU]>;

def DEC8 : PrefixIncDecInst<0x68, (outs GR8:$rd),
                             (ins GR8:$rs1, i8imm:$n),
                             "dec", "$n, $rd", []>,
           Sched<[WriteIALU, ReadIALU]>;

} // Constraints = "$rd = $rs1", Defs = [SR]

// --- Compare ---
let Defs = [SR], isCompare = 1 in {

def CP8rr : PrefixRegRegInst<0xF0, (outs), (ins GR8:$rs1, GR8:$rs2),
                              "cp", "$rs1, $rs2", []>,
            Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def CP8ri : PrefixRegImmInst<0xCF, 3, (outs), (ins GR8:$rs1, i8imm:$imm),
                              "cp", "$rs1, $imm", []>,
            Sched<[WriteIALU, ReadIALU]>;

// CP rd8, #(0-7) — Compare with small immediate: C8+r, 0xD8+val (2 bytes)
def CP8_small : PrefixSmallImmInst<0xD8, (outs), (ins GR8:$rs1, i8imm:$imm),
                                    "cps", "$rs1, $imm", []>,
                Sched<[WriteIALU, ReadIALU]>;

} // Defs = [SR]

// --- Rotates ---
let Constraints = "$rd = $rs1", Defs = [SR], Uses = [SR], hasSideEffects = 0 in {

def RLC8 : PrefixRotateInst<0xE8, (outs GR8:$rd), (ins GR8:$rs1),
                             "rlc", "$rd", []>,
           Sched<[WriteShift, ReadIALU]>;

def RRC8 : PrefixRotateInst<0xE9, (outs GR8:$rd), (ins GR8:$rs1),
                             "rrc", "$rd", []>,
           Sched<[WriteShift, ReadIALU]>;

def RL8 : PrefixRotateInst<0xEA, (outs GR8:$rd), (ins GR8:$rs1),
                            "rl", "$rd", []>,
          Sched<[WriteShift, ReadIALU]>;

def RR8 : PrefixRotateInst<0xEB, (outs GR8:$rd), (ins GR8:$rs1),
                            "rr", "$rd", []>,
          Sched<[WriteShift, ReadIALU]>;

} // Constraints, Defs, Uses

// --- Bit manipulation (8-bit registers) ---

let Defs = [SR] in
def BIT8 : PrefixBitInst<0x33, (outs), (ins i32imm:$bit, GR8:$rs),
                           "bit", "$bit, $rs", []>,
           Sched<[WriteIALU, ReadIALU]>;

let Constraints = "$rd = $rs1" in {
def SET8 : PrefixBitInst<0x31, (outs GR8:$rd), (ins i32imm:$bit, GR8:$rs1),
                           "set", "$bit, $rd", []>,
           Sched<[WriteIALU, ReadIALU]>;

def RES8 : PrefixBitInst<0x30, (outs GR8:$rd), (ins i32imm:$bit, GR8:$rs1),
                           "res", "$bit, $rd", []>,
           Sched<[WriteIALU, ReadIALU]>;
} // Constraints

// --- Memory load/store (8-bit data, register-indirect addressing) ---

// LD rd:8, (base+disp) — Load 8-bit from memory into 8-bit register.
// Assembler-visible: uses GR8 register class directly.
let mayLoad = 1 in
def LD8rm_asm : MemLoadInst<0x20, 3, (outs GR8:$rd), (ins MEMri:$addr),
                             "ld", "$rd, $addr", []>,
                Sched<[WriteLDW, ReadMemBase]>;

// LD (base+disp), rs:8 — Store 8-bit register to memory.
// Assembler-visible: uses GR8 register class directly.
def LD8mr_asm : MemStoreInst<0x40, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                              "ld", "$addr, $rs", []>,
                Sched<[WriteSTW, ReadMemBase]>;

// --- Memory ALU (8-bit data, register-indirect addressing) ---

// OP (mem), r8 — Read-modify-write memory with 8-bit register.
let Defs = [SR], mayLoad = 1, mayStore = 1 in {
def ADD8mr : MemALUInst<0x88, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                         "add", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def SUB8mr : MemALUInst<0xA8, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                         "sub", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def AND8mr : MemALUInst<0xC8, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                         "and", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def OR8mr : MemALUInst<0xE8, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                        "or", "$addr, $rs", []>,
            Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def XOR8mr : MemALUInst<0xD8, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                         "xor", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
} // Defs, mayLoad, mayStore

let Defs = [SR], Uses = [SR], mayLoad = 1, mayStore = 1 in {
def ADC8mr : MemALUInst<0x98, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                         "adc", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
def SBC8mr : MemALUInst<0xB8, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                         "sbc", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;
} // Defs, Uses, mayLoad, mayStore

let Defs = [SR], isCompare = 1 in
def CP8mr : MemALUInst<0xF8, 3, (outs), (ins MEMri:$addr, GR8:$rs),
                        "cp", "$addr, $rs", []>,
            Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

// OP r8, (mem) — ALU with register destination, memory source.
let Defs = [SR], mayLoad = 1 in {
def ADD8rm : MemLoadInst<0x80, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                          "add", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def SUB8rm : MemLoadInst<0xA0, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                          "sub", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def AND8rm : MemLoadInst<0xC0, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                          "and", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def OR8rm : MemLoadInst<0xE0, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                         "or", "$rs, $addr", []>,
            Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def XOR8rm : MemLoadInst<0xD0, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                          "xor", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
} // Defs, mayLoad

let Defs = [SR], Uses = [SR], mayLoad = 1 in {
def ADC8rm : MemLoadInst<0x90, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                          "adc", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
def SBC8rm : MemLoadInst<0xB0, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                          "sbc", "$rs, $addr", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;
} // Defs, Uses, mayLoad

let Defs = [SR], isCompare = 1 in
def CP8rm : MemLoadInst<0xF0, 3, (outs), (ins GR8:$rs, MEMri:$addr),
                         "cp", "$rs, $addr", []>,
            Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

} // OpSize = OpSize8.Value

//===----------------------------------------------------------------------===//
// Direct Addressing Instructions (16-bit and 24-bit absolute addresses)
//===----------------------------------------------------------------------===//
// These instructions use C1/D1/E1 (source, 16-bit addr), C2/D2/E2 (source,
// 24-bit addr), F1 (dest, 16-bit addr), or F2 (dest, 24-bit addr) prefixes
// followed by the address and a sub-opcode from the same table as register-
// indirect operations.
//
// Mnemonic convention: operation + "da" suffix (direct address).
//   Example: ldda8 = LD byte via direct address, cpda16 = CP word via direct addr

//--- Source direct: LD reg, (addr) — sub-opcode 0x20+reg ---

let mayLoad = 1, hasSideEffects = 0 in {

// 8-bit loads from 16-bit address: C1 + addr16 + (0x20+reg)
let OpSize = OpSize8.Value in
def LD8_da16 : DirectSrcRegInst<0x20, 4, (outs GPR:$dst),
                                 (ins i32imm:$addr),
                                 "ldda8", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

// 16-bit loads from 16-bit address: D1 + addr16 + (0x20+reg)
let OpSize = OpSize16.Value in
def LD16_da16 : DirectSrcRegInst<0x20, 4, (outs GPR:$dst),
                                  (ins i32imm:$addr),
                                  "ldda16", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

// 32-bit loads from 16-bit address: E1 + addr16 + (0x20+reg)
let OpSize = OpSize32.Value in
def LD32_da16 : DirectSrcRegInst<0x20, 4, (outs GPR:$dst),
                                  (ins i32imm:$addr),
                                  "ldda32", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

// 8-bit loads from 24-bit address: C2 + addr24 + (0x20+reg)
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8_da24 : DirectSrcRegInst<0x20, 5, (outs GPR:$dst),
                                 (ins i32imm:$addr),
                                 "ld8_24", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

// 16-bit loads from 24-bit address: D2 + addr24 + (0x20+reg)
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16_da24 : DirectSrcRegInst<0x20, 5, (outs GPR:$dst),
                                  (ins i32imm:$addr),
                                  "ld16_24", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

// 32-bit loads from 24-bit address: E2 + addr24 + (0x20+reg)
let OpSize = OpSize32.Value, AddrWidth = 1 in
def LD32_da24 : DirectSrcRegInst<0x20, 5, (outs GPR:$dst),
                                  (ins i32imm:$addr),
                                  "ld32_24", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

} // mayLoad, hasSideEffects

// GR8 variants for 8-bit LD reg8, (addr) — allows W, B, D, H (high-byte registers)
let mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def LD8_da16_r8 : DirectSrcRegInst<0x20, 4, (outs GR8:$dst),
                                     (ins i32imm:$addr),
                                     "ldda8", "$dst, $addr", []>,
                  Sched<[WriteLDW]>;
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8_da24_r8 : DirectSrcRegInst<0x20, 5, (outs GR8:$dst),
                                     (ins i32imm:$addr),
                                     "ld8_24", "$dst, $addr", []>,
                  Sched<[WriteLDW]>;
} // mayLoad, hasSideEffects

// GR8 variants for 8-bit ALU reg8, (addr16) — load direction
let Defs = [SR], mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
let Constraints = "$dst = $src1" in {
def ADD8_da16_r8 : DirectSrcRegInst<0x80, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, i32imm:$addr),
                                      "addda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def SUB8_da16_r8 : DirectSrcRegInst<0xA0, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, i32imm:$addr),
                                      "subda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def AND8_da16_r8 : DirectSrcRegInst<0xC0, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, i32imm:$addr),
                                      "andda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def XOR8_da16_r8 : DirectSrcRegInst<0xD0, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, i32imm:$addr),
                                      "xorda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def OR8_da16_r8 : DirectSrcRegInst<0xE0, 4, (outs GR8:$dst),
                                     (ins GR8:$src1, i32imm:$addr),
                                     "orda8", "$dst, $addr", []>,
                  Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP8_da16_r8 : DirectSrcRegInst<0xF0, 4, (outs),
                                     (ins GR8:$src, i32imm:$addr),
                                     "cpda8", "$src, $addr", []>,
                  Sched<[WriteIALU, ReadIALU]>;
} // OpSize8
} // Defs, mayLoad, hasSideEffects

// GR8 variants for 8-bit ALU (addr16), reg8 — store direction
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def ADD8m_da16_r8 : DirectSrcRegInst<0x88, 4, (outs),
                                       (ins i32imm:$addr, GR8:$src),
                                       "adddm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
def SUB8m_da16_r8 : DirectSrcRegInst<0xA8, 4, (outs),
                                       (ins i32imm:$addr, GR8:$src),
                                       "subdm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
def AND8m_da16_r8 : DirectSrcRegInst<0xC8, 4, (outs),
                                       (ins i32imm:$addr, GR8:$src),
                                       "anddm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
def OR8m_da16_r8 : DirectSrcRegInst<0xE8, 4, (outs),
                                      (ins i32imm:$addr, GR8:$src),
                                      "orddm8", "$addr, $src", []>,
                   Sched<[WriteSTW, ReadIALU]>;
def XOR8m_da16_r8 : DirectSrcRegInst<0xD8, 4, (outs),
                                       (ins i32imm:$addr, GR8:$src),
                                       "xordm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
} // OpSize8
} // Defs, mayLoad, mayStore, hasSideEffects

// GR8 variants for 8-bit CP (addr16), reg8 — store direction compare
let Defs = [SR], mayLoad = 1, isCompare = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def CP8m_da16_r8 : DirectSrcRegInst<0xF8, 4, (outs),
                                      (ins i32imm:$addr, GR8:$src),
                                      "cpdm8", "$addr, $src", []>,
                   Sched<[WriteIALU, ReadIALU]>;
} // Defs, mayLoad, isCompare, hasSideEffects

//--- Source direct: ALU reg, (addr) — sub-opcode = ALU_base + reg ---
// ADD=0x80, ADC=0x90, SUB=0xA0, SBC=0xB0, AND=0xC0, XOR=0xD0, OR=0xE0, CP=0xF0

// 8-bit ALU reg, (addr16) — result to register
let Defs = [SR], mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
let Constraints = "$dst = $src1" in {
def ADD8_da16 : DirectSrcRegInst<0x80, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, i32imm:$addr),
                                  "addda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def SUB8_da16 : DirectSrcRegInst<0xA0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, i32imm:$addr),
                                  "subda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def AND8_da16 : DirectSrcRegInst<0xC0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, i32imm:$addr),
                                  "andda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def XOR8_da16 : DirectSrcRegInst<0xD0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, i32imm:$addr),
                                  "xorda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def OR8_da16 : DirectSrcRegInst<0xE0, 4, (outs GPR:$dst),
                                 (ins GPR:$src1, i32imm:$addr),
                                 "orda8", "$dst, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP8_da16 : DirectSrcRegInst<0xF0, 4, (outs),
                                 (ins GPR:$src, i32imm:$addr),
                                 "cpda8", "$src, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
} // OpSize8
let OpSize = OpSize16.Value in {
let Constraints = "$dst = $src1" in {
def ADD16_da16 : DirectSrcRegInst<0x80, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "addda16", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB16_da16 : DirectSrcRegInst<0xA0, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "subda16", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def AND16_da16 : DirectSrcRegInst<0xC0, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "andda16", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def OR16_da16 : DirectSrcRegInst<0xE0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, i32imm:$addr),
                                  "orda16", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP16_da16 : DirectSrcRegInst<0xF0, 4, (outs),
                                  (ins GPR:$src, i32imm:$addr),
                                  "cpda16", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // OpSize16
} // Defs, mayLoad, hasSideEffects

// ALU (addr16), reg — result to memory (store direction, sub-opc base + 8)
// ADD=0x88, ADC=0x98, SUB=0xA8, SBC=0xB8, AND=0xC8, XOR=0xD8, OR=0xE8, CP=0xF8
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def ADD8m_da16 : DirectSrcRegInst<0x88, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "adddm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def SUB8m_da16 : DirectSrcRegInst<0xA8, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "subdm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def AND8m_da16 : DirectSrcRegInst<0xC8, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "anddm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def OR8m_da16 : DirectSrcRegInst<0xE8, 4, (outs),
                                  (ins i32imm:$addr, GPR:$src),
                                  "orddm8", "$addr, $src", []>,
                Sched<[WriteSTW, ReadIALU]>;
def XOR8m_da16 : DirectSrcRegInst<0xD8, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "xordm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def ADD16m_da16 : DirectSrcRegInst<0x88, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "adddm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def SUB16m_da16 : DirectSrcRegInst<0xA8, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "subdm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def AND16m_da16 : DirectSrcRegInst<0xC8, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "anddm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def OR16m_da16 : DirectSrcRegInst<0xE8, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "orddm16", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def XOR16m_da16 : DirectSrcRegInst<0xD8, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "xordm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
} // OpSize16
let OpSize = OpSize32.Value in {
def ADD32m_da16 : DirectSrcRegInst<0x88, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "adddm32", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def SUB32m_da16 : DirectSrcRegInst<0xA8, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "subdm32", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
} // OpSize32
} // Defs, mayLoad, mayStore, hasSideEffects

// CP (addr16), reg — store direction compare (no write, just flags)
let Defs = [SR], mayLoad = 1, isCompare = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def CP8m_da16 : DirectSrcRegInst<0xF8, 4, (outs),
                                  (ins i32imm:$addr, GPR:$src),
                                  "cpdm8", "$addr, $src", []>,
                Sched<[WriteIALU, ReadIALU]>;
let OpSize = OpSize16.Value in
def CP16m_da16 : DirectSrcRegInst<0xF8, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "cpdm16", "$addr, $src", []>,
                 Sched<[WriteIALU, ReadIALU]>;
let OpSize = OpSize32.Value in
def CP32m_da16 : DirectSrcRegInst<0xF8, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "cpdm32", "$addr, $src", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Defs, mayLoad, isCompare, hasSideEffects

// 32-bit ALU reg, (addr16) — load direction
let Defs = [SR], mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize32.Value in {
let Constraints = "$dst = $src1" in {
def ADD32_da16 : DirectSrcRegInst<0x80, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "addda32", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB32_da16 : DirectSrcRegInst<0xA0, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "subda32", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP32_da16 : DirectSrcRegInst<0xF0, 4, (outs),
                                  (ins GPR:$src, i32imm:$addr),
                                  "cpda32", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // OpSize32
} // Defs, mayLoad, hasSideEffects

//--- Source direct: ALU (addr), #imm — sub-opcode = 0x38 + alu_idx ---
// ADD=0x38, ADC=0x39, SUB=0x3A, SBC=0x3B, AND=0x3C, XOR=0x3D, OR=0x3E, CP=0x3F

let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {

// 8-bit ALU (addr16), #imm8
let OpSize = OpSize8.Value in {
def ADD8i_da16 : DirectSrcImmInst<0x38, 5, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "adddi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def SUB8i_da16 : DirectSrcImmInst<0x3A, 5, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "subdi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def AND8i_da16 : DirectSrcImmInst<0x3C, 5, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "anddi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def XOR8i_da16 : DirectSrcImmInst<0x3D, 5, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "xordi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def OR8i_da16 : DirectSrcImmInst<0x3E, 5, (outs),
                                  (ins i32imm:$addr, i8imm:$val),
                                  "ordi8", "$addr, $val", []>,
                Sched<[WriteSTW]>;
} // OpSize8

let isCompare = 1, mayStore = 0 in {
let OpSize = OpSize8.Value in
def CP8i_da16 : DirectSrcImmInst<0x3F, 5, (outs),
                                  (ins i32imm:$addr, i8imm:$val),
                                  "cpdi8", "$addr, $val", []>,
                Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def CP16i_da16 : DirectSrcImmInst<0x3F, 6, (outs),
                                   (ins i32imm:$addr, i16imm:$val),
                                   "cpdi16", "$addr, $val", []>,
                 Sched<[WriteIALU]>;
} // isCompare, mayStore

// 16-bit ALU (addr16), #imm16
let OpSize = OpSize16.Value in {
def ADD16i_da16 : DirectSrcImmInst<0x38, 6, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "adddi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def SUB16i_da16 : DirectSrcImmInst<0x3A, 6, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "subdi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def AND16i_da16 : DirectSrcImmInst<0x3C, 6, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "anddi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def OR16i_da16 : DirectSrcImmInst<0x3E, 6, (outs),
                                   (ins i32imm:$addr, i16imm:$val),
                                   "ordi16", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
} // OpSize16

// 24-bit address ALU (addr24), #imm — C2/D2 prefix
let isCompare = 1, mayStore = 0 in {
let OpSize = OpSize16.Value, AddrWidth = 1 in
def CP16i_da24 : DirectSrcImmInst<0x3F, 7, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "cpdi16_24", "$addr, $val", []>,
                 Sched<[WriteIALU]>;
} // isCompare, mayStore
let OpSize = OpSize16.Value, AddrWidth = 1 in {
def ADD16i_da24 : DirectSrcImmInst<0x38, 7, (outs),
                                     (ins i32imm:$addr, i16imm:$val),
                                     "adddi16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def SUB16i_da24 : DirectSrcImmInst<0x3A, 7, (outs),
                                     (ins i32imm:$addr, i16imm:$val),
                                     "subdi16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
} // OpSize16, AddrWidth

// 24-bit address ALU reg, (addr24) — load direction
let OpSize = OpSize16.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def ADD16_da24 : DirectSrcRegInst<0x80, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "addda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB16_da24 : DirectSrcRegInst<0xA0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "subda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP16_da24 : DirectSrcRegInst<0xF0, 5, (outs),
                                   (ins GPR:$src, i32imm:$addr),
                                   "cpda16_24", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
// 16-bit additional load-direction
let Constraints = "$dst = $src1" in {
def AND16_da24 : DirectSrcRegInst<0xC0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "andda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def XOR16_da24 : DirectSrcRegInst<0xD0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "xorda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def OR16_da24 : DirectSrcRegInst<0xE0, 5, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "orda16_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // Constraints
// 16-bit store-direction: ALU (addr24), reg
let Constraints = "" in {
def ADD16m_da24 : DirectSrcRegInst<0x88, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "adddm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def SUB16m_da24 : DirectSrcRegInst<0xA8, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "subdm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def AND16m_da24 : DirectSrcRegInst<0xC8, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "anddm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def XOR16m_da24 : DirectSrcRegInst<0xD8, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "xordm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def OR16m_da24 : DirectSrcRegInst<0xE8, 5, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "ordm16_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def CP16m_da24 : DirectSrcRegInst<0xF8, 5, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "cpdm16_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
} // Constraints
// 16-bit additional imm
def AND16i_da24 : DirectSrcImmInst<0x3C, 7, (outs),
                                     (ins i32imm:$addr, i16imm:$val),
                                     "anddi16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def OR16i_da24 : DirectSrcImmInst<0x3E, 7, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "ordi16_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
} // OpSize16, AddrWidth

// 24-bit address: 32-bit store and additional load operations
let OpSize = OpSize32.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def AND32_da24 : DirectSrcRegInst<0xC0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "andda32_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def OR32_da24 : DirectSrcRegInst<0xE0, 5, (outs GPR:$dst),
                                   (ins GPR:$src1, i32imm:$addr),
                                   "orda32_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // Constraints
// 32-bit store-direction
let Constraints = "" in {
def ADD32m_da24 : DirectSrcRegInst<0x88, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "addm32_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def SUB32m_da24 : DirectSrcRegInst<0xA8, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "subdm32_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def AND32m_da24 : DirectSrcRegInst<0xC8, 5, (outs),
                                     (ins i32imm:$addr, GPR:$src),
                                     "anddm32_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def OR32m_da24 : DirectSrcRegInst<0xE8, 5, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "ordm32_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def CP32m_da24 : DirectSrcRegInst<0xF8, 5, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "cpdm32_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
} // Constraints
} // OpSize32, AddrWidth

// 24-bit address: ALL ALU (addr24), #imm for C2 (8-bit)
let OpSize = OpSize8.Value, AddrWidth = 1 in {
def ADD8i_da24 : DirectSrcImmInst<0x38, 6, (outs),
                                    (ins i32imm:$addr, i8imm:$val),
                                    "adddi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def ADC8i_da24 : DirectSrcImmInst<0x39, 6, (outs),
                                    (ins i32imm:$addr, i8imm:$val),
                                    "addci8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def SUB8i_da24 : DirectSrcImmInst<0x3A, 6, (outs),
                                    (ins i32imm:$addr, i8imm:$val),
                                    "subdi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def SBC8i_da24 : DirectSrcImmInst<0x3B, 6, (outs),
                                    (ins i32imm:$addr, i8imm:$val),
                                    "sbcdi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def AND8i_da24 : DirectSrcImmInst<0x3C, 6, (outs),
                                    (ins i32imm:$addr, i8imm:$val),
                                    "anddi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def XOR8i_da24 : DirectSrcImmInst<0x3D, 6, (outs),
                                    (ins i32imm:$addr, i8imm:$val),
                                    "xordi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def OR8i_da24 : DirectSrcImmInst<0x3E, 6, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "ordi8_24", "$addr, $val", []>,
                Sched<[WriteSTW]>;
} // OpSize8, AddrWidth
let isCompare = 1, mayStore = 0, OpSize = OpSize8.Value, AddrWidth = 1 in
def CP8i_da24 : DirectSrcImmInst<0x3F, 6, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "cpi8_24", "$addr, $val", []>,
                Sched<[WriteIALU]>;

// 24-bit address: ALU reg, (addr24) — load direction for C2 (8-bit)
let OpSize = OpSize8.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def ADD8_da24 : DirectSrcRegInst<0x80, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, i32imm:$addr),
                                   "addda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def ADC8_da24 : DirectSrcRegInst<0x90, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, i32imm:$addr),
                                   "addcda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def SUB8_da24 : DirectSrcRegInst<0xA0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, i32imm:$addr),
                                   "subda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def SBC8_da24 : DirectSrcRegInst<0xB0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, i32imm:$addr),
                                   "sbcda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def AND8_da24 : DirectSrcRegInst<0xC0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, i32imm:$addr),
                                   "andda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def XOR8_da24 : DirectSrcRegInst<0xD0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, i32imm:$addr),
                                   "xorda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def OR8_da24 : DirectSrcRegInst<0xE0, 5, (outs GR8:$dst),
                                  (ins GR8:$src1, i32imm:$addr),
                                  "orda8_24", "$dst, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP8_da24 : DirectSrcRegInst<0xF0, 5, (outs),
                                  (ins GR8:$src, i32imm:$addr),
                                  "cpda8_24", "$src, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
// Store direction (result to memory): ALU (addr24), reg
let Constraints = "" in {
def ADD8m_da24 : DirectSrcRegInst<0x88, 5, (outs),
                                    (ins i32imm:$addr, GR8:$src),
                                    "adddm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def SUB8m_da24 : DirectSrcRegInst<0xA8, 5, (outs),
                                    (ins i32imm:$addr, GR8:$src),
                                    "subdm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def AND8m_da24 : DirectSrcRegInst<0xC8, 5, (outs),
                                    (ins i32imm:$addr, GR8:$src),
                                    "anddm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def XOR8m_da24 : DirectSrcRegInst<0xD8, 5, (outs),
                                    (ins i32imm:$addr, GR8:$src),
                                    "xordm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def OR8m_da24 : DirectSrcRegInst<0xE8, 5, (outs),
                                   (ins i32imm:$addr, GR8:$src),
                                   "ordm8_24", "$addr, $src", []>,
                Sched<[WriteSTW]>;
def CP8m_da24 : DirectSrcRegInst<0xF8, 5, (outs),
                                   (ins i32imm:$addr, GR8:$src),
                                   "cpdm8_24", "$addr, $src", []>,
                Sched<[WriteSTW]>;
} // Constraints
} // OpSize8, AddrWidth

// 24-bit address: ALU reg, (addr24) — load direction for E2 (32-bit)
let OpSize = OpSize32.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def ADD32_da24 : DirectSrcRegInst<0x80, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "addda32_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB32_da24 : DirectSrcRegInst<0xA0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, i32imm:$addr),
                                    "sub32_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP32_da24 : DirectSrcRegInst<0xF0, 5, (outs),
                                   (ins GPR:$src, i32imm:$addr),
                                   "cpda32_24", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // OpSize32, AddrWidth

// 24-bit address: INC/DEC via C2/D2 prefix
let AddrWidth = 1 in {
let OpSize = OpSize8.Value in {
def INC8_da24 : DirectSrcIncDecInst<0x60, 5, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "incdi8_24", "$count, $addr", []>,
                Sched<[WriteSTW]>;
def DEC8_da24 : DirectSrcIncDecInst<0x68, 5, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "decdi8_24", "$count, $addr", []>,
                Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_da24 : DirectSrcIncDecInst<0x60, 5, (outs),
                                       (ins i32imm:$addr, i32imm:$count),
                                       "incdi16_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC16_da24 : DirectSrcIncDecInst<0x68, 5, (outs),
                                       (ins i32imm:$addr, i32imm:$count),
                                       "decdi16_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize16
} // AddrWidth

} // Defs, mayLoad, mayStore, hasSideEffects

// 24-bit address BIT/SET/RES/CHG/TSET via F2 prefix
let mayLoad = 1, hasSideEffects = 0 in {
let AddrWidth = 1 in
def BIT_da24 : DirectDstBitOpInst<0xC8, 5, (outs),
                                    (ins i32imm:$addr, i32imm:$bit),
                                    "bitda_24", "$bit, $addr", []>,
               Sched<[WriteIALU]>;
} // mayLoad, hasSideEffects

let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let AddrWidth = 1 in {
def SET_da24 : DirectDstBitOpInst<0xB8, 5, (outs),
                                    (ins i32imm:$addr, i32imm:$bit),
                                    "setda_24", "$bit, $addr", []>,
               Sched<[WriteSTW]>;
def RES_da24 : DirectDstBitOpInst<0xB0, 5, (outs),
                                    (ins i32imm:$addr, i32imm:$bit),
                                    "resda_24", "$bit, $addr", []>,
               Sched<[WriteSTW]>;
def CHG_da24 : DirectDstBitOpInst<0xC0, 5, (outs),
                                    (ins i32imm:$addr, i32imm:$bit),
                                    "chgda_24", "$bit, $addr", []>,
               Sched<[WriteSTW]>;
def TSET_da24 : DirectDstBitOpInst<0xA0, 5, (outs),
                                     (ins i32imm:$addr, i32imm:$bit),
                                     "tsetda_24", "$bit, $addr", []>,
                Sched<[WriteSTW]>;
} // AddrWidth
} // mayLoad, mayStore, hasSideEffects

// 24-bit address: INC/DEC/INCW/DECW via F2 prefix
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let AddrWidth = 1 in {
let OpSize = OpSize8.Value in {
def INC8_dda24 : DirectDstBitOpInst<0x60, 5, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "incdd8_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC8_dda24 : DirectDstBitOpInst<0x68, 5, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "decdd8_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_dda24 : DirectDstBitOpInst<0x60, 5, (outs),
                                       (ins i32imm:$addr, i32imm:$count),
                                       "incdd16_24", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
def DEC16_dda24 : DirectDstBitOpInst<0x68, 5, (outs),
                                       (ins i32imm:$addr, i32imm:$count),
                                       "decdd16_24", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
} // OpSize16
} // AddrWidth
} // Defs, mayLoad, mayStore, hasSideEffects

// F2 conditional CALL: F2 + addr24 + (0xE0+cc) — 5 bytes
let isCall = 1, Defs = [XSP], Uses = [XSP], hasSideEffects = 0, AddrWidth = 1 in
def CALLCC_24 : DirectDstBitOpInst<0xE0, 5, (outs),
                                     (ins i32imm:$addr, cc:$cc),
                                     "call_24", "$cc, $addr", []>,
                Sched<[WriteJmp]>;

// F2 conditional JP: F2 + addr24 + (0xD0+cc) — 5 bytes
let isBranch = 1, isTerminator = 1, hasSideEffects = 0, AddrWidth = 1 in
def JPCC_24 : DirectDstBitOpInst<0xD0, 5, (outs),
                                    (ins i32imm:$addr, cc:$cc),
                                    "jp_24", "$cc, $addr", []>,
              Sched<[WriteJmp]>;

//--- Source direct: INC/DEC (addr) — sub-opcode 0x60+count / 0x68+count ---

let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def INC8_da16 : DirectSrcIncDecInst<0x60, 4, (outs),
                                     (ins i32imm:$addr, i32imm:$count),
                                     "incdi8", "$count, $addr", []>,
                Sched<[WriteSTW]>;
def DEC8_da16 : DirectSrcIncDecInst<0x68, 4, (outs),
                                     (ins i32imm:$addr, i32imm:$count),
                                     "decdi8", "$count, $addr", []>,
                Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_da16 : DirectSrcIncDecInst<0x60, 4, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "incdi16", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC16_da16 : DirectSrcIncDecInst<0x68, 4, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "decdi16", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize16
} // Defs, mayLoad, mayStore, hasSideEffects

//--- Destination direct: LD (addr), reg — sub-opcode 0x40+reg8 / 0x50+reg16 ---

let mayStore = 1, hasSideEffects = 0 in {

// 8-bit stores to 16-bit address: F1 + addr16 + (0x40+reg8)
let OpSize = OpSize8.Value in
def LD8m_da16 : DirectDstRegInst<0x40, 4, (outs),
                                  (ins i32imm:$addr, GPR:$src),
                                  "stda8", "$addr, $src", []>,
                Sched<[WriteSTW]>;

// 16-bit stores to 16-bit address: F1 + addr16 + (0x50+reg16)
let OpSize = OpSize16.Value in
def LD16m_da16 : DirectDstRegInst<0x50, 4, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "stda16", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

// 8-bit stores to 24-bit address: F2 + addr24 + (0x40+reg8)
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8m_da24 : DirectDstRegInst<0x40, 5, (outs),
                                  (ins i32imm:$addr, GPR:$src),
                                  "st8_24", "$addr, $src", []>,
                Sched<[WriteSTW]>;

// 16-bit stores to 24-bit address: F2 + addr24 + (0x50+reg16)
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16m_da24 : DirectDstRegInst<0x50, 5, (outs),
                                   (ins i32imm:$addr, GPR:$src),
                                   "st16_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

} // mayStore, hasSideEffects

// 32-bit stores to 16-bit address: F1 + addr16 + (0x60+reg32)
let OpSize = OpSize32.Value in
def LD32m_da16 : DirectDstRegInst<0x60, 4, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "stda32", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

// 32-bit stores to 24-bit address: F2 + addr24 + (0x60+reg32)
let OpSize = OpSize32.Value, AddrWidth = 1 in
def LD32m_da24 : DirectDstRegInst<0x60, 5, (outs),
                                    (ins i32imm:$addr, GPR:$src),
                                    "st32_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

// GR8 variants for 8-bit stores LD (addr), reg8 — allows W, B, D, H
let mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def LD8m_da16_r8 : DirectDstRegInst<0x40, 4, (outs),
                                      (ins i32imm:$addr, GR8:$src),
                                      "stda8", "$addr, $src", []>,
                   Sched<[WriteSTW]>;
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8m_da24_r8 : DirectDstRegInst<0x40, 5, (outs),
                                      (ins i32imm:$addr, GR8:$src),
                                      "st8_24", "$addr, $src", []>,
                   Sched<[WriteSTW]>;
} // mayStore, hasSideEffects

//--- Destination direct: LD (addr), #imm — sub-opcode 0x00 (byte) / 0x02 (word) ---

let mayStore = 1, hasSideEffects = 0 in {

// 8-bit store imm to 16-bit address: F1 + addr16 + 0x00 + imm8
let OpSize = OpSize8.Value in
def LD8mi_da16 : DirectDstImmInst<0x00, 5, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "stdi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;

// 16-bit store imm to 16-bit address: F1 + addr16 + 0x02 + imm16
let OpSize = OpSize16.Value in
def LD16mi_da16 : DirectDstImmInst<0x02, 6, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "stdi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;

// 8-bit store imm to 24-bit address: F2 + addr24 + 0x00 + imm8
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8mi_da24 : DirectDstImmInst<0x00, 6, (outs),
                                   (ins i32imm:$addr, i8imm:$val),
                                   "sti8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;

// 16-bit store imm to 24-bit address: F2 + addr24 + 0x02 + imm16
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16mi_da24 : DirectDstImmInst<0x02, 7, (outs),
                                    (ins i32imm:$addr, i16imm:$val),
                                    "sti16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;

} // mayStore, hasSideEffects

//--- Destination direct: LDA reg, addr — sub-opcode 0x30+reg32 ---

let mayLoad = 0, mayStore = 0, hasSideEffects = 0 in {

// LDA to 16-bit address: F1 + addr16 + (0x30+reg32)
let OpSize = OpSize32.Value in
def LDA_da16 : DirectDstRegInst<0x30, 4, (outs GPR:$dst),
                                 (ins i32imm:$addr),
                                 "ldada", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

// LDA to 24-bit address: F2 + addr24 + (0x30+reg32)
let OpSize = OpSize32.Value, AddrWidth = 1 in
def LDA_da24 : DirectDstRegInst<0x30, 5, (outs GPR:$dst),
                                 (ins i32imm:$addr),
                                 "lda_24", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

} // mayLoad, mayStore, hasSideEffects

//--- Destination direct: BIT/SET/RES (addr) — sub-opcode base + bit ---
// BIT: 0xC8+bit, SET: 0xB8+bit, RES: 0xB0+bit

let mayLoad = 1, hasSideEffects = 0 in {

// BIT from 16-bit address: F1 + addr16 + (0xC8+bit)
def BIT_da16 : DirectDstBitOpInst<0xC8, 4, (outs),
                                   (ins i32imm:$addr, i32imm:$bit),
                                   "bitda", "$bit, $addr", []>,
               Sched<[WriteIALU]>;

} // mayLoad, hasSideEffects

let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {

// SET from 16-bit address: F1 + addr16 + (0xB8+bit)
def SET_da16 : DirectDstBitOpInst<0xB8, 4, (outs),
                                   (ins i32imm:$addr, i32imm:$bit),
                                   "setda", "$bit, $addr", []>,
               Sched<[WriteSTW]>;

// RES from 16-bit address: F1 + addr16 + (0xB0+bit)
def RES_da16 : DirectDstBitOpInst<0xB0, 4, (outs),
                                   (ins i32imm:$addr, i32imm:$bit),
                                   "resda", "$bit, $addr", []>,
               Sched<[WriteSTW]>;

// TSET from 16-bit address: F1 + addr16 + (0xA0+bit)
def TSET_da16 : DirectDstBitOpInst<0xA0, 4, (outs),
                                    (ins i32imm:$addr, i32imm:$bit),
                                    "tsetda", "$bit, $addr", []>,
                Sched<[WriteSTW]>;

} // mayLoad, mayStore, hasSideEffects

//--- Destination direct: INC/DEC (addr) via F1 prefix ---
// INC: 0x60+count, DEC: 0x68+count (same sub-opcode as source, but via F1 prefix)

let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def INC8_dda16 : DirectDstBitOpInst<0x60, 4, (outs),
                                     (ins i32imm:$addr, i32imm:$count),
                                     "incdd8", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC8_dda16 : DirectDstBitOpInst<0x68, 4, (outs),
                                     (ins i32imm:$addr, i32imm:$count),
                                     "decdd8", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_dda16 : DirectDstBitOpInst<0x60, 4, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "incdd16", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
def DEC16_dda16 : DirectDstBitOpInst<0x68, 4, (outs),
                                      (ins i32imm:$addr, i32imm:$count),
                                      "decdd16", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
} // OpSize16
} // Defs, mayLoad, mayStore, hasSideEffects

//--- Source direct: LD (dst_addr), (src_addr) — sub-opcode 0x19 ---
// Memory-to-memory transfer via direct addressing.
// Encoding: prefix + src_addr16 + 0x19 + dst_addr16 (6 bytes)

let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
// 8-bit mem-to-mem: C1 + src_addr + 0x19 + dst_addr
let OpSize = OpSize8.Value in
def LDmm8_da16 : DirectMemToMemInst<0x19, 6, (outs),
                                      (ins i32imm:$src_addr, i32imm:$dst_addr),
                                      "ldmm8", "$dst_addr, $src_addr", []>,
                 Sched<[WriteSTW]>;
// 16-bit mem-to-mem: D1 + src_addr + 0x19 + dst_addr
let OpSize = OpSize16.Value in
def LDmm16_da16 : DirectMemToMemInst<0x19, 6, (outs),
                                       (ins i32imm:$src_addr, i32imm:$dst_addr),
                                       "ldmm16", "$dst_addr, $src_addr", []>,
                  Sched<[WriteSTW]>;
} // mayLoad, mayStore, hasSideEffects (DirectMemToMem)

//===----------------------------------------------------------------------===//
// Extended addressing mode instructions — computed prefix + literal bytes
//
// These provide semantic category names for addressing modes that were
// previously all lumped into the generic extpfx fallback. The MCCodeEmitter
// computes the prefix byte from Opcode + OpSize, then emits operand bytes
// literally. The operand count in the mnemonic = bytes AFTER the prefix.
//
// Source categories (prefix = base + OpSize * 0x10):
//   sd8 (C0/D0/E0): 8-bit direct address — (nn) where nn is 8-bit
//   sri (C3/D3/E3): register-indirect complex — (R32), (R32+d16), (R32+R8)
//   spi (C5/D5/E5): post-increment — (R32+)
//   erp (C7/D7/E7): extended register prefix — full register bank access
//
// Destination categories (prefix = base, no size adjustment):
//   dd8 (F0): 8-bit destination direct — (nn) where nn is 8-bit
//   dri (F3): destination register-indirect complex
//   dpi (F5): destination post-increment
//===----------------------------------------------------------------------===//

let hasSideEffects = 1, mayLoad = 1, mayStore = 1 in {

// --- Extended Register Prefix (C7/D7/E7) ---
// Format: C7/D7/E7 + reg_byte + sub_opcode [+ operand_bytes]
// Accesses any register in the full 256-entry register file.

let Opcode = 0xC7 in {
// 8-bit (C7) extended register prefix

// 16-bit (D7) extended register prefix

// 32-bit (E7) extended register prefix
} // Opcode = 0xC7

// --- Additional Register Prefix Instructions (C8-EF) ---
// Instructions that use standard register prefix encoding but weren't covered
// by the core instruction set definitions above.

// UNLK r32 — Stack frame teardown (2 bytes: E8+reg, 0x0D)
let hasSideEffects = 1, OpSize = OpSize32.Value in
def UNLK32 : PrefixUnaryInst<0x0D, (outs), (ins GPR:$rs1),
    "unlk32", "$rs1", []>, Sched<[WriteSTW]>;

// LINK r32, d16 — Stack frame setup (4 bytes: E8+reg, 0x0C, d16)
// Uses ExtPrefix because OpSize=32 would give ImmBytes=4 but LINK uses 16-bit.
def LINK32 : ExtPrefixInst<4, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "link32", "$b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;

// XORCF A,r — XOR carry flag with A bit of register (2 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def XORCF_A_8 : PrefixUnaryInst<0x2A, (outs), (ins GR8:$rs1),
    "xorcf_a_8", "$rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def XORCF_A_16 : PrefixUnaryInst<0x2A, (outs), (ins GR16:$rs1),
    "xorcf_a_16", "$rs1", []>, Sched<[WriteIALU]>;
}

// STCF A,r — Store carry flag to bit A of register (2 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def STCF_A_8 : PrefixUnaryInst<0x2C, (outs), (ins GR8:$rs1),
    "stcf_a_8", "$rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def STCF_A_16 : PrefixUnaryInst<0x2C, (outs), (ins GR16:$rs1),
    "stcf_a_16", "$rs1", []>, Sched<[WriteIALU]>;
}

// MUL/MULS/DIV/DIVS register-register 8-bit (2 bytes: C8+src, opc+dst)
let Defs = [SR], hasSideEffects = 0, OpSize = OpSize8.Value in {
def MUL8rr : PrefixRegRegInst<0x40, (outs), (ins GR8:$rs1, GR8:$rs2),
    "mul8rr", "$rs1, $rs2", []>, Sched<[WriteIMul]>;
def MULS8rr : PrefixRegRegInst<0x48, (outs), (ins GR8:$rs1, GR8:$rs2),
    "muls8rr", "$rs1, $rs2", []>, Sched<[WriteIMul]>;
def DIV8rr : PrefixRegRegInst<0x50, (outs), (ins GR8:$rs1, GR8:$rs2),
    "div8rr", "$rs1, $rs2", []>, Sched<[WriteIMul]>;
def DIVS8rr : PrefixRegRegInst<0x58, (outs), (ins GR8:$rs1, GR8:$rs2),
    "divs8rr", "$rs1, $rs2", []>, Sched<[WriteIMul]>;
}

// EX r,r — Exchange registers (2 bytes: prefix+src, 0xB8+dst)
// Separate from EX32 which uses 4-operand tied form for codegen.
let hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def EX8 : PrefixRegRegInst<0xB8, (outs), (ins GR8:$rs1, GR8:$rs2),
    "ex8", "$rs1, $rs2", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def EX16 : PrefixRegRegInst<0xB8, (outs), (ins GR16:$rs1, GR16:$rs2),
    "ex16", "$rs1, $rs2", []>, Sched<[WriteIALU]>;
}

// MINC1/MINC4 — Modular increment (4 bytes: D8+reg, 0x38/0x3A, imm16)
let Defs = [SR], hasSideEffects = 0, OpSize = OpSize16.Value in {
def MINC1_16 : PrefixRegImmInst<0x38, 4, (outs GR16:$rd),
    (ins GR16:$src1, i16imm:$imm), "minc1_16", "$rd, $imm", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
def MINC4_16 : PrefixRegImmInst<0x3A, 4, (outs GR16:$rd),
    (ins GR16:$src1, i16imm:$imm), "minc4_16", "$rd, $imm", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
}

// LDC — Load control register (3 bytes: prefix+reg, 0x2E/0x2F, cr_num)
// Uses PrefixShift format (prefix + opcode + 1-byte operand).
let hasSideEffects = 1 in {
let OpSize = OpSize8.Value in {
def LDC_CR8 : PrefixShiftInst<0x2E, (outs), (ins GR8:$rs1, i32imm:$cr),
    "ldc_cr8", "$rs1, $cr", []>, Sched<[WriteSTW]>;
def LDC_8_CR : PrefixShiftInst<0x2F, (outs), (ins GR8:$rs1, i32imm:$cr),
    "ldc_8_cr", "$rs1, $cr", []>, Sched<[WriteSTW]>;
}
let OpSize = OpSize16.Value in {
def LDC_CR16 : PrefixShiftInst<0x2E, (outs), (ins GR16:$rs1, i32imm:$cr),
    "ldc_cr16", "$rs1, $cr", []>, Sched<[WriteSTW]>;
def LDC_16_CR : PrefixShiftInst<0x2F, (outs), (ins GR16:$rs1, i32imm:$cr),
    "ldc_16_cr", "$rs1, $cr", []>, Sched<[WriteSTW]>;
}
let OpSize = OpSize32.Value in {
def LDC_CR32 : PrefixShiftInst<0x2E, (outs), (ins GPR:$rs1, i32imm:$cr),
    "ldc_cr32", "$rs1, $cr", []>, Sched<[WriteSTW]>;
def LDC_32_CR : PrefixShiftInst<0x2F, (outs), (ins GPR:$rs1, i32imm:$cr),
    "ldc_32_cr", "$rs1, $cr", []>, Sched<[WriteSTW]>;
}
}

// RLC/RRC with immediate count (3 bytes: prefix+reg, 0xE8/0xE9, count)
// Uses PrefixShift format. Existing PrefixRotate hardcodes count=1.
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def RLC_I_8 : PrefixShiftInst<0xE8, (outs GR8:$rd),
    (ins GR8:$src1, i32imm:$cnt), "rlc_i_8", "$rd, $cnt", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
def RRC_I_8 : PrefixShiftInst<0xE9, (outs GR8:$rd),
    (ins GR8:$src1, i32imm:$cnt), "rrc_i_8", "$rd, $cnt", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
}
let OpSize = OpSize16.Value in {
def RLC_I_16 : PrefixShiftInst<0xE8, (outs GR16:$rd),
    (ins GR16:$src1, i32imm:$cnt), "rlc_i_16", "$rd, $cnt", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
def RRC_I_16 : PrefixShiftInst<0xE9, (outs GR16:$rd),
    (ins GR16:$src1, i32imm:$cnt), "rrc_i_16", "$rd, $cnt", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
}
let OpSize = OpSize32.Value in {
def RLC_I_32 : PrefixShiftInst<0xE8, (outs GPR:$rd),
    (ins GPR:$src1, i32imm:$cnt), "rlc_i_32", "$rd, $cnt", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
def RRC_I_32 : PrefixShiftInst<0xE9, (outs GPR:$rd),
    (ins GPR:$src1, i32imm:$cnt), "rrc_i_32", "$rd, $cnt", []>,
    Sched<[WriteIALU]> { let Constraints = "$rd = $src1"; }
}
}

// DJNZ16 — Decrement and jump if not zero, 16-bit register
let Constraints = "$rd = $rs1", isBranch = 1, isTerminator = 1, Defs = [SR],
    OpSize = OpSize16.Value in
def DJNZ16 : PrefixDJNZInst<0x1C, (outs GR16:$rd),
    (ins GR16:$rs1, brtarget:$target), "djnz16", "$rd, $target", []>,
    Sched<[WriteIALU, WriteJmp]>;

// --- Extended Register Prefix (C7/D7/E7) — Native typed definitions ---
// These use ERPRegInst (register as operand) and ERPSmallImmInst (immediate 0-7),
// collapsing per-register defs into one def per operation+size.
// Encoding: [prefix, bank_idx, SubOpcode_base + reg_enc_or_imm3]

// 8-bit ERP operations with register operand
let OpSize = OpSize8.Value in {
def LDTO_BERP : ERPRegInst<0x88, (outs), (ins GR8:$rd, i32imm:$bank),
    "ldto_berp", "$rd, $bank", []>, Sched<[WriteSTW]>;
def LDFR_BERP : ERPRegInst<0x98, (outs), (ins GR8:$rs, i32imm:$bank),
    "ldfr_berp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def ADD_BERP : ERPRegInst<0x80, (outs), (ins GR8:$rs, i32imm:$bank),
    "add_berp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def SUB_BERP : ERPRegInst<0xA0, (outs), (ins GR8:$rs, i32imm:$bank),
    "sub_berp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def AND_BERP : ERPRegInst<0xC0, (outs), (ins GR8:$rs, i32imm:$bank),
    "and_berp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def OR_BERP : ERPRegInst<0xE0, (outs), (ins GR8:$rs, i32imm:$bank),
    "or_berp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def CP_BERP : ERPRegInst<0xF0, (outs), (ins GR8:$rs, i32imm:$bank),
    "cp_berp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def LDI_BERP : ERPSmallImmInst<0xA8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "ldi_berp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def CPI_BERP : ERPSmallImmInst<0xD8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "cpi_berp", "$bank, $imm", []>, Sched<[WriteSTW]>;
} // OpSize8

// 16-bit ERP operations with register operand
let OpSize = OpSize16.Value in {
def LDTO_WERP : ERPRegInst<0x88, (outs), (ins GR16:$rd, i32imm:$bank),
    "ldto_werp", "$rd, $bank", []>, Sched<[WriteSTW]>;
def LDFR_WERP : ERPRegInst<0x98, (outs), (ins GR16:$rs, i32imm:$bank),
    "ldfr_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def ADD_WERP : ERPRegInst<0x80, (outs), (ins GR16:$rs, i32imm:$bank),
    "add_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def SUB_WERP : ERPRegInst<0xA0, (outs), (ins GR16:$rs, i32imm:$bank),
    "sub_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def AND_WERP : ERPRegInst<0xC0, (outs), (ins GR16:$rs, i32imm:$bank),
    "and_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def OR_WERP : ERPRegInst<0xE0, (outs), (ins GR16:$rs, i32imm:$bank),
    "or_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def CP_WERP : ERPRegInst<0xF0, (outs), (ins GR16:$rs, i32imm:$bank),
    "cp_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def MUL_WERP : ERPRegInst<0x40, (outs), (ins GR16:$rs, i32imm:$bank),
    "mul_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def EX_WERP : ERPRegInst<0xB8, (outs), (ins GR16:$rs, i32imm:$bank),
    "ex_werp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def LDI_WERP : ERPSmallImmInst<0xA8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "ldi_werp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def CPI_WERP : ERPSmallImmInst<0xD8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "cpi_werp", "$bank, $imm", []>, Sched<[WriteSTW]>;
} // OpSize16

// 32-bit ERP operations with register operand
let OpSize = OpSize32.Value in {
def LDTO_LERP : ERPRegInst<0x88, (outs), (ins GPR:$rd, i32imm:$bank),
    "ldto_lerp", "$rd, $bank", []>, Sched<[WriteSTW]>;
def LDFR_LERP : ERPRegInst<0x98, (outs), (ins GPR:$rs, i32imm:$bank),
    "ldfr_lerp", "$rs, $bank", []>, Sched<[WriteSTW]>;
} // OpSize32

// --- Extended Register Prefix Suffix (C7/D7/E7 + reg_idx + SubOpcode) ---
// Format: C7/D7/E7 prefix + reg_idx_byte + SubOpcode(from TSFlags)
// These provide semantic mnemonics for erpb2/erpw2/erpl2 with known sub-opcodes.

let Opcode = 0xC7 in {
// B extended register prefix suffix instructions
let OpSize = OpSize8.Value in {
def XORCF_A_BERP : ERPUnaryInst< 0x2A, (outs), (ins i32imm:$b0),
    "xorcf_a_berp", "$b0", []>, Sched<[WriteSTW]>;
def INC1_BERP : ERPUnaryInst< 0x61, (outs), (ins i32imm:$b0),
    "inc1_berp", "$b0", []>, Sched<[WriteSTW]>;
def DEC1_BERP : ERPUnaryInst< 0x69, (outs), (ins i32imm:$b0),
    "dec1_berp", "$b0", []>, Sched<[WriteSTW]>;
def SLL_A_BERP : ERPUnaryInst< 0xFE, (outs), (ins i32imm:$b0),
    "sll_a_berp", "$b0", []>, Sched<[WriteSTW]>;
} // OpSize8

// W extended register prefix suffix instructions
let OpSize = OpSize16.Value in {
def PUSH_WERP : ERPUnaryInst< 0x04, (outs), (ins i32imm:$b0),
    "push_werp", "$b0", []>, Sched<[WriteSTW]>;
def POP_WERP : ERPUnaryInst< 0x05, (outs), (ins i32imm:$b0),
    "pop_werp", "$b0", []>, Sched<[WriteSTW]>;
def CPL_WERP : ERPUnaryInst< 0x06, (outs), (ins i32imm:$b0),
    "cpl_werp", "$b0", []>, Sched<[WriteSTW]>;
def XORCF_A_WERP : ERPUnaryInst< 0x2A, (outs), (ins i32imm:$b0),
    "xorcf_a_werp", "$b0", []>, Sched<[WriteSTW]>;
def STCF_A_WERP : ERPUnaryInst< 0x2C, (outs), (ins i32imm:$b0),
    "stcf_a_werp", "$b0", []>, Sched<[WriteSTW]>;
def INC1_WERP : ERPUnaryInst< 0x61, (outs), (ins i32imm:$b0),
    "inc1_werp", "$b0", []>, Sched<[WriteSTW]>;
def INC4_WERP : ERPUnaryInst< 0x64, (outs), (ins i32imm:$b0),
    "inc4_werp", "$b0", []>, Sched<[WriteSTW]>;
def DEC1_WERP : ERPUnaryInst< 0x69, (outs), (ins i32imm:$b0),
    "dec1_werp", "$b0", []>, Sched<[WriteSTW]>;
def SLA_A_WERP : ERPUnaryInst< 0xFC, (outs), (ins i32imm:$b0),
    "sla_a_werp", "$b0", []>, Sched<[WriteSTW]>;
} // OpSize16

// L extended register prefix suffix instructions
let OpSize = OpSize32.Value in {
def PUSH_LERP : ERPUnaryInst< 0x04, (outs), (ins i32imm:$b0),
    "push_lerp", "$b0", []>, Sched<[WriteSTW]>;
def POP_LERP : ERPUnaryInst< 0x05, (outs), (ins i32imm:$b0),
    "pop_lerp", "$b0", []>, Sched<[WriteSTW]>;
def INC4_LERP : ERPUnaryInst< 0x64, (outs), (ins i32imm:$b0),
    "inc4_lerp", "$b0", []>, Sched<[WriteSTW]>;
} // OpSize32
} // Opcode = 0xC7 (ERP suffix)

//===----------------------------------------------------------------------===//
// Previous register bank (PrevBank) instructions — typed Q register operands.
// These are the semantic equivalents of the ERP instructions above, but use
// PrevGR16 (QWA-QSP) register operands instead of raw i32imm bank bytes.
// Encoding: 0xD7 + mode_byte(QR) + sub-opcode bytes.
// mode_byte = 0xE0 + QR_enc * 4 + 2 (register direct mode).
//===----------------------------------------------------------------------===//

let Opcode = 0xC7, OpSize = OpSize16.Value in {

// --- PrevBank register-register operations ---
// LD r, QR (load from previous bank register to current register)
def LD_PBW_TO : PrevBankRRInst<0x88, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "ld", "$rd, $qs", []>, Sched<[WriteSTW]>;
// LD QR, r (store current register to previous bank register)
def LD_PBW_FR : PrevBankRRInst<0x98, (outs), (ins GR16:$rs, PrevGR16:$qd),
    "ld", "$qd, $rs", []>, Sched<[WriteSTW]>;
// ADD r, QR
def ADD_PBW : PrevBankRRInst<0x80, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "add", "$rd, $qs", []>, Sched<[WriteSTW]>;
// SUB r, QR
def SUB_PBW : PrevBankRRInst<0xA0, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "sub", "$rd, $qs", []>, Sched<[WriteSTW]>;
// OR r, QR
def OR_PBW : PrevBankRRInst<0xE0, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "or", "$rd, $qs", []>, Sched<[WriteSTW]>;
// MUL r, QR
def MUL_PBW : PrevBankRRInst<0x40, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "mul", "$rd, $qs", []>, Sched<[WriteSTW]>;

// --- PrevBank small immediate operations (3-bit value) ---
// LD QR, #small (0-7)
def LD_PBW_SI : PrevBankSmallImmInst<0xA8, (outs),
    (ins i32imm:$imm, PrevGR16:$qd),
    "ld", "$qd, $imm", []>, Sched<[WriteSTW]>;
// CP QR, #small (0-7)
def CP_PBW_SI : PrevBankSmallImmInst<0xD8, (outs),
    (ins i32imm:$imm, PrevGR16:$qd),
    "cp", "$qd, $imm", []>, Sched<[WriteSTW]>;
// INC n, QR
def INC_PBW : PrevBankSmallImmInst<0x60, (outs),
    (ins i32imm:$count, PrevGR16:$qd),
    "inc", "$count, $qd", []>, Sched<[WriteSTW]>;
// DEC n, QR
def DEC_PBW : PrevBankSmallImmInst<0x68, (outs),
    (ins i32imm:$count, PrevGR16:$qd),
    "dec", "$count, $qd", []>, Sched<[WriteSTW]>;

// --- PrevBank unary operations ---
// PUSH QR (sub-opcode 0x04)
def PUSH_PBW : PrevBankUnaryInst<0x04, (outs), (ins PrevGR16:$qd),
    "push", "$qd", []>, Sched<[WriteSTW]>;
// POP QR (sub-opcode 0x05)
def POP_PBW : PrevBankUnaryInst<0x05, (outs), (ins PrevGR16:$qd),
    "pop", "$qd", []>, Sched<[WriteSTW]>;
// NEG QR (sub-opcode 0x07)
def NEG_PBW : PrevBankUnaryInst<0x07, (outs), (ins PrevGR16:$qd),
    "neg", "$qd", []>, Sched<[WriteSTW]>;
// CPL QR
def CPL_PBW : PrevBankUnaryInst<0x06, (outs), (ins PrevGR16:$qd),
    "cpl", "$qd", []>, Sched<[WriteSTW]>;
// BS1B A, QR (bit search 1 backward, result in A)
def BS1B_PBW : PrevBankUnaryInst<0x0F, (outs), (ins PrevGR16:$qd),
    "bs1b", "$qd", []>, Sched<[WriteSTW]>;

// --- PrevBank with trailing immediate ---
// CP QR, #imm16 (word-size compare)
def CP_PBW_IMM : PrevBankImmAfterInst<0xCF, 5, (outs),
    (ins PrevGR16:$qd, i32imm:$imm),
    "cpw", "$qd, $imm", []>, Sched<[WriteSTW]>;
// LD QR, #imm16 (word-size load)
def LD_PBW_IMM : PrevBankImmAfterInst<0x03, 5, (outs),
    (ins PrevGR16:$qd, i32imm:$imm),
    "ldw", "$qd, $imm", []>, Sched<[WriteSTW]>;
// SET bit#, QR
def SET_PBW : PrevBankImmAfterInst<0x31, 4, (outs),
    (ins PrevGR16:$qd, i32imm:$bit),
    "set", "$bit, $qd", []>, Sched<[WriteSTW]>;
// BIT bit#, QR
def BIT_PBW : PrevBankImmAfterInst<0x33, 4, (outs),
    (ins PrevGR16:$qd, i32imm:$bit),
    "bit", "$bit, $qd", []>, Sched<[WriteSTW]>;
// RES bit#, QR
def RES_PBW : PrevBankImmAfterInst<0x30, 4, (outs),
    (ins PrevGR16:$qd, i32imm:$bit),
    "res", "$bit, $qd", []>, Sched<[WriteSTW]>;
// LDCF bit#, QR (load carry flag from bit)
def LDCF_PBW : PrevBankImmAfterInst<0x23, 4, (outs),
    (ins PrevGR16:$qd, i32imm:$bit),
    "ldcf", "$bit, $qd", []>, Sched<[WriteSTW]>;
// STCF bit#, QR (store carry flag to bit)
def STCF_PBW : PrevBankImmAfterInst<0x24, 4, (outs),
    (ins PrevGR16:$qd, i32imm:$bit),
    "stcf", "$bit, $qd", []>, Sched<[WriteSTW]>;

} // Opcode = 0xC7, OpSize16

// --- Source Post-Increment (SPI) native defs ---
// Encoding: [C5/D5/E5, base_reg_addr, SubOpc_base + data_reg_enc]
// Reuses ERPRegInst format with Opcode overridden to 0xC5.
// Operand 0: data register, Operand 1: base register address (i32imm).
let Opcode = 0xC5 in {
let OpSize = OpSize8.Value in {
def LD_SPIB : ERPRegInst<0x20, (outs), (ins GR8:$rd, i32imm:$base),
    "ld_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPIB : ERPRegInst<0x80, (outs), (ins GR8:$rd, i32imm:$base),
    "add_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPIB : ERPRegInst<0xF0, (outs), (ins GR8:$rd, i32imm:$base),
    "cp_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def LD_SPIW : ERPRegInst<0x20, (outs), (ins GR16:$rd, i32imm:$base),
    "ld_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPIW : ERPRegInst<0x80, (outs), (ins GR16:$rd, i32imm:$base),
    "add_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPIW : ERPRegInst<0xF0, (outs), (ins GR16:$rd, i32imm:$base),
    "cp_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def CPM_SPIW : ERPRegInst<0xF8, (outs), (ins GR16:$rd, i32imm:$base),
    "cpm_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
} // OpSize16
let OpSize = OpSize32.Value in {
def LD_SPIL : ERPRegInst<0x20, (outs), (ins GPR:$rd, i32imm:$base),
    "ld_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPIL : ERPRegInst<0x80, (outs), (ins GPR:$rd, i32imm:$base),
    "add_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
} // OpSize32
} // Opcode = 0xC5 (SPI native)

// --- Source Pre-Decrement (SPD) native defs ---
// Encoding: [C4/D4/E4, base_reg_addr, SubOpc_base + data_reg_enc]
let Opcode = 0xC4 in {
let OpSize = OpSize8.Value in {
def CP_SPDB : ERPRegInst<0xF0, (outs), (ins GR8:$rd, i32imm:$base),
    "cp_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
} // OpSize8
} // Opcode = 0xC4 (SPD native)

// --- Source Register-Indirect Complex (C3/D3/E3) ---
// Format: C3/D3/E3 + addressing_bytes + sub_opcode [+ operand_bytes]
// Addressing modes: (R32), (R32+d16), (R32+R8/R16), (PC+d16)

let Opcode = 0xC3 in {
} // Opcode = 0xC3

// ====================================================================
// Destination-table consolidated instruction defs
// These replace per-sub-opcode ExtAddrModeSuffix/ExtAddrModeOpImm defs
// with named instructions using native format classes.
// ====================================================================

// --- DD8 (prefix F0): bit/flag operations ---
// Encoding: [F0, addr8, SubOpc + bit]  (3 bytes)
// ExtImmMod: operand 0 = modifier (bit#), remaining = raw address bytes
def RES_DD8 : ExtImmModInst<0xF0, 0xB0, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "res_dd8", "$bit, $addr", []>;
def SET_DD8 : ExtImmModInst<0xF0, 0xB8, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "set_dd8", "$bit, $addr", []>;
def BIT_DD8 : ExtImmModInst<0xF0, 0xC8, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "bit_dd8", "$bit, $addr", []>;
def LDCF_DD8 : ExtImmModInst<0xF0, 0x98, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "ldcf_dd8", "$bit, $addr", []>;

// --- DD8 (prefix F0): register operations ---
// D8Reg: [F0, addr8, SubOpc + reg_enc]  (3 bytes)
// Operand 0 = register, Operand 1 = addr8
def ST_DD8B : D8RegInst<0xF0, 0x40, (outs), (ins GR8:$rs, i32imm:$addr),
    "st_dd8b", "$rs, $addr", []>;
def LDA_DD8L : D8RegInst<0xF0, 0x30, (outs), (ins GPR:$rd, i32imm:$addr),
    "lda_dd8l", "$rd, $addr", []>;

// --- DD16 (prefix F1): bit/flag operations ---
// Encoding: [F1, addr_lo, addr_hi, SubOpc + bit]  (4 bytes)
// ExtImmMod: operand 0 = modifier (bit#), remaining = raw address bytes
def TSET_DD16 : ExtImmModInst<0xF1, 0xA8, 4, (outs), (ins i32imm:$bit, i32imm:$lo, i32imm:$hi),
    "tset_dd16", "$bit, $lo, $hi", []>;
def LDCF_DD16 : ExtImmModInst<0xF1, 0x98, 4, (outs), (ins i32imm:$bit, i32imm:$lo, i32imm:$hi),
    "ldcf_dd16", "$bit, $lo, $hi", []>;

// --- DD16 (prefix F1): fixed sub-opcode operations ---
// ExtAddrModeSuffix: [F1, addr_lo, addr_hi, SubOpc]  (4 bytes)
def STCFA_DD16 : ExtAddrModeSuffixInst<4, 0x2C, (outs),
    (ins i32imm:$lo, i32imm:$hi),
    "stcfa_dd16", "$lo, $hi", []> {
  let Opcode = 0xF1;
}
def POPB_DD16 : ExtAddrModeSuffixInst<4, 0x04, (outs),
    (ins i32imm:$lo, i32imm:$hi),
    "popb_dd16", "$lo, $hi", []> {
  let Opcode = 0xF1;
}
def POPW_DD16 : ExtAddrModeSuffixInst<4, 0x06, (outs),
    (ins i32imm:$lo, i32imm:$hi),
    "popw_dd16", "$lo, $hi", []> {
  let Opcode = 0xF1;
}

// --- DD24 (prefix F2): memory-to-memory operations ---
// ExtAddrModeOpImm: [F2, addr_lo, addr_mid, addr_hi, SubOpc, src_lo, src_hi]  (7 bytes)
// 3 pre-ops (address bytes), then SubOpcode, then 2 trailing (source address)
def LDMMB_DD24 : ExtAddrModeOpImmInst<7, 0x14, 3, (outs),
    (ins i32imm:$a0, i32imm:$a1, i32imm:$a2, i32imm:$s0, i32imm:$s1),
    "ldmmb_dd24", "$a0, $a1, $a2, $s0, $s1", []> {
  let Opcode = 0xF2;
}
def LDMMW_DD24 : ExtAddrModeOpImmInst<7, 0x16, 3, (outs),
    (ins i32imm:$a0, i32imm:$a1, i32imm:$a2, i32imm:$s0, i32imm:$s1),
    "ldmmw_dd24", "$a0, $a1, $a2, $s0, $s1", []> {
  let Opcode = 0xF2;
}

// --- DRI (prefix F3): bit/flag/JP operations ---
// RIImmMod: [F3, MEMsri_bytes..., SubOpc + modifier]  (5 bytes for 3-byte MEMsri)
// Operand 0 = modifier (bit# or cc), Operands 1-3 = MEMsri (mode, lo, hi)
def RES_DRI : RIImmModInst<0xF3, 0xB0, 5, (outs), (ins i32imm:$bit, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "res_dri", "$bit, $b0, $b1, $b2", []>;
def SET_DRI : RIImmModInst<0xF3, 0xB8, 5, (outs), (ins i32imm:$bit, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "set_dri", "$bit, $b0, $b1, $b2", []>;
def BIT_DRI : RIImmModInst<0xF3, 0xC8, 5, (outs), (ins i32imm:$bit, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "bit_dri", "$bit, $b0, $b1, $b2", []>;
def LDCF_DRI : RIImmModInst<0xF3, 0x98, 5, (outs), (ins i32imm:$bit, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ldcf_dri", "$bit, $b0, $b1, $b2", []>;
def XORCF_DRI : RIImmModInst<0xF3, 0x90, 5, (outs), (ins i32imm:$bit, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "xorcf_dri", "$bit, $b0, $b1, $b2", []>;
def JP_DRI : RIImmModInst<0xF3, 0xD0, 5, (outs), (ins i32imm:$cc, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "jp_dri", "$cc, $b0, $b1, $b2", []>;

// --- DRI (prefix F3): store immediate ---
// RIImmAfter: [F3, MEMsri_bytes..., SubOpc, imm_bytes...]
// Operands 0-2 = MEMsri (mode, lo, hi), remaining = trailing immediate
def STIB_DRI : RIImmAfterInst<0xF3, 0x00, 6, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$imm),
    "stib_dri", "$b0, $b1, $b2, $imm", []>;
def STIW_DRI : RIImmAfterInst<0xF3, 0x02, 7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "stiw_dri", "$b0, $b1, $b2, $lo, $hi", []>;

// --- DRI (prefix F3): memory-to-memory ---
// RIImmAfter: [F3, MEMsri_bytes..., SubOpc, src_lo, src_hi]
// Operands 0-2 = MEMsri (dest mode, lo, hi), 3-4 = source address bytes
def LDMMB_DRI : RIImmAfterInst<0xF3, 0x14, 7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$s0, i32imm:$s1),
    "ldmmb_dri", "$b0, $b1, $b2, $s0, $s1", []>;
def LDMMW_DRI : RIImmAfterInst<0xF3, 0x16, 7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$s0, i32imm:$s1),
    "ldmmw_dri", "$b0, $b1, $b2, $s0, $s1", []>;

// --- DPD (prefix F4): store immediate ---
// ExtAddrModeOpImm: [F4, addr_reg, SubOpc, imm...]
// 1 pre-op (base register byte), then SubOpcode, then trailing imm
def STIB_DPD : ExtAddrModeOpImmInst<4, 0x00, 1, (outs),
    (ins i32imm:$reg, i32imm:$imm),
    "stib_dpd", "$reg, $imm", []> {
  let Opcode = 0xF4;
}

// --- DPI (prefix F5): store immediate ---
// ExtAddrModeOpImm: [F5, addr_reg, SubOpc, imm...]
// 1 pre-op (base register byte), then SubOpcode, then trailing imm
def STIB_DPI : ExtAddrModeOpImmInst<4, 0x00, 1, (outs),
    (ins i32imm:$reg, i32imm:$imm),
    "stib_dpi", "$reg, $imm", []> {
  let Opcode = 0xF5;
}
def STIW_DPI : ExtAddrModeOpImmInst<5, 0x02, 1, (outs),
    (ins i32imm:$reg, i32imm:$lo, i32imm:$hi),
    "stiw_dpi", "$reg, $lo, $hi", []> {
  let Opcode = 0xF5;
}

// --- Consolidated SRI LD defs (C3/D3/E3) with register operand ---
// Uses RIRegInst: [prefix, addr_bytes..., SubOpc + reg_enc]
// Prefix = C3 + OpSize * 0x10 (C3=byte, D3=word, E3=long)

let Opcode = 0xC3 in {
let OpSize = OpSize8.Value in {
def LD_SRIB3 : RIRegInst<0xC3, 0x20, 5, (outs), (ins GR8:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ld_srib3", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def LD_SRIB1 : RIRegInst<0xC3, 0x20, 3, (outs), (ins GR8:$rd, i32imm:$b0),
    "ld_srib1", "$rd, $b0", []>, Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def LD_SRIW3 : RIRegInst<0xC3, 0x20, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ld_sriw3", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def LD_SRIW1 : RIRegInst<0xC3, 0x20, 3, (outs), (ins GR16:$rd, i32imm:$b0),
    "ld_sriw1", "$rd, $b0", []>, Sched<[WriteSTW]>;
} // OpSize16
let OpSize = OpSize32.Value in {
def LD_SRIL3 : RIRegInst<0xC3, 0x20, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ld_sril3", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def LD_SRIL1 : RIRegInst<0xC3, 0x20, 3, (outs), (ins GPR:$rd, i32imm:$b0),
    "ld_sril1", "$rd, $b0", []>, Sched<[WriteSTW]>;
} // OpSize32
} // Opcode = 0xC3

// --- SRI LD with semantic operands (base GPR + d16 displacement) ---
// Replaces ld_sril3/ld_sriw3/ld_srib3 for mode type 1 (d16) cases.
// Syntax: ld_sril xwa, (xbc + 0x0e0a)
let Opcode = 0xC3 in {
let OpSize = OpSize8.Value in {
def LD_SRIB_D16 : SriD16RegInst<0xC3, 0x20, (outs), (ins GR8:$rd, MEMri:$addr),
    "ld_srib", "$rd, $addr", []>, Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def LD_SRIW_D16 : SriD16RegInst<0xC3, 0x20, (outs), (ins GR16:$rd, MEMri:$addr),
    "ld_sriw", "$rd, $addr", []>, Sched<[WriteSTW]>;
} // OpSize16
let OpSize = OpSize32.Value in {
def LD_SRIL_D16 : SriD16RegInst<0xC3, 0x20, (outs), (ins GPR:$rd, MEMri:$addr),
    "ld_sril", "$rd, $addr", []>, Sched<[WriteSTW]>;
} // OpSize32
} // Opcode = 0xC3

// --- Source Post-Increment (C5/D5/E5) ---
// Format: C5/D5/E5 + reg_byte + sub_opcode [+ operand_bytes]

let Opcode = 0xC5 in {
} // Opcode = 0xC5

// --- Source 8-bit Direct Address (C0/D0/E0) ---
// Format: C0/D0/E0 + addr8 + sub_opcode [+ operand_bytes]

let Opcode = 0xC0 in {
} // Opcode = 0xC0

// --- Destination Register-Indirect Complex (F3) ---
// Format: F3 + addressing_bytes + sub_opcode [+ operand_bytes]


// --- Consolidated DRI ST/LDA defs (F3) with register operand ---
// Uses RIRegInst: [F3, addr_bytes..., SubOpc + reg_enc]
// F3 prefix is size-independent (Opcode >= 0xF0, no OpSize adjustment)

let Opcode = 0xF3 in {
let OpSize = OpSize8.Value in {
def ST_DRI3B : RIRegInst<0xF3, 0x30, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "st_dri3b", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize8
def LDA_DRI3 : RIRegInst<0xF3, 0x40, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "lda_dri3", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
let OpSize = OpSize16.Value in {
def ST_DRI3W : RIRegInst<0xF3, 0x50, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "st_dri3w", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize16
def ST_DRI3L : RIRegInst<0xF3, 0x60, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "st_dri3l", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // Opcode = 0xF3


// --- Destination Post-Increment (F5) — consolidated defs ---
// Format: [F5, base_reg_addr_byte, SubOpc + data_reg_enc]
// F5 prefix is size-independent (Opcode >= 0xF0, no OpSize adjustment).
// Uses ERPRegInst: Operand 0 = data register, Operand 1 = base reg addr byte.

let Opcode = 0xF5 in {
let OpSize = OpSize8.Value in {
def ST_DPIB : ERPRegInst<0x30, (outs), (ins GR8:$rs, i32imm:$base),
    "st_dpib", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize8
def LDA_DPI : ERPRegInst<0x40, (outs), (ins GPR:$rd, i32imm:$base),
    "lda_dpi", "$rd, $base", []>, Sched<[WriteSTW]>;
let OpSize = OpSize16.Value in {
def ST_DPIW : ERPRegInst<0x50, (outs), (ins GR16:$rs, i32imm:$base),
    "st_dpiw", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize16
def ST_DPIL : ERPRegInst<0x60, (outs), (ins GPR:$rs, i32imm:$base),
    "st_dpil", "$rs, $base", []>, Sched<[WriteSTW]>;
} // Opcode = 0xF5

// --- Destination 8-bit Direct Address (F0) ---
// Format: F0 + addr8 + sub_opcode [+ operand_bytes]


// --- Source 16-bit Direct Address (C1/D1/E1) ---
// Format: C1/D1/E1 + addr16_LE + sub_opcode [+ operand_bytes]

let Opcode = 0xC1 in {
} // Opcode = 0xC1

// --- Source 24-bit Direct Address (C2/D2/E2) ---
// Format: C2/D2/E2 + addr24 + sub_opcode [+ operand_bytes]

let Opcode = 0xC2 in {
} // Opcode = 0xC2

// --- Source Pre-Decrement (C4/D4/E4) ---
// Format: C4/D4/E4 + reg_byte + sub_opcode [+ operand_bytes]

let Opcode = 0xC4 in {
} // Opcode = 0xC4

// --- Destination 16-bit Direct Address (F1) ---
// Format: F1 + addr16_LE + sub_opcode [+ operand_bytes]


// --- Destination 24-bit Direct Address (F2) ---
// Format: F2 + addr24 + sub_opcode [+ operand_bytes]


// --- Destination Pre-Decrement (F4) ---
// Format: F4 + reg_byte + sub_opcode [+ operand_bytes]

// === Auto-generated semantic extended addressing mode instructions ===
// Generated by scripts/gen_semantic_instrs.py
// Each definition replaces one or more raw ExtAddrModeInst wrappers.


// --- Consolidated SRI ALU defs (C3/D3/E3) with register operand ---
// Per-register ALU operations: sub_opc base + reg_enc
// Source table: ADD=0x80/0x88, ADC=0x90/0x98, SUB=0xA0/0xA8, SBC=0xB0/0xB8,
//              AND=0xC0/0xC8, XOR=0xD0/0xD8, OR=0xE0/0xE8, CP=0xF0/0xF8
// _rm = ALU reg, (mem); _mr = ALU (mem), reg

let Opcode = 0xC3 in {
// --- Byte SRI ALU ---
let OpSize = OpSize8.Value in {
def ADD_SRIB_MR : RIRegInst<0xC3, 0x88, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "add_srib_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def SUB_SRIB_MR : RIRegInst<0xC3, 0xA8, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "sub_srib_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def AND_SRIB_RM : RIRegInst<0xC3, 0xC0, 5, (outs), (ins GR8:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "and_srib_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def AND_SRIB_MR : RIRegInst<0xC3, 0xC8, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "and_srib_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def XOR_SRIB_RM : RIRegInst<0xC3, 0xD0, 5, (outs), (ins GR8:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "xor_srib_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def OR_SRIB_RM : RIRegInst<0xC3, 0xE0, 5, (outs), (ins GR8:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "or_srib_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def OR_SRIB_MR : RIRegInst<0xC3, 0xE8, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "or_srib_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIB_RM : RIRegInst<0xC3, 0xF0, 5, (outs), (ins GR8:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cp_srib_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIB_MR : RIRegInst<0xC3, 0xF8, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cp_srib_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize8

// --- Word SRI ALU ---
let OpSize = OpSize16.Value in {
def ADD_SRIW_RM : RIRegInst<0xC3, 0x80, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "add_sriw_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def ADD_SRIW_MR : RIRegInst<0xC3, 0x88, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "add_sriw_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def SUB_SRIW_RM : RIRegInst<0xC3, 0xA0, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "sub_sriw_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def AND_SRIW_RM : RIRegInst<0xC3, 0xC0, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "and_sriw_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def AND_SRIW_MR : RIRegInst<0xC3, 0xC8, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "and_sriw_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def OR_SRIW_RM : RIRegInst<0xC3, 0xE0, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "or_sriw_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def OR_SRIW_MR : RIRegInst<0xC3, 0xE8, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "or_sriw_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIW_RM : RIRegInst<0xC3, 0xF0, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cp_sriw_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIW_MR : RIRegInst<0xC3, 0xF8, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cp_sriw_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize16

// --- Long SRI ALU ---
let OpSize = OpSize32.Value in {
def ADD_SRIL_RM : RIRegInst<0xC3, 0x80, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "add_sril_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def ADD_SRIL_MR : RIRegInst<0xC3, 0x88, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "add_sril_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def SUB_SRIL_RM : RIRegInst<0xC3, 0xA0, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "sub_sril_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def SUB_SRIL_MR : RIRegInst<0xC3, 0xA8, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "sub_sril_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIL_RM : RIRegInst<0xC3, 0xF0, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cp_sril_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIL_MR : RIRegInst<0xC3, 0xF8, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cp_sril_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize32
} // Opcode = 0xC3





// --- Consolidated ERP Byte operations (prefix C7) ---
let Opcode = 0xC7, OpSize = OpSize8.Value in {
// ERPImmAfterInst: [C7, bank, sub_opc, imm_bytes...]
def LDI_ERPB : ERPImmAfterInst<0x03, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "ldi_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def MULS_ERPB : ERPImmAfterInst<0x09, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "muls_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def RES_ERPB : ERPImmAfterInst<0x30, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "res_erpb", "$bank, $bit", []>, Sched<[WriteSTW]>;
def SET_ERPB : ERPImmAfterInst<0x31, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "set_erpb", "$bank, $bit", []>, Sched<[WriteSTW]>;
def BIT_ERPB : ERPImmAfterInst<0x33, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "bit_erpb", "$bank, $bit", []>, Sched<[WriteSTW]>;
def ADD_ERPB : ERPImmAfterInst<0xC8, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "add_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def SUB_ERPB : ERPImmAfterInst<0xCA, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "sub_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def AND_ERPB : ERPImmAfterInst<0xCC, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "and_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def XOR_ERPB : ERPImmAfterInst<0xCD, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "xor_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def OR_ERPB : ERPImmAfterInst<0xCE, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "or_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def CP_ERPB : ERPImmAfterInst<0xCF, 4, (outs), (ins i32imm:$bank, i32imm:$imm),
    "cp_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def SLL_ERPB : ERPImmAfterInst<0xEE, 4, (outs), (ins i32imm:$bank, i32imm:$n),
    "sll_erpb", "$bank, $n", []>, Sched<[WriteSTW]>;
def SRL_ERPB : ERPImmAfterInst<0xEF, 4, (outs), (ins i32imm:$bank, i32imm:$n),
    "srl_erpb", "$bank, $n", []>, Sched<[WriteSTW]>;
// ERPUnaryInst byte: [C7, bank, sub_opc]
def XORCF_ERPB : ERPUnaryInst<0xE2, (outs), (ins i32imm:$bank),
    "xorcf_erpb", "$bank", []>, Sched<[WriteSTW]>;
def LDCF_ERPB : ERPUnaryInst<0xE6, (outs), (ins i32imm:$bank),
    "ldcf_erpb", "$bank", []>, Sched<[WriteSTW]>;
// ERPRegInst byte: [C7, bank, sub_opc + reg_enc]
def CP_ERPB_RR : ERPRegInst<0xF0, (outs), (ins GR8:$rd, i32imm:$bank),
    "cp_erpb_rr", "$rd, $bank", []>, Sched<[WriteSTW]>;
def OR_ERPB_RR : ERPRegInst<0xE0, (outs), (ins GR8:$rs, i32imm:$bank),
    "or_erpb_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
} // Opcode = 0xC7, OpSize8

// --- Consolidated ERP Word operations (prefix D7) ---
let Opcode = 0xC7, OpSize = OpSize16.Value in {
// ERPImmAfterInst word: [D7, bank, sub_opc, imm_bytes...]
def LDCF_ERPW : ERPImmAfterInst<0x23, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "ldcf_erpw", "$bank, $bit", []>, Sched<[WriteSTW]>;
def STCF_ERPW : ERPImmAfterInst<0x24, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "stcf_erpw", "$bank, $bit", []>, Sched<[WriteSTW]>;
def XORCF_ERPW : ERPImmAfterInst<0x22, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "xorcf_erpw", "$bank, $bit", []>, Sched<[WriteSTW]>;
def RES_ERPW : ERPImmAfterInst<0x30, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "res_erpw", "$bank, $bit", []>, Sched<[WriteSTW]>;
def SET_ERPW : ERPImmAfterInst<0x31, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "set_erpw", "$bank, $bit", []>, Sched<[WriteSTW]>;
def BIT_ERPW : ERPImmAfterInst<0x33, 4, (outs), (ins i32imm:$bank, i32imm:$bit),
    "bit_erpw", "$bank, $bit", []>, Sched<[WriteSTW]>;
def SRL_ERPW : ERPImmAfterInst<0xEF, 4, (outs), (ins i32imm:$bank, i32imm:$n),
    "srl_erpw", "$bank, $n", []>, Sched<[WriteSTW]>;
def ADD_ERPW : ERPImmAfterInst<0xC8, 5, (outs), (ins i32imm:$bank, i32imm:$lo, i32imm:$hi),
    "add_erpw", "$bank, $lo, $hi", []>, Sched<[WriteSTW]>;
def ADC_ERPW : ERPImmAfterInst<0xC9, 5, (outs), (ins i32imm:$bank, i32imm:$lo, i32imm:$hi),
    "adc_erpw", "$bank, $lo, $hi", []>, Sched<[WriteSTW]>;
def AND_ERPW : ERPImmAfterInst<0xCC, 5, (outs), (ins i32imm:$bank, i32imm:$lo, i32imm:$hi),
    "and_erpw", "$bank, $lo, $hi", []>, Sched<[WriteSTW]>;
def OR_ERPW : ERPImmAfterInst<0xCE, 5, (outs), (ins i32imm:$bank, i32imm:$lo, i32imm:$hi),
    "or_erpw", "$bank, $lo, $hi", []>, Sched<[WriteSTW]>;
def CP_ERPW : ERPImmAfterInst<0xCF, 5, (outs), (ins i32imm:$bank, i32imm:$lo, i32imm:$hi),
    "cp_erpw", "$bank, $lo, $hi", []>, Sched<[WriteSTW]>;
def LDI_ERPW : ERPImmAfterInst<0x03, 5, (outs), (ins i32imm:$bank, i32imm:$lo, i32imm:$hi),
    "ldi_erpw", "$bank, $lo, $hi", []>, Sched<[WriteSTW]>;
// ERPUnaryInst word: [D7, bank, sub_opc]
def BS1B_ERPW : ERPUnaryInst<0x0F, (outs), (ins i32imm:$bank),
    "bs1b_erpw", "$bank", []>, Sched<[WriteSTW]>;
def SRL_A_ERPW : ERPUnaryInst<0x82, (outs), (ins i32imm:$bank),
    "srl_a_erpw", "$bank", []>, Sched<[WriteSTW]>;
def SLA_ERPW : ERPUnaryInst<0x84, (outs), (ins i32imm:$bank),
    "sla_erpw", "$bank", []>, Sched<[WriteSTW]>;
def SLL_A_ERPW : ERPUnaryInst<0x9C, (outs), (ins i32imm:$bank),
    "sll_a_erpw", "$bank", []>, Sched<[WriteSTW]>;
def EX_ERPW : ERPUnaryInst<0xBA, (outs), (ins i32imm:$bank),
    "ex_erpw", "$bank", []>, Sched<[WriteSTW]>;
def CPL_ERPW : ERPUnaryInst<0xDA, (outs), (ins i32imm:$bank),
    "cpl_erpw", "$bank", []>, Sched<[WriteSTW]>;
def NEG_ERPW : ERPUnaryInst<0xDD, (outs), (ins i32imm:$bank),
    "neg_erpw", "$bank", []>, Sched<[WriteSTW]>;
def OR_ERPW_CF : ERPUnaryInst<0xE3, (outs), (ins i32imm:$bank),
    "or_erpw_cf", "$bank", []>, Sched<[WriteSTW]>;
// ERPSmallImmInst word: [D7, bank, 0xD8 + imm3]
def CPI3_ERPW : ERPSmallImmInst<0xD8, (outs), (ins i32imm:$bank, i32imm:$imm3),
    "cpi3_erpw", "$imm3, $bank", []>, Sched<[WriteSTW]>;
// ERPRegInst word: [D7, bank, sub_opc + reg_enc]
def ADD_ERPW_RR : ERPRegInst<0x80, (outs), (ins GR16:$rs, i32imm:$bank),
    "add_erpw_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
def LD_ERPW_RR : ERPRegInst<0x88, (outs), (ins GR16:$rs, i32imm:$bank),
    "ld_erpw_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
def LD2_ERPW_RR : ERPRegInst<0x98, (outs), (ins GR16:$rs, i32imm:$bank),
    "ld2_erpw_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
def EX_ERPW_RR : ERPRegInst<0xB8, (outs), (ins GR16:$rs, i32imm:$bank),
    "ex_erpw_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
def OR_ERPW_RR : ERPRegInst<0xE0, (outs), (ins GR16:$rs, i32imm:$bank),
    "or_erpw_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
} // Opcode = 0xC7, OpSize16

// --- Consolidated ERP Long operations (prefix E7) ---
let Opcode = 0xC7, OpSize = OpSize32.Value in {
def ADD_ERPL : ERPImmAfterInst<0xC8, 7,
    (outs), (ins i32imm:$bank, i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "add_erpl", "$bank, $b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;
} // Opcode = 0xC7, OpSize32

// --- Consolidated SPI Byte additional operations (prefix C5) ---
let Opcode = 0xC5, OpSize = OpSize8.Value in {
def OR_SPIB_RM : ERPRegInst<0xE0, (outs), (ins GR8:$rd, i32imm:$base),
    "or_spib_rm", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPIB_IM : ERPImmAfterInst<0x3F, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "cp_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
} // Opcode = 0xC5, OpSize8

// --- Consolidated SRI Byte non-register operations ---
let OpSize = OpSize8.Value in {
// SRI byte ALU-immediate: [C3, MEMsri(3), sub_opc, imm8]
def SUB_SRIB_IM : RIImmAfterInst<0xC3, 0x3A, 6, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$imm),
    "sub_srib_im", "$b0, $b1, $b2, $imm", []>, Sched<[WriteSTW]>;
def AND_SRIB_IM : RIImmAfterInst<0xC3, 0x3C, 6, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$imm),
    "and_srib_im", "$b0, $b1, $b2, $imm", []>, Sched<[WriteSTW]>;
def OR_SRIB_IM : RIImmAfterInst<0xC3, 0x3E, 6, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$imm),
    "or_srib_im", "$b0, $b1, $b2, $imm", []>, Sched<[WriteSTW]>;
def CP_SRIB_IM : RIImmAfterInst<0xC3, 0x3F, 6, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$imm),
    "cp_srib_im", "$b0, $b1, $b2, $imm", []>, Sched<[WriteSTW]>;
// SRI byte INC/DEC: [C3, MEMsri(3), 0x60+count / 0x68+count]
def INC_SRIB : RIImmModInst<0xC3, 0x60, 5, (outs), (ins i32imm:$count, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "inc_srib", "$count, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def DEC_SRIB : RIImmModInst<0xC3, 0x68, 5, (outs), (ins i32imm:$count, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "dec_srib", "$count, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
// SRI byte mem-to-mem: [C3, MEMsri(3), 0x19, dst_lo, dst_hi]
def LDMM_SRIB : RIImmAfterInst<0xC3, 0x19, 7,
    (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "ldmm_srib", "$b0, $b1, $b2, $lo, $hi", []>, Sched<[WriteSTW]>;
} // OpSize8

// --- Consolidated SRI Word non-register operations ---
let OpSize = OpSize16.Value in {
// SRI word ALU-immediate: [D3, MEMsri(3), sub_opc, imm_lo, imm_hi]
def AND_SRIW_IM : RIImmAfterInst<0xC3, 0x3C, 7, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "and_sriw_im", "$b0, $b1, $b2, $lo, $hi", []>, Sched<[WriteSTW]>;
def OR_SRIW_IM : RIImmAfterInst<0xC3, 0x3E, 7, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "or_sriw_im", "$b0, $b1, $b2, $lo, $hi", []>, Sched<[WriteSTW]>;
def CP_SRIW_IM : RIImmAfterInst<0xC3, 0x3F, 7, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "cp_sriw_im", "$b0, $b1, $b2, $lo, $hi", []>, Sched<[WriteSTW]>;
// SRI word PUSH: [D3, MEMsri(3), 0x04]
def PUSH_SRIW : RIUnaryInst<0xC3, 0x04, 5,
    (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "push_sriw", "$b0, $b1, $b2", []>, Sched<[WriteSTW]>;
// SRI word EX: [D3, MEMsri(3), 0x30 + reg_enc]
def EX_SRIW : RIRegInst<0xC3, 0x30, 5,
    (outs), (ins GR16:$reg, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ex_sriw", "$reg, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
// SRI word INC/DEC: [D3, MEMsri(3), 0x60+count / 0x68+count]
def INC_SRIW : RIImmModInst<0xC3, 0x60, 5, (outs), (ins i32imm:$count, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "inc_sriw", "$count, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def DEC_SRIW : RIImmModInst<0xC3, 0x68, 5, (outs), (ins i32imm:$count, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "dec_sriw", "$count, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
// SRI word mem-to-mem: [D3, MEMsri(3), 0x19, dst_lo, dst_hi]
def LDMM_SRIW : RIImmAfterInst<0xC3, 0x19, 7,
    (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "ldmm_sriw", "$b0, $b1, $b2, $lo, $hi", []>, Sched<[WriteSTW]>;
} // OpSize16

// --- Consolidated SD8 Byte operations (prefix C0) ---
let OpSize = OpSize8.Value in {
// D8ImmAfterInst: [C0, addr8, sub_opc, imm8]
def AND_SD8B_IM : D8ImmAfterInst<0xC0, 0x3C, 4,
    (outs), (ins i32imm:$addr, i32imm:$imm),
    "and_sd8b_im", "$addr, $imm", []>, Sched<[WriteSTW]>;
def OR_SD8B_IM : D8ImmAfterInst<0xC0, 0x3E, 4,
    (outs), (ins i32imm:$addr, i32imm:$imm),
    "or_sd8b_im", "$addr, $imm", []>, Sched<[WriteSTW]>;
// D8RegInst: [C0, addr8, sub_opc + reg_enc]
def LD_SD8B : D8RegInst<0xC0, 0x20, (outs), (ins GR8:$rd, i32imm:$addr),
    "ld_sd8b", "$rd, $addr", []>, Sched<[WriteSTW]>;
def OR_SD8B_MR : D8RegInst<0xC0, 0xE8, (outs), (ins GR8:$rs, i32imm:$addr),
    "or_sd8b_mr", "$rs, $addr", []>, Sched<[WriteSTW]>;
// D8ImmAfterInst: mem-to-mem [C0, addr8, 0x19, dst_lo, dst_hi]
def LDMM_SD8B : D8ImmAfterInst<0xC0, 0x19, 5,
    (outs), (ins i32imm:$addr, i32imm:$lo, i32imm:$hi),
    "ldmm_sd8b", "$addr, $lo, $hi", []>, Sched<[WriteSTW]>;
} // OpSize8

// --- Consolidated SD16 operations (prefix C1) ---
let Opcode = 0xC1 in {
let OpSize = OpSize8.Value in {
// ExtAddrModeSuffixInst: [C1, addr_lo, addr_hi, sub_opc]
def PUSH_SD16B : ExtAddrModeSuffixInst<4, 0x04,
    (outs), (ins i32imm:$lo, i32imm:$hi),
    "push_sd16b", "$lo, $hi", []>;
// ExtImmModInst: [C1, addr_lo, addr_hi, sub_opc + reg_enc]
def EX_SD16B : ExtImmModInst<0xC1, 0x30, 4,
    (outs), (ins GR8:$reg, i32imm:$lo, i32imm:$hi),
    "ex_sd16b", "$reg, $lo, $hi", []>;
def MUL_SD16B : ExtImmModInst<0xC1, 0x40, 4,
    (outs), (ins i32imm:$ridx, i32imm:$lo, i32imm:$hi),
    "mul_sd16b", "$ridx, $lo, $hi", []>;
def SLA_SD16B : ExtAddrModeSuffixInst<4, 0x7C,
    (outs), (ins i32imm:$lo, i32imm:$hi),
    "sla_sd16b", "$lo, $hi", []>;
} // OpSize8
let OpSize = OpSize16.Value in {
def PUSH_SD16W : ExtAddrModeSuffixInst<4, 0x04,
    (outs), (ins i32imm:$lo, i32imm:$hi),
    "push_sd16w", "$lo, $hi", []>;
def MULS_SD16W : ExtImmModInst<0xC1, 0x48, 4,
    (outs), (ins i32imm:$ridx, i32imm:$lo, i32imm:$hi),
    "muls_sd16w", "$ridx, $lo, $hi", []>;
} // OpSize16
} // Opcode = 0xC1

// --- Consolidated SD24 operations (prefix C2) ---
let Opcode = 0xC2 in {
let OpSize = OpSize8.Value in {
def LDMM_SD24B : ExtAddrModeOpImmInst<7, 0x19, 3,
    (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "ldmm_sd24b", "$b0, $b1, $b2, $lo, $hi", []>;
} // OpSize8
let OpSize = OpSize16.Value in {
def PUSH_SD24W : ExtAddrModeSuffixInst<5, 0x04,
    (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "push_sd24w", "$b0, $b1, $b2", []>;
def LDMM_SD24W : ExtAddrModeOpImmInst<7, 0x19, 3,
    (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "ldmm_sd24w", "$b0, $b1, $b2, $lo, $hi", []>;
} // OpSize16
} // Opcode = 0xC2

// --- Memory Register-Indirect (80-BF) ---
// Uses ExtPrefixInst (literal bytes) since prefix byte encodes register index.
// mri = no displacement, mrd = with d8 displacement
// Size suffixes: b=8-bit, w=16-bit, l=32-bit, d=destination

// 8-bit source, no displacement (80-87)
def MRIB2 : ExtPrefixInst<2, (outs), (ins i32imm:$b0, i32imm:$b1),
    "mrib2", "$b0, $b1", []>, Sched<[WriteSTW]>;
def MRIB4 : ExtPrefixInst<4, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "mrib4", "$b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;

// 8-bit source, d8 displacement (88-8F)
def MRDB3 : ExtPrefixInst<3, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "mrdb3", "$b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def MRDB4 : ExtPrefixInst<4, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "mrdb4", "$b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;
def MRDB5 : ExtPrefixInst<5, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3, i32imm:$b4),
    "mrdb5", "$b0, $b1, $b2, $b3, $b4", []>, Sched<[WriteSTW]>;

// 16-bit source, no displacement (90-97)
def MRIW2 : ExtPrefixInst<2, (outs), (ins i32imm:$b0, i32imm:$b1),
    "mriw2", "$b0, $b1", []>, Sched<[WriteSTW]>;
def MRIW4 : ExtPrefixInst<4, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "mriw4", "$b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;

// 16-bit source, d8 displacement (98-9F)
def MRDW3 : ExtPrefixInst<3, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "mrdw3", "$b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def MRDW5 : ExtPrefixInst<5, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3, i32imm:$b4),
    "mrdw5", "$b0, $b1, $b2, $b3, $b4", []>, Sched<[WriteSTW]>;

// 32-bit source, no displacement (A0-A7)
def MRIL2 : ExtPrefixInst<2, (outs), (ins i32imm:$b0, i32imm:$b1),
    "mril2", "$b0, $b1", []>, Sched<[WriteSTW]>;

// 32-bit source, d8 displacement (A8-AF)
def MRDL3 : ExtPrefixInst<3, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "mrdl3", "$b0, $b1, $b2", []>, Sched<[WriteSTW]>;

// Destination, no displacement (B0-B7)
def MRID2 : ExtPrefixInst<2, (outs), (ins i32imm:$b0, i32imm:$b1),
    "mrid2", "$b0, $b1", []>, Sched<[WriteSTW]>;
def MRID3 : ExtPrefixInst<3, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "mrid3", "$b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def MRID4 : ExtPrefixInst<4, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "mrid4", "$b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;

// Destination, d8 displacement (B8-BF)
def MRDD3 : ExtPrefixInst<3, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "mrdd3", "$b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def MRDD4 : ExtPrefixInst<4, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "mrdd4", "$b0, $b1, $b2, $b3", []>, Sched<[WriteSTW]>;
def MRDD5 : ExtPrefixInst<5, (outs), (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3, i32imm:$b4),
    "mrdd5", "$b0, $b1, $b2, $b3, $b4", []>, Sched<[WriteSTW]>;

} // hasSideEffects, mayLoad, mayStore

//===----------------------------------------------------------------------===//
// Extended prefix instructions — generic byte-literal encoding (fallback)
//
// These remain as catch-all for any prefix patterns not covered above.
//===----------------------------------------------------------------------===//

let hasSideEffects = 1, mayLoad = 1, mayStore = 1 in {

def EXTPFX2 : ExtPrefixInst<2, (outs),
    (ins i32imm:$b0, i32imm:$b1),
    "extpfx2", "$b0, $b1", []>,
    Sched<[WriteSTW]>;

def EXTPFX3 : ExtPrefixInst<3, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "extpfx3", "$b0, $b1, $b2", []>,
    Sched<[WriteSTW]>;

def EXTPFX4 : ExtPrefixInst<4, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3),
    "extpfx4", "$b0, $b1, $b2, $b3", []>,
    Sched<[WriteSTW]>;

def EXTPFX5 : ExtPrefixInst<5, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3, i32imm:$b4),
    "extpfx5", "$b0, $b1, $b2, $b3, $b4", []>,
    Sched<[WriteSTW]>;

def EXTPFX6 : ExtPrefixInst<6, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3, i32imm:$b4, i32imm:$b5),
    "extpfx6", "$b0, $b1, $b2, $b3, $b4, $b5", []>,
    Sched<[WriteSTW]>;

def EXTPFX7 : ExtPrefixInst<7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3, i32imm:$b4, i32imm:$b5, i32imm:$b6),
    "extpfx7", "$b0, $b1, $b2, $b3, $b4, $b5, $b6", []>,
    Sched<[WriteSTW]>;

def EXTPFX8 : ExtPrefixInst<8, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3,
         i32imm:$b4, i32imm:$b5, i32imm:$b6, i32imm:$b7),
    "extpfx8", "$b0, $b1, $b2, $b3, $b4, $b5, $b6, $b7", []>,
    Sched<[WriteSTW]>;

def EXTPFX9 : ExtPrefixInst<9, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3,
         i32imm:$b4, i32imm:$b5, i32imm:$b6, i32imm:$b7, i32imm:$b8),
    "extpfx9", "$b0, $b1, $b2, $b3, $b4, $b5, $b6, $b7, $b8", []>,
    Sched<[WriteSTW]>;

def EXTPFX10 : ExtPrefixInst<10, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$b3,
         i32imm:$b4, i32imm:$b5, i32imm:$b6, i32imm:$b7, i32imm:$b8, i32imm:$b9),
    "extpfx10", "$b0, $b1, $b2, $b3, $b4, $b5, $b6, $b7, $b8, $b9", []>,
    Sched<[WriteSTW]>;







} // hasSideEffects, mayLoad, mayStore
