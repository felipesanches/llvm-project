//=== TLCS900InstrFormats.td - TLCS900 Instruction Formats ---*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// TLCS900 instruction format definitions.
//
// The TLCS-900/H2 uses variable-length instructions (1-7 bytes) with a
// complex prefix-based encoding scheme. Binary encoding is done manually
// in C++ (TLCS900MCCodeEmitter) using TSFlags metadata from these classes.
//
//===----------------------------------------------------------------------===//

// InstFormat values — must match TLCS900II::InstFormat enum in BaseInfo.h
class InstFormat<bits<7> val> {
  bits<7> Value = val;
}
def InstFormatPseudo        : InstFormat<0>;
def InstFormatSingleByte    : InstFormat<1>;
def InstFormatSingleByteImm8 : InstFormat<2>;
def InstFormatSingleByteReg : InstFormat<3>;
def InstFormatSingleByteRegImm : InstFormat<4>;
def InstFormatPrefixUnary   : InstFormat<5>;
def InstFormatPrefixRegImm  : InstFormat<6>;
def InstFormatPrefixRegReg  : InstFormat<7>;
def InstFormatPrefixShift   : InstFormat<8>;
def InstFormatPrefixRotate  : InstFormat<9>;
def InstFormatPrefixBit     : InstFormat<10>;
def InstFormatPrefixIncDec  : InstFormat<11>;
def InstFormatMemLoad       : InstFormat<12>;
def InstFormatMemLoadDst    : InstFormat<13>;
def InstFormatMemStore      : InstFormat<14>;
def InstFormatMemALU        : InstFormat<15>;
def InstFormatBranch24      : InstFormat<16>;
def InstFormatBranchCond24  : InstFormat<17>;
def InstFormatBranchRel8    : InstFormat<18>;
def InstFormatBranchRel16   : InstFormat<19>;
def InstFormatCall24        : InstFormat<20>;
def InstFormatCallRel16     : InstFormat<21>;
def InstFormatCallIndirect  : InstFormat<22>;
def InstFormatPrefixDJNZ    : InstFormat<23>;
def InstFormatPrefixLDImm   : InstFormat<24>;
def InstFormatPrefixPush    : InstFormat<25>;
def InstFormatPrefixPop     : InstFormat<26>;
def InstFormatBlockTransfer : InstFormat<27>;
def InstFormatPrefixSmallImm : InstFormat<28>;
def InstFormatSingleByteCondRet : InstFormat<29>;
def InstFormatPrefixCondCode : InstFormat<30>;
def InstFormatMemStoreImm : InstFormat<31>;
def InstFormatMemIncDec : InstFormat<32>;
def InstFormatMemPush : InstFormat<33>;
def InstFormatMemDstBitOp : InstFormat<34>;
def InstFormatMemDstUnary : InstFormat<79>;
def InstFormatMemDstCC : InstFormat<80>;
def InstFormatDirectSrcReg : InstFormat<35>;
def InstFormatDirectSrcImm : InstFormat<36>;
def InstFormatDirectSrcIncDec : InstFormat<37>;
def InstFormatDirectDstReg : InstFormat<38>;
def InstFormatDirectDstImm : InstFormat<39>;
def InstFormatDirectDstBitOp : InstFormat<40>;
def InstFormatDirectMemToMem : InstFormat<41>;
def InstFormatLdIoImm : InstFormat<42>;
def InstFormatLdIoImm16 : InstFormat<43>;
def InstFormatExtPrefix : InstFormat<44>;
def InstFormatExtAddrModeSuffix : InstFormat<45>;
def InstFormatExtAddrModeOpImm : InstFormat<46>;

// Extended addressing mode native formats (typed operands)
def InstFormatERPReg : InstFormat<47>;
def InstFormatERPSmallImm : InstFormat<48>;
def InstFormatERPUnary : InstFormat<49>;
def InstFormatERPImmAfter : InstFormat<50>;
def InstFormatPIReg : InstFormat<51>;
def InstFormatPIUnary : InstFormat<52>;
def InstFormatRIReg : InstFormat<53>;
def InstFormatRIUnary : InstFormat<54>;
def InstFormatRIImmAfter : InstFormat<55>;
def InstFormatD8Reg : InstFormat<56>;
def InstFormatD8Unary : InstFormat<57>;
def InstFormatD8ImmAfter : InstFormat<58>;
def InstFormatExtImmMod : InstFormat<59>;
def InstFormatRIImmMod : InstFormat<60>;
def InstFormatSriD16Reg : InstFormat<61>;
def InstFormatPrevBankRR : InstFormat<62>;
def InstFormatPrevBankUnary : InstFormat<63>;
def InstFormatPrevBankSmallImm : InstFormat<64>;
def InstFormatPrevBankImmAfter : InstFormat<65>;
def InstFormatDirectSrcPush : InstFormat<66>;
def InstFormatMemRegSuffix : InstFormat<67>;
def InstFormatMemRegDispSuffix : InstFormat<68>;
def InstFormatMemRegImmMod : InstFormat<69>;
def InstFormatMemRegRegSuffix : InstFormat<70>;
def InstFormatMemRegRegDispSuffix : InstFormat<71>;
def InstFormatMemRegImmAfter : InstFormat<72>;
def InstFormatMemRegDispImmAfter : InstFormat<73>;

// SRI Register+Register (R+R) addressing: [prefix, mode, base_addr, idx_addr, ...]
def InstFormatSriRRReg : InstFormat<74>;
def InstFormatSriRRUnary : InstFormat<75>;
def InstFormatSriRR8Reg : InstFormat<76>;
def InstFormatBranch16 : InstFormat<77>;
def InstFormatCall16 : InstFormat<78>;
// SRI Register+Register (R+R) addressing, immediate and previous-bank index
def InstFormatSriRRImm : InstFormat<81>;
def InstFormatSriRRQReg : InstFormat<82>;
// Register prefix + fixed sub-opcode + 16-bit displacement (LINK).
def InstFormatPrefixDisp16 : InstFormat<83>;
def InstFormatMemToMemDst : InstFormat<84>;
def InstFormatMemToMemSrc : InstFormat<85>;
def InstFormatSriRRAddr16 : InstFormat<86>;

// Operand size values for TSFlags.
class OpSizeVal<bits<2> val> {
  bits<2> Value = val;
}
def OpSize8  : OpSizeVal<0>;
def OpSize16 : OpSizeVal<1>;
def OpSize32 : OpSizeVal<2>;

// Base class for all TLCS900 instructions.
// TSFlags layout: [6:0] InstFormat, [14:7] Opcode, [16:15] OpSize,
//                 [17] AddrWidth, [20:18] RegIdx, [28:21] SubOpcode,
//                 [31:29] NumPreOps
class TLCS900Inst<dag outs, dag ins, string opcodestr, string argstr,
                  list<dag> pattern>
    : Instruction {
  let Namespace = "TLCS900";

  // TSFlags fields — subclasses override these.
  bits<7> InstFormat = InstFormatPseudo.Value;
  bits<8> Opcode = 0;
  bits<2> OpSize = OpSize32.Value;
  bits<1> AddrWidth = 0; // 0=16-bit addr, 1=24-bit addr (direct addressing)
  bits<3> RegIdx = 0;    // Register index for block transfer prefix
  bits<8> SubOpcode = 0; // Sub-opcode byte (ExtAddrModeSuffix/OpImm)
  bits<3> NumPreOps = 0; // Operands before SubOpcode (ExtAddrModeOpImm)

  // Wire TSFlags.
  let TSFlags{6-0}   = InstFormat;
  let TSFlags{14-7}  = Opcode;
  let TSFlags{16-15} = OpSize;
  let TSFlags{17}    = AddrWidth;
  let TSFlags{20-18} = RegIdx;
  let TSFlags{28-21} = SubOpcode;
  let TSFlags{31-29} = NumPreOps;

  let Size = 0; // Default; subclasses set correct size.

  dag OutOperandList = outs;
  dag InOperandList = ins;
  let AsmString = opcodestr # "\t" # argstr;
  let Pattern = pattern;
}

// Pseudo instructions (no encoding, codegen only).
class Pseudo<dag outs, dag ins, list<dag> pattern,
             string opcodestr = "", string argstr = "">
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPseudo.Value;
  let isPseudo = 1;
  let isCodeGenOnly = 1;
}

//===----------------------------------------------------------------------===//
// Single-byte instructions (no prefix, no operands in encoding)
//===----------------------------------------------------------------------===//

// SingleByteInst: 1 byte, opcode only (NOP, RET, HALT, RETI)
class SingleByteInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSingleByte.Value;
  let Opcode = opc;
  let Size = 1;
}

// SingleByteImm8Inst: 1 byte opcode + 1 byte immediate (EI level, SWI num)
class SingleByteImm8Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                         string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSingleByteImm8.Value;
  let Opcode = opc;
  let Size = 2;
}

// SingleByteRegInst: opcode+reg, no immediate (PUSH r32, POP r32)
class SingleByteRegInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                        string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSingleByteReg.Value;
  let Opcode = opc;
  let Size = 1;
}

// SingleByteRegImmInst: opcode+reg + N-byte immediate (LD r32, #imm32)
class SingleByteRegImmInst<bits<8> opc, int sz, dag outs, dag ins,
                           string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSingleByteRegImm.Value;
  let Opcode = opc;
  let Size = sz;
}

//===----------------------------------------------------------------------===//
// Prefix-based instructions (prefix byte + opcode byte + optional operands)
//===----------------------------------------------------------------------===//

// PrefixUnaryInst: reg_prefix + opcode (NEG, CPL, EXTS, EXTZ)
class PrefixUnaryInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixUnary.Value;
  let Opcode = opc;
  let Size = 2;
}

// PrefixRegImmInst: reg_prefix + opcode + immediate (ADD ri, SUB ri, etc.)
class PrefixRegImmInst<bits<8> opc, int sz, dag outs, dag ins,
                       string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixRegImm.Value;
  let Opcode = opc;
  let Size = sz;
}

// PrefixRegRegInst: src_prefix + (opcode|dst_reg) (ADD rr, SUB rr, etc.)
class PrefixRegRegInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixRegReg.Value;
  let Opcode = opc;
  let Size = 2;
}

// PrefixShiftInst: reg_prefix + shift_opcode + amount_byte (SLA, SRA, SRL)
class PrefixShiftInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixShift.Value;
  let Opcode = opc;
  let Size = 3;
}

// PrefixRotateInst: reg_prefix + rotate_opcode + count (RLC, RRC, RL, RR)
class PrefixRotateInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixRotate.Value;
  let Opcode = opc;
  let Size = 3;
}

// PrefixBitInst: reg_prefix + opcode + bit_number (SET, RES, CHG, BIT, TSET)
class PrefixBitInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                    string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixBit.Value;
  let Opcode = opc;
  let Size = 3; // prefix + opcode + bit_number byte
}

// PrefixIncDecInst: reg_prefix + (opcode|count) (INC, DEC)
class PrefixIncDecInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixIncDec.Value;
  let Opcode = opc;
  let Size = 2;
}

//===----------------------------------------------------------------------===//
// Memory access instructions
//===----------------------------------------------------------------------===//

// MemLoadInst: mem_prefix [+disp] + opcode (LD rd, (mem))
// Size varies by addressing mode; set conservatively.
class MemLoadInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                  string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemLoad.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemLoadDstInst: dst_mem_prefix [+disp] + opcode (LDA rd, mem)
// Like MemLoadInst but uses B0/B8 destination memory prefix (for LDA).
class MemLoadDstInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemLoadDst.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemStoreInst: mem_prefix [+disp] + opcode (LD (mem), rs)
class MemStoreInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                   string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemStore.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemALUInst: mem_prefix [+disp] + opcode + operand (ADD/SUB/etc (mem), rs)
class MemALUInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                 string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemALU.Value;
  let Opcode = opc;
  let Size = sz;
}

//===----------------------------------------------------------------------===//
// Branch and call instructions
//===----------------------------------------------------------------------===//

// Branch24Inst: 0x1B + 24-bit absolute address (JP nnn)
class Branch16Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                   string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBranch16.Value;
  let Opcode = opc;
  let Size = 3;
}

class Branch24Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                   string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBranch24.Value;
  let Opcode = opc;
  let Size = 4;
}

// BranchCond24Inst: conditional JP cc, nnn — currently emits JRL cc, d16
class BranchCond24Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBranchCond24.Value;
  let Opcode = opc;
  let Size = 3; // JRL cc, d16 = 3 bytes
}

// BranchRel8Inst: 0x60+cc + signed 8-bit displacement (JR cc, d8)
class BranchRel8Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBranchRel8.Value;
  let Opcode = opc;
  let Size = 2;
}

// BranchRel16Inst: 0x70+cc + signed 16-bit displacement (JRL cc, d16)
class BranchRel16Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBranchRel16.Value;
  let Opcode = opc;
  let Size = 3;
}

// Call16Inst: 0x1C + 16-bit absolute address (CALL nn)
class Call16Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                 string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatCall16.Value;
  let Opcode = opc;
  let Size = 3;
}

// Call24Inst: 0x1D + 24-bit absolute address (CALL nnn)
class Call24Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                 string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatCall24.Value;
  let Opcode = opc;
  let Size = 4;
}

// CallRel16Inst: 0x1E + 16-bit relative displacement (CALR d16)
class CallRel16Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                    string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatCallRel16.Value;
  let Opcode = opc;
  let Size = 3;
}

// CallIndirectInst: reg prefix + opcode (CALL (reg))
class CallIndirectInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatCallIndirect.Value;
  let Opcode = opc;
  let Size = 2;
}

//===----------------------------------------------------------------------===//
// Misc prefix instructions
//===----------------------------------------------------------------------===//

// PrefixDJNZInst: reg_prefix + 0x1C + d8 (DJNZ r, d8)
class PrefixDJNZInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixDJNZ.Value;
  let Opcode = opc;
  let Size = 3;
}

// PrefixLDImmInst: reg_prefix + 0x03 + immediate (LD R, #imm via prefix form)
class PrefixLDImmInst<bits<8> opc, int sz, dag outs, dag ins,
                      string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixLDImm.Value;
  let Opcode = opc;
  let Size = sz;
}

// PrefixDisp16Inst: reg_prefix + opcode + 16-bit displacement.
// LINK r32, d16 — the displacement is 16-bit at every register width, which is
// why this cannot be PrefixLDImmInst (that one sizes its immediate from
// OpSize, and OpSize32 would ask for four bytes).
// Operand 0: GPR register, operand 1: the 16-bit displacement.
class PrefixDisp16Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixDisp16.Value;
  let Opcode = opc;
  let Size = 4;
}

// PrefixPushInst: reg_prefix + 0x04 (PUSH via prefix — 16-bit/8-bit)
class PrefixPushInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixPush.Value;
  let Opcode = opc;
  let Size = 2;
}

// PrefixPopInst: reg_prefix + 0x05 (POP via prefix — 16-bit/8-bit)
class PrefixPopInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                    string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixPop.Value;
  let Opcode = opc;
  let Size = 2;
}

// BlockTransferInst: 2-byte block operations (LDI, LDIR, etc.)
// Encoding: (0x80 + OpSize*16 + ridx) prefix + sub-opcode
// Default: OpSize8, ridx=0 → prefix 0x80 (standard byte-wide, register 0)
class BlockTransferInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                        string argstr, list<dag> pattern, bits<3> ridx = 0>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBlockTransfer.Value;
  let Opcode = opc;
  let RegIdx = ridx;
  let Size = 2;
}

// PrefixSmallImmInst: reg_prefix + (opcode + imm3) — LD r, 0-7 in 2 bytes
class PrefixSmallImmInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                         string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixSmallImm.Value;
  let Opcode = opc;
  let Size = 2;
}

// SingleByteCondRetInst: 2-byte, 0xB0 + (base_opc+cc)
// Used for RETcc: 0xB0, 0xF0+cc
class SingleByteCondRetInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                            string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSingleByteCondRet.Value;
  let Opcode = opc;
  let Size = 2;
}

// MemStoreImmInst: dst_mem_prefix [+disp] + opcode + immediate
// LD (mem), #imm: B0/B8 prefix + sub_opc + imm_data
class MemStoreImmInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemStoreImm.Value;
  let Opcode = opc;
  let Size = sz;
}

// PrefixCondCodeInst: prefix(reg) + (base_opc + cc)
// Used for SCC: reg_prefix + 0x70+cc
class PrefixCondCodeInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                         string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrefixCondCode.Value;
  let Opcode = opc;
  let Size = 2;
}

// MemIncDecInst: src_mem_prefix [+disp] + (opcode + count%8)
// INC/DEC on memory operand. Count (1-8) encoded in sub-opcode bits 0-2.
class MemIncDecInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                    string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemIncDec.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemPushInst: src_mem_prefix [+disp] + opcode (PUSH from memory)
class MemPushInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                  string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemPush.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemDstUnaryInst: dst_mem_prefix [+disp] + opcode, no register or modifier.
// POP/POPW (mem) and the carry-flag group ANDCF/ORCF/XORCF/LDCF/STCF A,(mem).
class MemDstUnaryInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemDstUnary.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemDstCCInst: dst_mem_prefix [+disp] + (opcode + cc)
// JP cc,(mem) and CALL cc,(mem).  The condition is FOUR bits, not the three
// a bit number takes, so this cannot share MemDstBitOpInst.
class MemDstCCInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                   string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemDstCC.Value;
  let Opcode = opc;
  let Size = sz;
}

// MemDstBitOpInst: dst_mem_prefix [+disp] + (opcode + bit_number)
// BIT/SET/RES/LDCF/STCF on memory. Bit number embedded in sub-opcode bits 0-2.
class MemDstBitOpInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemDstBitOp.Value;
  let Opcode = opc;
  let Size = sz;
}

//===----------------------------------------------------------------------===//
// Direct addressing instructions (16-bit or 24-bit absolute address)
//
// Source direct: C1/D1/E1 (16-bit addr) or C2/D2/E2 (24-bit addr)
//   — prefix byte depends on OpSize; dispatches to source memory sub-opcode table
// Destination direct: F1 (16-bit addr) or F2 (24-bit addr)
//   — size-independent; dispatches to destination memory sub-opcode table
//===----------------------------------------------------------------------===//

// DirectSrcRegInst: src_direct_prefix + addr + (opcode | reg_enc)
// LD reg, (addr); CP/ADD/SUB/AND/OR/XOR reg, (addr)
class DirectSrcRegInst<bits<8> opc, int sz, dag outs, dag ins,
                       string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectSrcReg.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectSrcImmInst: src_direct_prefix + addr + opcode + imm
// CP/AND/OR/XOR/ADD/SUB (addr), #imm
class DirectSrcImmInst<bits<8> opc, int sz, dag outs, dag ins,
                       string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectSrcImm.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectSrcIncDecInst: src_direct_prefix + addr + (opcode + count%8)
// INC/DEC (addr), count
class DirectSrcIncDecInst<bits<8> opc, int sz, dag outs, dag ins,
                          string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectSrcIncDec.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectSrcPushInst: src_direct_prefix + addr + opcode
// PUSH (addr) — no additional operands after the opcode
class DirectSrcPushInst<bits<8> opc, int sz, dag outs, dag ins,
                         string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectSrcPush.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectDstRegInst: F1/F2 + addr + (opcode | reg_enc)
// LD (addr), reg; LDA reg, addr
class DirectDstRegInst<bits<8> opc, int sz, dag outs, dag ins,
                       string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectDstReg.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectDstImmInst: F1/F2 + addr + opcode + imm
// LD (addr), #imm
class DirectDstImmInst<bits<8> opc, int sz, dag outs, dag ins,
                       string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectDstImm.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectDstBitOpInst: F1/F2 + addr + (opcode + bit%8)
// BIT/SET/RES (addr), bit
class DirectDstBitOpInst<bits<8> opc, int sz, dag outs, dag ins,
                         string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectDstBitOp.Value;
  let Opcode = opc;
  let Size = sz;
}

// DirectMemToMemInst: src_direct_prefix + src_addr + 0x19 + dst_addr
// Memory-to-memory transfer: LD (dst_addr), (src_addr)
class DirectMemToMemInst<bits<8> opc, int sz, dag outs, dag ins,
                          string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatDirectMemToMem.Value;
  let Opcode = opc;
  let Size = sz;
}

// LdIoImmInst: 3-byte I/O register write — 0x08 + addr8 + imm8
class LdIoImmInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                   string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatLdIoImm.Value;
  let Opcode = opc;
  let Size = 3;
}

// LdIoImm16Inst: 4-byte I/O register write — 0x0A + addr8 + imm16
class LdIoImm16Inst<bits<8> opc, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatLdIoImm16.Value;
  let Opcode = opc;
  let Size = 4;
}

// ExtPrefixInst: Generic extended-prefix instruction.
// All operand bytes are emitted literally by MCCodeEmitter.
// Used for addressing modes not yet fully modeled.
class ExtPrefixInst<int sz, dag outs, dag ins, string opcodestr,
                     string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatExtPrefix.Value;
  let Size = sz;
}

// ExtAddrModeSuffixInst: Computed prefix + operand bytes + appended SubOpcode byte.
// the operand bytes. Used for instructions where the operation is encoded as
// the last byte after variable-length addressing mode bytes.
//
// Encoding: [computed_prefix, operand_bytes..., SubOpcode]
//   - prefix computed from Opcode + OpSize * 0x10 (source) or Opcode (dest)
//   - operand bytes emitted from immediate operands
//   - SubOpcode appended from TSFlags
class ExtAddrModeSuffixInst<int nbytes, bits<8> sub_opc, dag outs, dag ins,
                             string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatExtAddrModeSuffix.Value;
  let SubOpcode = sub_opc;
  let Size = nbytes;
}

// ExtAddrModeOpImmInst: Like ExtAddrModeSuffix but inserts SubOpcode in the
// MIDDLE of the operand stream, between addressing bytes and trailing operands
// (immediates, register indices, etc.).
//
// Encoding: [computed_prefix, pre_operands..., SubOpcode, post_operands...]
//   - prefix computed from Opcode + OpSize * 0x10 (source) or Opcode (dest)
//   - NumPreOps operands emitted before SubOpcode
//   - SubOpcode inserted from TSFlags
//   - remaining operands emitted after SubOpcode
//
// Used for TLCS-900 instructions where the operation byte (sub-opcode) is
// encoded between the addressing mode bytes and the immediate/data bytes.
class ExtAddrModeOpImmInst<int nbytes, bits<8> sub_opc, int npreops,
                            dag outs, dag ins, string opcodestr,
                            string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatExtAddrModeOpImm.Value;
  let SubOpcode = sub_opc;
  let NumPreOps = npreops;
  let Size = nbytes;
}

//===----------------------------------------------------------------------===//
// Extended addressing mode — native format classes (typed operands)
//
// These replace ExtAddrModeSuffix/OpImm/ExtPrefix with proper register
// operands and typed immediates.
//
// All use prefix = Opcode + (Opcode < 0xF0 ? OpSize*0x10 : 0).
// SubOpcode stored in TSFlags encodes the sub-opcode BASE (low 3 bits
// combined with register encoding at emit time for Reg variants).
//===----------------------------------------------------------------------===//

// ERPRegInst: Extended Register Prefix with data register operand.
// Encoding: [prefix, bank_idx, SubOpcode + reg_enc]
// reg_enc comes from operand 0 (the data register).
// bank_idx comes from operand 1 (immediate).
class ERPRegInst<bits<8> sub_opc, dag outs, dag ins, string opcodestr,
                  string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatERPReg.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// ERPSmallImmInst: ERP with 3-bit immediate (LDI 0-7, CPI 0-7).
// Encoding: [prefix, bank_idx, SubOpcode + imm3]
// bank_idx from operand 0, imm3 from operand 1.
class ERPSmallImmInst<bits<8> sub_opc, dag outs, dag ins, string opcodestr,
                       string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatERPSmallImm.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// ERPUnaryInst: ERP with fixed sub-opcode (PUSH, POP, INC, DEC, CPL, etc.)
// Encoding: [prefix, bank_idx, SubOpcode]
// bank_idx from operand 0.
class ERPUnaryInst<bits<8> sub_opc, dag outs, dag ins, string opcodestr,
                    string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatERPUnary.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// ERPImmAfterInst: ERP with trailing immediate after SubOpcode.
// Encoding: [prefix, bank_idx, SubOpcode, imm_bytes...]
// bank_idx from operand 0, trailing imm from remaining operands.
class ERPImmAfterInst<bits<8> sub_opc, int sz, dag outs, dag ins,
                       string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatERPImmAfter.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// PIRegInst: Post-Increment/Pre-Decrement with GPR base and data register.
// Encoding: [prefix, base_reg_enc, SubOpcode + data_reg_enc]
// Operand 0: data register, Operand 1: base GPR.
class PIRegInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                 string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPIReg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// PIUnaryInst: Post-Increment/Pre-Decrement with fixed sub-opcode.
// Encoding: [prefix, base_reg_enc, SubOpcode]
// Operand 0: base GPR.
class PIUnaryInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                   string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPIUnary.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// RIRegInst: Register-Indirect Complex (SRI/DRI) with data register.
// Encoding: [prefix, MEMsri_bytes..., SubOpcode + reg_enc]
// Operand 0: data register, Operand 1-3: MEMsri (mode, lo, hi).
class RIRegInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                 string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatRIReg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// SriD16RegInst: SRI with typed base register + 16-bit displacement.
// Encoding: [prefix, computed_mode_byte, d16_lo, d16_hi, SubOpcode + reg_enc]
// Mode byte = 0xE0 + (base_reg_enc * 4) + 1 (current bank, d16 mode).
// Operand 0: data register, Operand 1-2: MEMri (base GPR, d16 disp).
class SriD16RegInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                     string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriD16Reg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 5;
}

// RIUnaryInst: Register-Indirect Complex with fixed sub-opcode.
// Encoding: [prefix, MEMsri_bytes..., SubOpcode]
class RIUnaryInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                   string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatRIUnary.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// RIImmAfterInst: Register-Indirect Complex with trailing immediate.
// Encoding: [prefix, MEMsri_bytes..., SubOpcode, imm_bytes...]
class RIImmAfterInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                      string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatRIImmAfter.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// D8RegInst: 8-bit Direct Address (SD8/DD8) with data register.
// Encoding: [prefix, addr8, SubOpcode + reg_enc]
// Operand 0: data register, Operand 1: addr8.
class D8RegInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                 string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatD8Reg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// D8UnaryInst: 8-bit Direct Address with fixed sub-opcode.
// Encoding: [prefix, addr8, SubOpcode]
class D8UnaryInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                   string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatD8Unary.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// D8ImmAfterInst: 8-bit Direct Address with trailing immediate.
// Encoding: [prefix, addr8, SubOpcode, imm_bytes...]
class D8ImmAfterInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                      string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatD8ImmAfter.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// ExtImmModInst: Extended addressing with immediate modifier added to sub-opcode.
// Encoding: [prefix, raw_addr_bytes..., SubOpcode + op0_imm]
// Operand 0: immediate modifier (bit#, cc, etc.), remaining: raw address bytes.
class ExtImmModInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                     string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatExtImmMod.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// RIImmModInst: Register-Indirect Complex with immediate modifier.
// Encoding: [prefix, MEMsri_bytes..., SubOpcode + op0_imm]
// Operand 0: immediate modifier, Operands 1-3: MEMsri (mode, lo, hi).
class RIImmModInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                    string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatRIImmMod.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

//===----------------------------------------------------------------------===//
// Previous register bank (PrevBank) instruction formats.
// All emit: 0xD7 + mode_byte(QR) + sub-opcode bytes.
// mode_byte = 0xE0 + QR_enc * 4 + 2 (direct register mode).
//===----------------------------------------------------------------------===//

// PrevBankRRInst: PrevBank with data register + Q register operands.
// Encoding: [0xD7, mode_byte(QR), SubOpcode + data_reg_enc]
// Operand 0: data register (GR16), Operand 1: Q register (PrevGR16).
class PrevBankRRInst<bits<8> sub_opc, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrevBankRR.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// PrevBankUnaryInst: PrevBank with only Q register (no data operand).
// Encoding: [0xD7, mode_byte(QR), SubOpcode]
// Operand 0: Q register (PrevGR16).
class PrevBankUnaryInst<bits<8> sub_opc, dag outs, dag ins, string opcodestr,
                         string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrevBankUnary.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// PrevBankSmallImmInst: PrevBank with Q register + 3-bit immediate modifier.
// Encoding: [0xD7, mode_byte(QR), SubOpcode + imm3]
// Operand 0: immediate (0-7), Operand 1: Q register (PrevGR16).
class PrevBankSmallImmInst<bits<8> sub_opc, dag outs, dag ins,
                            string opcodestr, string argstr,
                            list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrevBankSmallImm.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// PrevBankImmAfterInst: PrevBank with Q register + trailing immediate.
// Encoding: [0xD7, mode_byte(QR), SubOpcode, imm_bytes...]
// Operand 0: Q register (PrevGR16), remaining: trailing immediate bytes.
class PrevBankImmAfterInst<bits<8> sub_opc, int sz, dag outs, dag ins,
                            string opcodestr, string argstr,
                            list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatPrevBankImmAfter.Value;
  let Opcode = 0xC7;
  let SubOpcode = sub_opc;
  let Size = sz;
}

//===----------------------------------------------------------------------===//
// Memory register-indirect instruction formats.
// Register indirect: [PrefixBase + reg_enc, SubOpcode]
// Register indirect + d8: [PrefixBase + reg_enc, disp8, SubOpcode]
// PrefixBase is stored in Opcode field (0xB0 for indirect, 0xB8 for +d8).
//===----------------------------------------------------------------------===//

// MemRegSuffixInst: [prefix_base + reg, SubOpcode] (2 bytes)
// Operand 0: GPR register (determines prefix byte).
class MemRegSuffixInst<bits<8> prefix_base, bits<8> sub_opc, dag outs, dag ins,
                        string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegSuffix.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = 2;
}

// MemRegDispSuffixInst: [prefix_base + reg, disp8, SubOpcode] (3 bytes)
// Operand 0: GPR register, Operand 1: displacement (i32imm).
class MemRegDispSuffixInst<bits<8> prefix_base, bits<8> sub_opc, dag outs,
                            dag ins, string opcodestr, string argstr,
                            list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegDispSuffix.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// MemRegImmModInst: [prefix_base + reg, SubOpcode + modifier] (2 bytes)
// Operand 0: GPR register, Operand 1: immediate modifier (bit#, cc, etc.).
class MemRegImmModInst<bits<8> prefix_base, bits<8> sub_opc, dag outs,
                        dag ins, string opcodestr, string argstr,
                        list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegImmMod.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = 2;
}

// MemRegRegSuffixInst: [prefix_base + addr_reg, SubOpcode | data_reg] (2 bytes)
// Operand 0: address GPR register, Operand 1: data register.
class MemRegRegSuffixInst<bits<8> prefix_base, bits<8> sub_opc, dag outs,
                           dag ins, string opcodestr, string argstr,
                           list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegRegSuffix.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = 2;
}

// MemRegRegDispSuffixInst: [prefix_base + addr_reg, disp8, SubOpcode | data_reg] (3 bytes)
// Operand 0: address GPR register, Operand 1: displacement, Operand 2: data register.
class MemRegRegDispSuffixInst<bits<8> prefix_base, bits<8> sub_opc, dag outs,
                               dag ins, string opcodestr, string argstr,
                               list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegRegDispSuffix.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = 3;
}

// MemRegImmAfterInst: [prefix_base + reg, SubOpcode, imm_bytes...] (variable size)
// Operand 0: GPR register, remaining: immediate byte operands.
class MemRegImmAfterInst<bits<8> prefix_base, bits<8> sub_opc, int sz,
                          dag outs, dag ins, string opcodestr, string argstr,
                          list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegImmAfter.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// MemRegDispImmAfterInst: [prefix_base + reg, disp8, SubOpcode, imm_bytes...] (variable size)
// Operand 0: GPR register, Operand 1: displacement, remaining: immediate bytes.
class MemRegDispImmAfterInst<bits<8> prefix_base, bits<8> sub_opc, int sz,
                              dag outs, dag ins, string opcodestr,
                              string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemRegDispImmAfter.Value;
  let Opcode = prefix_base;
  let SubOpcode = sub_opc;
  let Size = sz;
}

//===----------------------------------------------------------------------===//
// SRI Register+Register (R+R) addressing instruction formats.
// Encoding: [prefix, mode(0x07), base_reg_addr, idx_reg_addr, SubOpc ...]
//   prefix = Opcode + (Opcode < 0xF0 ? OpSize*0x10 : 0)
//   base_reg_addr = 0xE0 + base_reg_enc * 4
//   idx_reg_addr  = 0xE0 + idx_reg_enc * 4
//===----------------------------------------------------------------------===//

// SriRRRegInst: R+R addressing with data register operand.
// Encoding: [prefix, 0x07, base_addr, idx_addr, SubOpc + data_reg_enc]
// Operand 0: data register, Operand 1: base GPR, Operand 2: index GR16.
class SriRRRegInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                    string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriRRReg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 5;
}

// SriRRUnaryInst: R+R addressing with fixed sub-opcode (JP, CALL).
// Encoding: [prefix, 0x07, base_addr, idx_addr, SubOpc + cc]
// Operand 0: condition code (imm), Operand 1: base GPR, Operand 2: index GR16.
class SriRRUnaryInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                      string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriRRUnary.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 5;
}

// SriRRImmInst: R+R addressing with a trailing immediate and no data register.
// Encoding: [prefix, 0x07, base_addr, idx_addr, SubOpc, imm_bytes...]
// Operand 0: base GPR, Operand 1: index GR16, remaining: immediate bytes.
class SriRRImmInst<bits<8> opc, bits<8> sub_opc, int sz, dag outs, dag ins,
                    string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriRRImm.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = sz;
}

// SriRRQRegInst: R+R addressing whose INDEX is a previous-bank register.
// Encoding: [prefix, 0x07, base_addr, idx_addr, SubOpc + data_reg_enc], with
// idx_addr = 0xE0 + idx_reg_enc * 4 + 2 -- the +2 is what selects the previous
// bank in the register-file address, exactly as the D7 prefix does elsewhere.
class SriRRQRegInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                     string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriRRQReg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 5;
}

// SriRR8RegInst: R+R addressing with 8-bit index register.
// Encoding: [prefix, 0x03, base_addr, idx_addr, SubOpc + data_reg_enc]
// Operand 0: data register, Operand 1: base GPR, Operand 2: index GR8.
class SriRR8RegInst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                     string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriRR8Reg.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 5;
}

//===----------------------------------------------------------------------===//
// MEMORY-TO-MEMORY: one register-indirect operand, one 16-bit DIRECT address.
//
// MI operand order is FIXED in both directions -- base, disp, addr16 -- so the
// emitter reads the same slots whichever way the data flows; the AsmString is
// what puts the destination first.
//===----------------------------------------------------------------------===//
class MemToMemDstInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemToMemDst.Value;
  let Opcode = opc;
  let Size = sz;
}

class MemToMemSrcInst<bits<8> opc, int sz, dag outs, dag ins, string opcodestr,
                      string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatMemToMemSrc.Value;
  let Opcode = opc;
  let Size = sz;
}

// SriRRAddr16Inst: the register-indexed operand paired with a 16-bit DIRECT
// address -- the memory-to-memory move whose memory half is `(Xrr+Rn)`.
// MI operand order: base, index, addr16.
class SriRRAddr16Inst<bits<8> opc, bits<8> sub_opc, dag outs, dag ins,
                      string opcodestr, string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatSriRRAddr16.Value;
  let Opcode = opc;
  let SubOpcode = sub_opc;
  let Size = 7;
}
