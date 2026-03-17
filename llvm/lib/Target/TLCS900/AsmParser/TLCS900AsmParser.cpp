//===-- TLCS900AsmParser.cpp - Parse TLCS900 assembly to MCInst instructions ---===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TargetInfo/TLCS900TargetInfo.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCParser/MCAsmLexer.h"
#include "llvm/MC/MCParser/MCParsedAsmOperand.h"
#include "llvm/MC/MCParser/MCTargetAsmParser.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Casting.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-asm-parser"

namespace {

/// TLCS900Operand - Instances of this class represent a parsed TLCS900
/// machine instruction operand.
class TLCS900Operand : public MCParsedAsmOperand {
  enum KindTy { k_Token, k_Register, k_Immediate, k_Memory, k_CondCode } Kind;

  SMLoc StartLoc, EndLoc;

  struct MemOp {
    MCRegister Base;
    const MCExpr *Disp;
  };

  union {
    StringRef Tok;
    MCRegister Reg;
    const MCExpr *Imm;
    MemOp Mem;
    unsigned CC;
  };

public:
  TLCS900Operand(KindTy K, SMLoc S, SMLoc E)
      : Kind(K), StartLoc(S), EndLoc(E) {}

  bool isToken() const override { return Kind == k_Token; }
  bool isReg() const override { return Kind == k_Register; }
  bool isImm() const override { return Kind == k_Immediate; }
  bool isMem() const override { return Kind == k_Memory; }
  bool isMemri() const { return Kind == k_Memory; }
  bool isCondCode() const { return Kind == k_CondCode; }

  SMLoc getStartLoc() const override { return StartLoc; }
  SMLoc getEndLoc() const override { return EndLoc; }

  MCRegister getReg() const override {
    assert(Kind == k_Register && "Invalid access!");
    return Reg;
  }

  StringRef getToken() const {
    assert(Kind == k_Token && "Invalid access!");
    return Tok;
  }

  const MCExpr *getImm() const {
    assert(Kind == k_Immediate && "Invalid access!");
    return Imm;
  }

  unsigned getCondCode() const {
    assert(Kind == k_CondCode && "Invalid access!");
    return CC;
  }

  void addRegOperands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    Inst.addOperand(MCOperand::createReg(getReg()));
  }

  void addImmOperands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    if (const auto *CE = dyn_cast<MCConstantExpr>(getImm()))
      Inst.addOperand(MCOperand::createImm(CE->getValue()));
    else
      Inst.addOperand(MCOperand::createExpr(getImm()));
  }

  void addMemriOperands(MCInst &Inst, unsigned N) const {
    assert(N == 2 && "Invalid number of operands!");
    assert(Kind == k_Memory);
    if (Mem.Base) {
      // Register-indirect: existing path
      Inst.addOperand(MCOperand::createReg(Mem.Base));
      if (const auto *CE = dyn_cast<MCConstantExpr>(Mem.Disp))
        Inst.addOperand(MCOperand::createImm(CE->getValue()));
      else
        Inst.addOperand(MCOperand::createExpr(Mem.Disp));
    } else {
      // Direct memory: (addr_expr) — expression as base, 0 as disp
      Inst.addOperand(MCOperand::createExpr(Mem.Disp));
      Inst.addOperand(MCOperand::createImm(0));
    }
  }

  void addCondCodeOperands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    Inst.addOperand(MCOperand::createImm(getCondCode()));
  }

  static std::unique_ptr<TLCS900Operand> createToken(StringRef Str, SMLoc S) {
    auto Op = std::make_unique<TLCS900Operand>(k_Token, S, S);
    Op->Tok = Str;
    return Op;
  }

  static std::unique_ptr<TLCS900Operand> createReg(MCRegister Reg, SMLoc S,
                                                    SMLoc E) {
    auto Op = std::make_unique<TLCS900Operand>(k_Register, S, E);
    Op->Reg = Reg;
    return Op;
  }

  static std::unique_ptr<TLCS900Operand> createImm(const MCExpr *Val, SMLoc S,
                                                    SMLoc E) {
    auto Op = std::make_unique<TLCS900Operand>(k_Immediate, S, E);
    Op->Imm = Val;
    return Op;
  }

  static std::unique_ptr<TLCS900Operand> createMem(MCRegister Base,
                                                    const MCExpr *Disp,
                                                    SMLoc S, SMLoc E) {
    auto Op = std::make_unique<TLCS900Operand>(k_Memory, S, E);
    Op->Mem.Base = Base;
    Op->Mem.Disp = Disp;
    return Op;
  }

  static std::unique_ptr<TLCS900Operand> createCondCode(unsigned CC, SMLoc S,
                                                         SMLoc E) {
    auto Op = std::make_unique<TLCS900Operand>(k_CondCode, S, E);
    Op->CC = CC;
    return Op;
  }

  void print(raw_ostream &OS) const override {
    switch (Kind) {
    case k_Token:
      OS << "Token: " << Tok;
      break;
    case k_Register:
      OS << "Reg: " << Reg;
      break;
    case k_Immediate:
      OS << "Imm: ";
      Imm->print(OS, nullptr);
      break;
    case k_Memory:
      OS << "Mem: " << Mem.Base << "+";
      Mem.Disp->print(OS, nullptr);
      break;
    case k_CondCode:
      OS << "CC: " << CC;
      break;
    }
  }
};

class TLCS900AsmParser : public MCTargetAsmParser {
  const MCSubtargetInfo &STI;
  MCAsmParser &Parser;

#define GET_ASSEMBLER_HEADER
#include "TLCS900GenAsmMatcher.inc"

  bool matchAndEmitInstruction(SMLoc IDLoc, unsigned &Opcode,
                               OperandVector &Operands, MCStreamer &Out,
                               uint64_t &ErrorInfo,
                               bool MatchingInlineAsm) override;

  bool parseRegister(MCRegister &Reg, SMLoc &StartLoc,
                     SMLoc &EndLoc) override;

  ParseStatus tryParseRegister(MCRegister &Reg, SMLoc &StartLoc,
                               SMLoc &EndLoc) override;

  bool parseInstruction(ParseInstructionInfo &Info, StringRef Name,
                        SMLoc NameLoc, OperandVector &Operands) override;

  ParseStatus parseDirective(AsmToken DirectiveID) override;

  // Custom operand parsers (called by MatchOperandParserImpl)
  ParseStatus parseMemriOperand(OperandVector &Operands);
  ParseStatus parseCondCodeOperand(OperandVector &Operands);

  bool parseOperand(OperandVector &Operands);

public:
  TLCS900AsmParser(const MCSubtargetInfo &STI, MCAsmParser &Parser,
                   const MCInstrInfo &MII, const MCTargetOptions &Options)
      : MCTargetAsmParser(Options, STI, MII), STI(STI), Parser(Parser) {
    MCAsmParserExtension::Initialize(Parser);
    setAvailableFeatures(ComputeAvailableFeatures(STI.getFeatureBits()));

    // Register directive aliases for data emission.
    // TLCS-900 uses .hword (16-bit) and .word (32-bit) in MCAsmInfo,
    // but the generic parser only knows .2byte/.4byte/.8byte.
    Parser.addAliasForDirective(".hword", ".2byte");
    Parser.addAliasForDirective(".word", ".4byte");
    Parser.addAliasForDirective(".dword", ".8byte");
  }
};

} // end anonymous namespace

#define GET_REGISTER_MATCHER
#define GET_MATCHER_IMPLEMENTATION
#include "TLCS900GenAsmMatcher.inc"

bool TLCS900AsmParser::matchAndEmitInstruction(SMLoc IDLoc, unsigned &Opcode,
                                               OperandVector &Operands,
                                               MCStreamer &Out,
                                               uint64_t &ErrorInfo,
                                               bool MatchingInlineAsm) {
  MCInst Inst;

  switch (MatchInstructionImpl(Operands, Inst, ErrorInfo, MatchingInlineAsm)) {
  case Match_Success:
    Inst.setLoc(IDLoc);
    Out.emitInstruction(Inst, STI);
    return false;
  case Match_MissingFeature:
    return Error(IDLoc,
                 "instruction requires a CPU feature not currently enabled");
  case Match_MnemonicFail:
    return Error(IDLoc, "unrecognized instruction mnemonic");
  case Match_InvalidOperand: {
    SMLoc ErrorLoc = IDLoc;
    if (ErrorInfo != ~0ULL && ErrorInfo < Operands.size()) {
      ErrorLoc = ((TLCS900Operand &)*Operands[ErrorInfo]).getStartLoc();
      if (ErrorLoc == SMLoc())
        ErrorLoc = IDLoc;
    }
    return Error(ErrorLoc, "invalid operand for instruction");
  }
  }

  llvm_unreachable("Unexpected match result");
}

bool TLCS900AsmParser::parseRegister(MCRegister &Reg, SMLoc &StartLoc,
                                     SMLoc &EndLoc) {
  auto Res = tryParseRegister(Reg, StartLoc, EndLoc);
  if (Res.isNoMatch())
    return Error(StartLoc, "expected register");
  return Res.isFailure();
}

ParseStatus TLCS900AsmParser::tryParseRegister(MCRegister &Reg,
                                               SMLoc &StartLoc,
                                               SMLoc &EndLoc) {
  if (getLexer().isNot(AsmToken::Identifier))
    return ParseStatus::NoMatch;

  StringRef Name = getLexer().getTok().getString();
  Reg = MatchRegisterName(Name.lower());
  if (!Reg)
    return ParseStatus::NoMatch;

  StartLoc = getLexer().getLoc();
  EndLoc = SMLoc::getFromPointer(StartLoc.getPointer() + Name.size());
  Parser.Lex(); // consume register name
  return ParseStatus::Success;
}

/// parseMemriOperand - Parse a memory operand:
///   (reg), (reg+disp), (reg-disp) — register-indirect
///   (symbol), (0x1234), (.equ_const) — direct memory addressing
ParseStatus TLCS900AsmParser::parseMemriOperand(OperandVector &Operands) {
  SMLoc S = getLexer().getLoc();

  if (getLexer().isNot(AsmToken::LParen))
    return ParseStatus::NoMatch;

  Parser.Lex(); // consume '('

  // Try register-indirect: (reg) or (reg+disp)
  MCRegister Reg;
  if (getLexer().is(AsmToken::Identifier)) {
    StringRef RegName = getLexer().getTok().getString();
    Reg = MatchRegisterName(RegName.lower());
    if (Reg) {
      Parser.Lex(); // consume register

      const MCExpr *Disp = MCConstantExpr::create(0, getContext());
      if (getLexer().is(AsmToken::Plus)) {
        Parser.Lex(); // consume '+'
        if (getParser().parseExpression(Disp))
          return ParseStatus::Failure;
      } else if (getLexer().is(AsmToken::Minus)) {
        // parseExpression handles the negative sign
        if (getParser().parseExpression(Disp))
          return ParseStatus::Failure;
      }

      if (getLexer().isNot(AsmToken::RParen))
        return Error(getLexer().getLoc(), "expected ')'");

      SMLoc E = SMLoc::getFromPointer(getLexer().getLoc().getPointer() + 1);
      Parser.Lex(); // consume ')'
      Operands.push_back(TLCS900Operand::createMem(Reg, Disp, S, E));
      return ParseStatus::Success;
    }
    // Not a register — fall through to expression parsing
  }

  // Direct memory: (symbol), (0x1234), (.equ_const)
  const MCExpr *Addr;
  if (getParser().parseExpression(Addr))
    return ParseStatus::Failure;

  if (getLexer().isNot(AsmToken::RParen))
    return Error(getLexer().getLoc(), "expected ')'");

  SMLoc E = SMLoc::getFromPointer(getLexer().getLoc().getPointer() + 1);
  Parser.Lex(); // consume ')'
  Operands.push_back(TLCS900Operand::createMem(MCRegister(), Addr, S, E));
  return ParseStatus::Success;
}

/// parseCondCodeOperand - Parse a condition code: z, nz, c, nc, lt, ge, etc.
ParseStatus TLCS900AsmParser::parseCondCodeOperand(OperandVector &Operands) {
  SMLoc S = getLexer().getLoc();

  if (getLexer().isNot(AsmToken::Identifier))
    return ParseStatus::NoMatch;

  StringRef Name = getLexer().getTok().getString();

  unsigned CC = StringSwitch<unsigned>(Name.lower())
                    .Case("f", TLCS900CC::COND_F)
                    .Case("lt", TLCS900CC::COND_LT)
                    .Case("le", TLCS900CC::COND_LE)
                    .Case("ule", TLCS900CC::COND_ULE)
                    .Case("ov", TLCS900CC::COND_OV)
                    .Case("pe", TLCS900CC::COND_OV)    // alias: PE = OV
                    .Case("mi", TLCS900CC::COND_MI)
                    .Case("z", TLCS900CC::COND_Z)
                    .Case("c", TLCS900CC::COND_C)
                    .Case("t", TLCS900CC::COND_T)
                    .Case("ge", TLCS900CC::COND_GE)
                    .Case("gt", TLCS900CC::COND_GT)
                    .Case("ugt", TLCS900CC::COND_UGT)
                    .Case("nov", TLCS900CC::COND_NOV)
                    .Case("po", TLCS900CC::COND_NOV)   // alias: PO = NOV
                    .Case("pl", TLCS900CC::COND_PL)
                    .Case("nz", TLCS900CC::COND_NZ)
                    .Case("nc", TLCS900CC::COND_NC)
                    .Default(~0U);

  if (CC == ~0U)
    return ParseStatus::NoMatch;

  SMLoc E = SMLoc::getFromPointer(S.getPointer() + Name.size());
  Parser.Lex(); // consume identifier

  Operands.push_back(TLCS900Operand::createCondCode(CC, S, E));
  return ParseStatus::Success;
}

/// parseOperand - Parse a single generic operand (register, immediate, or
/// literal token like parentheses).
bool TLCS900AsmParser::parseOperand(OperandVector &Operands) {
  SMLoc S = getLexer().getLoc();

  // Try register
  if (getLexer().is(AsmToken::Identifier)) {
    StringRef Name = getLexer().getTok().getString();
    MCRegister Reg = MatchRegisterName(Name.lower());
    if (Reg) {
      SMLoc E = SMLoc::getFromPointer(S.getPointer() + Name.size());
      Operands.push_back(TLCS900Operand::createReg(Reg, S, E));
      Parser.Lex(); // consume register
      return false;
    }
    // Not a register — fall through to expression parsing
  }

  // Literal '(' — add as token (for 'call (reg)' syntax)
  if (getLexer().is(AsmToken::LParen)) {
    Operands.push_back(TLCS900Operand::createToken("(", S));
    Parser.Lex();
    return false;
  }

  // Literal ')' — add as token
  if (getLexer().is(AsmToken::RParen)) {
    Operands.push_back(TLCS900Operand::createToken(")", S));
    Parser.Lex();
    return false;
  }

  // Try expression (immediate, label, etc.)
  const MCExpr *Expr;
  if (getParser().parseExpression(Expr))
    return Error(S, "unknown operand");

  SMLoc E = SMLoc::getFromPointer(getLexer().getLoc().getPointer());
  Operands.push_back(TLCS900Operand::createImm(Expr, S, E));
  return false;
}

bool TLCS900AsmParser::parseInstruction(ParseInstructionInfo &Info,
                                        StringRef Name, SMLoc NameLoc,
                                        OperandVector &Operands) {
  // Add the mnemonic as the first operand.
  Operands.push_back(TLCS900Operand::createToken(Name, NameLoc));

  // If no operands, we're done.
  if (getLexer().is(AsmToken::EndOfStatement))
    return false;

  // Parse operands.
  while (true) {
    // Try custom operand parsers first (MEMri, CondCode).
    ParseStatus Res = MatchOperandParserImpl(Operands, Name);
    if (Res.isSuccess()) {
      if (getLexer().is(AsmToken::Comma))
        Parser.Lex(); // consume comma
      if (getLexer().is(AsmToken::EndOfStatement))
        break;
      continue;
    }
    if (Res.isFailure())
      return true;

    // Generic operand parsing.
    if (parseOperand(Operands))
      return true;

    if (getLexer().is(AsmToken::Comma))
      Parser.Lex(); // consume comma

    if (getLexer().is(AsmToken::EndOfStatement))
      break;
  }

  return false;
}

ParseStatus TLCS900AsmParser::parseDirective(AsmToken DirectiveID) {
  // No custom directives yet.
  return ParseStatus::NoMatch;
}

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900AsmParser() {
  RegisterMCAsmParser<TLCS900AsmParser> X(getTheTLCS900Target());
}
