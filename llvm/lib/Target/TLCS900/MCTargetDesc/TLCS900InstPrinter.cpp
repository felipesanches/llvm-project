//===-- TLCS900InstPrinter.cpp - Convert TLCS900 MCInst to assembly syntax ----===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This class prints an TLCS900 MCInst to a .s file.
//
//===----------------------------------------------------------------------===//

#include "TLCS900InstPrinter.h"
#include "TLCS900BaseInfo.h"

#include "TLCS900MCTargetDesc.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "tlcs900-isel"

#define PRINT_ALIAS_INSTR
#include "TLCS900GenAsmWriter.inc"

void TLCS900InstPrinter::printInst(const MCInst *MI, uint64_t Address,
                                   StringRef Annot, const MCSubtargetInfo &STI,
                                   raw_ostream &O) {
  // Try to print any aliases first.
  if (!printAliasInstr(MI, Address, O)) {
    printInstruction(MI, Address, O);
  }
  printAnnotation(O, Annot);
}

void TLCS900InstPrinter::printOperand(const MCInst *MI, unsigned OpNo,
                                      raw_ostream &O) {
  const MCOperand &Op = MI->getOperand(OpNo);
  if (Op.isReg()) {
    O << StringRef(getRegisterName(Op.getReg())).lower();
    return;
  }

  if (Op.isImm()) {
    O << Op.getImm();
    return;
  }

  assert(Op.isExpr() && "unknown operand kind in printOperand");
  Op.getExpr()->print(O, &MAI, true);
}

void TLCS900InstPrinter::printDirectAddr(const MCInst *MI, unsigned OpNo,
                                          raw_ostream &O) {
  O << "(";
  printOperand(MI, OpNo, O);
  O << ")";
}

// The 8-bit direct address of the I/O short form, `(n:8)`: the width is
// stated so the assembler's daddr8 operand accepts the text back.
void TLCS900InstPrinter::printDirectAddr8(const MCInst *MI, unsigned OpNo,
                                           raw_ostream &O) {
  O << "(";
  printOperand(MI, OpNo, O);
  O << ":8)";
}

void TLCS900InstPrinter::printMemOperand(const MCInst *MI, unsigned OpNo,
                                          raw_ostream &O) {
  const MCOperand &Base = MI->getOperand(OpNo);
  const MCOperand &Disp = MI->getOperand(OpNo + 1);

  // POST-INCREMENT / PRE-DECREMENT, `(xde+)` / `(-xde)`.  The step is printed
  // only where the instruction's data size does not already imply it -- and
  // always for LDA and JP/CALL cc, which move no data: `(xwa+:1)`.
  if (Disp.isImm() && TLCS900II::isAutoInc(Disp.getImm())) {
    int64_t V = Disp.getImm();
    unsigned Byte = TLCS900II::getAutoIncRegByte(V);
    const char *Name = TLCS900II::getAutoIncRegName(Byte & 0xFC);
    unsigned Step = 1u << (Byte & 3);
    unsigned Natural =
        TLCS900II::getAutoIncNaturalStep(MII.get(MI->getOpcode()).TSFlags);
    bool Pre = TLCS900II::isAutoIncPreDec(V);
    O << "(" << (Pre ? "-" : "") << (Name ? Name : "?") << (Pre ? "" : "+");
    if (Natural == 0 || Step != Natural)
      O << ":" << Step;
    O << ")";
    return;
  }

  O << "(";
  if (Base.isReg())
    O << StringRef(getRegisterName(Base.getReg())).lower();
  else if (Base.isExpr())
    Base.getExpr()->print(O, &MAI, true);
  else if (Base.isImm())
    O << Base.getImm();

  if (Disp.isImm()) {
    int64_t DispVal = Disp.getImm();
    if (!Base.isReg() && TLCS900II::isDirectAddrWidth(DispVal)) {
      // A DIRECT memory operand has no displacement; the slot carries the
      // requested address width, which prints back as the `:8`/`:16`/`:24`
      // suffix the assembler accepts.
      O << ":" << (TLCS900II::getDirectAddrBytes(DispVal) * 8);
    } else if (Base.isReg() && TLCS900II::isForcedDisp(DispVal)) {
      // A requested displacement width, `(xsp+0:8)` / `(xiz+5:16)`: the
      // encoding the bytes use is not the one the value alone would pick.
      int64_t D = TLCS900II::getForcedDispValue(DispVal);
      if (D >= 0)
        O << "+";
      O << D << ":" << (TLCS900II::getForcedDispBytes(DispVal) * 8);
    } else if (DispVal > 0) {
      O << "+" << DispVal;
    } else if (DispVal < 0) {
      O << DispVal;
    }
  }

  O << ")";
}

// `(Xrr+Rn)` -- the REGISTER-INDEXED operand.  Two register operands, never a
// displacement: `(xbc+wa)` is [prefix, 0x07, 0xE4, 0xE0, sub] and is a wholly
// different encoding from `(xbc+0)`, which is [prefix, 0xE4, sub].
void TLCS900InstPrinter::printMemrrOperand(const MCInst *MI, unsigned OpNo,
                                           raw_ostream &O) {
  O << "(" << StringRef(getRegisterName(MI->getOperand(OpNo).getReg())).lower()
    << "+"
    << StringRef(getRegisterName(MI->getOperand(OpNo + 1).getReg())).lower()
    << ")";
}

void TLCS900InstPrinter::printCondCode(const MCInst *MI, unsigned OpNo,
                                        raw_ostream &O) {
  static const char *const CondNames[] = {
    "f", "lt", "le", "ule", "ov", "mi", "z", "c",
    "t", "ge", "gt", "ugt", "nov", "pl", "nz", "nc"
  };
  unsigned CC = MI->getOperand(OpNo).getImm();
  assert(CC < 16 && "Invalid condition code");
  O << CondNames[CC];
}

void TLCS900InstPrinter::printGPRAsLoByte(const MCInst *MI, unsigned OpNo,
                                           raw_ostream &O) {
  unsigned Reg = MI->getOperand(OpNo).getReg();
  // Map 32-bit GPR to its low 8-bit sub-register name.
  // Only XWA/XBC/XDE/XHL have 8-bit sub-registers.
  switch (Reg) {
  case TLCS900::XWA: O << "a"; break;
  case TLCS900::XBC: O << "c"; break;
  case TLCS900::XDE: O << "e"; break;
  case TLCS900::XHL: O << "l"; break;
  default: llvm_unreachable("Register has no 8-bit sub-register");
  }
}

// The 16-bit result pair of a byte MUL/DIV, carried as the GR8 of its low
// byte: A -> wa, C -> bc, E -> de, L -> hl.  An even register field has no
// pair (MAME prints "??"); the decoder refuses it, so reaching one here means
// an MCInst built by hand.
void TLCS900InstPrinter::printMulPair8(const MCInst *MI, unsigned OpNo,
                                       raw_ostream &O) {
  switch (MI->getOperand(OpNo).getReg()) {
  case TLCS900::A: O << "wa"; break;
  case TLCS900::C: O << "bc"; break;
  case TLCS900::E: O << "de"; break;
  case TLCS900::L: O << "hl"; break;
  default:
    O << "<no-pair:"
      << StringRef(getRegisterName(MI->getOperand(OpNo).getReg())).lower()
      << ">";
    break;
  }
}

// The 32-bit result of a word MUL/DIV, carried as the GR16 of the same field.
void TLCS900InstPrinter::printGR16AsX(const MCInst *MI, unsigned OpNo,
                                      raw_ostream &O) {
  O << "x"
    << StringRef(getRegisterName(MI->getOperand(OpNo).getReg())).lower();
}

void TLCS900InstPrinter::printGPRAsLoWord(const MCInst *MI, unsigned OpNo,
                                           raw_ostream &O) {
  unsigned Reg = MI->getOperand(OpNo).getReg();
  // Map 32-bit GPR to its low 16-bit sub-register name.
  switch (Reg) {
  case TLCS900::XWA: O << "wa"; break;
  case TLCS900::XBC: O << "bc"; break;
  case TLCS900::XDE: O << "de"; break;
  case TLCS900::XHL: O << "hl"; break;
  case TLCS900::XIX: O << "ix"; break;
  case TLCS900::XIY: O << "iy"; break;
  case TLCS900::XIZ: O << "iz"; break;
  case TLCS900::XSP: O << "sp"; break;
  default: llvm_unreachable("Invalid GPR for 16-bit operation");
  }
}
