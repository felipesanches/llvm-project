//===-- TLCS900RegisterInfo.td - TLCS900 Register defs ---------*- tablegen -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
//  Declarations that describe the TLCS900 register file
//===----------------------------------------------------------------------===//

class TLCS900Reg<string n, bits<16> Enc, list<Register> subregs = []> : Register<n> {
  let Namespace = "TLCS900";
  let HWEncoding = Enc;
  let SubRegs = subregs;
}

// Subregister indices.
let Namespace = "TLCS900" in {
  def sub_8bit     : SubRegIndex<8>;
  def sub_8bit_hi  : SubRegIndex<8, 8>;
  def sub_16bit    : SubRegIndex<16>;
  def sub_16bit_hi : SubRegIndex<16, 16>;
}

// 8-bit registers
// Low registers
def A : TLCS900Reg<"a", 1>;
def C : TLCS900Reg<"c", 3>;
def E : TLCS900Reg<"e", 5>;
def L : TLCS900Reg<"l", 7>;

// High registers
def W : TLCS900Reg<"w", 0>;
def B : TLCS900Reg<"b", 2>;
def D : TLCS900Reg<"d", 4>;
def H : TLCS900Reg<"h", 6>;

// 16-bit registers
let SubRegIndices = [sub_8bit, sub_8bit_hi], CoveredBySubRegs = 1 in {
def WA : TLCS900Reg<"wa", 0, [A,W]>;
def BC : TLCS900Reg<"bc", 1, [C,B]>;
def DE : TLCS900Reg<"de", 2, [E,D]>;
def HL : TLCS900Reg<"hl", 3, [L,H]>;
}

// 16-bit registers
def IX : TLCS900Reg<"ix", 4>;
def IY : TLCS900Reg<"iy", 5>;
def IZ : TLCS900Reg<"iz", 6>;
def SP : TLCS900Reg<"sp", 7>;

let isArtificial = 1 in {
// High word of the low 32 bits of the super-register:
def HWA : TLCS900Reg<"", -1>;
def HBC : TLCS900Reg<"", -1>;
def HDE : TLCS900Reg<"", -1>;
def HHL : TLCS900Reg<"", -1>;
def HIX : TLCS900Reg<"", -1>;
def HIY : TLCS900Reg<"", -1>;
def HIZ : TLCS900Reg<"", -1>;
def HSP : TLCS900Reg<"", -1>;
}

// 32-bit registers
let SubRegIndices = [sub_16bit, sub_16bit_hi], CoveredBySubRegs = 1 in {
def XWA : TLCS900Reg<"xwa", 0, [WA, HWA]>;
def XBC : TLCS900Reg<"xbc", 1, [BC, HBC]>;
def XDE : TLCS900Reg<"xde", 2, [DE, HDE]>;
def XHL : TLCS900Reg<"xhl", 3, [HL, HHL]>;
def XIX : TLCS900Reg<"xix", 4, [IX, HIX]>;
def XIY : TLCS900Reg<"xiy", 5, [IY, HIY]>;
def XIZ : TLCS900Reg<"xiz", 6, [IZ, HIZ]>;
def XSP : TLCS900Reg<"xsp", 7, [SP, HSP]>;
}

// The order of registers represents the preferred allocation sequence.
// Registers are listed in the order caller-save, callee-save, specials.

def GR8 : RegisterClass<"TLCS900", [i8],  8,
                        (add W, A, B, C, D, E, H, L)>;

def GR16 : RegisterClass<"TLCS900", [i16], 16,
                         (add WA, BC, DE, HL, IX, IY, IZ)>;

//def SP : RegisterClass<"TLCS900", [i32], 32, (add XSP)>;
