//===-- TLCS900MachineFunctionInfo.cpp - TLCS900 Machine Function Info ---------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "TLCS900MachineFunction.h"

using namespace llvm;

void TLCS900FunctionInfo::anchor() {}

MachineFunctionInfo *TLCS900FunctionInfo::clone(
    BumpPtrAllocator &Allocator, MachineFunction &DestMF,
    const DenseMap<MachineBasicBlock *, MachineBasicBlock *> &Src2DstMBB)
    const {
  return DestMF.cloneInfo<TLCS900FunctionInfo>(*this);
}
