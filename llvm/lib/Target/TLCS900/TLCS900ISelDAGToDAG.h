//===---- TLCS900ISelDAGToDAG.h - A Dag to Dag Inst Selector for TLCS900 ------===//
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

#ifndef LLVM_LIB_TARGET_TLCS900_TLCS900ISELDAGTODAG_H
#define LLVM_LIB_TARGET_TLCS900_TLCS900ISELDAGTODAG_H

#include "TLCS900Subtarget.h"
#include "TLCS900TargetMachine.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/SelectionDAGISel.h"

namespace llvm {

class TLCS900DAGToDAGISel : public SelectionDAGISel {
public:
  TLCS900DAGToDAGISel() = delete;

  explicit TLCS900DAGToDAGISel(TLCS900TargetMachine &TM, CodeGenOptLevel OL)
      : SelectionDAGISel(TM, OL), Subtarget(nullptr) {}

  bool runOnMachineFunction(MachineFunction &MF) override;

  void Select(SDNode *Node) override;

#include "TLCS900GenDAGISel.inc"

private:
  const TLCS900Subtarget *Subtarget;
};

class TLCS900DAGToDAGISelLegacy : public SelectionDAGISelLegacy {
public:
  static char ID;
  TLCS900DAGToDAGISelLegacy(TLCS900TargetMachine &TM, CodeGenOptLevel OptLevel);
};

FunctionPass *createTLCS900ISelDag(TLCS900TargetMachine &TM,
                                   CodeGenOptLevel OptLevel);

}

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900ISELDAGTODAG_H
