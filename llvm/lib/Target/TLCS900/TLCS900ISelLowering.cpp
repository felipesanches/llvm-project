//===-- TLCS900ISelLowering.cpp - TLCS900 DAG Lowering Implementation ---------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines the interfaces that TLCS900 uses to lower LLVM code into a
// selection DAG.
//
//===----------------------------------------------------------------------===//

#include "TLCS900ISelLowering.h"
#include "TLCS900.h"
#include "TLCS900MachineFunction.h"
#include "TLCS900Subtarget.h"
#include "TLCS900TargetMachine.h"
#include "llvm/CodeGen/CallingConvLower.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/SelectionDAG.h"
#include "llvm/CodeGen/SelectionDAGNodes.h"
#include "llvm/CodeGen/ValueTypes.h"
#include "llvm/IR/CallingConv.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-isellower"

#include "TLCS900GenCallingConv.inc"

static unsigned mapISDCCtoTLCS900CC(ISD::CondCode CC) {
  switch (CC) {
  case ISD::SETEQ:  return TLCS900CC::COND_Z;    // 6
  case ISD::SETNE:  return TLCS900CC::COND_NZ;   // 14
  case ISD::SETLT:  return TLCS900CC::COND_LT;   // 1
  case ISD::SETLE:  return TLCS900CC::COND_LE;   // 2
  case ISD::SETGT:  return TLCS900CC::COND_GT;   // 10
  case ISD::SETGE:  return TLCS900CC::COND_GE;   // 9
  case ISD::SETULT: return TLCS900CC::COND_C;    // 7 (carry = unsigned <)
  case ISD::SETULE: return TLCS900CC::COND_ULE;  // 3
  case ISD::SETUGT: return TLCS900CC::COND_UGT;  // 11
  case ISD::SETUGE: return TLCS900CC::COND_NC;   // 15 (no carry = unsigned >=)
  default: llvm_unreachable("Unsupported ISD condition code");
  }
}

TLCS900TargetLowering::TLCS900TargetLowering(const TargetMachine &TM,
                                         const TLCS900Subtarget &STI)
    : TargetLowering(TM), Subtarget(STI)
{
  addRegisterClass(MVT::i32, &TLCS900::GPRRegClass);
  computeRegisterProperties(Subtarget.getRegisterInfo());

  setSchedulingPreference(Sched::RegPressure);
  setStackPointerRegisterToSaveRestore(TLCS900::XSP);
  setBooleanContents(ZeroOrOneBooleanContent);

  // i32 MUL: custom-lowered to three 16×16→32 hardware multiplies.
  // Divide and extended multiplies still use libcalls.
  setOperationAction(ISD::MUL,       MVT::i32, Custom);
  setOperationAction(ISD::MULHS,     MVT::i32, Expand);
  setOperationAction(ISD::MULHU,     MVT::i32, Expand);
  setOperationAction(ISD::SMUL_LOHI, MVT::i32, Expand);
  setOperationAction(ISD::UMUL_LOHI, MVT::i32, Expand);
  setOperationAction(ISD::SDIV,      MVT::i32, Expand);
  setOperationAction(ISD::UDIV,      MVT::i32, Expand);
  setOperationAction(ISD::SREM,      MVT::i32, Expand);
  setOperationAction(ISD::UREM,      MVT::i32, Expand);
  setOperationAction(ISD::SDIVREM,   MVT::i32, Expand);
  setOperationAction(ISD::UDIVREM,   MVT::i32, Expand);

  // Expand shift parts
  setOperationAction(ISD::SHL_PARTS, MVT::i32, Expand);
  setOperationAction(ISD::SRL_PARTS, MVT::i32, Expand);
  setOperationAction(ISD::SRA_PARTS, MVT::i32, Expand);

  // Multi-precision arithmetic: ADC/SBC use carry flag for i64 add/sub
  setOperationAction(ISD::ADDC, MVT::i32, Legal);
  setOperationAction(ISD::ADDE, MVT::i32, Legal);
  setOperationAction(ISD::SUBC, MVT::i32, Legal);
  setOperationAction(ISD::SUBE, MVT::i32, Legal);

  // Expand bit operations
  setOperationAction(ISD::ROTL,  MVT::i32, Expand);
  setOperationAction(ISD::ROTR,  MVT::i32, Expand);
  setOperationAction(ISD::BSWAP, MVT::i32, Expand);
  setOperationAction(ISD::CTTZ,  MVT::i32, Expand);
  setOperationAction(ISD::CTLZ,  MVT::i32, Expand);
  setOperationAction(ISD::CTPOP, MVT::i32, Expand);

  // Branch / comparison lowering
  setOperationAction(ISD::BR_CC,     MVT::i32, Custom);
  setOperationAction(ISD::SELECT_CC, MVT::i32, Custom);
  setOperationAction(ISD::SETCC,     MVT::i32, Custom);
  setOperationAction(ISD::SELECT,    MVT::i32, Expand);
  setOperationAction(ISD::BRCOND,    MVT::Other, Expand);
  setOperationAction(ISD::BR_JT,     MVT::Other, Expand);

  // Address resolution
  setOperationAction(ISD::GlobalAddress,    MVT::i32, Custom);
  setOperationAction(ISD::BlockAddress,     MVT::i32, Custom);
  setOperationAction(ISD::ExternalSymbol,   MVT::i32, Custom);
  setOperationAction(ISD::JumpTable,        MVT::i32, Custom);

  // 8/16-bit truncating stores are supported directly by LD8mr/LD16mr
  setTruncStoreAction(MVT::i32, MVT::i16, Legal);
  setTruncStoreAction(MVT::i32, MVT::i8, Legal);

  // 8/16-bit extending loads are Legal (default) — handled by isel patterns:
  // zextloadi16 → LD16rm + EXTZ32, sextloadi16 → LD16rm + EXTS32,
  // zextloadi8 → LD8rm + AND 255, sextloadi8 → LD8rm + shift pair

  // Sign extend in register — i16 via EXTS, i8 via shift pair
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i16, Legal);
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i8,  Legal);
  setOperationAction(ISD::SIGN_EXTEND_INREG, MVT::i1,  Expand);

  // Trap — lower to TRAP pseudo which expands to SWI 0
  setOperationAction(ISD::TRAP, MVT::Other, Legal);

  // Frame/stack pointer
  setOperationAction(ISD::FRAMEADDR,          MVT::i32, Custom);
  setOperationAction(ISD::DYNAMIC_STACKALLOC, MVT::i32, Expand);

  // Varargs
  setOperationAction(ISD::VASTART, MVT::Other, Custom);
  setOperationAction(ISD::VAARG,   MVT::Other, Expand);
  setOperationAction(ISD::VACOPY,  MVT::Other, Expand);
  setOperationAction(ISD::VAEND,   MVT::Other, Expand);

  setMinFunctionAlignment(Align(1));
  setPrefFunctionAlignment(Align(1));
  setPrefLoopAlignment(Align(1));
}

const char *TLCS900TargetLowering::getTargetNodeName(unsigned Opcode) const {
  switch (Opcode) {
  case TLCS900ISD::Ret:       return "TLCS900ISD::Ret";
  case TLCS900ISD::Call:      return "TLCS900ISD::Call";
  case TLCS900ISD::TailCall:  return "TLCS900ISD::TailCall";
  case TLCS900ISD::CMP:       return "TLCS900ISD::CMP";
  case TLCS900ISD::BRCOND:    return "TLCS900ISD::BRCOND";
  case TLCS900ISD::SELECT_CC: return "TLCS900ISD::SELECT_CC";
  case TLCS900ISD::SCC:       return "TLCS900ISD::SCC";
  case TLCS900ISD::MUL16:     return "TLCS900ISD::MUL16";
  case TLCS900ISD::Wrapper:   return "TLCS900ISD::Wrapper";
  default:                    return nullptr;
  }
}

bool TLCS900TargetLowering::shouldConvertConstantLoadToIntImm(
    const APInt &Imm, Type *Ty) const {
  // Always prefer LD rd, #imm over loading from constant pool.
  // TLCS-900 can load any 32-bit immediate directly.
  return true;
}

EVT TLCS900TargetLowering::getSetCCResultType(const DataLayout &DL,
                                                LLVMContext &Context,
                                                EVT VT) const {
  // Comparison results are i32 (we only support i32 for now).
  return MVT::i32;
}

bool TLCS900TargetLowering::isLegalAddressingMode(const DataLayout &DL,
                                                   const AddrMode &AM,
                                                   Type *Ty, unsigned AS,
                                                   Instruction *I) const {
  // TLCS-900 supports: (reg), (reg+disp16), (imm24)
  // No scaled indexing: reg + scale*idx is not directly supported.
  if (AM.Scale != 0)
    return false;

  // Displacement must fit in 16 bits (signed).
  if (AM.BaseOffs < -32768 || AM.BaseOffs > 32767)
    return false;

  // Either base register or global address, not both in one operand.
  if (AM.HasBaseReg && AM.BaseGV)
    return false;

  return true;
}

SDValue TLCS900TargetLowering::LowerOperation(SDValue Op,
                                               SelectionDAG &DAG) const {
  switch (Op.getOpcode()) {
  default:                        llvm_unreachable("unimplemented operand");
  case ISD::GlobalAddress:        return LowerGlobalAddress(Op, DAG);
  case ISD::BlockAddress:         return LowerBlockAddress(Op, DAG);
  case ISD::ExternalSymbol:       return LowerExternalSymbol(Op, DAG);
  case ISD::JumpTable:            return LowerJumpTable(Op, DAG);
  case ISD::BR_CC:                return LowerBR_CC(Op, DAG);
  case ISD::SELECT_CC:            return LowerSELECT_CC(Op, DAG);
  case ISD::SETCC:                return LowerSETCC(Op, DAG);
  case ISD::MUL:                  return LowerMUL(Op, DAG);
  case ISD::FRAMEADDR:            return LowerFRAMEADDR(Op, DAG);
  case ISD::VASTART:              return LowerVASTART(Op, DAG);
  }
}

void TLCS900TargetLowering::ReplaceNodeResults(SDNode *N,
                                             SmallVectorImpl<SDValue> &Results,
                                             SelectionDAG &DAG) const {
  switch (N->getOpcode()) {
  default:
    llvm_unreachable("Don't know how to custom expand this!");
  }
}

//===----------------------------------------------------------------------===//
// Branch / Compare lowering
//===----------------------------------------------------------------------===//

SDValue TLCS900TargetLowering::LowerBR_CC(SDValue Op,
                                           SelectionDAG &DAG) const {
  SDValue Chain  = Op.getOperand(0);
  ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(1))->get();
  SDValue LHS    = Op.getOperand(2);
  SDValue RHS    = Op.getOperand(3);
  SDValue Dest   = Op.getOperand(4);
  SDLoc DL(Op);

  unsigned TLCS900CC = mapISDCCtoTLCS900CC(CC);
  SDValue Cmp = DAG.getNode(TLCS900ISD::CMP, DL, MVT::Glue, LHS, RHS);
  return DAG.getNode(TLCS900ISD::BRCOND, DL, MVT::Other, Chain,
                     DAG.getConstant(TLCS900CC, DL, MVT::i32), Dest, Cmp);
}

SDValue TLCS900TargetLowering::LowerSELECT_CC(SDValue Op,
                                                SelectionDAG &DAG) const {
  SDValue LHS      = Op.getOperand(0);
  SDValue RHS      = Op.getOperand(1);
  SDValue TrueVal  = Op.getOperand(2);
  SDValue FalseVal = Op.getOperand(3);
  ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(4))->get();
  SDLoc DL(Op);

  unsigned TLCS900CC = mapISDCCtoTLCS900CC(CC);
  SDValue Cmp = DAG.getNode(TLCS900ISD::CMP, DL, MVT::Glue, LHS, RHS);
  return DAG.getNode(TLCS900ISD::SELECT_CC, DL, Op.getValueType(),
                     TrueVal, FalseVal,
                     DAG.getConstant(TLCS900CC, DL, MVT::i32), Cmp);
}

SDValue TLCS900TargetLowering::LowerSETCC(SDValue Op,
                                           SelectionDAG &DAG) const {
  SDLoc DL(Op);
  SDValue LHS = Op.getOperand(0);
  SDValue RHS = Op.getOperand(1);
  ISD::CondCode CC = cast<CondCodeSDNode>(Op.getOperand(2))->get();

  unsigned TLCS900CC = mapISDCCtoTLCS900CC(CC);
  SDValue Cmp = DAG.getNode(TLCS900ISD::CMP, DL, MVT::Glue, LHS, RHS);
  return DAG.getNode(TLCS900ISD::SCC, DL, MVT::i32,
                     DAG.getConstant(TLCS900CC, DL, MVT::i32), Cmp);
}

MachineBasicBlock *
TLCS900TargetLowering::EmitInstrWithCustomInserter(MachineInstr &MI,
                                                    MachineBasicBlock *BB) const {
  assert((MI.getOpcode() == TLCS900::Select32 ||
          MI.getOpcode() == TLCS900::SCC32) &&
         "Unexpected instr type to insert");

  const TargetInstrInfo &TII = *Subtarget.getInstrInfo();
  DebugLoc DL = MI.getDebugLoc();

  // Both Select32 and SCC32 are expanded into a diamond control-flow pattern:
  //  ThisMBB:
  //   ...
  //   jp CC, SinkMBB
  //   fallthrough to FalseMBB
  //  FalseMBB:
  //   ...
  //   fallthrough to SinkMBB
  //  SinkMBB:
  //   %result = phi [ %trueVal, ThisMBB ], [ %falseVal, FalseMBB ]

  const BasicBlock *LLVM_BB = BB->getBasicBlock();
  MachineFunction::iterator I = ++BB->getIterator();

  MachineBasicBlock *ThisMBB = BB;
  MachineFunction *F = BB->getParent();
  MachineBasicBlock *FalseMBB = F->CreateMachineBasicBlock(LLVM_BB);
  MachineBasicBlock *SinkMBB = F->CreateMachineBasicBlock(LLVM_BB);
  F->insert(I, FalseMBB);
  F->insert(I, SinkMBB);

  // Transfer the remainder of BB and its successor edges to SinkMBB.
  SinkMBB->splice(SinkMBB->begin(), BB,
                  std::next(MachineBasicBlock::iterator(MI)), BB->end());
  SinkMBB->transferSuccessorsAndUpdatePHIs(BB);

  BB->addSuccessor(FalseMBB);
  BB->addSuccessor(SinkMBB);
  FalseMBB->addSuccessor(SinkMBB);

  Register DstReg = MI.getOperand(0).getReg();
  Register TrueReg, FalseReg;
  unsigned CC;

  if (MI.getOpcode() == TLCS900::SCC32) {
    // SCC32: operands are (rd, cc)
    // Materialize 1 (true) and 0 (false) into virtual registers.
    MachineRegisterInfo &MRI = F->getRegInfo();
    const TargetRegisterClass *RC = MRI.getRegClass(DstReg);

    TrueReg = MRI.createVirtualRegister(RC);
    FalseReg = MRI.createVirtualRegister(RC);

    // ThisMBB: ld trueReg, 1
    BuildMI(BB, DL, TII.get(TLCS900::LD32ri), TrueReg).addImm(1);

    // FalseMBB: ld falseReg, 0
    BuildMI(*FalseMBB, FalseMBB->end(), DL, TII.get(TLCS900::LD32ri), FalseReg)
        .addImm(0);

    CC = MI.getOperand(1).getImm();
  } else {
    // Select32: operands are (rd, trueVal, falseVal, cc)
    TrueReg = MI.getOperand(1).getReg();
    FalseReg = MI.getOperand(2).getReg();
    CC = MI.getOperand(3).getImm();
  }

  // Insert conditional branch: if CC is true, jump to SinkMBB (use trueVal)
  BuildMI(BB, DL, TII.get(TLCS900::JPcc))
      .addImm(CC)
      .addMBB(SinkMBB);

  // FalseMBB just falls through to SinkMBB (no instruction needed)

  // SinkMBB: insert PHI
  BuildMI(*SinkMBB, SinkMBB->begin(), DL, TII.get(TLCS900::PHI), DstReg)
      .addReg(TrueReg)
      .addMBB(ThisMBB)
      .addReg(FalseReg)
      .addMBB(FalseMBB);

  MI.eraseFromParent();
  return SinkMBB;
}

//===----------------------------------------------------------------------===//
// Address lowering
//===----------------------------------------------------------------------===//

SDValue
TLCS900TargetLowering::LowerGlobalAddress(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  auto *N = cast<GlobalAddressSDNode>(Op);
  SDValue GA = DAG.getTargetGlobalAddress(N->getGlobal(), DL, MVT::i32,
                                          N->getOffset());
  return DAG.getNode(TLCS900ISD::Wrapper, DL, MVT::i32, GA);
}

SDValue
TLCS900TargetLowering::LowerBlockAddress(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  auto *N = cast<BlockAddressSDNode>(Op);
  SDValue BA = DAG.getTargetBlockAddress(N->getBlockAddress(), MVT::i32,
                                         N->getOffset());
  return DAG.getNode(TLCS900ISD::Wrapper, DL, MVT::i32, BA);
}

SDValue
TLCS900TargetLowering::LowerExternalSymbol(SDValue Op,
                                            SelectionDAG &DAG) const {
  SDLoc DL(Op);
  auto *N = cast<ExternalSymbolSDNode>(Op);
  SDValue ES = DAG.getTargetExternalSymbol(N->getSymbol(), MVT::i32);
  return DAG.getNode(TLCS900ISD::Wrapper, DL, MVT::i32, ES);
}

SDValue
TLCS900TargetLowering::LowerJumpTable(SDValue Op, SelectionDAG &DAG) const {
  SDLoc DL(Op);
  auto *N = cast<JumpTableSDNode>(Op);
  SDValue Result = DAG.getTargetJumpTable(N->getIndex(), MVT::i32);
  return DAG.getNode(TLCS900ISD::Wrapper, DL, MVT::i32, Result);
}

//===----------------------------------------------------------------------===//
// Multiply lowering
//===----------------------------------------------------------------------===//

SDValue TLCS900TargetLowering::LowerMUL(SDValue Op, SelectionDAG &DAG) const {
  // Decompose i32 multiply into three 16×16→32 hardware multiplies:
  //   c = a * b  →  MUL16(a_lo, b_lo)
  //                + (MUL16(a_hi, b_lo) + MUL16(a_lo, b_hi)) << 16
  // The a_hi * b_hi term is entirely ≥ 2^32 and drops out.
  SDLoc DL(Op);
  SDValue A = Op.getOperand(0);
  SDValue B = Op.getOperand(1);

  SDValue Mask = DAG.getConstant(0xFFFF, DL, MVT::i32);
  SDValue Shift16 = DAG.getConstant(16, DL, MVT::i32);

  // Extract 16-bit halves (zero-extended in the 32-bit register).
  SDValue ALo = DAG.getNode(ISD::AND, DL, MVT::i32, A, Mask);
  SDValue AHi = DAG.getNode(ISD::SRL, DL, MVT::i32, A, Shift16);
  SDValue BLo = DAG.getNode(ISD::AND, DL, MVT::i32, B, Mask);
  SDValue BHi = DAG.getNode(ISD::SRL, DL, MVT::i32, B, Shift16);

  // Three 16×16→32 unsigned multiplies.
  SDValue LoLo = DAG.getNode(TLCS900ISD::MUL16, DL, MVT::i32, ALo, BLo);
  SDValue HiLo = DAG.getNode(TLCS900ISD::MUL16, DL, MVT::i32, AHi, BLo);
  SDValue LoHi = DAG.getNode(TLCS900ISD::MUL16, DL, MVT::i32, ALo, BHi);

  // Combine: result = LoLo + ((HiLo + LoHi) << 16)
  SDValue Cross = DAG.getNode(ISD::ADD, DL, MVT::i32, HiLo, LoHi);
  SDValue CrossShifted = DAG.getNode(ISD::SHL, DL, MVT::i32, Cross, Shift16);
  return DAG.getNode(ISD::ADD, DL, MVT::i32, LoLo, CrossShifted);
}

//===----------------------------------------------------------------------===//
// Frame address
//===----------------------------------------------------------------------===//

SDValue
TLCS900TargetLowering::LowerFRAMEADDR(SDValue Op, SelectionDAG &DAG) const {
  MachineFrameInfo &MFI = DAG.getMachineFunction().getFrameInfo();
  MFI.setFrameAddressIsTaken(true);

  unsigned Depth = Op.getConstantOperandVal(0);
  SDLoc DL(Op);

  if (Depth != 0)
    return SDValue(); // Only support depth 0 for now.

  // Return the current stack pointer (no frame pointer on TLCS-900).
  return DAG.getCopyFromReg(DAG.getEntryNode(), DL, TLCS900::XSP, MVT::i32);
}

//===----------------------------------------------------------------------===//
// Varargs
//===----------------------------------------------------------------------===//

SDValue
TLCS900TargetLowering::LowerVASTART(SDValue Op, SelectionDAG &DAG) const {
  MachineFunction &MF = DAG.getMachineFunction();
  auto *FuncInfo = MF.getInfo<TLCS900FunctionInfo>();
  SDLoc DL(Op);

  // va_start stores the address of the first vararg into the va_list pointer.
  SDValue FI = DAG.getFrameIndex(FuncInfo->getVarArgsFrameIndex(), MVT::i32);
  const Value *SV = cast<SrcValueSDNode>(Op.getOperand(2))->getValue();
  return DAG.getStore(Op.getOperand(0), DL, FI, Op.getOperand(1),
                      MachinePointerInfo(SV));
}

//===----------------------------------------------------------------------===//
// Formal Arguments
//===----------------------------------------------------------------------===//

SDValue TLCS900TargetLowering::LowerFormalArguments(
                                    SDValue Chain,
                                    CallingConv::ID CallConv,
                                    bool isVarArg,
                                    const SmallVectorImpl<ISD::InputArg> &Ins,
                                    const SDLoc &dl, SelectionDAG &DAG,
                                    SmallVectorImpl<SDValue> &InVals) const {
  MachineFunction &MF = DAG.getMachineFunction();
  MachineRegisterInfo &RegInfo = MF.getRegInfo();

  // Use the vararg calling convention for variadic functions (all args on stack)
  auto CCFunc = isVarArg ? TLCS900_VarargCC : TLCS900_CCallingConv;

  SmallVector<CCValAssign, 16> ArgLocs;
  CCState CCInfo(CallConv, isVarArg, DAG.getMachineFunction(), ArgLocs,
                 *DAG.getContext());
  CCInfo.AnalyzeFormalArguments(Ins, CCFunc);

  for (unsigned i = 0, e = ArgLocs.size(); i != e; ++i) {
    CCValAssign &VA = ArgLocs[i];

    if (VA.isRegLoc()) {
      EVT RegVT = VA.getLocVT();
      const TargetRegisterClass *RC = &TLCS900::GPRRegClass;
      assert(RegVT == MVT::i32 && "Unexpected register type");

      Register VReg = RegInfo.createVirtualRegister(RC);
      RegInfo.addLiveIn(VA.getLocReg(), VReg);
      SDValue ArgValue = DAG.getCopyFromReg(Chain, dl, VReg, RegVT);

      switch (VA.getLocInfo()) {
      default: llvm_unreachable("Unknown loc info!");
      case CCValAssign::Full: break;
      case CCValAssign::SExt:
        ArgValue = DAG.getNode(ISD::AssertSext, dl, RegVT, ArgValue,
                               DAG.getValueType(VA.getValVT()));
        ArgValue = DAG.getNode(ISD::TRUNCATE, dl, VA.getValVT(), ArgValue);
        break;
      case CCValAssign::ZExt:
        ArgValue = DAG.getNode(ISD::AssertZext, dl, RegVT, ArgValue,
                               DAG.getValueType(VA.getValVT()));
        ArgValue = DAG.getNode(ISD::TRUNCATE, dl, VA.getValVT(), ArgValue);
        break;
      }

      InVals.push_back(ArgValue);
    } else {
      // Stack argument
      assert(VA.isMemLoc());
      EVT ValVT = VA.getValVT();
      int FI = MF.getFrameInfo().CreateFixedObject(
          ValVT.getSizeInBits() / 8, VA.getLocMemOffset(), true);
      SDValue FIN = DAG.getFrameIndex(FI, MVT::i32);
      SDValue Load = DAG.getLoad(ValVT, dl, Chain, FIN,
                                 MachinePointerInfo::getFixedStack(MF, FI));
      InVals.push_back(Load);
    }
  }

  // For variadic functions, record the frame index where varargs begin
  if (isVarArg) {
    auto *FuncInfo = MF.getInfo<TLCS900FunctionInfo>();
    unsigned StackSize = CCInfo.getStackSize();
    int FI = MF.getFrameInfo().CreateFixedObject(4, StackSize, true);
    FuncInfo->setVarArgsFrameIndex(FI);
  }

  return Chain;
}

//===----------------------------------------------------------------------===//
// Return Value
//===----------------------------------------------------------------------===//

bool TLCS900TargetLowering::CanLowerReturn(CallingConv::ID CallConv,
                                MachineFunction &MF, bool isVarArg,
                                const SmallVectorImpl<ISD::OutputArg> &Outs,
                                LLVMContext &Context,
                                const Type *RetTy) const {
  SmallVector<CCValAssign, 16> RVLocs;
  CCState CCInfo(CallConv, isVarArg, MF, RVLocs, Context);
  return CCInfo.CheckReturn(Outs, TLCS900_CRetConv);
}

SDValue
TLCS900TargetLowering::LowerReturn(SDValue Chain,
                                 CallingConv::ID CallConv, bool isVarArg,
                                 const SmallVectorImpl<ISD::OutputArg> &Outs,
                                 const SmallVectorImpl<SDValue> &OutVals,
                                 const SDLoc &dl, SelectionDAG &DAG) const {
  SmallVector<CCValAssign, 16> RVLocs;
  CCState CCInfo(CallConv, isVarArg, DAG.getMachineFunction(), RVLocs,
                 *DAG.getContext());
  CCInfo.AnalyzeReturn(Outs, TLCS900_CRetConv);

  SDValue Glue;
  SmallVector<SDValue, 4> RetOps;
  RetOps.push_back(Chain);

  for (unsigned i = 0; i != RVLocs.size(); ++i) {
    CCValAssign &VA = RVLocs[i];
    assert(VA.isRegLoc() && "Can only return in registers!");

    SDValue Arg = OutVals[i];

    switch (VA.getLocInfo()) {
    default: llvm_unreachable("Unknown loc info!");
    case CCValAssign::Full: break;
    case CCValAssign::BCvt:
      Arg = DAG.getNode(ISD::BITCAST, dl, VA.getLocVT(), Arg);
      break;
    }

    Chain = DAG.getCopyToReg(Chain, dl, VA.getLocReg(), Arg, Glue);
    Glue = Chain.getValue(1);
    RetOps.push_back(DAG.getRegister(VA.getLocReg(), VA.getLocVT()));
  }

  RetOps[0] = Chain;
  if (Glue.getNode())
    RetOps.push_back(Glue);

  return DAG.getNode(TLCS900ISD::Ret, dl, MVT::Other, RetOps);
}

//===----------------------------------------------------------------------===//
// Call lowering
//===----------------------------------------------------------------------===//

/// Return true if the call can be lowered as a tail call.
static bool isEligibleForTailCallOptimization(
    TargetLowering::CallLoweringInfo &CLI) {
  // No tail calls with varargs.
  if (CLI.IsVarArg)
    return false;

  // Caller and callee must use the same calling convention.
  MachineFunction &MF = CLI.DAG.getMachineFunction();
  CallingConv::ID CallerCC = MF.getFunction().getCallingConv();
  if (CLI.CallConv != CallerCC)
    return false;

  // Don't tail call if the callee has byval/inalloca/preallocated args.
  for (const auto &Arg : CLI.Outs) {
    if (Arg.Flags.isByVal() || Arg.Flags.isInAlloca() ||
        Arg.Flags.isPreallocated())
      return false;
  }

  // Check that the return values can be lowered the same way.
  // If the caller returns void, any callee is fine.
  // Otherwise, the callee's return type must match the caller's.
  if (!CLI.Ins.empty()) {
    SmallVector<CCValAssign, 16> CallerRVLocs;
    CCState CallerCCInfo(CallerCC, false, MF, CallerRVLocs,
                         *CLI.DAG.getContext());
    // Get the caller's return outputs from the function signature.
    const Function &F = MF.getFunction();
    SmallVector<ISD::OutputArg, 4> CallerOuts;
    // Simple check: if caller doesn't return, tail call is fine.
    if (F.getReturnType()->isVoidTy())
      return true;
  }

  return true;
}

SDValue TLCS900TargetLowering::LowerCall(TargetLowering::CallLoweringInfo &CLI,
                                       SmallVectorImpl<SDValue> &InVals) const {
  SelectionDAG &DAG = CLI.DAG;
  SDLoc &DL = CLI.DL;
  SmallVectorImpl<ISD::OutputArg> &Outs = CLI.Outs;
  SmallVectorImpl<SDValue> &OutVals = CLI.OutVals;
  SmallVectorImpl<ISD::InputArg> &Ins = CLI.Ins;
  SDValue Chain = CLI.Chain;
  SDValue Callee = CLI.Callee;
  CallingConv::ID CallConv = CLI.CallConv;
  bool IsVarArg = CLI.IsVarArg;
  bool IsTailCall = CLI.IsTailCall;

  // Use the vararg calling convention for variadic calls (all args on stack)
  auto CCFunc = IsVarArg ? TLCS900_VarargCC : TLCS900_CCallingConv;

  SmallVector<CCValAssign, 16> ArgLocs;
  CCState CCInfo(CallConv, IsVarArg, DAG.getMachineFunction(), ArgLocs,
                 *DAG.getContext());
  CCInfo.AnalyzeCallOperands(Outs, CCFunc);

  unsigned NumBytes = CCInfo.getStackSize();

  // Check tail call eligibility.
  if (IsTailCall) {
    if (!isEligibleForTailCallOptimization(CLI))
      IsTailCall = false;
    // Tail calls can't have stack arguments (we'd need to write to the
    // caller's frame which is being deallocated).
    if (NumBytes != 0)
      IsTailCall = false;
  }
  CLI.IsTailCall = IsTailCall;

  if (!IsTailCall)
    Chain = DAG.getCALLSEQ_START(Chain, NumBytes, 0, DL);

  SmallVector<std::pair<unsigned, SDValue>, 4> RegsToPass;
  SmallVector<SDValue, 8> MemOpChains;

  for (unsigned i = 0, e = ArgLocs.size(); i != e; ++i) {
    CCValAssign &VA = ArgLocs[i];
    SDValue Arg = OutVals[i];

    switch (VA.getLocInfo()) {
    default: llvm_unreachable("Unknown loc info!");
    case CCValAssign::Full: break;
    case CCValAssign::SExt:
      Arg = DAG.getNode(ISD::SIGN_EXTEND, DL, VA.getLocVT(), Arg);
      break;
    case CCValAssign::ZExt:
      Arg = DAG.getNode(ISD::ZERO_EXTEND, DL, VA.getLocVT(), Arg);
      break;
    case CCValAssign::AExt:
      Arg = DAG.getNode(ISD::ANY_EXTEND, DL, VA.getLocVT(), Arg);
      break;
    }

    if (VA.isRegLoc()) {
      RegsToPass.push_back(std::make_pair(VA.getLocReg(), Arg));
    } else {
      assert(VA.isMemLoc());
      assert(!IsTailCall && "Tail call with stack args should be rejected");
      SDValue StackPtr = DAG.getCopyFromReg(Chain, DL, TLCS900::XSP,
                                            MVT::i32);
      SDValue PtrOff = DAG.getNode(
          ISD::ADD, DL, MVT::i32, StackPtr,
          DAG.getIntPtrConstant(VA.getLocMemOffset(), DL));
      MemOpChains.push_back(
          DAG.getStore(Chain, DL, Arg, PtrOff, MachinePointerInfo()));
    }
  }

  if (!MemOpChains.empty())
    Chain = DAG.getNode(ISD::TokenFactor, DL, MVT::Other, MemOpChains);

  // Build a sequence of copy-to-reg nodes chained together with glue
  SDValue InGlue;
  for (auto &Reg : RegsToPass) {
    Chain = DAG.getCopyToReg(Chain, DL, Reg.first, Reg.second, InGlue);
    InGlue = Chain.getValue(1);
  }

  // Resolve callee
  if (GlobalAddressSDNode *G = dyn_cast<GlobalAddressSDNode>(Callee))
    Callee = DAG.getTargetGlobalAddress(G->getGlobal(), DL, MVT::i32);
  else if (ExternalSymbolSDNode *E = dyn_cast<ExternalSymbolSDNode>(Callee))
    Callee = DAG.getTargetExternalSymbol(E->getSymbol(), MVT::i32);

  // Build the CALL or TAIL_CALL node
  SmallVector<SDValue, 8> Ops;
  Ops.push_back(Chain);
  Ops.push_back(Callee);

  for (auto &Reg : RegsToPass)
    Ops.push_back(DAG.getRegister(Reg.first, Reg.second.getValueType()));

  // Add register mask for call-clobbered registers
  const TargetRegisterInfo *TRI = Subtarget.getRegisterInfo();
  const uint32_t *Mask =
      TRI->getCallPreservedMask(DAG.getMachineFunction(), CallConv);
  Ops.push_back(DAG.getRegisterMask(Mask));

  if (InGlue.getNode())
    Ops.push_back(InGlue);

  if (IsTailCall) {
    DAG.getMachineFunction().getFrameInfo().setHasTailCall();
    return DAG.getNode(TLCS900ISD::TailCall, DL, MVT::Other, Ops);
  }

  SDVTList NodeTys = DAG.getVTList(MVT::Other, MVT::Glue);
  Chain = DAG.getNode(TLCS900ISD::Call, DL, NodeTys, Ops);
  InGlue = Chain.getValue(1);

  Chain = DAG.getCALLSEQ_END(Chain, NumBytes, 0, InGlue, DL);
  InGlue = Chain.getValue(1);

  // Handle return values
  SmallVector<CCValAssign, 16> RVLocs;
  CCState RVInfo(CallConv, IsVarArg, DAG.getMachineFunction(), RVLocs,
                 *DAG.getContext());
  RVInfo.AnalyzeCallResult(Ins, TLCS900_CRetConv);

  for (auto &VA : RVLocs) {
    SDValue RetVal =
        DAG.getCopyFromReg(Chain, DL, VA.getLocReg(), VA.getValVT(), InGlue);
    Chain = RetVal.getValue(1);
    InGlue = RetVal.getValue(2);
    InVals.push_back(RetVal);
  }

  return Chain;
}

//===----------------------------------------------------------------------===//
// Inline Assembly Support
//===----------------------------------------------------------------------===//

TLCS900TargetLowering::ConstraintType
TLCS900TargetLowering::getConstraintType(StringRef Constraint) const {
  if (Constraint.size() == 1) {
    switch (Constraint[0]) {
    case 'r': // General-purpose register
      return C_RegisterClass;
    default:
      break;
    }
  }
  return TargetLowering::getConstraintType(Constraint);
}

std::pair<unsigned, const TargetRegisterClass *>
TLCS900TargetLowering::getRegForInlineAsmConstraint(
    const TargetRegisterInfo *TRI, StringRef Constraint, MVT VT) const {
  if (Constraint.size() == 1) {
    switch (Constraint[0]) {
    case 'r':
      return std::make_pair(0U, &TLCS900::GPRRegClass);
    default:
      break;
    }
  }

  // Use the default implementation in TargetLowering to convert the register
  // constraint into an actual register (handles {xwa}, {xbc}, etc.).
  return TargetLowering::getRegForInlineAsmConstraint(TRI, Constraint, VT);
}
