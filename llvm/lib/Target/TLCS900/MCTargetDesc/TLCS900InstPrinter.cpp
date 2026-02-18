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

#include "TLCS900InstrInfo.h"
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
    if (DispVal > 0)
      O << "+" << DispVal;
    else if (DispVal < 0)
      O << DispVal;
  }

  O << ")";
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
