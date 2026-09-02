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

void TLCS900InstPrinter::printMemOperand(const MCInst *MI, unsigned OpNo,
                                          raw_ostream &O) {
  const MCOperand &Base = MI->getOperand(OpNo);
  const MCOperand &Disp = MI->getOperand(OpNo + 1);

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
