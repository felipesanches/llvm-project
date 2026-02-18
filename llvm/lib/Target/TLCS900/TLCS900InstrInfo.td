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
                          "sla", "$rd, $imm",
                          [(set GPR:$rd, (shl GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteShift, ReadIALU]>;

// SRA rd, rs — Shift Right Arithmetic
def SRA32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sra", "$rd, $rs2",
                          [(set GPR:$rd, (sra GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRA rd, #imm
def SRA32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "sra", "$rd, $imm",
                          [(set GPR:$rd, (sra GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteShift, ReadIALU]>;

// SRL rd, rs — Shift Right Logical
def SRL32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "srl", "$rd, $rs2",
                          [(set GPR:$rd, (srl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRL rd, #imm
def SRL32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "srl", "$rd, $imm",
                          [(set GPR:$rd, (srl GPR:$rs1, (imm):$imm))]>,
              Sched<[WriteShift, ReadIALU]>;

} // Constraints = "$rd = $rs1"

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

// JP target — Unconditional branch
let isBranch = 1, isTerminator = 1, isBarrier = 1 in
def JP : TLCS900Inst<(outs), (ins brtarget:$target),
                     "jp", "$target",
                     [(br bb:$target)]>,
         Sched<[WriteJmp]>;

// JP cc, target — Conditional branch
let isBranch = 1, isTerminator = 1, Uses = [SR] in
def JPcc : TLCS900Inst<(outs), (ins cc:$cc, brtarget:$target),
                       "jp", "$cc, $target",
                       [(tlcs900_brcond (i32 imm:$cc), bb:$target)]>,
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

// SELECT_CC pseudo — Expanded to branch diamond by custom inserter.
// Operands: trueVal, falseVal, condition code. Reads flags from SR.
let usesCustomInserter = 1, Uses = [SR] in
def Select32 : Pseudo<(outs GPR:$rd),
                      (ins GPR:$trueVal, GPR:$falseVal, i32imm:$cc),
                      [(set GPR:$rd,
                        (tlcs900_select_cc GPR:$trueVal, GPR:$falseVal,
                                           (i32 imm:$cc)))]>;
