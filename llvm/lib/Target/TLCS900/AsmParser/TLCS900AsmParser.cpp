//===-- TLCS900AsmParser.cpp - Parse TLCS900 assembly to MCInst instructions ---===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "TLCS900BaseInfo.h"
#include "MCTargetDesc/TLCS900MCTargetDesc.h"
#include "TargetInfo/TLCS900TargetInfo.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/Twine.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCParser/MCAsmLexer.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCParser/MCParsedAsmOperand.h"
#include "llvm/MC/MCParser/MCTargetAsmParser.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/MathExtras.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-asm-parser"

namespace {

/// TLCS900Operand - Instances of this class represent a parsed TLCS900
/// machine instruction operand.
class TLCS900Operand : public MCParsedAsmOperand {
  enum KindTy { k_Token, k_Register, k_Immediate, k_Memory, k_MemoryRR,
                k_CondCode } Kind;

  SMLoc StartLoc, EndLoc;

  struct MemOp {
    MCRegister Base;
    const MCExpr *Disp;
    // For the REGISTER-INDEXED operand `(Xrr+Rn)` (k_MemoryRR) this holds the
    // index register.  The index is a register, not a displacement, and the
    // two are different encodings -- see parseMemriOperand.
    MCRegister Index;
    // For a DIRECT memory operand `(addr)`, the address width the source
    // asked for, in bytes (1, 2 or 3); 0 means "unspecified".  See
    // TLCS900II::DirectAddrWidth -- the width is part of the encoding and
    // cannot be inferred from the address value.
    unsigned AddrBytes;
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
  bool isMem() const override {
    return Kind == k_Memory || Kind == k_MemoryRR;
  }
  bool isMemri() const { return Kind == k_Memory; }

  // `(Xrr+Rn)` -- three flavours, distinguished by the INDEX register's class,
  // because the register-file address the encoder writes differs for each:
  // a current-bank word register (0xE0 + enc*4), a previous-bank word register
  // (+2), or one of the eight byte halves of WA/BC/DE/HL.
  bool isMemrrIdxIn(unsigned RCID) const {
    return Kind == k_MemoryRR &&
           TLCS900MCRegisterClasses[RCID].contains(Mem.Index);
  }
  bool isMemrr() const { return isMemrrIdxIn(TLCS900::GR16RegClassID); }
  bool isMemrr8() const { return isMemrrIdxIn(TLCS900::GR8RegClassID); }
  bool isMemrrq() const { return isMemrrIdxIn(TLCS900::PrevGR16RegClassID); }
  bool isDirectAddr() const { return Kind == k_Immediate; }

  // A PARENTHESISED direct address, and nothing else.
  //
  // ⚠ `directaddr` above answers true to a BARE IMMEDIATE, because that is
  // what its parser leaves behind.  Reusing it for the memory-to-memory
  // operand silently re-encoded an existing spelling: `ldw (xwa), 36152` --
  // a store-immediate written in hundreds of places -- started matching
  // `ldw (mem),(nn)` and moved from b0 02 38 8d to b0 16 38 8d.  A form
  // whose operand must be an ADDRESS has to reject a value.
  bool isDaddr16() const {
    return Kind == k_Memory && !Mem.Base &&
           (Mem.AddrBytes == 0 || Mem.AddrBytes == 2);
  }

  // An 8-bit direct address for the I/O short form (`:io`), written `(n:8)`.
  // AddrBytes == 1 EXACTLY: an unsuffixed `(n)` keeps its 24-bit default
  // everywhere, so the width is still never inferred.  The address must be a
  // constant in 0..255 -- LdIoImm's encoder has no fixup for it and would
  // otherwise emit 0x00 or a truncated byte in silence.
  bool isDaddr8() const {
    if (Kind != k_Memory || Mem.Base || Mem.AddrBytes != 1)
      return false;
    const auto *CE = dyn_cast<MCConstantExpr>(Mem.Disp);
    return CE && isUInt<8>(CE->getValue());
  }

  // The `:i3` immediate: the value is packed into the opcode byte's low three
  // bits.  No relocation can reach an opcode field, so a symbol is never
  // legitimate here, and a value outside 0..7 does not fit.
  bool isImmI3() const {
    if (Kind != k_Immediate)
      return false;
    const auto *CE = dyn_cast<MCConstantExpr>(Imm);
    return CE && isUInt<3>(CE->getValue());
  }

  // The `:io` immediates.  LdIoImm / LdIoImm16 emit no fixup and push a
  // literal 0 for anything that is not a constant, so a constant is required.
  bool isImmIO8() const {
    if (Kind != k_Immediate)
      return false;
    const auto *CE = dyn_cast<MCConstantExpr>(Imm);
    return CE && (isInt<8>(CE->getValue()) || isUInt<8>(CE->getValue()));
  }
  bool isImmIO16() const {
    if (Kind != k_Immediate)
      return false;
    const auto *CE = dyn_cast<MCConstantExpr>(Imm);
    return CE && (isInt<16>(CE->getValue()) || isUInt<16>(CE->getValue()));
  }

  bool isCondCode() const { return Kind == k_CondCode; }

  // MUL/DIV registers named as the CPU names them (TLCS900InstrInfo.td,
  // mulpair8 / gr16asx / gpraslo16).  Each accepts ONLY the true name: the
  // old spellings (`mul a, (xbc)` for mul WA,(XBC), `div xwa, xbc` for
  // div XWA,BC) are refused rather than kept as aliases, because `mul wa,
  // (xbc)` used to mean the WORD multiply and now names the byte one -- an
  // alias could not keep both readings.  The tree was respelled in lockstep.
  bool isMulPair8() const {
    return Kind == k_Register &&
           (Reg == TLCS900::WA || Reg == TLCS900::BC || Reg == TLCS900::DE ||
            Reg == TLCS900::HL);
  }
  bool isGR16AsX() const {
    return Kind == k_Register &&
           TLCS900MCRegisterClasses[TLCS900::GPRRegClassID].contains(Reg);
  }
  bool isGPRAsLo16() const {
    return Kind == k_Register &&
           TLCS900MCRegisterClasses[TLCS900::GR16SPRegClassID].contains(Reg);
  }

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

  bool hasMemBase() const {
    assert(Kind == k_Memory && "Invalid access!");
    return Mem.Base.isValid();
  }
  const MCExpr *getMemDisp() const {
    assert(Kind == k_Memory && "Invalid access!");
    return Mem.Disp;
  }
  unsigned getMemAddrBytes() const {
    assert(Kind == k_Memory && "Invalid access!");
    return Mem.AddrBytes;
  }

  void addRegOperands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    Inst.addOperand(MCOperand::createReg(getReg()));
  }

  // The byte multiply's result pair travels as the GR8 of its low byte,
  // whose register field (A=1, C=3, E=5, L=7) is the one the CPU decodes.
  void addMulPair8Operands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    MCRegister R = Reg == TLCS900::WA   ? TLCS900::A
                   : Reg == TLCS900::BC ? TLCS900::C
                   : Reg == TLCS900::DE ? TLCS900::E
                                        : TLCS900::L;
    Inst.addOperand(MCOperand::createReg(R));
  }
  // XWA..XSP -> WA..SP: the same register field.
  void addGR16AsXOperands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    static const MCRegister Lo[8] = {TLCS900::WA, TLCS900::BC, TLCS900::DE,
                                     TLCS900::HL, TLCS900::IX, TLCS900::IY,
                                     TLCS900::IZ, TLCS900::SP};
    static const MCRegister X[8] = {TLCS900::XWA, TLCS900::XBC, TLCS900::XDE,
                                    TLCS900::XHL, TLCS900::XIX, TLCS900::XIY,
                                    TLCS900::XIZ, TLCS900::XSP};
    for (unsigned I = 0; I < 8; ++I)
      if (X[I] == Reg) {
        Inst.addOperand(MCOperand::createReg(Lo[I]));
        return;
      }
    llvm_unreachable("isGR16AsX admitted a non-GPR register");
  }
  // WA..SP -> XWA..XSP: codegen models the 16-bit operand as its GPR.
  void addGPRAsLo16Operands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    static const MCRegister Lo[8] = {TLCS900::WA, TLCS900::BC, TLCS900::DE,
                                     TLCS900::HL, TLCS900::IX, TLCS900::IY,
                                     TLCS900::IZ, TLCS900::SP};
    static const MCRegister X[8] = {TLCS900::XWA, TLCS900::XBC, TLCS900::XDE,
                                    TLCS900::XHL, TLCS900::XIX, TLCS900::XIY,
                                    TLCS900::XIZ, TLCS900::XSP};
    for (unsigned I = 0; I < 8; ++I)
      if (Lo[I] == Reg) {
        Inst.addOperand(MCOperand::createReg(X[I]));
        return;
      }
    llvm_unreachable("isGPRAsLo16 admitted a non-GR16 register");
  }

  void addImmOperands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    if (const auto *CE = dyn_cast<MCConstantExpr>(getImm()))
      Inst.addOperand(MCOperand::createImm(CE->getValue()));
    else
      Inst.addOperand(MCOperand::createExpr(getImm()));
  }

  void addDirectAddrOperands(MCInst &Inst, unsigned N) const {
    addImmOperands(Inst, N);
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
      // Direct memory: (addr_expr) — expression as base.  The displacement
      // slot is unused by the direct form, so it carries the requested
      // address width instead (0 = the default 24-bit form).
      Inst.addOperand(MCOperand::createExpr(Mem.Disp));
      int64_t WidthSentinel = TLCS900II::DirectAddrDefault;
      switch (Mem.AddrBytes) {
      case 1: WidthSentinel = TLCS900II::DirectAddrW8; break;
      case 2: WidthSentinel = TLCS900II::DirectAddrW16; break;
      case 3: WidthSentinel = TLCS900II::DirectAddrW24; break;
      default: break;
      }
      Inst.addOperand(MCOperand::createImm(WidthSentinel));
    }
  }

  void addDaddr16Operands(MCInst &Inst, unsigned N) const {
    assert(N == 1 && "Invalid number of operands!");
    assert(Kind == k_Memory && !Mem.Base);
    if (const auto *CE = dyn_cast<MCConstantExpr>(Mem.Disp))
      Inst.addOperand(MCOperand::createImm(CE->getValue()));
    else
      Inst.addOperand(MCOperand::createExpr(Mem.Disp));
  }

  // One MCOperand, exactly as `i32imm:$addr` rendered before the operand was
  // retyped, so the MCInst layout the encoder sees is unchanged.
  void addDaddr8Operands(MCInst &Inst, unsigned N) const {
    addDaddr16Operands(Inst, N);
  }

  void addMemrrOperands(MCInst &Inst, unsigned N) const {
    assert(N == 2 && "Invalid number of operands!");
    assert(Kind == k_MemoryRR);
    Inst.addOperand(MCOperand::createReg(Mem.Base));
    Inst.addOperand(MCOperand::createReg(Mem.Index));
  }

  void addMemrr8Operands(MCInst &Inst, unsigned N) const {
    addMemrrOperands(Inst, N);
  }

  void addMemrrqOperands(MCInst &Inst, unsigned N) const {
    addMemrrOperands(Inst, N);
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
                                                    SMLoc S, SMLoc E,
                                                    unsigned AddrBytes = 0) {
    auto Op = std::make_unique<TLCS900Operand>(k_Memory, S, E);
    Op->Mem.Base = Base;
    Op->Mem.Disp = Disp;
    Op->Mem.AddrBytes = AddrBytes;
    return Op;
  }

  static std::unique_ptr<TLCS900Operand> createMemRR(MCRegister Base,
                                                     MCRegister Index,
                                                     SMLoc S, SMLoc E) {
    auto Op = std::make_unique<TLCS900Operand>(k_MemoryRR, S, E);
    Op->Mem.Base = Base;
    Op->Mem.Disp = nullptr;
    Op->Mem.Index = Index;
    Op->Mem.AddrBytes = 0;
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
    case k_MemoryRR:
      OS << "MemRR: " << Mem.Base << "+" << Mem.Index;
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
  ParseStatus parseDirectAddrOperand(OperandVector &Operands);
  ParseStatus parseMemriOperand(OperandVector &Operands);
  ParseStatus parseCondCodeOperand(OperandVector &Operands);
  ParseStatus parseEncodingSelector(OperandVector &Operands);
  ParseStatus tryParseAutoIncOperand(OperandVector &Operands);
  bool finalizeMemOperands(MCInst &Inst, SMLoc IDLoc);
  bool parseAddressExpression(const MCExpr *&Res, SMLoc &Loc);

  bool parseOperand(OperandVector &Operands);

public:
  // The Match_<DiagnosticType> codes the generated matcher returns for an
  // AsmOperandClass that declares a DiagnosticType (ImmI3, ImmIO8, ImmIO16,
  // Daddr8).  They land in matchAndEmitInstruction's default arm.
  enum TLCS900MatchResultTy : unsigned {
    Match_Dummy = FIRST_TARGET_MATCH_RESULT_TY,
#define GET_OPERAND_DIAGNOSTIC_TYPES
#include "TLCS900GenAsmMatcher.inc"
#undef GET_OPERAND_DIAGNOSTIC_TYPES
  };

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
    if (finalizeMemOperands(Inst, IDLoc))
      return true;
    Out.emitInstruction(Inst, STI);
    return false;
  case Match_MissingFeature:
    return Error(IDLoc,
                 "instruction requires a CPU feature not currently enabled");
  case Match_MnemonicFail:
    return Error(IDLoc, "unrecognized instruction mnemonic");
  case Match_InvalidOperand:
  default: {
    // An AsmOperandClass that declares a DiagnosticType makes TableGen return
    // its own Match_<Type> code from MatchInstructionImpl, and that code lands
    // here.  Without this arm it would fall into llvm_unreachable: an abort in
    // an assertions build and undefined behaviour in a release one.
    SMLoc ErrorLoc = IDLoc;
    if (ErrorInfo != ~0ULL && ErrorInfo < Operands.size()) {
      const auto &Op = (TLCS900Operand &)*Operands[ErrorInfo];
      ErrorLoc = Op.getStartLoc();
      if (ErrorLoc == SMLoc())
        ErrorLoc = IDLoc;
      // An encoding selector is a literal token; if no matchable took it,
      // this instruction has no encoding under that selector for these
      // operands (or a selector was written where none belongs).
      if (Op.isToken() && Op.getToken().starts_with(":"))
        return Error(ErrorLoc, "no encoding of '" +
                                   ((TLCS900Operand &)*Operands[0]).getToken() +
                                   "' takes the '" + Op.getToken() +
                                   "' selector with these operands");
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

static int autoIncRegAddr(StringRef Name);

/// A name this assembler reads as a REGISTER: a current-bank register
/// (MatchRegisterName) or one of the sixteen bank registers xwa0..xhl3.
static bool isRegisterName(StringRef Name) {
  return MatchRegisterName(Name.lower()) || autoIncRegAddr(Name) >= 0;
}

/// The first symbol reference in E whose name is a register, or null.
static const MCSymbolRefExpr *findRegisterSymbol(const MCExpr *E) {
  switch (E->getKind()) {
  case MCExpr::SymbolRef: {
    const auto *SRE = cast<MCSymbolRefExpr>(E);
    return isRegisterName(SRE->getSymbol().getName()) ? SRE : nullptr;
  }
  case MCExpr::Binary: {
    const auto *BE = cast<MCBinaryExpr>(E);
    if (const MCSymbolRefExpr *R = findRegisterSymbol(BE->getLHS()))
      return R;
    return findRegisterSymbol(BE->getRHS());
  }
  case MCExpr::Unary:
    return findRegisterSymbol(cast<MCUnaryExpr>(E)->getSubExpr());
  default:
    return nullptr;
  }
}

/// parseAddressExpression - parseExpression for an ADDRESS, DISPLACEMENT or
/// IMMEDIATE, refusing an expression that names a register.
///
/// A name the operand parsers do not take as a register falls through to the
/// expression parser, which reads it as a SYMBOL.  `(xbc3)`, `(xwa3+5)` and
/// `(5+xsp)` therefore assembled to a DIRECT address with a relocation
/// against an undefined symbol `xbc3` / `xsp` -- the bytes of another
/// instruction, caught only by the link (and not at all if something defines
/// the symbol).  This is the `(+xde)` trap of TOOLCHAIN_VERSION UPDATE 17 in
/// every other operand shape, so it gets the same answer: a register name is
/// never a symbol.
bool TLCS900AsmParser::parseAddressExpression(const MCExpr *&Res, SMLoc &Loc) {
  Loc = getLexer().getLoc();
  if (getParser().parseExpression(Res))
    return true;
  if (const MCSymbolRefExpr *R = findRegisterSymbol(Res)) {
    StringRef N = R->getSymbol().getName();
    if (autoIncRegAddr(N) >= 0 && !MatchRegisterName(N.lower()))
      return Error(Loc, "'" + N + "' is a bank register; the only operands "
                        "that take one are (" + N + "+) and (-" + N + ")");
    return Error(Loc, "'" + N + "' is a register, not a symbol: a register "
                      "is written first inside the parentheses, (" + N +
                      "+d)");
  }
  return false;
}

/// parseDirectAddrOperand - Parse a parenthesized direct address: (expr)
/// Returns an immediate operand containing the address value.
ParseStatus TLCS900AsmParser::parseDirectAddrOperand(OperandVector &Operands) {
  SMLoc S = getLexer().getLoc();

  if (getLexer().isNot(AsmToken::LParen))
    return ParseStatus::NoMatch;

  // Peek: if next token is a register, this is register-indirect, not direct
  const AsmToken &Next = getLexer().peekTok();
  if (Next.is(AsmToken::Identifier) &&
      MatchRegisterName(Next.getString().lower()) != 0)
    return ParseStatus::NoMatch;

  Parser.Lex(); // consume '('

  const MCExpr *Addr;
  SMLoc ALoc;
  if (parseAddressExpression(Addr, ALoc))
    return ParseStatus::Failure;

  if (getLexer().isNot(AsmToken::RParen))
    return Error(getLexer().getLoc(), "expected ')'");

  SMLoc E = SMLoc::getFromPointer(getLexer().getLoc().getPointer() + 1);
  Parser.Lex(); // consume ')'

  Operands.push_back(TLCS900Operand::createImm(Addr, S, E));
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
      // ⚠ The base of every register-indirect form -- (r), (r+d), (r+D:8),
      // (r+D:16), (r+Rn) -- is a 32-bit register: the encodings hold its
      // 3-bit field (or its register-file address) and nothing else.  Any
      // other register used to be encoded BY INDEX, so `ld a, (a)` assembled
      // ld A,(XBC), `(qiz+0:8)` became (XIZ+0) and `(h-1)` (XIZ-1), in
      // silence.  (R+) / (-R) are parsed before this and say the same.
      if (!TLCS900MCRegisterClasses[TLCS900::GPRRegClassID].contains(Reg))
        return Error(getLexer().getLoc(),
                     "the base of a register-indirect operand is a 32-bit "
                     "register (xwa..xsp), not '" + RegName + "'");
      Parser.Lex(); // consume register

      const MCExpr *Disp = MCConstantExpr::create(0, getContext());
      SMLoc DLoc = getLexer().getLoc();
      if (getLexer().is(AsmToken::Plus)) {
        Parser.Lex(); // consume '+'
        // ⚠ `(Xrr+Rn)` is the REGISTER-INDEXED operand, a DIFFERENT ENCODING
        // from `(Xrr+d16)`: [prefix, 0x07, base_addr, idx_addr, sub_opcode]
        // rather than [prefix, 0xE0+base*4+1, d16, sub_opcode].  Letting
        // parseExpression have the index register turned it into an undefined
        // SYMBOL, so `ld wa,(xix+iz)` assembled to the d16 form -- d3 f1 00 00
        // 20 where the hardware wants d3 07 f0 f8 20 -- and failed only at link
        // time, and only because nothing happened to define a symbol named
        // `iz`.  It is parsed here as its own operand KIND, so the two can
        // never be confused again: an index register cannot reach the
        // displacement slot even when no instruction accepts the R+R form.
        if (getLexer().is(AsmToken::Identifier)) {
          MCRegister Idx =
              MatchRegisterName(getLexer().getTok().getString().lower());
          if (Idx) {
            SMLoc IdxLoc = getLexer().getLoc();
            Parser.Lex(); // consume the index register
            if (getLexer().isNot(AsmToken::RParen))
              return Error(getLexer().getLoc(),
                           "expected ')' after a register-indexed operand");
            SMLoc E2 =
                SMLoc::getFromPointer(getLexer().getLoc().getPointer() + 1);
            Parser.Lex(); // consume ')'
            (void)IdxLoc;
            Operands.push_back(TLCS900Operand::createMemRR(Reg, Idx, S, E2));
            return ParseStatus::Success;
          }
        }
        if (parseAddressExpression(Disp, DLoc))
          return ParseStatus::Failure;
      } else if (getLexer().is(AsmToken::Minus)) {
        // parseExpression handles the negative sign
        if (parseAddressExpression(Disp, DLoc))
          return ParseStatus::Failure;
      }

      // ⚠ A constant displacement must fit the d16 field HERE, before
      // anything else reads it.  A width request `:8` / `:16` and (R+) / (-R)
      // ride in this same immediate as TAG BITS far above d16 (1<<40, 1<<41,
      // 1<<42 -- TLCS900BaseInfo.h), and the encoder trusts a tagged value:
      // `ld a, (xbc+0x40000000005)` assembled c5 05 21 = ld A,(XBC0+), and
      // `(xbc+0x10000000005)` the d8 form, in silence, where the old pin said
      // "too large for d16".
      if (const auto *CE = dyn_cast<MCConstantExpr>(Disp))
        if (!isInt<16>(CE->getValue()))
          return Error(DLoc, "displacement " + Twine(CE->getValue()) +
                                 " does not fit the signed 16-bit (Xrr+d16) "
                                 "field (-32768..32767)");

      // Optional DISPLACEMENT WIDTH request, `(xsp+0:8)` / `(xiz+5:16)`:
      // the (Xrr+d8) and (Xrr+d16) encodings both hold a small displacement,
      // firmware uses both, and the value alone picks only one of them.  Same
      // shape as the direct-address width `(0x8a:24)`.
      if (getLexer().is(AsmToken::Colon)) {
        Parser.Lex(); // consume ':'
        if (getLexer().isNot(AsmToken::Integer))
          return Error(getLexer().getLoc(),
                       "expected a displacement width of 8 or 16 after ':'");
        SMLoc WLoc = getLexer().getLoc();
        int64_t Bits = getLexer().getTok().getIntVal();
        if (Bits != 8 && Bits != 16)
          return Error(WLoc, "a register-indirect displacement width must be "
                             "8 or 16");
        const auto *CE = dyn_cast<MCConstantExpr>(Disp);
        if (!CE)
          return Error(WLoc, "a displacement whose width is written must be a "
                             "constant");
        int64_t D = CE->getValue();
        if ((Bits == 8 && !isInt<8>(D)) || (Bits == 16 && !isInt<16>(D)))
          return Error(WLoc, "displacement " + Twine(D) +
                                 " does not fit the signed " + Twine(Bits) +
                                 "-bit (Xrr+d" + Twine(Bits) + ") field");
        Parser.Lex(); // consume the width
        Disp = MCConstantExpr::create(
            TLCS900II::makeForcedDisp(D, Bits / 8), getContext());
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
  SMLoc ALoc;
  if (parseAddressExpression(Addr, ALoc))
    return ParseStatus::Failure;

  // Optional address-width request: (0x8a:8), (0x2075:16), (0x8a:24).
  // The TLCS-900 has three direct-address widths and picks between them in
  // the prefix byte, so the width is a spelling choice the source has to
  // make -- `set 7,(0x00008a)` really is F2 8A 00 00 BF in shipped firmware.
  // Without a suffix the operand keeps the 24-bit default.
  unsigned AddrBytes = 0;
  if (getLexer().is(AsmToken::Colon)) {
    Parser.Lex(); // consume ':'
    if (getLexer().isNot(AsmToken::Integer))
      return Error(getLexer().getLoc(),
                   "expected an address width of 8, 16 or 24 after ':'");
    int64_t Bits = getLexer().getTok().getIntVal();
    switch (Bits) {
    case 8: AddrBytes = 1; break;
    case 16: AddrBytes = 2; break;
    case 24: AddrBytes = 3; break;
    default:
      return Error(getLexer().getLoc(),
                   "address width must be 8, 16 or 24");
    }
    Parser.Lex(); // consume the width
  }

  if (getLexer().isNot(AsmToken::RParen))
    return Error(getLexer().getLoc(), "expected ')'");

  SMLoc E = SMLoc::getFromPointer(getLexer().getLoc().getPointer() + 1);
  Parser.Lex(); // consume ')'
  Operands.push_back(
      TLCS900Operand::createMem(MCRegister(), Addr, S, E, AddrBytes));
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

/// parseEncodingSelector - Parse an ENCODING SELECTOR written after an
/// operand: `:i3`, `:opc` or `:io` (defined in TLCS900EncodingForms.td).
///
/// A selector names ONE encoding of the instruction.  It is pushed as a
/// literal token operand, exactly like the `(` / `)` of `jp (xix)`, so the
/// short form's matchable carries one more asm operand than the default
/// form's and a source line that writes no selector is structurally unable
/// to reach it.  Nothing here or in the matcher compares encoding lengths.
///
/// Each selector is bound to exactly one encoder path, so the contract that
/// path imposes on its operand is checked here, at the selector, where the
/// value is known and the message can name it:
///   :i3  the value is packed into the opcode byte's low 3 bits -- a constant
///        in 0..7, never a relocatable expression (no fixup reaches an opcode)
///   :opc the operation's own primary-map opcode (0x20+r) -- its encoder emits
///        a real fixup, so a symbolic immediate stays legal
///   :io  the I/O-space store opcode (0x08 / 0x0A) -- its encoder has no
///        fixup at all, so the value must be a constant and the address must
///        be written (n:8) with n in 0..255
/// The operand-class predicates (isImmI3, isImmIO8/16, isDaddr8) restate the
/// same contracts for the matcher; these checks exist so the failure is a
/// named error at the selector rather than a generic mismatch.
ParseStatus TLCS900AsmParser::parseEncodingSelector(OperandVector &Operands) {
  if (getLexer().isNot(AsmToken::Colon))
    return ParseStatus::NoMatch;

  SMLoc ColonLoc = getLexer().getLoc();
  Parser.Lex(); // consume ':'

  if (getLexer().is(AsmToken::Integer))
    return Error(getLexer().getLoc(),
                 "an encoding selector is an identifier such as ':i3'; a "
                 "numeric ':N' is an ADDRESS WIDTH and is written inside the "
                 "parentheses of a direct address, e.g. (0x2075:16)");
  if (getLexer().isNot(AsmToken::Identifier))
    return Error(getLexer().getLoc(),
                 "expected an encoding selector after ':' (:i3, :opc or :io)");

  SMLoc NameLoc = getLexer().getLoc();
  StringRef Name = getLexer().getTok().getString();
  if (NameLoc.getPointer() != ColonLoc.getPointer() + 1)
    return Error(NameLoc,
                 "an encoding selector is written directly after the ':', "
                 "with no space");

  // The token pushed is a string literal, so it has static lifetime and is
  // exactly the spelling the matcher's token class compares against.
  StringRef Selector = StringSwitch<StringRef>(Name)
                           .Case("i3", ":i3")
                           .Case("opc", ":opc")
                           .Case("io", ":io")
                           .Default("");
  if (Selector.empty())
    return Error(NameLoc, "unknown encoding selector ':" + Name +
                              "'; expected :i3, :opc or :io");

  const auto *Prev = Operands.size() > 1
                         ? &(TLCS900Operand &)*Operands.back()
                         : nullptr;
  if (Selector == ":i3") {
    if (!Prev || !Prev->isImm())
      return Error(ColonLoc, "':i3' selects a 3-bit immediate field and is "
                             "written after an immediate operand");
    const auto *CE = dyn_cast<MCConstantExpr>(Prev->getImm());
    if (!CE)
      return Error(Prev->getStartLoc(),
                   "the 3-bit opcode field cannot hold a relocatable "
                   "expression");
    if (!isUInt<3>(CE->getValue()))
      return Error(Prev->getStartLoc(),
                   Twine(CE->getValue()) +
                       " does not fit the 3-bit opcode field (must be 0..7)");
  } else if (Selector == ":io") {
    if (!Prev || !Prev->isImm())
      return Error(ColonLoc, "':io' is written after the value of an "
                             "I/O-space store: ld (n:8), value:io");
    if (!isa<MCConstantExpr>(Prev->getImm()))
      return Error(Prev->getStartLoc(),
                   "the I/O short form cannot hold a relocatable expression; "
                   "its encoder has no fixup");
    const auto *Addr = Operands.size() > 2
                           ? &(TLCS900Operand &)*Operands[Operands.size() - 2]
                           : nullptr;
    if (!Addr || !Addr->isMemri() || Addr->hasMemBase() ||
        Addr->getMemAddrBytes() != 1)
      return Error(Addr ? Addr->getStartLoc() : ColonLoc,
                   "the I/O short form takes an 8-bit direct address, "
                   "written (n:8)");
    const auto *ACE = dyn_cast<MCConstantExpr>(Addr->getMemDisp());
    if (!ACE)
      return Error(Addr->getStartLoc(),
                   "the I/O short form's address must be a constant; its "
                   "encoder has no fixup");
    if (!isUInt<8>(ACE->getValue()))
      return Error(Addr->getStartLoc(),
                   "0x" + Twine::utohexstr(ACE->getValue()) +
                       " does not fit an 8-bit direct address");
  }

  Parser.Lex(); // consume the selector name
  if (getLexer().is(AsmToken::Colon))
    return Error(getLexer().getLoc(), "one encoding selector per operand");

  Operands.push_back(TLCS900Operand::createToken(Selector, ColonLoc));
  return ParseStatus::Success;
}

/// Look up a register usable as the base of `(R+)` / `(-R)`: its
/// register-file address (4-aligned), or -1.  The eight current-bank 32-bit
/// registers, and XWA0..XHL3 -- the four 32-bit registers of banks 0-3, which
/// the KN5000 SLIDE decompressor walks as (XBC3+) / (XDE3+).
static int autoIncRegAddr(StringRef Name) {
  std::string L = Name.lower();
  for (unsigned A = 0; A < 0x100; A += 4)
    if (const char *N = TLCS900II::getAutoIncRegName(A))
      if (L == N)
        return A;
  return -1;
}

/// tryParseAutoIncOperand - `(R+)`, `(R+:N)`, `(-R)`, `(-R:N)`.
///
/// The TLCS-900 has a POST-increment and a PRE-decrement mode and nothing
/// else, so the two other shapes are refused by name rather than falling
/// through to the expression parser: `(+R)` would otherwise assemble to the
/// absolute address of a symbol called R, and `(R-)` is a syntax error that
/// says nothing useful.  N is the step, 1, 2 or 4; left out, the instruction's
/// own data size supplies it (finalizeMemOperands), and an instruction that
/// moves no data -- LDA -- must write it.
ParseStatus TLCS900AsmParser::tryParseAutoIncOperand(OperandVector &Operands) {
  if (getLexer().isNot(AsmToken::LParen))
    return ParseStatus::NoMatch;

  AsmToken Buf[4];
  size_t N = getLexer().peekTokens(Buf);
  auto IsBaseName = [&](const AsmToken &T) {
    return T.is(AsmToken::Identifier) &&
           (autoIncRegAddr(T.getString()) >= 0 ||
            MatchRegisterName(T.getString().lower()));
  };

  bool Pre;
  if (N >= 2 && (Buf[0].is(AsmToken::Plus) || Buf[0].is(AsmToken::Minus)) &&
      IsBaseName(Buf[1])) {
    if (Buf[0].is(AsmToken::Plus))
      return Error(Buf[0].getLoc(),
                   "'(+" + Buf[1].getString() + ")' is not a TLCS-900 "
                   "addressing mode: post-increment is written (" +
                       Buf[1].getString() + "+), pre-decrement (-" +
                       Buf[1].getString() + ")");
    Pre = true;
  } else if (N >= 3 && IsBaseName(Buf[0]) &&
             (Buf[1].is(AsmToken::Plus) || Buf[1].is(AsmToken::Minus)) &&
             (Buf[2].is(AsmToken::RParen) || Buf[2].is(AsmToken::Colon))) {
    if (Buf[1].is(AsmToken::Minus))
      return Error(Buf[1].getLoc(),
                   "'(" + Buf[0].getString() + "-)' is not a TLCS-900 "
                   "addressing mode: there is no post-decrement; "
                   "pre-decrement is written (-" + Buf[0].getString() + ")");
    Pre = false;
  } else {
    return ParseStatus::NoMatch;
  }

  SMLoc S = getLexer().getLoc();
  Parser.Lex(); // '('
  if (Pre)
    Parser.Lex(); // '-'
  SMLoc RegLoc = getLexer().getLoc();
  StringRef RegName = getLexer().getTok().getString();
  int Addr = autoIncRegAddr(RegName);
  if (Addr < 0)
    return Error(RegLoc, "the base of a post-increment / pre-decrement "
                         "operand is a 32-bit register (xwa..xsp, or "
                         "xwa0..xhl3 in banks 0-3), not '" +
                             RegName + "'");
  Parser.Lex(); // register
  if (!Pre)
    Parser.Lex(); // '+'

  bool StepUnset = true;
  unsigned StepBits = 0;
  if (getLexer().is(AsmToken::Colon)) {
    Parser.Lex(); // ':'
    if (getLexer().isNot(AsmToken::Integer))
      return Error(getLexer().getLoc(), "expected a step of 1, 2 or 4 after ':'");
    int64_t Step = getLexer().getTok().getIntVal();
    switch (Step) {
    case 1: StepBits = 0; break;
    case 2: StepBits = 1; break;
    case 4: StepBits = 2; break;
    default:
      return Error(getLexer().getLoc(), "a post-increment / pre-decrement step "
                                        "is 1, 2 or 4");
    }
    StepUnset = false;
    Parser.Lex(); // the step
  }
  if (getLexer().isNot(AsmToken::RParen))
    return Error(getLexer().getLoc(), "expected ')'");
  SMLoc E = SMLoc::getFromPointer(getLexer().getLoc().getPointer() + 1);
  Parser.Lex(); // ')'

  // The MEMri base register is informational (the encoder writes the
  // register-file byte carried in the displacement): the current-bank
  // register itself, or XWA as a placeholder for a bank register.
  MCRegister Base = Addr >= 0xE0 ? MatchRegisterName(RegName.lower())
                                 : MCRegister(TLCS900::XWA);
  const MCExpr *Disp = MCConstantExpr::create(
      TLCS900II::makeAutoInc(unsigned(Addr) | StepBits, Pre, StepUnset),
      getContext());
  Operands.push_back(TLCS900Operand::createMem(Base, Disp, S, E));
  return ParseStatus::Success;
}

/// finalizeMemOperands - after a match, settle what only the matched
/// instruction knows: the step of a `(R+)` / `(-R)` written without `:N`,
/// and whether its encoding can hold a post-increment or width-requested
/// operand at all.  Returns true (having reported) on error.
bool TLCS900AsmParser::finalizeMemOperands(MCInst &Inst, SMLoc IDLoc) {
  uint64_t TSFlags = MII.get(Inst.getOpcode()).TSFlags;
  for (unsigned I = 0, E = Inst.getNumOperands(); I != E; ++I) {
    MCOperand &Op = Inst.getOperand(I);
    if (!Op.isImm())
      continue;
    int64_t V = Op.getImm();
    bool AI = TLCS900II::isAutoInc(V), FD = TLCS900II::isForcedDisp(V);
    if (!AI && !FD)
      continue;
    StringRef Mn = MII.getName(Inst.getOpcode());
    if (!TLCS900II::usesGenericMemPrefix(TSFlags))
      return Error(IDLoc, Twine("this instruction form (") + Mn +
                              ") has no " +
                              (AI ? "post-increment / pre-decrement"
                                  : "width-requested displacement") +
                              " operand");
    if (AI && TLCS900II::isAutoIncStepUnset(V)) {
      unsigned Step = TLCS900II::getAutoIncNaturalStep(TSFlags);
      if (!Step)
        return Error(IDLoc, "this instruction moves no data through its "
                            "post-increment / pre-decrement operand, so the "
                            "step must be written: (R+:1), (R+:2) or (R+:4)");
      unsigned Byte = TLCS900II::getAutoIncRegByte(V) |
                      (Step == 1 ? 0 : Step == 2 ? 1 : 2);
      Op.setImm(TLCS900II::makeAutoInc(Byte, TLCS900II::isAutoIncPreDec(V),
                                       false));
    }
  }
  return false;
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

  // '(' handling: if the next token after '(' is a register, treat '(' as a
  // literal token for 'call (reg)' / 'jp (reg)' syntax.  Otherwise, fall
  // through to parseExpression which handles parenthesized expressions like
  // (0xE00010 - .) for branch-target arithmetic.
  if (getLexer().is(AsmToken::LParen)) {
    // Peek at the token after '(' to decide.
    const AsmToken &Next = getLexer().peekTok();
    bool NextIsReg = false;
    if (Next.is(AsmToken::Identifier))
      NextIsReg = MatchRegisterName(Next.getString().lower()) != 0;
    if (NextIsReg) {
      Operands.push_back(TLCS900Operand::createToken("(", S));
      Parser.Lex();
      return false;
    }
    // Not a register — fall through to expression parsing which will
    // handle the parenthesized expression (including consuming '(' and ')').
  }

  // Literal ')' — add as token
  if (getLexer().is(AsmToken::RParen)) {
    Operands.push_back(TLCS900Operand::createToken(")", S));
    Parser.Lex();
    return false;
  }

  // Try expression (immediate, label, etc.)  A register name inside it is
  // an error (parseAddressExpression), not an undefined symbol: `ld xwa,
  // xbc3` would otherwise load the address of a symbol called xbc3.
  const MCExpr *Expr;
  SMLoc ELoc;
  if (parseAddressExpression(Expr, ELoc))
    return true;

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
    // A post-increment `(R+)` / pre-decrement `(-R)` operand is recognised
    // before any other parser, whatever the mnemonic: left to them, `(+xde)`
    // and `(-xde)` parse as the ABSOLUTE address expressions +xde / -xde (an
    // undefined symbol each) and assemble in silence.
    ParseStatus Res = tryParseAutoIncOperand(Operands);
    if (Res.isFailure())
      return true;
    // Try custom operand parsers first (MEMri, CondCode).
    if (!Res.isSuccess())
      Res = MatchOperandParserImpl(Operands, Name);
    if (Res.isFailure())
      return true;

    // Generic operand parsing.
    if (!Res.isSuccess() && parseOperand(Operands))
      return true;

    // An encoding selector (`:i3` / `:opc` / `:io`) may follow any operand.
    if (parseEncodingSelector(Operands).isFailure())
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
