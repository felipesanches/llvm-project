//=== TLCS900.td - Describe the TLCS900 Target Machine ---------*- tablegen -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// Top tablegen file that pulls in code from the LLVM framework along with
// code specific to this target.
//
//===----------------------------------------------------------------------===//

include "llvm/Target/Target.td"

//===----------------------------------------------------------------------===//
// Calling Conv, Instruction Descriptions, Register information, etc
//===----------------------------------------------------------------------===//

include "TLCS900Schedule.td"
include "TLCS900RegisterInfo.td"
include "TLCS900CallingConv.td"
include "TLCS900InstrInfo.td"

def TLCS900InstrInfo : InstrInfo;

def TLCS900AsmParser : AsmParser;

//===----------------------------------------------------------------------===//
// TLCS900 processors supported
//===----------------------------------------------------------------------===//

def : ProcessorModel<"generic",  NoSchedModel, []>;

//===----------------------------------------------------------------------===//
// TLCS900 Target declaration
//===----------------------------------------------------------------------===//

def TLCS900 : Target {
  let InstructionSet = TLCS900InstrInfo;
  let AssemblyParsers = [TLCS900AsmParser];
}
