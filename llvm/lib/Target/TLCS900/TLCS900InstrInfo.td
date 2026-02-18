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

// Condition code operand for conditional branches
def cc : Operand<i32> {
  let PrintMethod = "printCondCode";
}

// Branch target (basic block reference)
def brtarget : Operand<OtherVT>;

// Memory operand: base register + 16-bit displacement
def MEMri : Operand<i32> {
  let MIOperandInfo = (ops GPR:$base, i32imm:$disp);
  let PrintMethod = "printMemOperand";
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
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD32ri : TLCS900Inst<(outs GPR:$rd), (ins i32imm:$imm),
                         "ld", "$rd, $imm",
                         [(set GPR:$rd, (imm):$imm)]>,
             Sched<[WriteIALU]>;

// LD rd, rs — Copy register to register
let isAsCheapAsAMove = 1 in
def LD32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs),
                         "ld", "$rd, $rs",
                         []>,
             Sched<[WriteIALU]>;

// LD rd, (base+disp) — Load 32-bit from memory
def LD32rm : TLCS900Inst<(outs GPR:$rd), (ins MEMri:$addr),
                         "ld", "$rd, $addr",
                         [(set GPR:$rd, (load addr:$addr))]>,
             Sched<[WriteLDW, ReadMemBase]>;

// LD (base+disp), rs — Store 32-bit to memory
def LD32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                         "ld", "$addr, $rs",
                         [(store GPR:$rs, addr:$addr)]>,
             Sched<[WriteSTW, ReadMemBase]>;

// LD (base+disp), #imm — Store immediate to memory
def LD32mi : TLCS900Inst<(outs), (ins MEMri:$addr, i32imm:$val),
                         "ld", "$addr, $val",
                         [(store (i32 imm:$val), addr:$addr)]>,
             Sched<[WriteSTW, ReadMemBase]>;

// LD rd:lo16, (base+disp) — Load 16-bit from memory into low word of GPR
// Note: upper 16 bits of the 32-bit register are UNCHANGED by hardware.
// This is used internally; zextloadi16/sextloadi16 patterns add explicit
// EXTZ/EXTS to clear/sign-extend the upper bits.
def LD16rm : TLCS900Inst<(outs GPR_lo16:$rd), (ins MEMri:$addr),
                          "ld", "$rd, $addr", []>,
             Sched<[WriteLDW, ReadMemBase]>;

// LD rd:lo8, (base+disp) — Load 8-bit from memory into low byte of GPR
// Note: other bytes of the register are UNCHANGED by hardware.
def LD8rm : TLCS900Inst<(outs GPR_lo8:$rd), (ins MEMri:$addr),
                         "ld", "$rd, $addr", []>,
            Sched<[WriteLDW, ReadMemBase]>;

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

// LD (base+disp), rs:lo16 — Truncating store: writes low 16 bits to memory
def LD16mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR_lo16:$rs),
                          "ld", "$addr, $rs",
                          [(truncstorei16 GPR:$rs, addr:$addr)]>,
             Sched<[WriteSTW, ReadMemBase]>;

// LD (base+disp), rs:lo8 — Truncating store: writes low 8 bits to memory
def LD8mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR_lo8:$rs),
                         "ld", "$addr, $rs",
                         [(truncstorei8 GPR:$rs, addr:$addr)]>,
            Sched<[WriteSTW, ReadMemBase]>;

// Patterns for global address and external symbol materialization
def : Pat<(i32 tglobaladdr:$addr), (LD32ri tglobaladdr:$addr)>;
def : Pat<(i32 texternalsym:$addr), (LD32ri texternalsym:$addr)>;
def : Pat<(i32 tblockaddress:$addr), (LD32ri tblockaddress:$addr)>;

//===----------------------------------------------------------------------===//
// Arithmetic Instructions (two-address: rd = rd op rs)
//===----------------------------------------------------------------------===//

let Constraints = "$rd = $rs1" in {

// ADD rd, rs — rd = rd + rs
def ADD32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "add", "$rd, $rs2",
                          [(set GPR:$rd, (add GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// ADD rd, #imm — rd = rd + imm
def ADD32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "add", "$rd, $imm",
                          [(set GPR:$rd, (add GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// SUB rd, rs — rd = rd - rs
def SUB32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sub", "$rd, $rs2",
                          [(set GPR:$rd, (sub GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// SUB rd, #imm — rd = rd - imm
def SUB32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "sub", "$rd, $imm",
                          [(set GPR:$rd, (sub GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// ADC rd, rs — rd = rd + rs + carry
let Defs = [SR], Uses = [SR] in {
def ADC32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "adc", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// ADC rd, #imm — rd = rd + imm + carry
def ADC32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "adc", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;

// SBC rd, rs — rd = rd - rs - carry
def SBC32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sbc", "$rd, $rs2", []>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// SBC rd, #imm — rd = rd - imm - carry
def SBC32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "sbc", "$rd, $imm", []>,
              Sched<[WriteIALU, ReadIALU]>;
} // Defs = [SR], Uses = [SR]

//===----------------------------------------------------------------------===//
// Logic Instructions (two-address)
//===----------------------------------------------------------------------===//

// AND rd, rs
def AND32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "and", "$rd, $rs2",
                          [(set GPR:$rd, (and GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// AND rd, #imm
def AND32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "and", "$rd, $imm",
                          [(set GPR:$rd, (and GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// OR rd, rs
def OR32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                         "or", "$rd, $rs2",
                         [(set GPR:$rd, (or GPR:$rs1, GPR:$rs2))]>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// OR rd, #imm
def OR32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                         "or", "$rd, $imm",
                         [(set GPR:$rd, (or GPR:$rs1, (imm):$imm))]>,
             Sched<[WriteIALU, ReadIALU]>;

// XOR rd, rs
def XOR32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "xor", "$rd, $rs2",
                          [(set GPR:$rd, (xor GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// XOR rd, #imm
def XOR32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "xor", "$rd, $imm",
                          [(set GPR:$rd, (xor GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Shift Instructions (two-address)
//===----------------------------------------------------------------------===//

// SLA rd, rs — Shift Left Arithmetic
def SLA32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sla", "$rd, $rs2",
                          [(set GPR:$rd, (shl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SLA rd, #imm
def SLA32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "sla", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// SRA rd, rs — Shift Right Arithmetic
def SRA32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sra", "$rd, $rs2",
                          [(set GPR:$rd, (sra GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRA rd, #imm
def SRA32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "sra", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

// SRL rd, rs — Shift Right Logical
def SRL32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "srl", "$rd, $rs2",
                          [(set GPR:$rd, (srl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRL rd, #imm
def SRL32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "srl", "$rd, $imm", []>,
              Sched<[WriteShift, ReadIALU]>;

} // Constraints = "$rd = $rs1"

//===----------------------------------------------------------------------===//
// Unary Instructions (single-operand, in-place)
//===----------------------------------------------------------------------===//

let Constraints = "$rd = $rs1" in {

// NEG rd — Negate: rd = 0 - rd
def NEG32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                         "neg", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

// CPL rd — Complement (bitwise NOT): rd = ~rd
def CPL32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                         "cpl", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

// INC #n, rd — Increment by n (n = 1..8, encoded as 3-bit: 0 means 8)
def INC32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$n),
                         "inc", "$n, $rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

// DEC #n, rd — Decrement by n (n = 1..8, encoded as 3-bit: 0 means 8)
def DEC32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$n),
                         "dec", "$n, $rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

// EXTS rd — Sign extend: low 16 bits sign-extended to 32 bits
def EXTS32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                          "exts", "$rd", []>,
              Sched<[WriteIALU, ReadIALU]>;

// EXTZ rd — Zero extend: low 16 bits zero-extended to 32 bits
def EXTZ32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                          "extz", "$rd", []>,
              Sched<[WriteIALU, ReadIALU]>;

// DAA rd — Decimal Adjust after Addition (BCD)
def DAA32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                         "daa", "$rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

} // Constraints = "$rd = $rs1"

// Patterns for NEG and CPL
def : Pat<(sub 0, GPR:$rs), (NEG32 GPR:$rs)>;
def : Pat<(not GPR:$rs), (CPL32 GPR:$rs)>;

// Pattern for EXTS: sign extend from i16 to i32
def : Pat<(sext_inreg GPR:$rs, i16), (EXTS32 GPR:$rs)>;

// Pattern for sign extend i8 to i32 (shift pair)
def : Pat<(sext_inreg GPR:$rs, i8), (SRA32ri (SLA32ri GPR:$rs, 24), 24)>;

// Pattern for EXTZ: zero extend low 16 bits (AND with 0xFFFF)
def : Pat<(and GPR:$rs, 65535), (EXTZ32 GPR:$rs)>;

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

let Defs = [SR] in {

// CP rd, rs — Compare registers (rd - rs, set flags, discard result)
def CP32rr : TLCS900Inst<(outs), (ins GPR:$rs1, GPR:$rs2),
                         "cp", "$rs1, $rs2",
                         [(tlcs900_cmp GPR:$rs1, GPR:$rs2)]>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// CP rd, #imm — Compare register with immediate
def CP32ri : TLCS900Inst<(outs), (ins GPR:$rs1, i32imm:$imm),
                         "cp", "$rs1, $imm",
                         [(tlcs900_cmp GPR:$rs1, (imm):$imm)]>,
             Sched<[WriteIALU, ReadIALU]>;

} // Defs = [SR]

//===----------------------------------------------------------------------===//
// Branch Instructions
//===----------------------------------------------------------------------===//

// JP target — Unconditional branch (absolute address)
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JP : TLCS900Inst<(outs), (ins brtarget:$target),
                     "jp", "$target",
                     [(br bb:$target)]>,
         Sched<[WriteJmp]>;

// JP cc, target — Conditional branch (absolute address)
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JPcc : TLCS900Inst<(outs), (ins cc:$cc, brtarget:$target),
                       "jp", "$cc, $target",
                       [(tlcs900_brcond (i32 imm:$cc), bb:$target)]>,
           Sched<[WriteJmp]>;

// JR target — Relative jump (8-bit signed offset, shorter encoding)
// No isel patterns; used by linker relaxation JP→JR when target is near.
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JR : TLCS900Inst<(outs), (ins brtarget:$target),
                     "jr", "$target", []>,
         Sched<[WriteJmp]>;

// JR cc, target — Conditional relative jump (8-bit signed offset)
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JRcc : TLCS900Inst<(outs), (ins cc:$cc, brtarget:$target),
                       "jr", "$cc, $target", []>,
           Sched<[WriteJmp]>;

// JRL target — Relative jump (16-bit signed offset)
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JRL : TLCS900Inst<(outs), (ins brtarget:$target),
                      "jrl", "$target", []>,
          Sched<[WriteJmp]>;

// JRL cc, target — Conditional relative jump (16-bit signed offset)
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JRLcc : TLCS900Inst<(outs), (ins cc:$cc, brtarget:$target),
                        "jrl", "$cc, $target", []>,
            Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Call Instructions
//===----------------------------------------------------------------------===//

let isCall = 1 in {

// CALL target — Direct function call
def CALL : TLCS900Inst<(outs), (ins i32imm:$target),
                       "call", "$target",
                       [(tlcs900_call tglobaladdr:$target)]>,
           Sched<[WriteJmp]>;

// CALL (rs) — Indirect function call through register
def CALL_r : TLCS900Inst<(outs), (ins GPR:$target),
                          "call", "($target)",
                          [(tlcs900_call GPR:$target)]>,
              Sched<[WriteJmp]>;

// CALR target — Relative call (16-bit signed offset, shorter encoding)
// No isel patterns; used by linker relaxation CALL→CALR when target is near.
def CALR : TLCS900Inst<(outs), (ins i32imm:$target),
                        "calr", "$target", []>,
            Sched<[WriteJmp]>;

} // isCall = 1

def : Pat<(tlcs900_call texternalsym:$target), (CALL texternalsym:$target)>;

//===----------------------------------------------------------------------===//
// Return
//===----------------------------------------------------------------------===//

// RET — Return from subroutine
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RET : TLCS900Inst<(outs), (ins),
                      "ret", "",
                      [(tlcs900_ret)]>,
          Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Stack Instructions
//===----------------------------------------------------------------------===//

let Defs = [XSP], Uses = [XSP] in {

// PUSH rs — Push 32-bit register to stack
let mayStore = 1 in
def PUSH32 : TLCS900Inst<(outs), (ins GPR:$rs),
                         "push", "$rs", []>,
             Sched<[WritePush]>;

// POP rd — Pop 32-bit register from stack
let mayLoad = 1 in
def POP32 : TLCS900Inst<(outs GPR:$rd), (ins),
                        "pop", "$rd", []>,
            Sched<[WritePop]>;

} // Defs = [XSP], Uses = [XSP]

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
let Uses = [SR] in
def SCC32 : TLCS900Inst<(outs GPR:$rd), (ins cc:$cc),
                         "scc", "$cc, $rd", []>,
            Sched<[WriteIALU]>;

//===----------------------------------------------------------------------===//
// System Instructions
//===----------------------------------------------------------------------===//

// NOP — No operation
def NOP : TLCS900Inst<(outs), (ins), "nop", "", []>,
          Sched<[WriteNop]>;

// HALT — Halt CPU until interrupt
def HALT : TLCS900Inst<(outs), (ins), "halt", "", []>,
           Sched<[WriteNop]>;

// DI — Disable interrupts
def DI : TLCS900Inst<(outs), (ins), "di", "", []>,
         Sched<[WriteNop]>;

// EI — Enable interrupts (with level)
def EI : TLCS900Inst<(outs), (ins i32imm:$level), "ei", "$level", []>,
         Sched<[WriteNop]>;

// SWI — Software interrupt (with vector number)
def SWI : TLCS900Inst<(outs), (ins i32imm:$num), "swi", "$num", []>,
          Sched<[WriteJmp]>;

// RETI — Return from interrupt
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RETI : TLCS900Inst<(outs), (ins), "reti", "", []>,
           Sched<[WriteJmp]>;

// RETD — Return and deallocate stack space
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RETD : TLCS900Inst<(outs), (ins i32imm:$imm), "retd", "$imm", []>,
           Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Rotate Instructions (single-operand, in-place)
//===----------------------------------------------------------------------===//

let Constraints = "$rd = $rs1", Defs = [SR] in {

// RLC rd — Rotate left through carry (1 bit)
def RLC32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                          "rlc", "$rd", []>,
             Sched<[WriteShift, ReadIALU]>;

// RRC rd — Rotate right through carry (1 bit)
def RRC32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                          "rrc", "$rd", []>,
             Sched<[WriteShift, ReadIALU]>;

// RL rd — Rotate left (9-bit rotation through carry)
def RL32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                         "rl", "$rd", []>,
            Sched<[WriteShift, ReadIALU]>;

// RR rd — Rotate right (9-bit rotation through carry)
def RR32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1),
                         "rr", "$rd", []>,
            Sched<[WriteShift, ReadIALU]>;

} // Constraints, Defs

//===----------------------------------------------------------------------===//
// Bit Manipulation Instructions
//===----------------------------------------------------------------------===//

// BIT #bit, rd — Test bit (set Z flag)
let Defs = [SR] in
def BIT32 : TLCS900Inst<(outs), (ins i32imm:$bit, GPR:$rs),
                         "bit", "$bit, $rs", []>,
            Sched<[WriteIALU, ReadIALU]>;

// SET #bit, rd — Set bit
let Constraints = "$rd = $rs1" in
def SET32 : TLCS900Inst<(outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                         "set", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// RES #bit, rd — Reset (clear) bit
let Constraints = "$rd = $rs1" in
def RES32 : TLCS900Inst<(outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                         "res", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// CHG #bit, rd — Change (toggle) bit
let Constraints = "$rd = $rs1" in
def CHG32 : TLCS900Inst<(outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                         "chg", "$bit, $rd", []>,
            Sched<[WriteIALU, ReadIALU]>;

// TSET #bit, rd — Test and set bit (set Z flag, then set the bit)
let Constraints = "$rd = $rs1", Defs = [SR] in
def TSET32 : TLCS900Inst<(outs GPR:$rd), (ins i32imm:$bit, GPR:$rs1),
                          "tset", "$bit, $rd", []>,
             Sched<[WriteIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Exchange Instructions
//===----------------------------------------------------------------------===//

// EX rd, rs — Exchange contents of two registers
let Constraints = "$rd_out = $rd_in, $rs_out = $rs_in" in
def EX32 : TLCS900Inst<(outs GPR:$rd_out, GPR:$rs_out),
                        (ins GPR:$rd_in, GPR:$rs_in),
                        "ex", "$rd_out, $rs_out", []>,
           Sched<[WriteIALU]>;

//===----------------------------------------------------------------------===//
// Load Effective Address
//===----------------------------------------------------------------------===//

// LDA rd, (base+disp) — Load effective address into register
def LDA32 : TLCS900Inst<(outs GPR:$rd), (ins MEMri:$addr),
                         "lda", "$rd, $addr", []>,
            Sched<[WriteIALU]>;

//===----------------------------------------------------------------------===//
// Loop Instruction
//===----------------------------------------------------------------------===//

// DJNZ rd, target — Decrement and jump if not zero
let Constraints = "$rd = $rs1", isBranch = 1, isTerminator = 1 in
def DJNZ32 : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, brtarget:$target),
                          "djnz", "$rd, $target", []>,
             Sched<[WriteIALU, WriteJmp]>;

//===----------------------------------------------------------------------===//
// Memory-register arithmetic (CISC: operates directly on memory)
//===----------------------------------------------------------------------===//

// ADD (mem), rs — Add register to memory location
def ADD32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                           "add", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// SUB (mem), rs — Subtract register from memory location
def SUB32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                           "sub", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// AND (mem), rs — AND register with memory location
def AND32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                           "and", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// OR (mem), rs — OR register with memory location
def OR32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                          "or", "$addr, $rs", []>,
             Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// XOR (mem), rs — XOR register with memory location
def XOR32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                           "xor", "$addr, $rs", []>,
              Sched<[WriteSTW, ReadMemBase, ReadIALU]>;

// CP (mem), rs — Compare memory with register
let Defs = [SR] in
def CP32mr : TLCS900Inst<(outs), (ins MEMri:$addr, GPR:$rs),
                          "cp", "$addr, $rs", []>,
             Sched<[WriteLDW, ReadMemBase, ReadIALU]>;

// CP (mem), #imm — Compare memory with immediate
let Defs = [SR] in
def CP32mi : TLCS900Inst<(outs), (ins MEMri:$addr, i32imm:$imm),
                          "cp", "$addr, $imm", []>,
             Sched<[WriteLDW, ReadMemBase]>;

// ADD (mem), #imm — Add immediate to memory location
def ADD32mi : TLCS900Inst<(outs), (ins MEMri:$addr, i32imm:$imm),
                           "add", "$addr, $imm", []>,
              Sched<[WriteSTW, ReadMemBase]>;

// SUB (mem), #imm — Subtract immediate from memory location
def SUB32mi : TLCS900Inst<(outs), (ins MEMri:$addr, i32imm:$imm),
                           "sub", "$addr, $imm", []>,
              Sched<[WriteSTW, ReadMemBase]>;

//===----------------------------------------------------------------------===//
// Multiply / Divide Instructions (hardware, 16-bit operands)
//===----------------------------------------------------------------------===//
// TLCS-900 hardware MUL: 16-bit × 16-bit → 32-bit result
// MUL WA, #imm16 → result in XWA
// MULS WA, #imm16 → signed result in XWA
// DIV WA, #imm16 → XWA / imm16, quotient in WA, remainder in upper 16
// DIVS WA, #imm16 → signed divide

// These use GR16 sub-registers of GPR. For now, defined without isel patterns
// since we only support i32 types. These will be useful once i16 support is added
// or for inline assembly.

let Constraints = "$rd = $rs1" in {

// MUL rr, rs — Unsigned multiply: result in next-wider register
def MUL32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                           "mul", "$rd, $rs2", []>,
              Sched<[WriteIMul, ReadIALU, ReadIALU]>;

// MULS rr, rs — Signed multiply
def MULS32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                            "muls", "$rd, $rs2", []>,
               Sched<[WriteIMul, ReadIALU, ReadIALU]>;

// DIV rr, rs — Unsigned divide
def DIV32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                           "div", "$rd, $rs2", []>,
              Sched<[WriteIDiv, ReadIALU, ReadIALU]>;

// DIVS rr, rs — Signed divide
def DIVS32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                            "divs", "$rd, $rs2", []>,
               Sched<[WriteIDiv, ReadIALU, ReadIALU]>;

} // Constraints

//===----------------------------------------------------------------------===//
// Block Transfer Instructions (no isel patterns — for inline asm / builtins)
//===----------------------------------------------------------------------===//

// LDI — Load and increment: (XDE) ← (XHL), XDE++, XHL++, XBC--
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDI : TLCS900Inst<(outs), (ins), "ldi", "", []>,
          Sched<[WriteSTW]>;

// LDIR — Load, increment, repeat: LDI until XBC == 0
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDIR : TLCS900Inst<(outs), (ins), "ldir", "", []>,
           Sched<[WriteSTW]>;

// LDD — Load and decrement: (XDE) ← (XHL), XDE--, XHL--, XBC--
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDD : TLCS900Inst<(outs), (ins), "ldd", "", []>,
          Sched<[WriteSTW]>;

// LDDR — Load, decrement, repeat: LDD until XBC == 0
let Defs = [XDE, XHL, XBC], Uses = [XDE, XHL, XBC], mayLoad = 1, mayStore = 1 in
def LDDR : TLCS900Inst<(outs), (ins), "lddr", "", []>,
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
def CPI : TLCS900Inst<(outs), (ins), "cpi", "", []>,
          Sched<[WriteIALU]>;

// CPIR — Compare, increment, repeat: CPI until match or XBC == 0
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
def CPIR : TLCS900Inst<(outs), (ins), "cpir", "", []>,
           Sched<[WriteIALU]>;

// CPD — Compare and decrement: compare A with (XHL), XHL--, XBC--
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
def CPD : TLCS900Inst<(outs), (ins), "cpd", "", []>,
          Sched<[WriteIALU]>;

// CPDR — Compare, decrement, repeat: CPD until match or XBC == 0
let Defs = [XHL, XBC, SR], Uses = [XWA, XHL, XBC], mayLoad = 1 in
def CPDR : TLCS900Inst<(outs), (ins), "cpdr", "", []>,
           Sched<[WriteIALU]>;
