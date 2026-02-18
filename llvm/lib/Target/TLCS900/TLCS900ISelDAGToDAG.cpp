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
  Subtarget = &static_cast<const TLCS900Subtarget &>(MF.getSubtarget());
  return SelectionDAGISel::runOnMachineFunction(MF);
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
  default: break;
  }

  // Select the default instruction
  SelectCode(Node);
}
