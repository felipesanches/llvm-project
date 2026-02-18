//=== TLCS900InstrFormats.td - TLCS900 Instruction Formats ---*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// TLCS900 instruction format definitions.
//
// The TLCS-900/H2 uses variable-length instructions (1-7 bytes) with a
// complex prefix-based encoding scheme. Binary encoding is not yet
// implemented; these format classes support assembly output and instruction
// selection only.
//
//===----------------------------------------------------------------------===//

// Base class for all TLCS900 instructions.
class TLCS900Inst<dag outs, dag ins, string opcodestr, string argstr,
                  list<dag> pattern>
    : Instruction {
  let Namespace = "TLCS900";
  let Size = 0; // Variable length — encoding TBD

  dag OutOperandList = outs;
  dag InOperandList = ins;
  let AsmString = opcodestr # "\t" # argstr;
  let Pattern = pattern;
}

// Pseudo instructions (no encoding, codegen only).
class Pseudo<dag outs, dag ins, list<dag> pattern,
             string opcodestr = "", string argstr = "">
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let isPseudo = 1;
  let isCodeGenOnly = 1;
}
