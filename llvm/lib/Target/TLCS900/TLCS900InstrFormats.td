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
class InstFormat<bits<6> val> {
  bits<6> Value = val;
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
def InstFormatDirectSrcReg : InstFormat<35>;
def InstFormatDirectSrcImm : InstFormat<36>;
def InstFormatDirectSrcIncDec : InstFormat<37>;
def InstFormatDirectDstReg : InstFormat<38>;
def InstFormatDirectDstImm : InstFormat<39>;
def InstFormatDirectDstBitOp : InstFormat<40>;
def InstFormatDirectMemToMem : InstFormat<41>;

// Operand size values for TSFlags.
class OpSizeVal<bits<2> val> {
  bits<2> Value = val;
}
def OpSize8  : OpSizeVal<0>;
def OpSize16 : OpSizeVal<1>;
def OpSize32 : OpSizeVal<2>;

// Base class for all TLCS900 instructions.
// TSFlags layout: [4:0] InstFormat, [12:5] Opcode, [14:13] OpSize
class TLCS900Inst<dag outs, dag ins, string opcodestr, string argstr,
                  list<dag> pattern>
    : Instruction {
  let Namespace = "TLCS900";

  // TSFlags fields — subclasses override these.
  bits<6> InstFormat = InstFormatPseudo.Value;
  bits<8> Opcode = 0;
  bits<2> OpSize = OpSize32.Value;
  bits<1> AddrWidth = 0; // 0=16-bit addr, 1=24-bit addr (direct addressing)

  // Wire TSFlags.
  let TSFlags{5-0}   = InstFormat;
  let TSFlags{13-6}  = Opcode;
  let TSFlags{15-14} = OpSize;
  let TSFlags{16}    = AddrWidth;

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
// Encoding: 0x80 prefix (byte-wide source memory, register 0) + sub-opcode
class BlockTransferInst<bits<8> opc, dag outs, dag ins, string opcodestr,
                        string argstr, list<dag> pattern>
    : TLCS900Inst<outs, ins, opcodestr, argstr, pattern> {
  let InstFormat = InstFormatBlockTransfer.Value;
  let Opcode = opc;
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
