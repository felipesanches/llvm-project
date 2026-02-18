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
// TLCS900 -specific SDNodes
//===----------------------------------------------------------------------===//

// Procedure return
def tlcs900_ret : SDNode<"TLCS900ISD::Ret", SDTNone,
                       [SDNPHasChain, SDNPOptInGlue, SDNPVariadic]>;

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

// 32-bit immediate (any value)
def imm32 : ImmLeaf<i32, [{ return true; }]>;

//===----------------------------------------------------------------------===//
// Data Transfer Instructions
//===----------------------------------------------------------------------===//

// LD rd, #imm32 — Load 32-bit immediate into register
let isReMaterializable = 1, isAsCheapAsAMove = 1 in
def LD32ri : TLCS900Inst<(outs GPR:$rd), (ins i32imm:$imm),
                         "ld", "$rd, $imm",
                         [(set GPR:$rd, imm32:$imm)]>,
             Sched<[WriteIALU]>;

// LD rd, rs — Copy register to register
let isAsCheapAsAMove = 1 in
def LD32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs),
                         "ld", "$rd, $rs",
                         []>,
             Sched<[WriteIALU]>;

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
                          [(set GPR:$rd, (add GPR:$rs1, imm32:$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

// SUB rd, rs — rd = rd - rs
def SUB32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sub", "$rd, $rs2",
                          [(set GPR:$rd, (sub GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// SUB rd, #imm — rd = rd - imm
def SUB32ri : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, i32imm:$imm),
                          "sub", "$rd, $imm",
                          [(set GPR:$rd, (sub GPR:$rs1, imm32:$imm))]>,
              Sched<[WriteIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Logic Instructions (two-address)
//===----------------------------------------------------------------------===//

// AND rd, rs
def AND32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "and", "$rd, $rs2",
                          [(set GPR:$rd, (and GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// OR rd, rs
def OR32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                         "or", "$rd, $rs2",
                         [(set GPR:$rd, (or GPR:$rs1, GPR:$rs2))]>,
             Sched<[WriteIALU, ReadIALU, ReadIALU]>;

// XOR rd, rs
def XOR32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "xor", "$rd, $rs2",
                          [(set GPR:$rd, (xor GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteIALU, ReadIALU, ReadIALU]>;

//===----------------------------------------------------------------------===//
// Shift Instructions (two-address)
//===----------------------------------------------------------------------===//

// SLA rd, rs — Shift Left Arithmetic (same as SLL for positive values)
def SLA32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sla", "$rd, $rs2",
                          [(set GPR:$rd, (shl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRA rd, rs — Shift Right Arithmetic
def SRA32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sra", "$rd, $rs2",
                          [(set GPR:$rd, (sra GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SLL rd, rs — Shift Left Logical
def SLL32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "sll", "$rd, $rs2",
                          []>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

// SRL rd, rs — Shift Right Logical
def SRL32rr : TLCS900Inst<(outs GPR:$rd), (ins GPR:$rs1, GPR:$rs2),
                          "srl", "$rd, $rs2",
                          [(set GPR:$rd, (srl GPR:$rs1, GPR:$rs2))]>,
              Sched<[WriteShift, ReadIALU, ReadShift]>;

} // Constraints = "$rd = $rs1"

//===----------------------------------------------------------------------===//
// Multiply / Divide (placeholder — TLCS900 MUL/DIV have unusual semantics)
//===----------------------------------------------------------------------===//

// For now, expand multiply/divide to libcalls. Real TLCS900 MUL/DIV operate
// on sub-register pairs (e.g., MUL HL,rs → result in XHL) and will need
// custom lowering later.

//===----------------------------------------------------------------------===//
// Control Flow
//===----------------------------------------------------------------------===//

// RET — Return from subroutine
let isReturn = 1, isBarrier = 1, isTerminator = 1 in
def RET : TLCS900Inst<(outs), (ins),
                      "ret", "",
                      [(tlcs900_ret)]>,
          Sched<[WriteJmp]>;

//===----------------------------------------------------------------------===//
// Pseudo Instructions
//===----------------------------------------------------------------------===//

let Defs = [XSP], Uses = [XSP] in {
def ADJCALLSTACKDOWN : Pseudo<(outs), (ins i32imm:$amt1, i32imm:$amt2),
                              [(callseq_start timm:$amt1, timm:$amt2)]>;
def ADJCALLSTACKUP   : Pseudo<(outs), (ins i32imm:$amt1, i32imm:$amt2),
                              [(callseq_end timm:$amt1, timm:$amt2)]>;
} // Defs = [XSP], Uses = [XSP]
