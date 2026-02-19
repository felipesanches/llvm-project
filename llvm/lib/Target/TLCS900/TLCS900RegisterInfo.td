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
// DWARF register numbers: 8-bit regs = 16-23
// Low registers
def A : TLCS900Reg<"a", 1>, DwarfRegNum<[17]>;
def C : TLCS900Reg<"c", 3>, DwarfRegNum<[19]>;
def E : TLCS900Reg<"e", 5>, DwarfRegNum<[21]>;
def L : TLCS900Reg<"l", 7>, DwarfRegNum<[23]>;

// High registers
def W : TLCS900Reg<"w", 0>, DwarfRegNum<[16]>;
def B : TLCS900Reg<"b", 2>, DwarfRegNum<[18]>;
def D : TLCS900Reg<"d", 4>, DwarfRegNum<[20]>;
def H : TLCS900Reg<"h", 6>, DwarfRegNum<[22]>;

// 16-bit registers (with 8-bit sub-register pairs)
// DWARF register numbers: 16-bit regs = 8-15
let SubRegIndices = [sub_8bit, sub_8bit_hi], CoveredBySubRegs = 1 in {
def WA : TLCS900Reg<"wa", 0, [A,W]>, DwarfRegNum<[8]>;
def BC : TLCS900Reg<"bc", 1, [C,B]>, DwarfRegNum<[9]>;
def DE : TLCS900Reg<"de", 2, [E,D]>, DwarfRegNum<[10]>;
def HL : TLCS900Reg<"hl", 3, [L,H]>, DwarfRegNum<[11]>;
}

// 16-bit registers (index/stack pointer — no 8-bit sub-registers)
def IX : TLCS900Reg<"ix", 4>, DwarfRegNum<[12]>;
def IY : TLCS900Reg<"iy", 5>, DwarfRegNum<[13]>;
def IZ : TLCS900Reg<"iz", 6>, DwarfRegNum<[14]>;
def SP : TLCS900Reg<"sp", 7>, DwarfRegNum<[15]>;

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
// DWARF register numbers: 32-bit regs = 0-7
let SubRegIndices = [sub_16bit, sub_16bit_hi], CoveredBySubRegs = 1 in {
def XWA : TLCS900Reg<"xwa", 0, [WA, HWA]>, DwarfRegNum<[0]>;
def XBC : TLCS900Reg<"xbc", 1, [BC, HBC]>, DwarfRegNum<[1]>;
def XDE : TLCS900Reg<"xde", 2, [DE, HDE]>, DwarfRegNum<[2]>;
def XHL : TLCS900Reg<"xhl", 3, [HL, HHL]>, DwarfRegNum<[3]>;
def XIX : TLCS900Reg<"xix", 4, [IX, HIX]>, DwarfRegNum<[4]>;
def XIY : TLCS900Reg<"xiy", 5, [IY, HIY]>, DwarfRegNum<[5]>;
def XIZ : TLCS900Reg<"xiz", 6, [IZ, HIZ]>, DwarfRegNum<[6]>;
def XSP : TLCS900Reg<"xsp", 7, [SP, HSP]>, DwarfRegNum<[7]>;
}

// Status Register (flags) — not allocatable, used implicitly by compare/branch
def SR : TLCS900Reg<"sr", 8>, DwarfRegNum<[24]>;

// Program Counter — not directly accessible in instructions, but needed for
// DWARF unwinding as the return address register.
def PC : TLCS900Reg<"pc", 9>, DwarfRegNum<[25]>;

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
