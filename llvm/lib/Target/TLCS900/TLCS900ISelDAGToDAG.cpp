//===-- TLCS900ISelDAGToDAG.cpp - A Dag to Dag Inst Selector for TLCS900 ------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines an instruction selector for the TLCS900 target.
//
//===----------------------------------------------------------------------===//

#include "TLCS900ISelDAGToDAG.h"
#include "TLCS900Subtarget.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/SelectionDAGISel.h"
#include "llvm/Support/Debug.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-isel"
#define PASS_NAME "TLCS900 DAG->DAG Pattern Instruction Selection"

char TLCS900DAGToDAGISelLegacy::ID = 0;

INITIALIZE_PASS(TLCS900DAGToDAGISelLegacy, DEBUG_TYPE, PASS_NAME, false, false)

TLCS900DAGToDAGISelLegacy::TLCS900DAGToDAGISelLegacy(TLCS900TargetMachine &TM,
                                                     CodeGenOptLevel OptLevel)
    : SelectionDAGISelLegacy(
          ID, std::make_unique<TLCS900DAGToDAGISel>(TM, OptLevel)) {}

FunctionPass *llvm::createTLCS900ISelDag(TLCS900TargetMachine &TM,
                                         CodeGenOptLevel OptLevel) {
  return new TLCS900DAGToDAGISelLegacy(TM, OptLevel);
}

bool TLCS900DAGToDAGISel::runOnMachineFunction(MachineFunction &MF) {
  Subtarget = &MF.getSubtarget<TLCS900Subtarget>();
  return SelectionDAGISel::runOnMachineFunction(MF);
}

bool TLCS900DAGToDAGISel::SelectAddr(SDValue Addr, SDValue &Base,
                                     SDValue &Offset) {
  SDLoc DL(Addr);

  // Match frame index
  if (auto *FIN = dyn_cast<FrameIndexSDNode>(Addr)) {
    Base = CurDAG->getTargetFrameIndex(FIN->getIndex(), MVT::i32);
    Offset = CurDAG->getTargetConstant(0, DL, MVT::i32);
    return true;
  }

  // Match base + constant offset
  if (Addr.getOpcode() == ISD::ADD) {
    if (auto *CN = dyn_cast<ConstantSDNode>(Addr.getOperand(1))) {
      SDValue PossibleBase = Addr.getOperand(0);
      if (auto *FIN = dyn_cast<FrameIndexSDNode>(PossibleBase))
        Base = CurDAG->getTargetFrameIndex(FIN->getIndex(), MVT::i32);
      else
        Base = PossibleBase;
      Offset = CurDAG->getTargetConstant(CN->getSExtValue(), DL, MVT::i32);
      return true;
    }
  }

  // Default: treat entire address as base, offset = 0
  Base = Addr;
  Offset = CurDAG->getTargetConstant(0, DL, MVT::i32);
  return true;
}

void TLCS900DAGToDAGISel::Select(SDNode *Node) {
  // If we have a custom node, we already have selected!
  if (Node->isMachineOpcode()) {
    LLVM_DEBUG(errs() << "== "; Node->dump(CurDAG); errs() << "\n");
    Node->setNodeId(-1);
    return;
  }

  // Instruction Selection not handled by the auto-generated tablegen selection
  // should be handled here.
  unsigned Opcode = Node->getOpcode();
  SDLoc DL(Node);

  switch(Opcode) {
  case ISD::FrameIndex: {
    // Materialize frame index address into a register using LDA.
    // This handles cases like passing &local_var to a function call.
    int FI = cast<FrameIndexSDNode>(Node)->getIndex();
    SDValue TFI = CurDAG->getTargetFrameIndex(FI, MVT::i32);
    SDValue Zero = CurDAG->getTargetConstant(0, DL, MVT::i32);
    ReplaceNode(Node,
                CurDAG->getMachineNode(TLCS900::LDA32, DL, MVT::i32, TFI, Zero));
    return;
  }
  default: break;
  }

  // Select the default instruction
  SelectCode(Node);
}
