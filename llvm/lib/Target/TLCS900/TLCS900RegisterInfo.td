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
let DwarfRegNum = [17] in def A : TLCS900Reg<"a", 1>;
let DwarfRegNum = [19] in def C : TLCS900Reg<"c", 3>;
let DwarfRegNum = [21] in def E : TLCS900Reg<"e", 5>;
let DwarfRegNum = [23] in def L : TLCS900Reg<"l", 7>;

// High registers
let DwarfRegNum = [16] in def W : TLCS900Reg<"w", 0>;
let DwarfRegNum = [18] in def B : TLCS900Reg<"b", 2>;
let DwarfRegNum = [20] in def D : TLCS900Reg<"d", 4>;
let DwarfRegNum = [22] in def H : TLCS900Reg<"h", 6>;

// 16-bit registers
let SubRegIndices = [sub_8bit, sub_8bit_hi], CoveredBySubRegs = 1 in {
let DwarfRegNum = [8]  in def WA : TLCS900Reg<"wa", 0, [A,W]>;
let DwarfRegNum = [9]  in def BC : TLCS900Reg<"bc", 1, [C,B]>;
let DwarfRegNum = [10] in def DE : TLCS900Reg<"de", 2, [E,D]>;
let DwarfRegNum = [11] in def HL : TLCS900Reg<"hl", 3, [L,H]>;
}

// 16-bit registers
let DwarfRegNum = [12] in def IX : TLCS900Reg<"ix", 4>;
let DwarfRegNum = [13] in def IY : TLCS900Reg<"iy", 5>;
let DwarfRegNum = [14] in def IZ : TLCS900Reg<"iz", 6>;
let DwarfRegNum = [15] in def SP : TLCS900Reg<"sp", 7>;

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
let DwarfRegNum = [0] in def XWA : TLCS900Reg<"xwa", 0, [WA, HWA]>;
let DwarfRegNum = [1] in def XBC : TLCS900Reg<"xbc", 1, [BC, HBC]>;
let DwarfRegNum = [2] in def XDE : TLCS900Reg<"xde", 2, [DE, HDE]>;
let DwarfRegNum = [3] in def XHL : TLCS900Reg<"xhl", 3, [HL, HHL]>;
let DwarfRegNum = [4] in def XIX : TLCS900Reg<"xix", 4, [IX, HIX]>;
let DwarfRegNum = [5] in def XIY : TLCS900Reg<"xiy", 5, [IY, HIY]>;
let DwarfRegNum = [6] in def XIZ : TLCS900Reg<"xiz", 6, [IZ, HIZ]>;
let DwarfRegNum = [7] in def XSP : TLCS900Reg<"xsp", 7, [SP, HSP]>;
}

// Status Register (flags) — not allocatable, used implicitly by compare/branch
let DwarfRegNum = [24] in
def SR : TLCS900Reg<"sr", 8>;

// Program Counter — not directly accessible in instructions, but needed for
// DWARF unwinding as the return address register.
let DwarfRegNum = [25] in
def PC : TLCS900Reg<"pc", 9>;

// The order of registers represents the preferred allocation sequence.
// Registers are listed in the order caller-save, callee-save, specials.

def GR8 : RegisterClass<"TLCS900", [i8],  8,
                        (add W, A, B, C, D, E, H, L)>;

def GR16 : RegisterClass<"TLCS900", [i16], 16,
                         (add WA, BC, DE, HL, IX, IY, IZ)>;

def GPR : RegisterClass<"TLCS900", [i32], 32,
                         (add XWA, XBC, XDE, XHL, XIX, XIY, XIZ, XSP)>;

// GPR registers that have 8-bit sub-registers (for byte operations).
// XIX/XIY/XIZ/XSP lack 8-bit sub-registers on TLCS-900.
def GPR_with_sub8 : RegisterClass<"TLCS900", [i32], 32,
                                   (add XWA, XBC, XDE, XHL)>;
