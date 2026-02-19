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
// word). This definition exists only for the disassembler; ISel lowers
// 32-bit immediate stores as: LD reg, #imm; LD (mem), reg.
let isCodeGenOnly = 0 in
def LD32mi : MemStoreInst<0x08, 8, (outs), (ins MEMri:$addr, i32imm:$val),
                          "ld", "$addr, $val", []>,
             Sched<[WriteSTW, ReadMemBase]>;

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
// Encoding: E8+rd, 0x07 (2 bytes)
def NEG32 : PrefixUnaryInst<0x07, (outs GPR:$rd), (ins GPR:$rs1),
                            "neg", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// CPL rd — Complement (bitwise NOT): rd = ~rd (affects H=1, N=1)
// Encoding: E8+rd, 0x06 (2 bytes)
def CPL32 : PrefixUnaryInst<0x06, (outs GPR:$rd), (ins GPR:$rs1),
                            "cpl", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// INC #n, rd — Increment by n (n = 1..8)
// Encoding: E8+rd, 0x60+(n-1) (2 bytes)
// Affects S, Z, H, V but NOT C (carry is preserved on hardware, but we
// model SR as a single register so we must declare it as clobbered).
def INC32 : PrefixIncDecInst<0x60, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$n),
                             "inc", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// DEC #n, rd — Decrement by n (n = 1..8)
// Encoding: E8+rd, 0x68+(n-1) (2 bytes)
// Same flag behavior as INC.
def DEC32 : PrefixIncDecInst<0x68, (outs GPR:$rd), (ins GPR:$rs1, i32imm:$n),
                             "dec", "$n, $rd", []>,
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

// DAA rd — Decimal Adjust after Addition (BCD) (affects all flags)
// Reads N and H flags from prior arithmetic to determine BCD correction.
// Encoding: E8+rd, 0x10 (2 bytes)
let Constraints = "$rd = $rs1", Defs = [SR], Uses = [SR] in
def DAA32 : PrefixUnaryInst<0x10, (outs GPR:$rd), (ins GPR:$rs1),
                            "daa", "$rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// Patterns for NEG and CPL
def : Pat<(sub 0, GPR:$rs), (NEG32 GPR:$rs)>;
def : Pat<(not GPR:$rs), (CPL32 GPR:$rs)>;

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

// Patterns for 16-bit extending loads
def : Pat<(i32 (zextloadi16 addr:$addr)), (EXTZ32 (LD16rm addr:$addr))>;
def : Pat<(i32 (sextloadi16 addr:$addr)), (EXTS32 (LD16rm addr:$addr))>;
def : Pat<(i32 (extloadi16 addr:$addr)),  (EXTZ32 (LD16rm addr:$addr))>;

// Patterns for 8-bit extending loads
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
// Encoding: B0+rs, 0x1C (2 bytes)
let isBranch = 1, isTerminator = 1, isBarrier = 1, isIndirectBranch = 1 in
def JP_r : CallIndirectInst<0x1C, (outs), (ins GPR:$target),
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
// Encoding: mem_prefix(0xB0+rs), 0x1F (2 bytes)
def CALL_r : CallIndirectInst<0x1F, (outs), (ins GPR:$target),
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
// Encoding: 0x48+r (1 byte)
let mayStore = 1 in
def PUSH32 : SingleByteRegInst<0x48, (outs), (ins GPR:$rs),
                               "push", "$rs", []>,
             Sched<[WritePush]>;

// POP rd — Pop 32-bit register from stack (load, post-increment SP)
// Encoding: 0x58+r (1 byte)
let mayLoad = 1 in
def POP32 : SingleByteRegInst<0x58, (outs GPR:$rd), (ins),
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

} // Defs = [XSP], Uses = [XSP], hasSideEffects

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

//===----------------------------------------------------------------------===//
// System Instructions
//===----------------------------------------------------------------------===//

// NOP — No operation (safe to remove)
// Encoding: 0x00 (1 byte)
let hasSideEffects = 0 in
def NOP : SingleByteInst<0x00, (outs), (ins), "nop", "", []>,
          Sched<[WriteNop]>;

// HALT — Halt CPU until interrupt
// Encoding: 0x06 (1 byte)
def HALT : SingleByteInst<0x06, (outs), (ins), "halt", "", []>,
           Sched<[WriteNop]>;

// DI — Disable interrupts
// Encoding: 0x07 (1 byte)
def DI : SingleByteInst<0x07, (outs), (ins), "di", "", []>,
         Sched<[WriteNop]>;

// EI — Enable interrupts (with level)
// Encoding: 0x08+level (1 byte, level encoded in bits 0-2)
// Using SingleByteImm8 as a close approximation; encoder handles specially.
def EI : SingleByteImm8Inst<0x08, (outs), (ins i32imm:$level),
                            "ei", "$level", []>,
         Sched<[WriteNop]>;

// SWI — Software interrupt (with vector number)
// Encoding: 0xF8+num (1 byte, num in bits 0-2)
// Using SingleByteImm8 as approximation; encoder emits 0xF8+num as 1 byte.
def SWI : SingleByteImm8Inst<0xF8, (outs), (ins i32imm:$num),
                             "swi", "$num", []>,
          Sched<[WriteJmp]>;

// RETI — Return from interrupt (pops SR then PC from stack)
// Encoding: 0x0B (1 byte)
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RETI : SingleByteInst<0x0B, (outs), (ins), "reti", "", []>,
           Sched<[WriteJmp]>;

// RETD — Return and deallocate stack space
// Encoding: 0x0F, d16 (3 bytes)
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RETD : SingleByteImm8Inst<0x0F, (outs), (ins i32imm:$imm),
                              "retd", "$imm", []>,
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
// Bit Manipulation Instructions
//===----------------------------------------------------------------------===//

// BIT #bit, rd — Test bit (set Z flag; effect captured by Defs)
// Encoding: E8+rs, 0x33, bit_num (3 bytes)
let Defs = [SR], hasSideEffects = 0 in
def BIT32 : PrefixBitInst<0x33, (outs), (ins i32imm:$bit, GPR:$rs),
                          "bit", "$bit, $rs", []>,
            Sched<[WriteIALU, ReadIALU]>;

// SET #bit, rd — Set bit (pure computation on register)
// Encoding: E8+rd, 0x31, bit_num (3 bytes)
let Constraints = "$rd = $rs1", hasSideEffects = 0 in
def SET32 : PrefixBitInst<0x31, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "set", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// RES #bit, rd — Reset (clear) bit (pure computation on register)
// Encoding: E8+rd, 0x30, bit_num (3 bytes)
let Constraints = "$rd = $rs1", hasSideEffects = 0 in
def RES32 : PrefixBitInst<0x30, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "res", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// CHG #bit, rd — Change (toggle) bit (pure computation on register)
// Encoding: E8+rd, 0x32, bit_num (3 bytes)
let Constraints = "$rd = $rs1", hasSideEffects = 0 in
def CHG32 : PrefixBitInst<0x32, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "chg", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// TSET #bit, rd — Test and set bit (set Z flag, then set the bit)
// Encoding: E8+rd, 0x34, bit_num (3 bytes)
let Constraints = "$rd = $rs1", Defs = [SR], hasSideEffects = 0 in
def TSET32 : PrefixBitInst<0x34, (outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                           "tset", "$bit, $rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Exchange Instructions
//===----------------------------------------------------------------------===//

// EX rd, rs — Exchange contents of two registers (no side effects)
// Encoding: E8+rs, 0xB8+rd (2 bytes) — using LD R,C form variant
let Constraints = "$rd_out = $rd_in, $rs_out = $rs_in", hasSideEffects = 0 in
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
// Encoding: E8+rd, 0x1C, d8 (3 bytes)
let Constraints = "$rd = $rs1", isBranch = 1, isTerminator = 1, Defs = [SR] in
def DJNZ32 : PrefixDJNZInst<0x1C, (outs GPR:$rd), (ins GPR:$rs1, brtarget:$target),
                             "djnz", "$rd, $target", []>,
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

// CP (mem), #imm — Compare memory with immediate (folds load into compare)
def CP32mi : MemALUInst<0xCF, 8, (outs), (ins MEMri:$addr, i32imm:$imm),
                        "cp", "$addr, $imm",
                        [(tlcs900_cmp (i32 (load addr:$addr)), (i32 (imm):$imm))]>,
             Sched<[WriteLDW, ReadMemBase]>;

} // Defs = [SR]

// ADD/SUB memory-immediate: also read-modify-write
let Defs = [SR], mayLoad = 1, mayStore = 1 in {

// ADD (mem), #imm — Add immediate to memory location (read-modify-write)
def ADD32mi : MemALUInst<0xC8, 8, (outs), (ins MEMri:$addr, i32imm:$imm),
                         "add", "$addr, $imm", []>,
              Sched<[WriteSTW, ReadMemBase]>;

// SUB (mem), #imm — Subtract immediate from memory location (read-modify-write)
def SUB32mi : MemALUInst<0xCA, 8, (outs), (ins MEMri:$addr, i32imm:$imm),
                         "sub", "$addr, $imm", []>,
              Sched<[WriteSTW, ReadMemBase]>;

} // Defs = [SR], mayLoad, mayStore

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

// Memory-immediate patterns for ADD and SUB.
def : Pat<(store (add (load addr:$a), (i32 imm:$v)), addr:$a),
          (ADD32mi addr:$a, imm:$v)>;
def : Pat<(store (sub (load addr:$a), (i32 imm:$v)), addr:$a),
          (SUB32mi addr:$a, imm:$v)>;

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

//===----------------------------------------------------------------------===//
// Block Transfer Instructions (no isel patterns — for inline asm / builtins)
//===----------------------------------------------------------------------===//

// LDI — Load and increment: (XDE) ← (XHL), XDE++, XHL++, XBC--
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDI : BlockTransferInst<0x10, (outs), (ins), "ldi", "", []>,
          Sched<[WriteSTW]>;

// LDIR — Load, increment, repeat: LDI until XBC == 0
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDIR : BlockTransferInst<0x11, (outs), (ins), "ldir", "", []>,
           Sched<[WriteSTW]>;

// LDD — Load and decrement: (XDE) ← (XHL), XDE--, XHL--, XBC--
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDD : BlockTransferInst<0x12, (outs), (ins), "ldd", "", []>,
          Sched<[WriteSTW]>;

// LDDR — Load, decrement, repeat: LDD until XBC == 0
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDDR : BlockTransferInst<0x13, (outs), (ins), "lddr", "", []>,
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

// SET: x | (1 << n) → set bit n
def : Pat<(or GPR:$rs, IsPow2_32:$mask), (SET32 (Log2_32 $mask), GPR:$rs)>;

// RES: x & ~(1 << n) → reset bit n
def : Pat<(and GPR:$rs, IsNotPow2_32:$mask),
          (RES32 (Log2Not_32 $mask), GPR:$rs)>;

// CHG: x ^ (1 << n) → toggle bit n
def : Pat<(xor GPR:$rs, IsPow2_32:$mask), (CHG32 (Log2_32 $mask), GPR:$rs)>;

//===----------------------------------------------------------------------===//
// Compare/Search Block Instructions
//===----------------------------------------------------------------------===//

// CPI — Compare and increment: compare A with (XHL), XHL++, XBC--
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
def CPI : BlockTransferInst<0x14, (outs), (ins), "cpi", "", []>,
          Sched<[WriteIALU]>;

// CPIR — Compare, increment, repeat: CPI until match or XBC == 0
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
def CPIR : BlockTransferInst<0x15, (outs), (ins), "cpir", "", []>,
           Sched<[WriteIALU]>;

// CPD — Compare and decrement: compare A with (XHL), XHL--, XBC--
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
def CPD : BlockTransferInst<0x16, (outs), (ins), "cpd", "", []>,
          Sched<[WriteIALU]>;

// CPDR — Compare, decrement, repeat: CPD until match or XBC == 0
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
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

// LD rd16, #imm16: D8+rd, 0x03, imm16
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD16ri_asm : PrefixLDImmInst<0x03, 4, (outs GR16:$rd), (ins i16imm:$imm),
                                  "ld", "$rd, $imm", []>,
                 Sched<[WriteIALU]>;

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

// --- INC/DEC ---

def INC16 : PrefixIncDecInst<0x60, (outs GR16:$rd),
                              (ins GR16:$rs1, i16imm:$n),
                              "inc", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

def DEC16 : PrefixIncDecInst<0x68, (outs GR16:$rd),
                              (ins GR16:$rs1, i16imm:$n),
                              "dec", "$n, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

} // Constraints = "$rd = $rs1", Defs = [SR]

// --- Compare (no output register) ---
let Defs = [SR], isCompare = 1 in {

def CP16rr : PrefixRegRegInst<0xF0, (outs), (ins GR16:$rs1, GR16:$rs2),
                               "cp", "$rs1, $rs2", []>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

def CP16ri : PrefixRegImmInst<0xCF, 4, (outs), (ins GR16:$rs1, i16imm:$imm),
                               "cp", "$rs1, $imm", []>,
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

} // OpSize = OpSize8.Value
