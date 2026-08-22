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

// AsmOperandClass for parenthesized direct address (addr)
def DirectAddrAsmOperand : AsmOperandClass {
  let Name = "DirectAddr";
  let ParserMethod = "parseDirectAddrOperand";
}

// Direct address operand: (addr) — prints with parentheses, stored as immediate
def directaddr : Operand<i32> {
  let PrintMethod = "printDirectAddr";
  let ParserMatchClass = DirectAddrAsmOperand;
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

// SLA rd, #imm — Shift Left Arithmetic by immediate
// Encoding: E8+rd, 0xEC, amt (3 bytes)
def SLA32ri : PrefixShiftInst<0xEC, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "sla", "$rd, $imm",
                              [(set GPR:$rd, (shl GPR:$rs1, (i32 imm:$imm)))]>,
              Sched<[WriteShift, ReadIALU]>;

// SRA rd, #imm — Shift Right Arithmetic by immediate
// Encoding: E8+rd, 0xED, amt (3 bytes)
def SRA32ri : PrefixShiftInst<0xED, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "sra", "$rd, $imm",
                              [(set GPR:$rd, (sra GPR:$rs1, (i32 imm:$imm)))]>,
              Sched<[WriteShift, ReadIALU]>;

// SLL rd, #imm — Shift Left Logical (same result as SLA, different flags)
// Encoding: E8+rd, 0xEE, amt (3 bytes)
def SLL32ri : PrefixShiftInst<0xEE, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "sll", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// SRL rd, #imm — Shift Right Logical by immediate
// Encoding: E8+rd, 0xEF, amt (3 bytes)
def SRL32ri : PrefixShiftInst<0xEF, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                              "srl", "$rd, $imm",
                              [(set GPR:$rd, (srl GPR:$rs1, (i32 imm:$imm)))]>,
              Sched<[WriteShift, ReadIALU]>;

// Variable shift pseudos — expanded by custom inserter into:
//   COPY XWA, $rs2  (puts shift count in A register)
//   SLA_A_32 $rd    (shift $rd by A)
// Destination constrained to GPRnoXWA since A (part of XWA) holds the count.
let usesCustomInserter = 1, Defs = [XWA] in {
def SLA32rr : Pseudo<(outs GPRnoXWA:$rd), (ins GPRnoXWA:$rs1, GPR:$rs2),
                     [(set GPRnoXWA:$rd, (shl GPRnoXWA:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;
def SRA32rr : Pseudo<(outs GPRnoXWA:$rd), (ins GPRnoXWA:$rs1, GPR:$rs2),
                     [(set GPRnoXWA:$rd, (sra GPRnoXWA:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;
def SRL32rr : Pseudo<(outs GPRnoXWA:$rd), (ins GPRnoXWA:$rs1, GPR:$rs2),
                     [(set GPRnoXWA:$rd, (srl GPRnoXWA:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;
} // usesCustomInserter, Defs = [XWA]

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

} // Constraints = "$rd = $rs1", Defs = [SR]

// EXTS/EXTZ on 32-bit registers do NOT set flags on TLCS-900/H.
// Confirmed via MAME hardware emulation: op_EXTZLR and op_EXTSLR perform
// only the masking/sign-extension without modifying the status register.
let Constraints = "$rd = $rs1" in {

// EXTS rd — Sign extend: low 16 bits sign-extended to 32 bits
// Encoding: E8+rd, 0x13 (2 bytes)
def EXTS32 : PrefixUnaryInst<0x13, (outs GPR:$rd), (ins GPR:$rs1),
                             "exts", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

// EXTZ rd — Zero extend: low 16 bits zero-extended to 32 bits
// Encoding: E8+rd, 0x12 (2 bytes)
def EXTZ32 : PrefixUnaryInst<0x12, (outs GPR:$rd), (ins GPR:$rs1),
                             "extz", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

} // Constraints = "$rd = $rs1" (no Defs=[SR]: EXTS/EXTZ don't set flags)

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

// JP nn — Unconditional jump to 16-bit absolute address
// Encoding: 0x1A + addr16 (3 bytes)
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JP16 : Branch16Inst<0x1A, (outs), (ins i32imm:$target),
                         "jp16", "$target", []>,
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

// CALL nn — Function call to 16-bit absolute address
// Encoding: 0x1C + addr16 (3 bytes)
let isCall = 1 in
def CALL16 : Call16Inst<0x1C, (outs), (ins i32imm:$target),
                         "call16", "$target", []>,
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
def PUSH16_short : SingleByteRegInst<0x28, (outs), (ins GR16SP:$rs),
                                      "pushw", "$rs", []>,
                   Sched<[WritePush]>;

// POP rd16 — Short form: 0x48+r (1 byte)
let mayLoad = 1 in
def POP16_short : SingleByteRegInst<0x48, (outs GR16SP:$rd), (ins),
                                     "popw", "$rd", []>,
                  Sched<[WritePop]>;

// PUSH #imm8 — Push 8-bit immediate to stack
// Encoding: 0x09, imm8 (2 bytes)
let mayStore = 1 in
def PUSH_imm8 : SingleByteImm8Inst<0x09, (outs), (ins i32imm:$imm),
                                     "push", "$imm", []>,
                Sched<[WritePush]>;

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
                              "push\tsr", "", []>,
              Sched<[WritePush]>;

// POP SR — Pop status register (0x03, 1 byte)
let Defs = [XSP, SR], Uses = [XSP], hasSideEffects = 0, mayLoad = 1 in
def POP_SR : SingleByteInst<0x03, (outs), (ins),
                             "pop\tsr", "", []>,
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

// NORMAL — Exit MAX mode, return to normal operation
// Encoding: 0x01 (1 byte)
let hasSideEffects = 1 in
def NORMAL : SingleByteInst<0x01, (outs), (ins), "normal", "", []>,
             Sched<[WriteNop]>;

// MAX — Enter MAX mode (expands register file to 32-bit)
// Encoding: 0x04 (1 byte)
let hasSideEffects = 1 in
def MAX : SingleByteInst<0x04, (outs), (ins), "max", "", []>,
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

// LDF — Load register file (switch register bank)
// Encoding: 0x17, bank (2 bytes — opcode then bank number 0-3)
let hasSideEffects = 1 in
def LDF : SingleByteImm8Inst<0x17, (outs), (ins i32imm:$bank),
                             "ldf", "$bank", []>,
          Sched<[WriteNop]>;

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
// LINK / UNLK — Stack frame creation/destruction
//===----------------------------------------------------------------------===//

// LINK rd, #d16 — Push rd, copy XSP to rd, then subtract d16 from XSP.
// Encoding: E8+rd, 0x0C, d16_lo, d16_hi (4 bytes)
// Uses 32-bit prefix (E8) because it operates on 32-bit GPR registers.
let hasSideEffects = 1, mayStore = 1, Defs = [XSP],
    OpSize = OpSize32.Value in
def LINK : PrefixRegImmInst<0x0C, 4, (outs), (ins GPR:$reg, i32imm:$disp),
                             "link", "$reg, $disp", []>,
           Sched<[WriteSTW]>;

// UNLK rd — Copy rd to XSP, then pop rd from stack.
// Encoding: E8+rd, 0x0D (2 bytes)
// Uses 32-bit prefix (E8) because it operates on 32-bit GPR registers.
let hasSideEffects = 1, mayLoad = 1, Defs = [XSP],
    OpSize = OpSize32.Value in
def UNLK : PrefixUnaryInst<0x0D, (outs), (ins GPR:$reg),
                            "unlk", "$reg", []>,
           Sched<[WriteLDW]>;

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
                         "and", "$addr, $imm", []>,
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
                          "andw", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def OR16mi  : MemALUInst<0x3E, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "ormi16", "$addr, $imm", []>,
              Sched<[WriteLDW, ReadMemBase]>;
def ADD16mi : MemALUInst<0x38, 5, (outs), (ins MEMri:$addr, i16imm:$imm),
                          "addiw_da", "$addr, $imm", []>,
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
                            "bit", "$bit, $addr", []>,
           Sched<[WriteIALU, ReadMemBase]>;
let Defs = [SR] in
def LDCFm : MemDstBitOpInst<0x98, 2, (outs),
                              (ins MEMri:$addr, i32imm:$bit),
                              "ldcf", "$bit, $addr", []>,
            Sched<[WriteIALU, ReadMemBase]>;
} // mayLoad, hasSideEffects
let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
def SETm : MemDstBitOpInst<0xB8, 2, (outs),
                            (ins MEMri:$addr, i32imm:$bit),
                            "set", "$bit, $addr", []>,
           Sched<[WriteSTW, ReadMemBase]>;
def RESm : MemDstBitOpInst<0xB0, 2, (outs),
                            (ins MEMri:$addr, i32imm:$bit),
                            "res", "$bit, $addr", []>,
           Sched<[WriteSTW, ReadMemBase]>;
let Uses = [SR] in
def STCFm : MemDstBitOpInst<0xA0, 2, (outs),
                              (ins MEMri:$addr, i32imm:$bit),
                              "stcf", "$bit, $addr", []>,
            Sched<[WriteSTW, ReadMemBase]>;
def CHGm : MemDstBitOpInst<0xC0, 2, (outs),
                             (ins MEMri:$addr, i32imm:$bit),
                             "chgm", "$bit, $addr", []>,
           Sched<[WriteSTW, ReadMemBase]>;
let Defs = [SR] in
def TSETm : MemDstBitOpInst<0xA8, 2, (outs),
                              (ins MEMri:$addr, i32imm:$bit),
                              "tsetm", "$bit, $addr", []>,
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

// LDX — Load and eXchange: exchange (XDE)↔(XHL), increment both, decrement XBC
// Encoding: 0xF7 (1 byte) — NOT in the block transfer prefix group
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1,
    hasSideEffects = 0 in
def LDX : SingleByteInst<0xF7, (outs), (ins), "ldx", "", []>,
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
                                 (ins directaddr:$addr),
                                 "ldb_d8", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

// 16-bit loads from 16-bit address: D1 + addr16 + (0x20+reg)
let OpSize = OpSize16.Value in
def LD16_da16 : DirectSrcRegInst<0x20, 4, (outs GPR:$dst),
                                  (ins directaddr:$addr),
                                  "ldw_d16", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

// 32-bit loads from 16-bit address: E1 + addr16 + (0x20+reg)
let OpSize = OpSize32.Value in
def LD32_da16 : DirectSrcRegInst<0x20, 4, (outs GPR:$dst),
                                  (ins directaddr:$addr),
                                  "ldda32", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

// 8-bit loads from 24-bit address: C2 + addr24 + (0x20+reg)
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8_da24 : DirectSrcRegInst<0x20, 5, (outs GPR:$dst),
                                 (ins directaddr:$addr),
                                 "ldb_da", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

// 16-bit loads from 24-bit address: D2 + addr24 + (0x20+reg)
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16_da24 : DirectSrcRegInst<0x20, 5, (outs GPR:$dst),
                                  (ins directaddr:$addr),
                                  "ldw_da", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

// 32-bit loads from 24-bit address: E2 + addr24 + (0x20+reg)
let OpSize = OpSize32.Value, AddrWidth = 1 in
def LD32_da24 : DirectSrcRegInst<0x20, 5, (outs GPR:$dst),
                                  (ins directaddr:$addr),
                                  "ldl_da", "$dst, $addr", []>,
                Sched<[WriteLDW]>;

} // mayLoad, hasSideEffects

// GR8 variants for 8-bit LD reg8, (addr) — allows W, B, D, H (high-byte registers)
let mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def LD8_da16_r8 : DirectSrcRegInst<0x20, 4, (outs GR8:$dst),
                                     (ins directaddr:$addr),
                                     "ldb_d8", "$dst, $addr", []>,
                  Sched<[WriteLDW]>;
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8_da24_r8 : DirectSrcRegInst<0x20, 5, (outs GR8:$dst),
                                     (ins directaddr:$addr),
                                     "ldb_da", "$dst, $addr", []>,
                  Sched<[WriteLDW]>;
} // mayLoad, hasSideEffects

// GR16 variants for 16-bit LD reg16, (addr) — allows all 16-bit register names
let mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize16.Value in
def LD16_da16_r16 : DirectSrcRegInst<0x20, 4, (outs GR16:$dst),
                                       (ins directaddr:$addr),
                                       "ldw_d16", "$dst, $addr", []>,
                    Sched<[WriteLDW]>;
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16_da24_r16 : DirectSrcRegInst<0x20, 5, (outs GR16:$dst),
                                       (ins directaddr:$addr),
                                       "ldw_da", "$dst, $addr", []>,
                    Sched<[WriteLDW]>;
} // mayLoad, hasSideEffects

// GR8 variants for 8-bit ALU reg8, (addr16) — load direction
let Defs = [SR], mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
let Constraints = "$dst = $src1" in {
def ADD8_da16_r8 : DirectSrcRegInst<0x80, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, directaddr:$addr),
                                      "addda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def SUB8_da16_r8 : DirectSrcRegInst<0xA0, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, directaddr:$addr),
                                      "subda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def AND8_da16_r8 : DirectSrcRegInst<0xC0, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, directaddr:$addr),
                                      "andda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def XOR8_da16_r8 : DirectSrcRegInst<0xD0, 4, (outs GR8:$dst),
                                      (ins GR8:$src1, directaddr:$addr),
                                      "xorda8", "$dst, $addr", []>,
                   Sched<[WriteIALU, ReadIALU]>;
def OR8_da16_r8 : DirectSrcRegInst<0xE0, 4, (outs GR8:$dst),
                                     (ins GR8:$src1, directaddr:$addr),
                                     "orda8", "$dst, $addr", []>,
                  Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP8_da16_r8 : DirectSrcRegInst<0xF0, 4, (outs),
                                     (ins GR8:$src, directaddr:$addr),
                                     "cpda8", "$src, $addr", []>,
                  Sched<[WriteIALU, ReadIALU]>;
} // OpSize8
} // Defs, mayLoad, hasSideEffects

// GR8 variants for 8-bit ALU (addr16), reg8 — store direction
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def ADD8m_da16_r8 : DirectSrcRegInst<0x88, 4, (outs),
                                       (ins directaddr:$addr, GR8:$src),
                                       "adddm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
def SUB8m_da16_r8 : DirectSrcRegInst<0xA8, 4, (outs),
                                       (ins directaddr:$addr, GR8:$src),
                                       "subdm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
def AND8m_da16_r8 : DirectSrcRegInst<0xC8, 4, (outs),
                                       (ins directaddr:$addr, GR8:$src),
                                       "anddm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
def OR8m_da16_r8 : DirectSrcRegInst<0xE8, 4, (outs),
                                      (ins directaddr:$addr, GR8:$src),
                                      "orddm8", "$addr, $src", []>,
                   Sched<[WriteSTW, ReadIALU]>;
def XOR8m_da16_r8 : DirectSrcRegInst<0xD8, 4, (outs),
                                       (ins directaddr:$addr, GR8:$src),
                                       "xordm8", "$addr, $src", []>,
                    Sched<[WriteSTW, ReadIALU]>;
} // OpSize8
} // Defs, mayLoad, mayStore, hasSideEffects

// GR8 variants for 8-bit CP (addr16), reg8 — store direction compare
let Defs = [SR], mayLoad = 1, isCompare = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def CP8m_da16_r8 : DirectSrcRegInst<0xF8, 4, (outs),
                                      (ins directaddr:$addr, GR8:$src),
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
                                  (ins GPR:$src1, directaddr:$addr),
                                  "addda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def SUB8_da16 : DirectSrcRegInst<0xA0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, directaddr:$addr),
                                  "subda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def AND8_da16 : DirectSrcRegInst<0xC0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, directaddr:$addr),
                                  "andda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def XOR8_da16 : DirectSrcRegInst<0xD0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, directaddr:$addr),
                                  "xorda8", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def OR8_da16 : DirectSrcRegInst<0xE0, 4, (outs GPR:$dst),
                                 (ins GPR:$src1, directaddr:$addr),
                                 "orda8", "$dst, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP8_da16 : DirectSrcRegInst<0xF0, 4, (outs),
                                 (ins GPR:$src, directaddr:$addr),
                                 "cpda8", "$src, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
} // OpSize8
let OpSize = OpSize16.Value in {
let Constraints = "$dst = $src1" in {
def ADD16_da16 : DirectSrcRegInst<0x80, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "addda16", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB16_da16 : DirectSrcRegInst<0xA0, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "subda16", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def AND16_da16 : DirectSrcRegInst<0xC0, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "andda16", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def OR16_da16 : DirectSrcRegInst<0xE0, 4, (outs GPR:$dst),
                                  (ins GPR:$src1, directaddr:$addr),
                                  "orda16", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP16_da16 : DirectSrcRegInst<0xF0, 4, (outs),
                                  (ins GPR:$src, directaddr:$addr),
                                  "cpda16", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // OpSize16
} // Defs, mayLoad, hasSideEffects

// ALU (addr16), reg — result to memory (store direction, sub-opc base + 8)
// ADD=0x88, ADC=0x98, SUB=0xA8, SBC=0xB8, AND=0xC8, XOR=0xD8, OR=0xE8, CP=0xF8
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def ADD8m_da16 : DirectSrcRegInst<0x88, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "adddm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def SUB8m_da16 : DirectSrcRegInst<0xA8, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "subdm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def AND8m_da16 : DirectSrcRegInst<0xC8, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "anddm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def OR8m_da16 : DirectSrcRegInst<0xE8, 4, (outs),
                                  (ins directaddr:$addr, GPR:$src),
                                  "orddm8", "$addr, $src", []>,
                Sched<[WriteSTW, ReadIALU]>;
def XOR8m_da16 : DirectSrcRegInst<0xD8, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "xordm8", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def ADD16m_da16 : DirectSrcRegInst<0x88, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "adddm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def SUB16m_da16 : DirectSrcRegInst<0xA8, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "subdm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def AND16m_da16 : DirectSrcRegInst<0xC8, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "anddm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def OR16m_da16 : DirectSrcRegInst<0xE8, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "orddm16", "$addr, $src", []>,
                 Sched<[WriteSTW, ReadIALU]>;
def XOR16m_da16 : DirectSrcRegInst<0xD8, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "xordm16", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
} // OpSize16
let OpSize = OpSize32.Value in {
def ADD32m_da16 : DirectSrcRegInst<0x88, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "adddm32", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
def SUB32m_da16 : DirectSrcRegInst<0xA8, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "subdm32", "$addr, $src", []>,
                  Sched<[WriteSTW, ReadIALU]>;
} // OpSize32
} // Defs, mayLoad, mayStore, hasSideEffects

// CP (addr16), reg — store direction compare (no write, just flags)
let Defs = [SR], mayLoad = 1, isCompare = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def CP8m_da16 : DirectSrcRegInst<0xF8, 4, (outs),
                                  (ins directaddr:$addr, GPR:$src),
                                  "cpdm8", "$addr, $src", []>,
                Sched<[WriteIALU, ReadIALU]>;
let OpSize = OpSize16.Value in
def CP16m_da16 : DirectSrcRegInst<0xF8, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "cpdm16", "$addr, $src", []>,
                 Sched<[WriteIALU, ReadIALU]>;
let OpSize = OpSize32.Value in
def CP32m_da16 : DirectSrcRegInst<0xF8, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "cpdm32", "$addr, $src", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Defs, mayLoad, isCompare, hasSideEffects

// 32-bit ALU reg, (addr16) — load direction
let Defs = [SR], mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize32.Value in {
let Constraints = "$dst = $src1" in {
def ADD32_da16 : DirectSrcRegInst<0x80, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "addda32", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB32_da16 : DirectSrcRegInst<0xA0, 4, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "subda32", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP32_da16 : DirectSrcRegInst<0xF0, 4, (outs),
                                  (ins GPR:$src, directaddr:$addr),
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
                                   (ins directaddr:$addr, i8imm:$val),
                                   "adddi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def SUB8i_da16 : DirectSrcImmInst<0x3A, 5, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "subdi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def AND8i_da16 : DirectSrcImmInst<0x3C, 5, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "anddi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def XOR8i_da16 : DirectSrcImmInst<0x3D, 5, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "xordi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def OR8i_da16 : DirectSrcImmInst<0x3E, 5, (outs),
                                  (ins directaddr:$addr, i8imm:$val),
                                  "ordi8", "$addr, $val", []>,
                Sched<[WriteSTW]>;
} // OpSize8

let isCompare = 1, mayStore = 0 in {
let OpSize = OpSize8.Value in
def CP8i_da16 : DirectSrcImmInst<0x3F, 5, (outs),
                                  (ins directaddr:$addr, i8imm:$val),
                                  "cpdi8", "$addr, $val", []>,
                Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def CP16i_da16 : DirectSrcImmInst<0x3F, 6, (outs),
                                   (ins directaddr:$addr, i16imm:$val),
                                   "cpdi16", "$addr, $val", []>,
                 Sched<[WriteIALU]>;
} // isCompare, mayStore

// 16-bit ALU (addr16), #imm16
let OpSize = OpSize16.Value in {
def ADD16i_da16 : DirectSrcImmInst<0x38, 6, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "adddi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def SUB16i_da16 : DirectSrcImmInst<0x3A, 6, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "subdi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def AND16i_da16 : DirectSrcImmInst<0x3C, 6, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "anddi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def OR16i_da16 : DirectSrcImmInst<0x3E, 6, (outs),
                                   (ins directaddr:$addr, i16imm:$val),
                                   "ordi16", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
} // OpSize16

// 24-bit address ALU (addr24), #imm — C2/D2 prefix
let isCompare = 1, mayStore = 0 in {
let OpSize = OpSize16.Value, AddrWidth = 1 in
def CP16i_da24 : DirectSrcImmInst<0x3F, 7, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "cpw_da", "$addr, $val", []>,
                 Sched<[WriteIALU]>;
} // isCompare, mayStore
let OpSize = OpSize16.Value, AddrWidth = 1 in {
def ADD16i_da24 : DirectSrcImmInst<0x38, 7, (outs),
                                     (ins directaddr:$addr, i16imm:$val),
                                     "adddi16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def SUB16i_da24 : DirectSrcImmInst<0x3A, 7, (outs),
                                     (ins directaddr:$addr, i16imm:$val),
                                     "subdi16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
} // OpSize16, AddrWidth

// 24-bit address ALU reg, (addr24) — load direction
let OpSize = OpSize16.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def ADD16_da24 : DirectSrcRegInst<0x80, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "addda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB16_da24 : DirectSrcRegInst<0xA0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "subda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP16_da24 : DirectSrcRegInst<0xF0, 5, (outs),
                                   (ins GPR:$src, directaddr:$addr),
                                   "cpda16_24", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
// 16-bit additional load-direction
let Constraints = "$dst = $src1" in {
def AND16_da24 : DirectSrcRegInst<0xC0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "andda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def XOR16_da24 : DirectSrcRegInst<0xD0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "xorda16_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def OR16_da24 : DirectSrcRegInst<0xE0, 5, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "orda16_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // Constraints
// 16-bit store-direction: ALU (addr24), reg
let Constraints = "" in {
def ADD16m_da24 : DirectSrcRegInst<0x88, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "adddm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def SUB16m_da24 : DirectSrcRegInst<0xA8, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "subdm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def AND16m_da24 : DirectSrcRegInst<0xC8, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "anddm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def XOR16m_da24 : DirectSrcRegInst<0xD8, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "xordm16_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def OR16m_da24 : DirectSrcRegInst<0xE8, 5, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "ordm16_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def CP16m_da24 : DirectSrcRegInst<0xF8, 5, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "cpdm16_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
} // Constraints
// 16-bit additional imm
def AND16i_da24 : DirectSrcImmInst<0x3C, 7, (outs),
                                     (ins directaddr:$addr, i16imm:$val),
                                     "anddi16_24", "$addr, $val", []>,
                  Sched<[WriteSTW]>;
def OR16i_da24 : DirectSrcImmInst<0x3E, 7, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "ordi16_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
} // OpSize16, AddrWidth

// 24-bit address: 16-bit ALU with GR16 register class (wa, bc, de, hl, ix, iy, iz)
let OpSize = OpSize16.Value, AddrWidth = 1 in {
// Load direction: reg = reg OP (addr24)
let Constraints = "$dst = $src1" in {
def ADD16_da24_r16 : DirectSrcRegInst<0x80, 5, (outs GR16:$dst),
                                        (ins GR16:$src1, directaddr:$addr),
                                        "addda16_24", "$dst, $addr", []>,
                     Sched<[WriteIALU, ReadIALU]>;
def SUB16_da24_r16 : DirectSrcRegInst<0xA0, 5, (outs GR16:$dst),
                                        (ins GR16:$src1, directaddr:$addr),
                                        "subda16_24", "$dst, $addr", []>,
                     Sched<[WriteIALU, ReadIALU]>;
def AND16_da24_r16 : DirectSrcRegInst<0xC0, 5, (outs GR16:$dst),
                                        (ins GR16:$src1, directaddr:$addr),
                                        "andda16_24", "$dst, $addr", []>,
                     Sched<[WriteIALU, ReadIALU]>;
def XOR16_da24_r16 : DirectSrcRegInst<0xD0, 5, (outs GR16:$dst),
                                        (ins GR16:$src1, directaddr:$addr),
                                        "xorda16_24", "$dst, $addr", []>,
                     Sched<[WriteIALU, ReadIALU]>;
def OR16_da24_r16 : DirectSrcRegInst<0xE0, 5, (outs GR16:$dst),
                                       (ins GR16:$src1, directaddr:$addr),
                                       "orda16_24", "$dst, $addr", []>,
                    Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP16_da24_r16 : DirectSrcRegInst<0xF0, 5, (outs),
                                       (ins GR16:$src, directaddr:$addr),
                                       "cpda16_24", "$src, $addr", []>,
                    Sched<[WriteIALU, ReadIALU]>;
// Store direction: (addr24) = (addr24) OP reg
let Constraints = "" in {
def ADD16m_da24_r16 : DirectSrcRegInst<0x88, 5, (outs),
                                         (ins directaddr:$addr, GR16:$src),
                                         "adddm16_24", "$addr, $src", []>,
                      Sched<[WriteSTW]>;
def SUB16m_da24_r16 : DirectSrcRegInst<0xA8, 5, (outs),
                                         (ins directaddr:$addr, GR16:$src),
                                         "subdm16_24", "$addr, $src", []>,
                      Sched<[WriteSTW]>;
def AND16m_da24_r16 : DirectSrcRegInst<0xC8, 5, (outs),
                                         (ins directaddr:$addr, GR16:$src),
                                         "anddm16_24", "$addr, $src", []>,
                      Sched<[WriteSTW]>;
def XOR16m_da24_r16 : DirectSrcRegInst<0xD8, 5, (outs),
                                         (ins directaddr:$addr, GR16:$src),
                                         "xordm16_24", "$addr, $src", []>,
                      Sched<[WriteSTW]>;
def OR16m_da24_r16 : DirectSrcRegInst<0xE8, 5, (outs),
                                        (ins directaddr:$addr, GR16:$src),
                                        "ordm16_24", "$addr, $src", []>,
                     Sched<[WriteSTW]>;
def CP16m_da24_r16 : DirectSrcRegInst<0xF8, 5, (outs),
                                        (ins directaddr:$addr, GR16:$src),
                                        "cpdm16_24", "$addr, $src", []>,
                     Sched<[WriteSTW]>;
} // Constraints
} // OpSize16, AddrWidth

// 24-bit address: 32-bit store and additional load operations
let OpSize = OpSize32.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def AND32_da24 : DirectSrcRegInst<0xC0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "andda32_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def OR32_da24 : DirectSrcRegInst<0xE0, 5, (outs GPR:$dst),
                                   (ins GPR:$src1, directaddr:$addr),
                                   "orda32_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // Constraints
// 32-bit store-direction
let Constraints = "" in {
def ADD32m_da24 : DirectSrcRegInst<0x88, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "addl_da", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def SUB32m_da24 : DirectSrcRegInst<0xA8, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "subdm32_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def AND32m_da24 : DirectSrcRegInst<0xC8, 5, (outs),
                                     (ins directaddr:$addr, GPR:$src),
                                     "anddm32_24", "$addr, $src", []>,
                  Sched<[WriteSTW]>;
def OR32m_da24 : DirectSrcRegInst<0xE8, 5, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "ordm32_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def CP32m_da24 : DirectSrcRegInst<0xF8, 5, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "cpdm32_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
} // Constraints
} // OpSize32, AddrWidth

// 24-bit address: ALL ALU (addr24), #imm for C2 (8-bit)
let OpSize = OpSize8.Value, AddrWidth = 1 in {
def ADD8i_da24 : DirectSrcImmInst<0x38, 6, (outs),
                                    (ins directaddr:$addr, i8imm:$val),
                                    "adddi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def ADC8i_da24 : DirectSrcImmInst<0x39, 6, (outs),
                                    (ins directaddr:$addr, i8imm:$val),
                                    "addci8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def SUB8i_da24 : DirectSrcImmInst<0x3A, 6, (outs),
                                    (ins directaddr:$addr, i8imm:$val),
                                    "subdi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def SBC8i_da24 : DirectSrcImmInst<0x3B, 6, (outs),
                                    (ins directaddr:$addr, i8imm:$val),
                                    "sbcdi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def AND8i_da24 : DirectSrcImmInst<0x3C, 6, (outs),
                                    (ins directaddr:$addr, i8imm:$val),
                                    "anddi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def XOR8i_da24 : DirectSrcImmInst<0x3D, 6, (outs),
                                    (ins directaddr:$addr, i8imm:$val),
                                    "xordi8_24", "$addr, $val", []>,
                 Sched<[WriteSTW]>;
def OR8i_da24 : DirectSrcImmInst<0x3E, 6, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "ordi8_24", "$addr, $val", []>,
                Sched<[WriteSTW]>;
} // OpSize8, AddrWidth
let isCompare = 1, mayStore = 0, OpSize = OpSize8.Value, AddrWidth = 1 in
def CP8i_da24 : DirectSrcImmInst<0x3F, 6, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "cpib_da", "$addr, $val", []>,
                Sched<[WriteIALU]>;

// 24-bit address: ALU reg, (addr24) — load direction for C2 (8-bit)
let OpSize = OpSize8.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def ADD8_da24 : DirectSrcRegInst<0x80, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, directaddr:$addr),
                                   "addda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def ADC8_da24 : DirectSrcRegInst<0x90, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, directaddr:$addr),
                                   "addcda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def SUB8_da24 : DirectSrcRegInst<0xA0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, directaddr:$addr),
                                   "subda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def SBC8_da24 : DirectSrcRegInst<0xB0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, directaddr:$addr),
                                   "sbcda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def AND8_da24 : DirectSrcRegInst<0xC0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, directaddr:$addr),
                                   "andda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def XOR8_da24 : DirectSrcRegInst<0xD0, 5, (outs GR8:$dst),
                                   (ins GR8:$src1, directaddr:$addr),
                                   "xorda8_24", "$dst, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
def OR8_da24 : DirectSrcRegInst<0xE0, 5, (outs GR8:$dst),
                                  (ins GR8:$src1, directaddr:$addr),
                                  "orda8_24", "$dst, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP8_da24 : DirectSrcRegInst<0xF0, 5, (outs),
                                  (ins GR8:$src, directaddr:$addr),
                                  "cpda8_24", "$src, $addr", []>,
               Sched<[WriteIALU, ReadIALU]>;
// Store direction (result to memory): ALU (addr24), reg
let Constraints = "" in {
def ADD8m_da24 : DirectSrcRegInst<0x88, 5, (outs),
                                    (ins directaddr:$addr, GR8:$src),
                                    "adddm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def SUB8m_da24 : DirectSrcRegInst<0xA8, 5, (outs),
                                    (ins directaddr:$addr, GR8:$src),
                                    "subdm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def AND8m_da24 : DirectSrcRegInst<0xC8, 5, (outs),
                                    (ins directaddr:$addr, GR8:$src),
                                    "anddm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def XOR8m_da24 : DirectSrcRegInst<0xD8, 5, (outs),
                                    (ins directaddr:$addr, GR8:$src),
                                    "xordm8_24", "$addr, $src", []>,
                 Sched<[WriteSTW]>;
def OR8m_da24 : DirectSrcRegInst<0xE8, 5, (outs),
                                   (ins directaddr:$addr, GR8:$src),
                                   "ordm8_24", "$addr, $src", []>,
                Sched<[WriteSTW]>;
def CP8m_da24 : DirectSrcRegInst<0xF8, 5, (outs),
                                   (ins directaddr:$addr, GR8:$src),
                                   "cpdm8_24", "$addr, $src", []>,
                Sched<[WriteSTW]>;
} // Constraints
} // OpSize8, AddrWidth

// 24-bit address: ALU reg, (addr24) — load direction for E2 (32-bit)
let OpSize = OpSize32.Value, AddrWidth = 1 in {
let Constraints = "$dst = $src1" in {
def ADD32_da24 : DirectSrcRegInst<0x80, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "addda32_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
def SUB32_da24 : DirectSrcRegInst<0xA0, 5, (outs GPR:$dst),
                                    (ins GPR:$src1, directaddr:$addr),
                                    "sub32_24", "$dst, $addr", []>,
                 Sched<[WriteIALU, ReadIALU]>;
} // Constraints
def CP32_da24 : DirectSrcRegInst<0xF0, 5, (outs),
                                   (ins GPR:$src, directaddr:$addr),
                                   "cpda32_24", "$src, $addr", []>,
                Sched<[WriteIALU, ReadIALU]>;
} // OpSize32, AddrWidth

// 24-bit address: INC/DEC via C2/D2 prefix
let AddrWidth = 1 in {
let OpSize = OpSize8.Value in {
def INC8_da24 : DirectSrcIncDecInst<0x60, 5, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "incdi8_24", "$count, $addr", []>,
                Sched<[WriteSTW]>;
def DEC8_da24 : DirectSrcIncDecInst<0x68, 5, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "decdi8_24", "$count, $addr", []>,
                Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_da24 : DirectSrcIncDecInst<0x60, 5, (outs),
                                       (ins directaddr:$addr, i32imm:$count),
                                       "incdi16_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC16_da24 : DirectSrcIncDecInst<0x68, 5, (outs),
                                       (ins directaddr:$addr, i32imm:$count),
                                       "decdi16_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize16
} // AddrWidth

} // Defs, mayLoad, mayStore, hasSideEffects

// 24-bit address PUSH via D2 prefix (source prefix, 16-bit data)
let mayLoad = 1, hasSideEffects = 0, Uses = [XSP], Defs = [XSP] in {
let OpSize = OpSize16.Value, AddrWidth = 1 in
def PUSH_da24 : DirectSrcPushInst<0x04, 5, (outs),
                                    (ins directaddr:$addr),
                                    "pushdi_24", "$addr", []>,
                Sched<[WriteSTW]>;
} // mayLoad, hasSideEffects, Uses, Defs

// 24-bit address BIT/SET/RES/CHG/TSET via F2 prefix
let mayLoad = 1, hasSideEffects = 0 in {
let AddrWidth = 1 in
def BIT_da24 : DirectDstBitOpInst<0xC8, 5, (outs),
                                    (ins directaddr:$addr, i32imm:$bit),
                                    "bitda_24", "$bit, $addr", []>,
               Sched<[WriteIALU]>;
} // mayLoad, hasSideEffects

let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let AddrWidth = 1 in {
def SET_da24 : DirectDstBitOpInst<0xB8, 5, (outs),
                                    (ins directaddr:$addr, i32imm:$bit),
                                    "setda_24", "$bit, $addr", []>,
               Sched<[WriteSTW]>;
def RES_da24 : DirectDstBitOpInst<0xB0, 5, (outs),
                                    (ins directaddr:$addr, i32imm:$bit),
                                    "resda_24", "$bit, $addr", []>,
               Sched<[WriteSTW]>;
def CHG_da24 : DirectDstBitOpInst<0xC0, 5, (outs),
                                    (ins directaddr:$addr, i32imm:$bit),
                                    "chgda_24", "$bit, $addr", []>,
               Sched<[WriteSTW]>;
def TSET_da24 : DirectDstBitOpInst<0xA0, 5, (outs),
                                     (ins directaddr:$addr, i32imm:$bit),
                                     "tsetda_24", "$bit, $addr", []>,
                Sched<[WriteSTW]>;
} // AddrWidth
} // mayLoad, mayStore, hasSideEffects

// 24-bit address: INC/DEC/INCW/DECW via F2 prefix
let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let AddrWidth = 1 in {
let OpSize = OpSize8.Value in {
def INC8_dda24 : DirectDstBitOpInst<0x60, 5, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "incdd8_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC8_dda24 : DirectDstBitOpInst<0x68, 5, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "decdd8_24", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_dda24 : DirectDstBitOpInst<0x60, 5, (outs),
                                       (ins directaddr:$addr, i32imm:$count),
                                       "incdd16_24", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
def DEC16_dda24 : DirectDstBitOpInst<0x68, 5, (outs),
                                       (ins directaddr:$addr, i32imm:$count),
                                       "decdd16_24", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
} // OpSize16
} // AddrWidth
} // Defs, mayLoad, mayStore, hasSideEffects

// F2 conditional CALL: F2 + addr24 + (0xE0+cc) — 5 bytes
let isCall = 1, Defs = [XSP], Uses = [XSP], hasSideEffects = 0, AddrWidth = 1 in
def CALLCC_24 : DirectDstBitOpInst<0xE0, 5, (outs),
                                     (ins directaddr:$addr, cc:$cc),
                                     "call_24", "$cc, $addr", []>,
                Sched<[WriteJmp]>;

// F2 conditional JP: F2 + addr24 + (0xD0+cc) — 5 bytes
let isBranch = 1, isTerminator = 1, hasSideEffects = 0, AddrWidth = 1 in
def JPCC_24 : DirectDstBitOpInst<0xD0, 5, (outs),
                                    (ins directaddr:$addr, cc:$cc),
                                    "jp_24", "$cc, $addr", []>,
              Sched<[WriteJmp]>;

//--- Source direct: INC/DEC (addr) — sub-opcode 0x60+count / 0x68+count ---

let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def INC8_da16 : DirectSrcIncDecInst<0x60, 4, (outs),
                                     (ins directaddr:$addr, i32imm:$count),
                                     "incdi8", "$count, $addr", []>,
                Sched<[WriteSTW]>;
def DEC8_da16 : DirectSrcIncDecInst<0x68, 4, (outs),
                                     (ins directaddr:$addr, i32imm:$count),
                                     "decdi8", "$count, $addr", []>,
                Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_da16 : DirectSrcIncDecInst<0x60, 4, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "incdi16", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC16_da16 : DirectSrcIncDecInst<0x68, 4, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "decdi16", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize16
} // Defs, mayLoad, mayStore, hasSideEffects

//--- Destination direct: LD (addr), reg — sub-opcode 0x40+reg8 / 0x50+reg16 ---

let mayStore = 1, hasSideEffects = 0 in {

// 8-bit stores to 16-bit address: F1 + addr16 + (0x40+reg8)
let OpSize = OpSize8.Value in
def LD8m_da16 : DirectDstRegInst<0x40, 4, (outs),
                                  (ins directaddr:$addr, GPR:$src),
                                  "stb_d8", "$addr, $src", []>,
                Sched<[WriteSTW]>;

// 16-bit stores to 16-bit address: F1 + addr16 + (0x50+reg16)
let OpSize = OpSize16.Value in
def LD16m_da16 : DirectDstRegInst<0x50, 4, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "stda16", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

// 8-bit stores to 24-bit address: F2 + addr24 + (0x40+reg8)
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8m_da24 : DirectDstRegInst<0x40, 5, (outs),
                                  (ins directaddr:$addr, GPR:$src),
                                  "stb_da", "$addr, $src", []>,
                Sched<[WriteSTW]>;

// 16-bit stores to 24-bit address: F2 + addr24 + (0x50+reg16)
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16m_da24 : DirectDstRegInst<0x50, 5, (outs),
                                   (ins directaddr:$addr, GPR:$src),
                                   "stw_da", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

} // mayStore, hasSideEffects

// 32-bit stores to 16-bit address: F1 + addr16 + (0x60+reg32)
let OpSize = OpSize32.Value in
def LD32m_da16 : DirectDstRegInst<0x60, 4, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "stda32", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

// 32-bit stores to 24-bit address: F2 + addr24 + (0x60+reg32)
let OpSize = OpSize32.Value, AddrWidth = 1 in
def LD32m_da24 : DirectDstRegInst<0x60, 5, (outs),
                                    (ins directaddr:$addr, GPR:$src),
                                    "stl_da", "$addr, $src", []>,
                 Sched<[WriteSTW]>;

// GR8 variants for 8-bit stores LD (addr), reg8 — allows W, B, D, H
let mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def LD8m_da16_r8 : DirectDstRegInst<0x40, 4, (outs),
                                      (ins directaddr:$addr, GR8:$src),
                                      "stb_d8", "$addr, $src", []>,
                   Sched<[WriteSTW]>;
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8m_da24_r8 : DirectDstRegInst<0x40, 5, (outs),
                                      (ins directaddr:$addr, GR8:$src),
                                      "stb_da", "$addr, $src", []>,
                   Sched<[WriteSTW]>;
} // mayStore, hasSideEffects

// GR16 variants for 16-bit stores LD (addr), reg16 — allows all 16-bit register names
let mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize16.Value in
def LD16m_da16_r16 : DirectDstRegInst<0x50, 4, (outs),
                                        (ins directaddr:$addr, GR16:$src),
                                        "stda16", "$addr, $src", []>,
                     Sched<[WriteSTW]>;
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16m_da24_r16 : DirectDstRegInst<0x50, 5, (outs),
                                        (ins directaddr:$addr, GR16:$src),
                                        "stw_da", "$addr, $src", []>,
                     Sched<[WriteSTW]>;
} // mayStore, hasSideEffects

//--- Destination direct: LD (addr), #imm — sub-opcode 0x00 (byte) / 0x02 (word) ---

let mayStore = 1, hasSideEffects = 0 in {

// 8-bit store imm to 16-bit address: F1 + addr16 + 0x00 + imm8
let OpSize = OpSize8.Value in
def LD8mi_da16 : DirectDstImmInst<0x00, 5, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "stdi8", "$addr, $val", []>,
                 Sched<[WriteSTW]>;

// 16-bit store imm to 16-bit address: F1 + addr16 + 0x02 + imm16
let OpSize = OpSize16.Value in
def LD16mi_da16 : DirectDstImmInst<0x02, 6, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "stdi16", "$addr, $val", []>,
                  Sched<[WriteSTW]>;

// 8-bit store imm to 24-bit address: F2 + addr24 + 0x00 + imm8
let OpSize = OpSize8.Value, AddrWidth = 1 in
def LD8mi_da24 : DirectDstImmInst<0x00, 6, (outs),
                                   (ins directaddr:$addr, i8imm:$val),
                                   "stib_da", "$addr, $val", []>,
                 Sched<[WriteSTW]>;

// 16-bit store imm to 24-bit address: F2 + addr24 + 0x02 + imm16
let OpSize = OpSize16.Value, AddrWidth = 1 in
def LD16mi_da24 : DirectDstImmInst<0x02, 7, (outs),
                                    (ins directaddr:$addr, i16imm:$val),
                                    "stiw_da", "$addr, $val", []>,
                  Sched<[WriteSTW]>;

} // mayStore, hasSideEffects

//--- Destination direct: LDA reg, addr — sub-opcode 0x30+reg32 ---

let mayLoad = 0, mayStore = 0, hasSideEffects = 0 in {

// LDA to 16-bit address: F1 + addr16 + (0x30+reg32)
let OpSize = OpSize32.Value in
def LDA_da16 : DirectDstRegInst<0x30, 4, (outs GPR:$dst),
                                 (ins directaddr:$addr),
                                 "lda_d16", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

// LDA to 24-bit address: F2 + addr24 + (0x30+reg32)
let OpSize = OpSize32.Value, AddrWidth = 1 in
def LDA_da24 : DirectDstRegInst<0x30, 5, (outs GPR:$dst),
                                 (ins directaddr:$addr),
                                 "lda_24", "$dst, $addr", []>,
               Sched<[WriteLDW]>;

} // mayLoad, mayStore, hasSideEffects

//--- Destination direct: BIT/SET/RES (addr) — sub-opcode base + bit ---
// BIT: 0xC8+bit, SET: 0xB8+bit, RES: 0xB0+bit

let mayLoad = 1, hasSideEffects = 0 in {

// BIT from 16-bit address: F1 + addr16 + (0xC8+bit)
def BIT_da16 : DirectDstBitOpInst<0xC8, 4, (outs),
                                   (ins directaddr:$addr, i32imm:$bit),
                                   "bitda", "$bit, $addr", []>,
               Sched<[WriteIALU]>;

} // mayLoad, hasSideEffects

let mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {

// SET from 16-bit address: F1 + addr16 + (0xB8+bit)
def SET_da16 : DirectDstBitOpInst<0xB8, 4, (outs),
                                   (ins directaddr:$addr, i32imm:$bit),
                                   "setda", "$bit, $addr", []>,
               Sched<[WriteSTW]>;

// RES from 16-bit address: F1 + addr16 + (0xB0+bit)
def RES_da16 : DirectDstBitOpInst<0xB0, 4, (outs),
                                   (ins directaddr:$addr, i32imm:$bit),
                                   "resda", "$bit, $addr", []>,
               Sched<[WriteSTW]>;

// TSET from 16-bit address: F1 + addr16 + (0xA0+bit)
def TSET_da16 : DirectDstBitOpInst<0xA0, 4, (outs),
                                    (ins directaddr:$addr, i32imm:$bit),
                                    "tsetda", "$bit, $addr", []>,
                Sched<[WriteSTW]>;

} // mayLoad, mayStore, hasSideEffects

//--- Destination direct: INC/DEC (addr) via F1 prefix ---
// INC: 0x60+count, DEC: 0x68+count (same sub-opcode as source, but via F1 prefix)

let Defs = [SR], mayLoad = 1, mayStore = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in {
def INC8_dda16 : DirectDstBitOpInst<0x60, 4, (outs),
                                     (ins directaddr:$addr, i32imm:$count),
                                     "incdd8", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
def DEC8_dda16 : DirectDstBitOpInst<0x68, 4, (outs),
                                     (ins directaddr:$addr, i32imm:$count),
                                     "decdd8", "$count, $addr", []>,
                 Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def INC16_dda16 : DirectDstBitOpInst<0x60, 4, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
                                      "incdd16", "$count, $addr", []>,
                  Sched<[WriteSTW]>;
def DEC16_dda16 : DirectDstBitOpInst<0x68, 4, (outs),
                                      (ins directaddr:$addr, i32imm:$count),
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

// ANDCF A,r — AND carry flag with bit A of register (2 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def ANDCF_A_8 : PrefixUnaryInst<0x28, (outs), (ins GR8:$rs1),
    "andcf_a_8", "$rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def ANDCF_A_16 : PrefixUnaryInst<0x28, (outs), (ins GR16:$rs1),
    "andcf_a_16", "$rs1", []>, Sched<[WriteIALU]>;
}

// ORCF A,r — OR carry flag with bit A of register (2 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def ORCF_A_8 : PrefixUnaryInst<0x29, (outs), (ins GR8:$rs1),
    "orcf_a_8", "$rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def ORCF_A_16 : PrefixUnaryInst<0x29, (outs), (ins GR16:$rs1),
    "orcf_a_16", "$rs1", []>, Sched<[WriteIALU]>;
}

// STCF bit#,r — Store carry flag to bit# of register (3 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def STCF8ri : PrefixRegImmInst<0x24, 3, (outs), (ins GR8:$rs1, i32imm:$bit),
    "stcf8ri", "$bit, $rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def STCF16ri : PrefixRegImmInst<0x24, 3, (outs), (ins GR16:$rs1, i32imm:$bit),
    "stcf16ri", "$bit, $rs1", []>, Sched<[WriteIALU]>;
}

// LDCF bit#,r — Load carry from bit# of register (3 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def LDCF8ri : PrefixRegImmInst<0x23, 3, (outs), (ins GR8:$rs1, i32imm:$bit),
    "ldcf8ri", "$bit, $rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def LDCF16ri : PrefixRegImmInst<0x23, 3, (outs), (ins GR16:$rs1, i32imm:$bit),
    "ldcf16ri", "$bit, $rs1", []>, Sched<[WriteIALU]>;
}

// BS1B A,r — Bit search 1 backward, result in A (2 bytes)
let Defs = [SR], hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def BS1B8 : PrefixUnaryInst<0x0F, (outs), (ins GR8:$rs1),
    "bs1b8", "$rs1", []>, Sched<[WriteIALU]>;
let OpSize = OpSize16.Value in
def BS1B16 : PrefixUnaryInst<0x0F, (outs), (ins GR16:$rs1),
    "bs1b16", "$rs1", []>, Sched<[WriteIALU]>;
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
    "stb_erp", "$rd, $bank", []>, Sched<[WriteSTW]>;
def LDFR_BERP : ERPRegInst<0x98, (outs), (ins GR8:$rs, i32imm:$bank),
    "ldb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def ADD_BERP : ERPRegInst<0x80, (outs), (ins GR8:$rs, i32imm:$bank),
    "addb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def SUB_BERP : ERPRegInst<0xA0, (outs), (ins GR8:$rs, i32imm:$bank),
    "subb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def AND_BERP : ERPRegInst<0xC0, (outs), (ins GR8:$rs, i32imm:$bank),
    "andb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def OR_BERP : ERPRegInst<0xE0, (outs), (ins GR8:$rs, i32imm:$bank),
    "orb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def CP_BERP : ERPRegInst<0xF0, (outs), (ins GR8:$rs, i32imm:$bank),
    "cpb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def LDI_BERP : ERPSmallImmInst<0xA8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "ldib_erp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def CPI_BERP : ERPSmallImmInst<0xD8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "cpib_erp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def INC_BERP : ERPSmallImmInst<0x60, (outs), (ins i32imm:$bank, i32imm:$imm),
    "incb_erp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def DEC_BERP : ERPSmallImmInst<0x68, (outs), (ins i32imm:$bank, i32imm:$imm),
    "decb_erp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def XOR_BERP : ERPRegInst<0xD0, (outs), (ins GR8:$rs, i32imm:$bank),
    "xorb_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
} // OpSize8

// 16-bit ERP operations with register operand
let OpSize = OpSize16.Value in {
def LDTO_WERP : ERPRegInst<0x88, (outs), (ins GR16:$rd, i32imm:$bank),
    "stw_erp", "$rd, $bank", []>, Sched<[WriteSTW]>;
def LDFR_WERP : ERPRegInst<0x98, (outs), (ins GR16:$rs, i32imm:$bank),
    "ldw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def ADD_WERP : ERPRegInst<0x80, (outs), (ins GR16:$rs, i32imm:$bank),
    "addw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def SUB_WERP : ERPRegInst<0xA0, (outs), (ins GR16:$rs, i32imm:$bank),
    "subw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def AND_WERP : ERPRegInst<0xC0, (outs), (ins GR16:$rs, i32imm:$bank),
    "andw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def OR_WERP : ERPRegInst<0xE0, (outs), (ins GR16:$rs, i32imm:$bank),
    "orw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def CP_WERP : ERPRegInst<0xF0, (outs), (ins GR16:$rs, i32imm:$bank),
    "cpw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def MUL_WERP : ERPRegInst<0x40, (outs), (ins GR16:$rs, i32imm:$bank),
    "mulw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def EX_WERP : ERPRegInst<0xB8, (outs), (ins GR16:$rs, i32imm:$bank),
    "exw_erp", "$rs, $bank", []>, Sched<[WriteSTW]>;
def LDI_WERP : ERPSmallImmInst<0xA8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "ldiw_erp", "$bank, $imm", []>, Sched<[WriteSTW]>;
def CPI_WERP : ERPSmallImmInst<0xD8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "cpiw_erp", "$bank, $imm", []>, Sched<[WriteSTW]>;
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
    "xorcfb_erp", "$b0", []>, Sched<[WriteSTW]>;
def INC1_BERP : ERPUnaryInst< 0x61, (outs), (ins i32imm:$b0),
    "inc1b_erp", "$b0", []>, Sched<[WriteSTW]>;
def DEC1_BERP : ERPUnaryInst< 0x69, (outs), (ins i32imm:$b0),
    "dec1b_erp", "$b0", []>, Sched<[WriteSTW]>;
def SLL_A_BERP : ERPUnaryInst< 0xFE, (outs), (ins i32imm:$b0),
    "sllb_erp", "$b0", []>, Sched<[WriteSTW]>;
} // OpSize8

// W extended register prefix suffix instructions
let OpSize = OpSize16.Value in {
def PUSH_WERP : ERPUnaryInst< 0x04, (outs), (ins i32imm:$b0),
    "pushw_erp", "$b0", []>, Sched<[WriteSTW]>;
def POP_WERP : ERPUnaryInst< 0x05, (outs), (ins i32imm:$b0),
    "popw_erp", "$b0", []>, Sched<[WriteSTW]>;
def CPL_WERP : ERPUnaryInst< 0x06, (outs), (ins i32imm:$b0),
    "cplw_erp", "$b0", []>, Sched<[WriteSTW]>;
def XORCF_A_WERP : ERPUnaryInst< 0x2A, (outs), (ins i32imm:$b0),
    "xorcfw_erp", "$b0", []>, Sched<[WriteSTW]>;
def STCF_A_WERP : ERPUnaryInst< 0x2C, (outs), (ins i32imm:$b0),
    "stcfw_erp", "$b0", []>, Sched<[WriteSTW]>;
def INC1_WERP : ERPUnaryInst< 0x61, (outs), (ins i32imm:$b0),
    "inc1w_erp", "$b0", []>, Sched<[WriteSTW]>;
def INC4_WERP : ERPUnaryInst< 0x64, (outs), (ins i32imm:$b0),
    "inc4w_erp", "$b0", []>, Sched<[WriteSTW]>;
def DEC1_WERP : ERPUnaryInst< 0x69, (outs), (ins i32imm:$b0),
    "dec1w_erp", "$b0", []>, Sched<[WriteSTW]>;
def SLA_A_WERP : ERPUnaryInst< 0xFC, (outs), (ins i32imm:$b0),
    "slaw_erp", "$b0", []>, Sched<[WriteSTW]>;
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
// CP r, QR
def CP_PBW : PrevBankRRInst<0xF0, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "cp", "$rd, $qs", []>, Sched<[WriteSTW]>;
// AND r, QR
def AND_PBW : PrevBankRRInst<0xC0, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "and", "$rd, $qs", []>, Sched<[WriteSTW]>;
// XOR r, QR
def XOR_PBW : PrevBankRRInst<0xD0, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "xor", "$rd, $qs", []>, Sched<[WriteSTW]>;
// ADC r, QR
def ADC_PBW : PrevBankRRInst<0x90, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "adc", "$rd, $qs", []>, Sched<[WriteSTW]>;
// SBC r, QR
def SBC_PBW : PrevBankRRInst<0xB0, (outs), (ins GR16:$rd, PrevGR16:$qs),
    "sbc", "$rd, $qs", []>, Sched<[WriteSTW]>;

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
//
// TLCS-900 post-increment / pre-decrement addressing modes:
//   SPI source: C5 (byte), D5 (word), E5 (long) — (R+) as source
//   SPD source: C4 (byte), D4 (word), E4 (long) — (-R) as source
//   DPI dest:   F5 — (R+) as destination (size-independent prefix)
//   DPD dest:   F4 — (-R) as destination (size-independent prefix)
//
// The base register is encoded as a register file address byte:
//   XWA=0xE0, XBC=0xE4, XDE=0xE8, XHL=0xEC, XIX=0xF0, XIY=0xF4, XIZ=0xF8, XSP=0xFC
//
// Sub-opcode table (same as standard memory addressing):
//   0x04: PUSH    0x06: POP (word only in source table)
//   0x20+r: LD reg,(mem)    0x30+r: ST (mem),reg (dest only)
//   0x38+opc: ALU (mem),#imm  (0x38=ADD,0x39=ADC,0x3A=SUB,0x3B=SBC,0x3C=AND,0x3D=XOR,0x3E=OR,0x3F=CP)
//   0x40+r: LDA reg,mem (dest only)
//   0x60+n: INC #n,(mem)    0x68+n: DEC #n,(mem)
//   0x80+r: ADD reg,(mem)   0x88+r: ADD (mem),reg
//   0x90+r: ADC reg,(mem)   0x98+r: ADC (mem),reg
//   0xA0+r: SUB reg,(mem)   0xA8+r: SUB (mem),reg
//   0xB0+r: SBC reg,(mem)   0xB8+r: SBC (mem),reg
//   0xC0+r: AND reg,(mem)   0xC8+r: AND (mem),reg
//   0xD0+r: XOR reg,(mem)   0xD8+r: XOR (mem),reg
//   0xE0+r: OR reg,(mem)    0xE8+r: OR (mem),reg
//   0xF0+r: CP reg,(mem)    0xF8+r: CP (mem),reg

let Opcode = 0xC5 in {
// --- SPI Byte (prefix C5) ---
let OpSize = OpSize8.Value in {
// Load: LD r8, (R+)
def LD_SPIB : ERPRegInst<0x20, (outs), (ins GR8:$rd, i32imm:$base),
    "ldb_spi", "$rd, $base", []>, Sched<[WriteSTW]>;
// ALU reg,(mem): ADD/ADC/SUB/SBC/AND/XOR/OR/CP r8, (R+)
def ADD_SPIB : ERPRegInst<0x80, (outs), (ins GR8:$rd, i32imm:$base),
    "add_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADC_SPIB : ERPRegInst<0x90, (outs), (ins GR8:$rd, i32imm:$base),
    "adc_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def SUB_SPIB : ERPRegInst<0xA0, (outs), (ins GR8:$rd, i32imm:$base),
    "sub_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def SBC_SPIB : ERPRegInst<0xB0, (outs), (ins GR8:$rd, i32imm:$base),
    "sbc_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def AND_SPIB : ERPRegInst<0xC0, (outs), (ins GR8:$rd, i32imm:$base),
    "and_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def XOR_SPIB : ERPRegInst<0xD0, (outs), (ins GR8:$rd, i32imm:$base),
    "xor_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
def OR_SPIB_RM : ERPRegInst<0xE0, (outs), (ins GR8:$rd, i32imm:$base),
    "or_spib_rm", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPIB : ERPRegInst<0xF0, (outs), (ins GR8:$rd, i32imm:$base),
    "cp_spib", "$rd, $base", []>, Sched<[WriteSTW]>;
// ALU (mem),reg: ADD/ADC/SUB/SBC/AND/XOR/OR/CP (R+), r8
def ADD_SPIB_MR : ERPRegInst<0x88, (outs), (ins GR8:$rs, i32imm:$base),
    "add_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def ADC_SPIB_MR : ERPRegInst<0x98, (outs), (ins GR8:$rs, i32imm:$base),
    "adc_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def SUB_SPIB_MR : ERPRegInst<0xA8, (outs), (ins GR8:$rs, i32imm:$base),
    "sub_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def SBC_SPIB_MR : ERPRegInst<0xB8, (outs), (ins GR8:$rs, i32imm:$base),
    "sbc_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def AND_SPIB_MR : ERPRegInst<0xC8, (outs), (ins GR8:$rs, i32imm:$base),
    "and_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def XOR_SPIB_MR : ERPRegInst<0xD8, (outs), (ins GR8:$rs, i32imm:$base),
    "xor_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def OR_SPIB_MR : ERPRegInst<0xE8, (outs), (ins GR8:$rs, i32imm:$base),
    "or_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def CP_SPIB_MR : ERPRegInst<0xF8, (outs), (ins GR8:$rs, i32imm:$base),
    "cp_spib_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
// ALU (mem),#imm: ADD/ADC/SUB/SBC/AND/XOR/OR/CP (R+), #n
def ADD_SPIB_IM : ERPImmAfterInst<0x38, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "add_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def ADC_SPIB_IM : ERPImmAfterInst<0x39, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "adc_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def SUB_SPIB_IM : ERPImmAfterInst<0x3A, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "sub_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def SBC_SPIB_IM : ERPImmAfterInst<0x3B, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "sbc_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def AND_SPIB_IM : ERPImmAfterInst<0x3C, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "and_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def XOR_SPIB_IM : ERPImmAfterInst<0x3D, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "xor_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def OR_SPIB_IM : ERPImmAfterInst<0x3E, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "or_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def CP_SPIB_IM : ERPImmAfterInst<0x3F, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "cp_spib_im", "$base, $imm", []>, Sched<[WriteSTW]>;
// INC/DEC (R+): count in bits 0-2 of sub-opcode
def INC_SPIB : ERPSmallImmInst<0x60, (outs), (ins i32imm:$base, i32imm:$count),
    "inc_spib", "$count, $base", []>, Sched<[WriteSTW]>;
def DEC_SPIB : ERPSmallImmInst<0x68, (outs), (ins i32imm:$base, i32imm:$count),
    "dec_spib", "$count, $base", []>, Sched<[WriteSTW]>;
// PUSH (R+)
def PUSH_SPIB : ERPUnaryInst<0x04, (outs), (ins i32imm:$base),
    "push_spib", "$base", []>, Sched<[WriteSTW]>;
} // OpSize8

// --- SPI Word (prefix D5) ---
let OpSize = OpSize16.Value in {
def LD_SPIW : ERPRegInst<0x20, (outs), (ins GR16:$rd, i32imm:$base),
    "ld_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPIW : ERPRegInst<0x80, (outs), (ins GR16:$rd, i32imm:$base),
    "add_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADC_SPIW : ERPRegInst<0x90, (outs), (ins GR16:$rd, i32imm:$base),
    "adc_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def SUB_SPIW : ERPRegInst<0xA0, (outs), (ins GR16:$rd, i32imm:$base),
    "sub_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def SBC_SPIW : ERPRegInst<0xB0, (outs), (ins GR16:$rd, i32imm:$base),
    "sbc_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def AND_SPIW : ERPRegInst<0xC0, (outs), (ins GR16:$rd, i32imm:$base),
    "and_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def XOR_SPIW : ERPRegInst<0xD0, (outs), (ins GR16:$rd, i32imm:$base),
    "xor_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def OR_SPIW : ERPRegInst<0xE0, (outs), (ins GR16:$rd, i32imm:$base),
    "or_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPIW : ERPRegInst<0xF0, (outs), (ins GR16:$rd, i32imm:$base),
    "cp_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
def CPM_SPIW : ERPRegInst<0xF8, (outs), (ins GR16:$rd, i32imm:$base),
    "cpm_spiw", "$rd, $base", []>, Sched<[WriteSTW]>;
// ALU (mem),reg word
def ADD_SPIW_MR : ERPRegInst<0x88, (outs), (ins GR16:$rs, i32imm:$base),
    "add_spiw_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def SUB_SPIW_MR : ERPRegInst<0xA8, (outs), (ins GR16:$rs, i32imm:$base),
    "sub_spiw_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def AND_SPIW_MR : ERPRegInst<0xC8, (outs), (ins GR16:$rs, i32imm:$base),
    "and_spiw_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def OR_SPIW_MR : ERPRegInst<0xE8, (outs), (ins GR16:$rs, i32imm:$base),
    "or_spiw_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def CP_SPIW_MR : ERPRegInst<0xF8, (outs), (ins GR16:$rs, i32imm:$base),
    "cp_spiw_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
// ALU (mem),#imm word (trailing 2-byte immediate)
def ADD_SPIW_IM : ERPImmAfterInst<0x38, 5, (outs), (ins i32imm:$base, i32imm:$lo, i32imm:$hi),
    "add_spiw_im", "$base, $lo, $hi", []>, Sched<[WriteSTW]>;
def SUB_SPIW_IM : ERPImmAfterInst<0x3A, 5, (outs), (ins i32imm:$base, i32imm:$lo, i32imm:$hi),
    "sub_spiw_im", "$base, $lo, $hi", []>, Sched<[WriteSTW]>;
def AND_SPIW_IM : ERPImmAfterInst<0x3C, 5, (outs), (ins i32imm:$base, i32imm:$lo, i32imm:$hi),
    "and_spiw_im", "$base, $lo, $hi", []>, Sched<[WriteSTW]>;
def OR_SPIW_IM : ERPImmAfterInst<0x3E, 5, (outs), (ins i32imm:$base, i32imm:$lo, i32imm:$hi),
    "or_spiw_im", "$base, $lo, $hi", []>, Sched<[WriteSTW]>;
def CP_SPIW_IM : ERPImmAfterInst<0x3F, 5, (outs), (ins i32imm:$base, i32imm:$lo, i32imm:$hi),
    "cp_spiw_im", "$base, $lo, $hi", []>, Sched<[WriteSTW]>;
// INC/DEC word
def INC_SPIW : ERPSmallImmInst<0x60, (outs), (ins i32imm:$base, i32imm:$count),
    "inc_spiw", "$count, $base", []>, Sched<[WriteSTW]>;
def DEC_SPIW : ERPSmallImmInst<0x68, (outs), (ins i32imm:$base, i32imm:$count),
    "dec_spiw", "$count, $base", []>, Sched<[WriteSTW]>;
// PUSH word
def PUSH_SPIW : ERPUnaryInst<0x04, (outs), (ins i32imm:$base),
    "push_spiw", "$base", []>, Sched<[WriteSTW]>;
} // OpSize16

// --- SPI Long (prefix E5) ---
let OpSize = OpSize32.Value in {
def LD_SPIL : ERPRegInst<0x20, (outs), (ins GPR:$rd, i32imm:$base),
    "ld_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPIL : ERPRegInst<0x80, (outs), (ins GPR:$rd, i32imm:$base),
    "add_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def SUB_SPIL : ERPRegInst<0xA0, (outs), (ins GPR:$rd, i32imm:$base),
    "sub_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def AND_SPIL : ERPRegInst<0xC0, (outs), (ins GPR:$rd, i32imm:$base),
    "and_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def OR_SPIL : ERPRegInst<0xE0, (outs), (ins GPR:$rd, i32imm:$base),
    "or_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPIL : ERPRegInst<0xF0, (outs), (ins GPR:$rd, i32imm:$base),
    "cp_spil", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPIL_MR : ERPRegInst<0x88, (outs), (ins GPR:$rs, i32imm:$base),
    "add_spil_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def SUB_SPIL_MR : ERPRegInst<0xA8, (outs), (ins GPR:$rs, i32imm:$base),
    "sub_spil_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def CP_SPIL_MR : ERPRegInst<0xF8, (outs), (ins GPR:$rs, i32imm:$base),
    "cp_spil_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize32
} // Opcode = 0xC5 (SPI native)

// --- Source Pre-Decrement (SPD) native defs ---
// Encoding: [C4/D4/E4, base_reg_addr, SubOpc_base + data_reg_enc]
let Opcode = 0xC4 in {
let OpSize = OpSize8.Value in {
def LD_SPDB : ERPRegInst<0x20, (outs), (ins GR8:$rd, i32imm:$base),
    "ld_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
def ADD_SPDB : ERPRegInst<0x80, (outs), (ins GR8:$rd, i32imm:$base),
    "add_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
def SUB_SPDB : ERPRegInst<0xA0, (outs), (ins GR8:$rd, i32imm:$base),
    "sub_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
def AND_SPDB : ERPRegInst<0xC0, (outs), (ins GR8:$rd, i32imm:$base),
    "and_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
def OR_SPDB : ERPRegInst<0xE0, (outs), (ins GR8:$rd, i32imm:$base),
    "or_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPDB : ERPRegInst<0xF0, (outs), (ins GR8:$rd, i32imm:$base),
    "cp_spdb", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPDB_MR : ERPRegInst<0xF8, (outs), (ins GR8:$rs, i32imm:$base),
    "cp_spdb_mr", "$rs, $base", []>, Sched<[WriteSTW]>;
def CP_SPDB_IM : ERPImmAfterInst<0x3F, 4, (outs), (ins i32imm:$base, i32imm:$imm),
    "cp_spdb_im", "$base, $imm", []>, Sched<[WriteSTW]>;
def PUSH_SPDB : ERPUnaryInst<0x04, (outs), (ins i32imm:$base),
    "push_spdb", "$base", []>, Sched<[WriteSTW]>;
def INC_SPDB : ERPSmallImmInst<0x60, (outs), (ins i32imm:$base, i32imm:$count),
    "inc_spdb", "$count, $base", []>, Sched<[WriteSTW]>;
def DEC_SPDB : ERPSmallImmInst<0x68, (outs), (ins i32imm:$base, i32imm:$count),
    "dec_spdb", "$count, $base", []>, Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def LD_SPDW : ERPRegInst<0x20, (outs), (ins GR16:$rd, i32imm:$base),
    "ld_spdw", "$rd, $base", []>, Sched<[WriteSTW]>;
def CP_SPDW : ERPRegInst<0xF0, (outs), (ins GR16:$rd, i32imm:$base),
    "cp_spdw", "$rd, $base", []>, Sched<[WriteSTW]>;
} // OpSize16
let OpSize = OpSize32.Value in {
def LD_SPDL : ERPRegInst<0x20, (outs), (ins GPR:$rd, i32imm:$base),
    "ld_spdl", "$rd, $base", []>, Sched<[WriteSTW]>;
} // OpSize32
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
def CHG_DD8 : ExtImmModInst<0xF0, 0xC0, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "chg_dd8", "$bit, $addr", []>;
def LDCF_DD8 : ExtImmModInst<0xF0, 0x98, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "ldcf_dd8", "$bit, $addr", []>;
def TSET_DD8 : ExtImmModInst<0xF0, 0xA8, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "tset_dd8", "$bit, $addr", []>;
def STCF_DD8 : ExtImmModInst<0xF0, 0xA0, 3, (outs), (ins i32imm:$bit, i32imm:$addr),
    "stcf_dd8", "$bit, $addr", []>;

// --- DD8 (prefix F0): flag operations with A register ---
// D8Unary: [F0, addr8, SubOpc]  (3 bytes) — no data register, fixed sub-opcode
def ANDCF_DD8 : D8UnaryInst<0xF0, 0x28, (outs), (ins i32imm:$addr),
    "andcf_dd8", "$addr", []>;
def ORCF_DD8 : D8UnaryInst<0xF0, 0x29, (outs), (ins i32imm:$addr),
    "orcf_dd8", "$addr", []>;
def XORCF_DD8 : D8UnaryInst<0xF0, 0x2A, (outs), (ins i32imm:$addr),
    "xorcf_dd8", "$addr", []>;
def STCFA_DD8 : D8UnaryInst<0xF0, 0x2C, (outs), (ins i32imm:$addr),
    "stcfa_dd8", "$addr", []>;

// --- DD8 (prefix F0): control flow operations ---
// JP cc, (addr8): [F0, addr8, 0xD0 + cc]  (3 bytes)
def JP_DD8 : ExtImmModInst<0xF0, 0xD0, 3, (outs), (ins i32imm:$cc, i32imm:$addr),
    "jp_dd8", "$cc, $addr", []>;
// CALL (addr8): [F0, addr8, 0x08]  (3 bytes)
def CALL_DD8 : D8UnaryInst<0xF0, 0x08, (outs), (ins i32imm:$addr),
    "call_dd8", "$addr", []>;

// --- DD8 (prefix F0): register operations ---
// D8Reg: [F0, addr8, SubOpc + reg_enc]  (3 bytes)
// Operand 0 = register, Operand 1 = addr8
def ST_DD8B : D8RegInst<0xF0, 0x40, (outs), (ins GR8:$rs, i32imm:$addr),
    "st_dd8b", "$rs, $addr", []>;
def ST_DD8W : D8RegInst<0xF0, 0x50, (outs), (ins GR16:$rs, i32imm:$addr),
    "st_dd8w", "$rs, $addr", []>;
def ST_DD8L : D8RegInst<0xF0, 0x60, (outs), (ins GPR:$rs, i32imm:$addr),
    "st_dd8l", "$rs, $addr", []>;
def LDA_DD8L : D8RegInst<0xF0, 0x30, (outs), (ins GPR:$rd, i32imm:$addr),
    "lda_dd8l", "$rd, $addr", []>;

// --- DD8 (prefix F0): store immediate operations ---
// D8ImmAfter: [F0, addr8, SubOpc, imm_bytes...]
// Operand 0 = addr8, remaining = trailing immediate
def STIB_DD8 : D8ImmAfterInst<0xF0, 0x00, 4,
    (outs), (ins i32imm:$addr, i32imm:$imm),
    "stib_d8", "$addr, $imm", []>;
def STIW_DD8 : D8ImmAfterInst<0xF0, 0x02, 5,
    (outs), (ins i32imm:$addr, i32imm:$lo, i32imm:$hi),
    "stiw_d8", "$addr, $lo, $hi", []>;

// --- DD8 (prefix F0): stack operations ---
def POPB_DD8 : D8UnaryInst<0xF0, 0x04, (outs), (ins i32imm:$addr),
    "popb_dd8", "$addr", []>;
def POPW_DD8 : D8UnaryInst<0xF0, 0x06, (outs), (ins i32imm:$addr),
    "popw_dd8", "$addr", []>;

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
    "jp_ind", "$cc, $b0, $b1, $b2", []>;

// --- DRI (prefix F3): store immediate ---
// RIImmAfter: [F3, MEMsri_bytes..., SubOpc, imm_bytes...]
// Operands 0-2 = MEMsri (mode, lo, hi), remaining = trailing immediate
def STIB_DRI : RIImmAfterInst<0xF3, 0x00, 6, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$imm),
    "stib_ind", "$b0, $b1, $b2, $imm", []>;
def STIW_DRI : RIImmAfterInst<0xF3, 0x02, 7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$lo, i32imm:$hi),
    "stiw_ind", "$b0, $b1, $b2, $lo, $hi", []>;

// --- DRI (prefix F3): memory-to-memory ---
// RIImmAfter: [F3, MEMsri_bytes..., SubOpc, src_lo, src_hi]
// Operands 0-2 = MEMsri (dest mode, lo, hi), 3-4 = source address bytes
def LDMMB_DRI : RIImmAfterInst<0xF3, 0x14, 7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$s0, i32imm:$s1),
    "ldmmb_dri", "$b0, $b1, $b2, $s0, $s1", []>;
def LDMMW_DRI : RIImmAfterInst<0xF3, 0x16, 7, (outs),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2, i32imm:$s0, i32imm:$s1),
    "ldmmw_dri", "$b0, $b1, $b2, $s0, $s1", []>;

// --- SRI R+R addressing (Register+Register indexed) ---
// Encoding: [prefix, 0x07, base_addr, idx_addr, SubOpc + data_reg]
// prefix = C3 (8-bit src), D3 (16-bit src), E3 (32-bit src), F3 (dest)
// base_addr = 0xE0 + base_enc*4, idx_addr = 0xE0 + idx_enc*4

// Source loads: ld reg, (base + index)
let hasSideEffects = 0, mayLoad = 1 in {
def LD_RRB : SriRRRegInst<0xC3, 0x20, (outs GR8:$dst),
    (ins GPR:$base, GR16:$idx),
    "ld_rrb", "$dst, $base, $idx", []>,
    Sched<[WriteLDW, ReadMemBase]> {
  let OpSize = OpSize8.Value;
}
def LD_RRW : SriRRRegInst<0xC3, 0x20, (outs GR16:$dst),
    (ins GPR:$base, GR16:$idx),
    "ld_rrw", "$dst, $base, $idx", []>,
    Sched<[WriteLDW, ReadMemBase]> {
  let OpSize = OpSize16.Value;
}
def LD_RRL : SriRRRegInst<0xC3, 0x20, (outs GPR:$dst),
    (ins GPR:$base, GR16:$idx),
    "ld_rrl", "$dst, $base, $idx", []>,
    Sched<[WriteLDW, ReadMemBase]> {
  let OpSize = OpSize32.Value;
}
} // hasSideEffects, mayLoad

// Destination stores: ld (base + index), reg
// F3 prefix is size-independent; OpSize selects sub-opcode range.
let hasSideEffects = 0, mayStore = 1 in {
def ST_RRB : SriRRRegInst<0xF3, 0x40, (outs),
    (ins GR8:$src, GPR:$base, GR16:$idx),
    "st_rrb", "$src, $base, $idx", []>,
    Sched<[WriteSTW, ReadMemBase]> {
  let OpSize = OpSize8.Value;
}
// ⚠ The SubOpc must be spelled out per size. The comment above says "OpSize
// selects sub-opcode range", but the emitter only applies that adjustment when
// Opcode < 0xF0 (TLCS900MCCodeEmitter.cpp), and this prefix is 0xF3 -- so all
// three defs carrying 0x40 made st_rrw and st_rrl emit the BYTE sub-opcode,
// silently and identically to st_rrb.
def ST_RRW : SriRRRegInst<0xF3, 0x50, (outs),
    (ins GR16:$src, GPR:$base, GR16:$idx),
    "st_rrw", "$src, $base, $idx", []>,
    Sched<[WriteSTW, ReadMemBase]> {
  let OpSize = OpSize16.Value;
}
def ST_RRL : SriRRRegInst<0xF3, 0x60, (outs),
    (ins GPR:$src, GPR:$base, GR16:$idx),
    "st_rrl", "$src, $base, $idx", []>,
    Sched<[WriteSTW, ReadMemBase]> {
  let OpSize = OpSize32.Value;
}
} // hasSideEffects, mayStore

// LDA: load effective address of (base + index)
let hasSideEffects = 0, mayLoad = 0 in {
def LDA_RR : SriRRRegInst<0xF3, 0x30, (outs GPR:$dst),
    (ins GPR:$base, GR16:$idx),
    "lda_rr", "$dst, $base, $idx", []>,
    Sched<[WriteIALU]> {
  let OpSize = OpSize32.Value;
}
} // hasSideEffects, mayLoad

// JP cc, (base + index) — conditional/unconditional jump via R+R
let hasSideEffects = 0, isBarrier = 1, isBranch = 1, isTerminator = 1,
    isIndirectBranch = 1 in {
def JP_RR : SriRRUnaryInst<0xF3, 0xD0, (outs),
    (ins i32imm:$cc, GPR:$base, GR16:$idx),
    "jp_rr", "$cc, $base, $idx", []>,
    Sched<[WriteJmp]> {
  let OpSize = OpSize32.Value;
}
} // JP flags

// CALL (base + index) — call via R+R
let hasSideEffects = 0, isCall = 1 in {
def CALL_RR : SriRRUnaryInst<0xF3, 0x08, (outs),
    (ins i32imm:$cc, GPR:$base, GR16:$idx),
    "call_rr", "$cc, $base, $idx", []>,
    Sched<[WriteJmp]> {
  let OpSize = OpSize32.Value;
}
} // isCall

// R+R with 8-bit index register (mode byte 0x03 instead of 0x07)
// Source loads: ld reg, (base + index8)
let hasSideEffects = 0, mayLoad = 1 in {
def LD_RR8B : SriRR8RegInst<0xC3, 0x20, (outs GR8:$dst),
    (ins GPR:$base, GR8:$idx),
    "ld_rr8b", "$dst, $base, $idx", []>,
    Sched<[WriteLDW, ReadMemBase]> {
  let OpSize = OpSize8.Value;
}
def LD_RR8W : SriRR8RegInst<0xC3, 0x20, (outs GR16:$dst),
    (ins GPR:$base, GR8:$idx),
    "ld_rr8w", "$dst, $base, $idx", []>,
    Sched<[WriteLDW, ReadMemBase]> {
  let OpSize = OpSize16.Value;
}
def LD_RR8L : SriRR8RegInst<0xC3, 0x20, (outs GPR:$dst),
    (ins GPR:$base, GR8:$idx),
    "ld_rr8l", "$dst, $base, $idx", []>,
    Sched<[WriteLDW, ReadMemBase]> {
  let OpSize = OpSize32.Value;
}
} // hasSideEffects, mayLoad
// Destination stores: ld (base + index8), reg
let hasSideEffects = 0, mayStore = 1 in {
def ST_RR8B : SriRR8RegInst<0xF3, 0x40, (outs),
    (ins GR8:$src, GPR:$base, GR8:$idx),
    "st_rr8b", "$src, $base, $idx", []>,
    Sched<[WriteSTW, ReadMemBase]> {
  let OpSize = OpSize8.Value;
}
def ST_RR8W : SriRR8RegInst<0xF3, 0x50, (outs),
    (ins GR16:$src, GPR:$base, GR8:$idx),
    "st_rr8w", "$src, $base, $idx", []>,
    Sched<[WriteSTW, ReadMemBase]> {
  let OpSize = OpSize16.Value;
}
def ST_RR8L : SriRR8RegInst<0xF3, 0x60, (outs),
    (ins GPR:$src, GPR:$base, GR8:$idx),
    "st_rr8l", "$src, $base, $idx", []>,
    Sched<[WriteSTW, ReadMemBase]> {
  let OpSize = OpSize32.Value;
}
} // hasSideEffects, mayStore

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
    "stib_dsp", "$reg, $imm", []> {
  let Opcode = 0xF5;
}
def STIW_DPI : ExtAddrModeOpImmInst<5, 0x02, 1, (outs),
    (ins i32imm:$reg, i32imm:$lo, i32imm:$hi),
    "stiw_dsp", "$reg, $lo, $hi", []> {
  let Opcode = 0xF5;
}

// --- Register indirect (RI): [B0+reg, SubOpc] and [B8+reg, disp, SubOpc] ---
// Carry flag operations with register indirect addressing.
let Defs = [SR], hasSideEffects = 0 in {
// XORCF A, (XRR) — [B0+reg, 0x2A]
def XORCFA_RI : MemRegSuffixInst<0xB0, 0x2A, (outs), (ins GPR:$reg),
    "xorcfa_ri", "$reg", []>, Sched<[WriteIALU]>;
// ANDCF A, (XRR) — [B0+reg, 0x28]
def ANDCFA_RI : MemRegSuffixInst<0xB0, 0x28, (outs), (ins GPR:$reg),
    "andcfa_ri", "$reg", []>, Sched<[WriteIALU]>;
// ORCF A, (XRR) — [B0+reg, 0x29]
def ORCFA_RI : MemRegSuffixInst<0xB0, 0x29, (outs), (ins GPR:$reg),
    "orcfa_ri", "$reg", []>, Sched<[WriteIALU]>;
// STCF A, (XRR) — [B0+reg, 0x2C]
def STCFA_RI : MemRegSuffixInst<0xB0, 0x2C, (outs), (ins GPR:$reg),
    "stcfa_ri", "$reg", []>, Sched<[WriteIALU]>;
// XORCF A, (XRR+d8) — [B8+reg, disp, 0x2A]
def XORCFA_RID8 : MemRegDispSuffixInst<0xB8, 0x2A, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "xorcfa_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
// ANDCF A, (XRR+d8) — [B8+reg, disp, 0x2A]
def ANDCFA_RID8 : MemRegDispSuffixInst<0xB8, 0x28, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "andcfa_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
// ORCF A, (XRR+d8) — [B8+reg, disp, 0x29]
def ORCFA_RID8 : MemRegDispSuffixInst<0xB8, 0x29, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "orcfa_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
// STCF A, (XRR+d8) — [B8+reg, disp, 0x2C]
def STCFA_RID8 : MemRegDispSuffixInst<0xB8, 0x2C, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "stcfa_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
}

// --- Carry flag bit# operations with register indirect ---
// ANDCF #n, (XRR) — [B0+reg, 0x80+n]
// ORCF #n, (XRR) — [B0+reg, 0x88+n]
// XORCF #n, (XRR) — [B0+reg, 0x90+n]
let Defs = [SR], hasSideEffects = 0 in {
def ANDCFN_RI : MemRegImmModInst<0xB0, 0x80, (outs),
    (ins GPR:$reg, i32imm:$bit),
    "andcfn_ri", "$reg, $bit", []>, Sched<[WriteIALU]>;
def ORCFN_RI : MemRegImmModInst<0xB0, 0x88, (outs),
    (ins GPR:$reg, i32imm:$bit),
    "orcfn_ri", "$reg, $bit", []>, Sched<[WriteIALU]>;
def XORCFN_RI : MemRegImmModInst<0xB0, 0x90, (outs),
    (ins GPR:$reg, i32imm:$bit),
    "xorcfn_ri", "$reg, $bit", []>, Sched<[WriteIALU]>;
}

// --- Shift/rotate operations with source-memory register indirect ---
// 8-bit: [0x80+reg, SubOpc], 16-bit: [0x90+reg, SubOpc]
// With d8: [0x88+reg, disp, SubOpc] / [0x98+reg, disp, SubOpc]
let Defs = [SR], hasSideEffects = 0 in {
// SRL — 0x7F
def SRL_RI : MemRegSuffixInst<0x80, 0x7F, (outs), (ins GPR:$reg),
    "srl_ri", "$reg", []>, Sched<[WriteIALU]>;
def SRLW_RI : MemRegSuffixInst<0x90, 0x7F, (outs), (ins GPR:$reg),
    "srlw_ri", "$reg", []>, Sched<[WriteIALU]>;
def SRLW_RID8 : MemRegDispSuffixInst<0x98, 0x7F, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "srlw_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
// SRA — 0x7D
def SRA_RI : MemRegSuffixInst<0x80, 0x7D, (outs), (ins GPR:$reg),
    "sra_ri", "$reg", []>, Sched<[WriteIALU]>;
def SRAW_RI : MemRegSuffixInst<0x90, 0x7D, (outs), (ins GPR:$reg),
    "sraw_ri", "$reg", []>, Sched<[WriteIALU]>;
// SLL — 0x7E
def SLLW_RI : MemRegSuffixInst<0x90, 0x7E, (outs), (ins GPR:$reg),
    "sllw_ri", "$reg", []>, Sched<[WriteIALU]>;
// RLC — 0x78
def RLC_RI : MemRegSuffixInst<0x80, 0x78, (outs), (ins GPR:$reg),
    "rlc_ri", "$reg", []>, Sched<[WriteIALU]>;
def RLCW_RI : MemRegSuffixInst<0x90, 0x78, (outs), (ins GPR:$reg),
    "rlcw_ri", "$reg", []>, Sched<[WriteIALU]>;
// RRC — 0x79
def RRC_RI : MemRegSuffixInst<0x80, 0x79, (outs), (ins GPR:$reg),
    "rrc_ri", "$reg", []>, Sched<[WriteIALU]>;
def RRCW_RI : MemRegSuffixInst<0x90, 0x79, (outs), (ins GPR:$reg),
    "rrcw_ri", "$reg", []>, Sched<[WriteIALU]>;
// RR — 0x7B
def RR_RI : MemRegSuffixInst<0x80, 0x7B, (outs), (ins GPR:$reg),
    "rr_ri", "$reg", []>, Sched<[WriteIALU]>;
def RRW_RI : MemRegSuffixInst<0x90, 0x7B, (outs), (ins GPR:$reg),
    "rrw_ri", "$reg", []>, Sched<[WriteIALU]>;
}

// --- MUL/MULS/DIV/DIVS with source-memory register indirect ---
// [SrcPrefix+addr_reg, SubOpc|data_reg], [SrcPrefix+addr_reg, disp, SubOpc|data_reg]
// 8-bit: prefix 0x80/0x88, 16-bit: prefix 0x90/0x98
let Defs = [SR], hasSideEffects = 0 in {
// MUL — sub 0x40
def MUL8_RI : MemRegRegSuffixInst<0x80, 0x40, (outs),
    (ins GPR:$addr, GR8:$data),
    "mul8_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def MUL16_RI : MemRegRegSuffixInst<0x90, 0x40, (outs),
    (ins GPR:$addr, GR16:$data),
    "mul16_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def MUL16_RID8 : MemRegRegDispSuffixInst<0x98, 0x40, (outs),
    (ins GPR:$addr, i32imm:$disp, GR16:$data),
    "mul16_rid8", "$addr, $disp, $data", []>, Sched<[WriteIALU]>;
// MUL 8-bit with displacement — sub 0x40
def MUL8_RID8 : MemRegRegDispSuffixInst<0x88, 0x40, (outs),
    (ins GPR:$addr, i32imm:$disp, GR8:$data),
    "mul8_rid8", "$addr, $disp, $data", []>, Sched<[WriteIALU]>;
// MULS — sub 0x48
def MULS8_RI : MemRegRegSuffixInst<0x80, 0x48, (outs),
    (ins GPR:$addr, GR8:$data),
    "muls8_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def MULS16_RI : MemRegRegSuffixInst<0x90, 0x48, (outs),
    (ins GPR:$addr, GR16:$data),
    "muls16_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def MULS16_RID8 : MemRegRegDispSuffixInst<0x98, 0x48, (outs),
    (ins GPR:$addr, i32imm:$disp, GR16:$data),
    "muls16_rid8", "$addr, $disp, $data", []>, Sched<[WriteIALU]>;
// DIV — sub 0x50
def DIV8_RI : MemRegRegSuffixInst<0x80, 0x50, (outs),
    (ins GPR:$addr, GR8:$data),
    "div8_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def DIV16_RI : MemRegRegSuffixInst<0x90, 0x50, (outs),
    (ins GPR:$addr, GR16:$data),
    "div16_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
// DIVS — sub 0x58
def DIVS8_RI : MemRegRegSuffixInst<0x80, 0x58, (outs),
    (ins GPR:$addr, GR8:$data),
    "divs8_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def DIVS16_RI : MemRegRegSuffixInst<0x90, 0x58, (outs),
    (ins GPR:$addr, GR16:$data),
    "divs16_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def DIVS16_RID8 : MemRegRegDispSuffixInst<0x98, 0x58, (outs),
    (ins GPR:$addr, i32imm:$disp, GR16:$data),
    "divs16_rid8", "$addr, $disp, $data", []>, Sched<[WriteIALU]>;
}

// --- LD source-memory register indirect (load from memory) ---
// [SrcPrefix + addr_reg, (disp,) 0x20 | data_reg]
let hasSideEffects = 0 in {
def LD8_SRC_RI : MemRegRegSuffixInst<0x80, 0x20, (outs),
    (ins GPR:$addr, GR8:$data),
    "ld8_src_ri", "$addr, $data", []>, Sched<[WriteSTW]>;
def LD8_SRC_RID8 : MemRegRegDispSuffixInst<0x88, 0x20, (outs),
    (ins GPR:$addr, i32imm:$disp, GR8:$data),
    "ld8_src_rid8", "$addr, $disp, $data", []>, Sched<[WriteSTW]>;
def LD16_SRC_RID8 : MemRegRegDispSuffixInst<0x98, 0x20, (outs),
    (ins GPR:$addr, i32imm:$disp, GR16:$data),
    "ld16_src_rid8", "$addr, $disp, $data", []>, Sched<[WriteSTW]>;
}

// --- LD dest-memory register indirect (store to memory) ---
// [B0/B8 + addr_reg, (disp,) 0x40|r8 or 0x50|r16]
let hasSideEffects = 0 in {
def LD_DST8_RI : MemRegRegSuffixInst<0xB0, 0x40, (outs),
    (ins GPR:$addr, GR8:$data),
    "ld_dst8_ri", "$addr, $data", []>, Sched<[WriteSTW]>;
def LD_DST16_RID8 : MemRegRegDispSuffixInst<0xB8, 0x50, (outs),
    (ins GPR:$addr, i32imm:$disp, GR16:$data),
    "ld_dst16_rid8", "$addr, $disp, $data", []>, Sched<[WriteSTW]>;
}

// --- LDA (load address, dest-memory register indirect) ---
// [B0/B8 + addr_reg, (disp,) 0x20 | data_reg]
let hasSideEffects = 0 in {
def LDA_RI : MemRegRegSuffixInst<0xB0, 0x20, (outs),
    (ins GPR:$addr, GPR:$data),
    "lda_ri", "$addr, $data", []>, Sched<[WriteSTW]>;
def LDA_RID8 : MemRegRegDispSuffixInst<0xB8, 0x20, (outs),
    (ins GPR:$addr, i32imm:$disp, GPR:$data),
    "lda_rid8", "$addr, $disp, $data", []>, Sched<[WriteSTW]>;
}

// --- EX (exchange, source-memory register indirect) ---
// [SrcPrefix + addr_reg, 0x30 | data_reg]
let hasSideEffects = 0 in {
def EX8_RI : MemRegRegSuffixInst<0x80, 0x30, (outs),
    (ins GPR:$addr, GR8:$data),
    "ex8_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
def EX16_RI : MemRegRegSuffixInst<0x90, 0x30, (outs),
    (ins GPR:$addr, GR16:$data),
    "ex16_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
}

// --- ALU (mem),r / r,(mem) with register indirect ---
// (mem),r direction: sub = base + data_reg_enc
// r,(mem) direction: sub = base + data_reg_enc
let Defs = [SR], hasSideEffects = 0 in {
// OR (mem), r8: sub base = 0xE8
def OR8_MEM_RI : MemRegRegSuffixInst<0x80, 0xE8, (outs),
    (ins GPR:$addr, GR8:$data),
    "or8_mem_ri", "$addr, $data", []>, Sched<[WriteIALU]>;
// XOR (mem), r8 with d8: sub base = 0xD8
def XOR8_MEM_RID8 : MemRegRegDispSuffixInst<0x88, 0xD8, (outs),
    (ins GPR:$addr, i32imm:$disp, GR8:$data),
    "xor8_mem_rid8", "$addr, $disp, $data", []>, Sched<[WriteIALU]>;
// SUB (mem), r16 with d8: sub base = 0xA8
def SUB16_MEM_RID8 : MemRegRegDispSuffixInst<0x98, 0xA8, (outs),
    (ins GPR:$addr, i32imm:$disp, GR16:$data),
    "sub16_mem_rid8", "$addr, $disp, $data", []>, Sched<[WriteIALU]>;
}

// --- CALL/JP/RET cc with dest-memory register indirect ---
// [B0 + reg, 0xE0/0xD0/0xF0 + cc_enc]
let hasSideEffects = 0 in {
let isCall = 1 in
def CALL_CC_RI : MemRegImmModInst<0xB0, 0xE0, (outs),
    (ins GPR:$reg, i32imm:$cc),
    "call_cc_ri", "$reg, $cc", []>, Sched<[WriteIALU]>;
let isBranch = 1, isTerminator = 1 in
def JP_CC_RI : MemRegImmModInst<0xB0, 0xD0, (outs),
    (ins GPR:$reg, i32imm:$cc),
    "jp_cc_ri", "$reg, $cc", []>, Sched<[WriteIALU]>;
let isReturn = 1, isTerminator = 1 in
def RET_CC_RI : MemRegImmModInst<0xB0, 0xF0, (outs),
    (ins GPR:$reg, i32imm:$cc),
    "ret_cc_ri", "$reg, $cc", []>, Sched<[WriteIALU]>;
}

// --- INC/DEC with source-memory register indirect + d8 ---
// [SrcPrefix + reg, disp, SubOpc]
let Defs = [SR], hasSideEffects = 0 in {
def INC1_8_RID8 : MemRegDispSuffixInst<0x88, 0x61, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "inc1_8_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
def DEC1_16_RID8 : MemRegDispSuffixInst<0x98, 0x69, (outs),
    (ins GPR:$reg, i32imm:$disp),
    "dec1_16_rid8", "$reg, $disp", []>, Sched<[WriteIALU]>;
}

// --- Block transfer/compare operations with source-memory prefix ---
let hasSideEffects = 1 in {
def LDIW_RI : MemRegSuffixInst<0x90, 0x10, (outs), (ins GPR:$reg),
    "ldiw_ri", "$reg", []>, Sched<[WriteIALU]>;
def CPDW_RI : MemRegSuffixInst<0x90, 0x16, (outs), (ins GPR:$reg),
    "cpdw_ri", "$reg", []>, Sched<[WriteIALU]>;
def CPDR_RI : MemRegSuffixInst<0x80, 0x17, (outs), (ins GPR:$reg),
    "cpdr_ri", "$reg", []>, Sched<[WriteIALU]>;
}

// --- ALU (mem), #imm with source-memory register indirect ---
// [SrcPrefix + reg, SubOpc, imm_bytes...]
// 8-bit ops: 3 bytes (prefix, sub, imm8)
// 16-bit ops: 4 bytes (prefix, sub, imm16_lo, imm16_hi)
let Defs = [SR], hasSideEffects = 0 in {
// 8-bit AND/OR/SBC/XOR (mem), #imm8 — 3 bytes
def AND8_IMM_RI : MemRegImmAfterInst<0x80, 0x3C, 3, (outs),
    (ins GPR:$reg, i32imm:$imm),
    "and8_imm_ri", "$reg, $imm", []>, Sched<[WriteIALU]>;
def OR8_IMM_RI : MemRegImmAfterInst<0x80, 0x3E, 3, (outs),
    (ins GPR:$reg, i32imm:$imm),
    "or8_imm_ri", "$reg, $imm", []>, Sched<[WriteIALU]>;
def SBC8_IMM_RI : MemRegImmAfterInst<0x80, 0x3B, 3, (outs),
    (ins GPR:$reg, i32imm:$imm),
    "sbc8_imm_ri", "$reg, $imm", []>, Sched<[WriteIALU]>;
def XOR8_IMM_RI : MemRegImmAfterInst<0x80, 0x3D, 3, (outs),
    (ins GPR:$reg, i32imm:$imm),
    "xor8_imm_ri", "$reg, $imm", []>, Sched<[WriteIALU]>;
// 16-bit AND/OR/XOR (mem), #imm16 — 4 bytes
def AND16_IMM_RI : MemRegImmAfterInst<0x90, 0x3C, 4, (outs),
    (ins GPR:$reg, i32imm:$lo, i32imm:$hi),
    "and16_imm_ri", "$reg, $lo, $hi", []>, Sched<[WriteIALU]>;
def OR16_IMM_RI : MemRegImmAfterInst<0x90, 0x3E, 4, (outs),
    (ins GPR:$reg, i32imm:$lo, i32imm:$hi),
    "or16_imm_ri", "$reg, $lo, $hi", []>, Sched<[WriteIALU]>;
def XOR16_IMM_RI : MemRegImmAfterInst<0x90, 0x3D, 4, (outs),
    (ins GPR:$reg, i32imm:$lo, i32imm:$hi),
    "xor16_imm_ri", "$reg, $lo, $hi", []>, Sched<[WriteIALU]>;
// 8-bit AND (mem+d8), #imm8 — 4 bytes
def AND8_IMM_RID8 : MemRegDispImmAfterInst<0x88, 0x3C, 4, (outs),
    (ins GPR:$reg, i32imm:$disp, i32imm:$imm),
    "and8_imm_rid8", "$reg, $disp, $imm", []>, Sched<[WriteIALU]>;
}

// --- Consolidated SRI LD defs (C3/D3/E3) with register operand ---
// Uses RIRegInst: [prefix, addr_bytes..., SubOpc + reg_enc]
// Prefix = C3 + OpSize * 0x10 (C3=byte, D3=word, E3=long)

let Opcode = 0xC3 in {
let OpSize = OpSize8.Value in {
def LD_SRIB3 : RIRegInst<0xC3, 0x20, 5, (outs), (ins GR8:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ldb_sri", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def LD_SRIB1 : RIRegInst<0xC3, 0x20, 3, (outs), (ins GR8:$rd, i32imm:$b0),
    "ld_srib1", "$rd, $b0", []>, Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def LD_SRIW3 : RIRegInst<0xC3, 0x20, 5, (outs), (ins GR16:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ldw_sri", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
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
    "ldb_sri0", "$rd, $addr", []>, Sched<[WriteSTW]>;
} // OpSize8
let OpSize = OpSize16.Value in {
def LD_SRIW_D16 : SriD16RegInst<0xC3, 0x20, (outs), (ins GR16:$rd, MEMri:$addr),
    "ldw_sri0", "$rd, $addr", []>, Sched<[WriteSTW]>;
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
// ⚠ These two SubOpcs were SWAPPED. SubOpc 0x30 is LDA and 0x40 is the byte
// store, which the neighbouring stw_dri=0x50 / stl_dri=0x60 already implied.
// The KN5000 v7 ROM settles it: `f3 07 e4 e0 31` disassembles as
// `lda XBC,XBC+WA`, and 0x31 = 0x30 | reg. Before this fix you had to write
// `stb_dri` to obtain an LDA, so every disassembly using it named a store
// where the CPU computes an address.
def ST_DRI3B : RIRegInst<0xF3, 0x40, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "stb_dri", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize8
def LDA_DRI3 : RIRegInst<0xF3, 0x30, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "lda_dri", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
let OpSize = OpSize16.Value in {
def ST_DRI3W : RIRegInst<0xF3, 0x50, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "stw_dri", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // OpSize16
def ST_DRI3L : RIRegInst<0xF3, 0x60, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "stl_dri", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
} // Opcode = 0xF3

// --- Register-indexed LOAD (C3/D3/E3) ---
// The store direction above exists; the load direction did not, so a
// disassembly could not write `ld A,(XIX+HL)` at all. Encodings read off the
// KN5000 v7 ROM, which contains all three:
//     c3 07 f0 ec 21   ld A,(XIX+HL)      8-bit,  A   = reg 1 -> 0x20|1
//     d3 07 f0 ec 20   ld WA,(XIX+HL)     16-bit, WA  = reg 0 -> 0x20|0
//     e3 07 ec f4 25   ld XIY,(XHL+IY)    32-bit, XIY = reg 5 -> 0x20|5
// Same [prefix, sub-mode, base byte, index byte, SubOpc|reg] shape as the
// stores, with SubOpc 0x20. All three take BASE opcode 0xC3 and let OpSize
// pick the prefix: RIRegInst adds 0x10 for OpSize16 and 0x20 for 32-bit, an
// adjustment the 0xF3 stores never see because it is skipped above 0xF0.
// Writing 0xD3/0xE3 literally here yielded 0xE3 and 0x03 instead.
let mayLoad = 1, hasSideEffects = 0 in {
let OpSize = OpSize8.Value in
def LD_DRI3B : RIRegInst<0xC3, 0x20, 5, (outs GR8:$rd),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ldb_dri", "$rd, $b0, $b1, $b2", []>, Sched<[WriteLDW]>;
let OpSize = OpSize16.Value in
def LD_DRI3W : RIRegInst<0xC3, 0x20, 5, (outs GR16:$rd),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ldw_dri", "$rd, $b0, $b1, $b2", []>, Sched<[WriteLDW]>;
def LD_DRI3L : RIRegInst<0xC3, 0x20, 5, (outs GPR:$rd),
    (ins i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "ldl_dri", "$rd, $b0, $b1, $b2", []>, Sched<[WriteLDW]>;
} // mayLoad


// --- Destination Post-Increment (F5) — consolidated defs ---
// Format: [F5, base_reg_addr_byte, SubOpc + data_reg_enc]
// F5 prefix is size-independent (Opcode >= 0xF0, no OpSize adjustment).
// Uses ERPRegInst: Operand 0 = data register, Operand 1 = base reg addr byte.
//
// Destination sub-opcode table (F5/F4):
//   0x00: LD (R+), #imm8    0x02: LD (R+), #imm16
//   0x04: POP byte (R+)     0x06: POP word (R+)
//   0x14: LD (dst), (src)   0x19: LD (mem), (mem) (mem-to-mem)
//   0x30+r: ST r8, (R+)     0x40+r: LDA r32, (R+)
//   0x50+r: ST r16, (R+)    0x60+r: ST r32, (R+)

let Opcode = 0xF5 in {
let OpSize = OpSize8.Value in {
def ST_DPIB : ERPRegInst<0x30, (outs), (ins GR8:$rs, i32imm:$base),
    "stb_dpi", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize8
def LDA_DPI : ERPRegInst<0x40, (outs), (ins GPR:$rd, i32imm:$base),
    "lda_dpi", "$rd, $base", []>, Sched<[WriteSTW]>;
let OpSize = OpSize16.Value in {
def ST_DPIW : ERPRegInst<0x50, (outs), (ins GR16:$rs, i32imm:$base),
    "stw_dpi", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize16
def ST_DPIL : ERPRegInst<0x60, (outs), (ins GPR:$rs, i32imm:$base),
    "stl_dpi", "$rs, $base", []>, Sched<[WriteSTW]>;
// POP to (R+)
def POPB_DPI : ERPUnaryInst<0x04, (outs), (ins i32imm:$base),
    "popb_dpi", "$base", []>, Sched<[WriteSTW]>;
def POPW_DPI : ERPUnaryInst<0x06, (outs), (ins i32imm:$base),
    "popw_dpi", "$base", []>, Sched<[WriteSTW]>;
} // Opcode = 0xF5

// --- Destination Pre-Decrement (F4) — consolidated defs ---
let Opcode = 0xF4 in {
let OpSize = OpSize8.Value in {
def ST_DPDB : ERPRegInst<0x30, (outs), (ins GR8:$rs, i32imm:$base),
    "st_dpdb", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize8
def LDA_DPD : ERPRegInst<0x40, (outs), (ins GPR:$rd, i32imm:$base),
    "lda_dpd", "$rd, $base", []>, Sched<[WriteSTW]>;
let OpSize = OpSize16.Value in {
def ST_DPDW : ERPRegInst<0x50, (outs), (ins GR16:$rs, i32imm:$base),
    "st_dpdw", "$rs, $base", []>, Sched<[WriteSTW]>;
} // OpSize16
def ST_DPDL : ERPRegInst<0x60, (outs), (ins GPR:$rs, i32imm:$base),
    "st_dpdl", "$rs, $base", []>, Sched<[WriteSTW]>;
def POPB_DPD : ERPUnaryInst<0x04, (outs), (ins i32imm:$base),
    "popb_dpd", "$base", []>, Sched<[WriteSTW]>;
def POPW_DPD : ERPUnaryInst<0x06, (outs), (ins i32imm:$base),
    "popw_dpd", "$base", []>, Sched<[WriteSTW]>;
} // Opcode = 0xF4

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
    "cpb_sri_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIB_MR : RIRegInst<0xC3, 0xF8, 5, (outs), (ins GR8:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cpb_sri_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
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
    "cpw_sri_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIW_MR : RIRegInst<0xC3, 0xF8, 5, (outs), (ins GR16:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cpw_sri_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
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
    "cpl_sri_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def CP_SRIL_MR : RIRegInst<0xC3, 0xF8, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "cpl_sri_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def ADC_SRIL_MR : RIRegInst<0xC3, 0x98, 5, (outs), (ins GPR:$rs, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "adc_sril_mr", "$rs, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
def OR_SRIL_RM : RIRegInst<0xC3, 0xE0, 5, (outs), (ins GPR:$rd, i32imm:$b0, i32imm:$b1, i32imm:$b2),
    "or_sril_rm", "$rd, $b0, $b1, $b2", []>, Sched<[WriteSTW]>;
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

// --- ERP byte: LD short-immediate and LD register, both missing ---
// The KN5000 v7 ROM uses both and neither had a mnemonic, so `ld QIZH,1` and
// `ld C,QIZH` could not be written at all. 86 instances between them.
//     c7 fb a9   ld QIZH,1     [C7, bank, 0xA8 + imm3]   imm 1 -> 0xA9
//     c7 fb 8b   ld C,QIZH     [C7, bank, 0x88 + reg]    C = reg 3 -> 0x8B
// LDI_ERPB above covers the LONG immediate form (c7 fb 03 0f); this is the
// three-bit one, which is a different encoding rather than a shorter spelling.
def LDS_ERPB : ERPSmallImmInst<0xA8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "lds_erpb", "$bank, $imm", []>, Sched<[WriteSTW]>;
def LD_ERPB_RR : ERPRegInst<0x88, (outs GR8:$rd), (ins i32imm:$bank),
    "ld_erpb_rr", "$rd, $bank", []>, Sched<[WriteSTW]>;

// The mirror images of the two above, both also used by the v7 ROM and both
// also absent. The backend kept having one direction of a pair:
//     c7 fb db   cp QIZH,3    [C7, bank, 0xD8 + imm3]   3 -> 0xDB
//     c7 f0 99   ld IXL,A     [C7, bank, 0x98 + reg]    A = reg 1 -> 0x99
// cps_erpb is to CP what lds_erpb is to LD; st_erpb_rr stores a plain register
// INTO the ERP byte, where ld_erpb_rr reads one out of it.
let Defs = [SR] in
def CPS_ERPB : ERPSmallImmInst<0xD8, (outs), (ins i32imm:$bank, i32imm:$imm),
    "cps_erpb", "$bank, $imm", []>, Sched<[WriteIALU]>;
def ST_ERPB_RR : ERPRegInst<0x98, (outs), (ins GR8:$rs, i32imm:$bank),
    "st_erpb_rr", "$rs, $bank", []>, Sched<[WriteSTW]>;
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

// (SPI byte operations moved to main SPI block above)

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
    "cpib_sri", "$b0, $b1, $b2, $imm", []>, Sched<[WriteSTW]>;
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
    "cpiw_sri", "$b0, $b1, $b2, $lo, $hi", []>, Sched<[WriteSTW]>;
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
    "pushw_da", "$b0, $b1, $b2", []>;
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
    "mri_d2", "$b0, $b1", []>, Sched<[WriteSTW]>;
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


// ---------------------------------------------------------------------------
// Real TLCS-900 mnemonics for the memory-operand forms.
//
// These instructions always encoded correctly, but were only reachable under
// invented spellings ("andmi8", "bitm", "ldcfm"), so a disassembly could not
// write `and (xix), 0x7f` even though the encoder produced 84 3C 7F for it.
// CP8mi already used the real "cp", which is the pattern followed here.
//
// The old spellings are kept as aliases: kn5000-roms-disasm uses them in
// hundreds of files (bitm in 53, incm in 80), and renaming alone would break
// every one of them.
// ---------------------------------------------------------------------------
def : InstAlias<"andmi8 $addr, $imm", (AND8mi MEMri:$addr, i8imm:$imm)>;
def : InstAlias<"andmi16 $addr, $imm", (AND16mi MEMri:$addr, i16imm:$imm)>;
def : InstAlias<"bitm $bit, $addr", (BITm MEMri:$addr, i32imm:$bit)>;
def : InstAlias<"setm $bit, $addr", (SETm MEMri:$addr, i32imm:$bit)>;
def : InstAlias<"resm $bit, $addr", (RESm MEMri:$addr, i32imm:$bit)>;
def : InstAlias<"ldcfm $bit, $addr", (LDCFm MEMri:$addr, i32imm:$bit)>;
def : InstAlias<"stcfm $bit, $addr", (STCFm MEMri:$addr, i32imm:$bit)>;

// SCC under its real mnemonic. SCC8/SCC16 are the encodable forms and were
// reachable only as "scc8"/"scc16"; SCC32 above is a codegen pseudo that already
// holds the plain "scc" AsmString, so these go in as aliases rather than a
// rename to avoid two definitions printing the same string.
def : InstAlias<"scc $cc, $rd", (SCC8 GR8:$rd, cc:$cc)>;
def : InstAlias<"scc $cc, $rd", (SCC16 GR16:$rd, cc:$cc)>;
