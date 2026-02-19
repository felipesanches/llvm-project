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
// TLCS900 subtarget features
//===----------------------------------------------------------------------===//

// TLCS-900/H series features (vs. TLCS-900/L base)
def FeatureHWMul
 : SubtargetFeature<"hwmul", "HasHWMul", "true",
                    "Enable hardware multiply (MUL/MULS/DIV/DIVS)">;

def FeatureMinMax
 : SubtargetFeature<"minmax", "HasMinMax", "true",
                    "Enable MIN/MAX instructions">;

def FeatureMDMA
 : SubtargetFeature<"mdma", "HasMDMA", "true",
                    "Enable micro-DMA controller">;

//===----------------------------------------------------------------------===//
// TLCS900 processors supported
//===----------------------------------------------------------------------===//

// Generic TLCS-900 with no special features (safe baseline).
def : ProcessorModel<"generic",  NoSchedModel, []>;

// TLCS-900/H series — adds hardware multiply/divide.
def : ProcessorModel<"tlcs900h", NoSchedModel, [FeatureHWMul]>;

// TLCS-900/H1 — first revision of H series.
def : ProcessorModel<"tlcs900h1", NoSchedModel, [FeatureHWMul]>;

// TLCS-900/H2 — second revision, used in TMP94C241 and other modern variants.
def : ProcessorModel<"tlcs900h2", NoSchedModel, [FeatureHWMul, FeatureMinMax]>;

// Specific CPU models — aliases for the appropriate feature set.
// TMP94C241: Toshiba TLCS-900/H2 used in Technics KN5000 keyboard.
def : ProcessorModel<"tmp94c241", NoSchedModel, [FeatureHWMul, FeatureMinMax]>;

//===----------------------------------------------------------------------===//
// TLCS900 Target declaration
//===----------------------------------------------------------------------===//

def TLCS900 : Target {
  let InstructionSet = TLCS900InstrInfo;
  let AssemblyParsers = [TLCS900AsmParser];
}
