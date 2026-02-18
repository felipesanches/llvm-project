//=== TLCS900MachineFunctionInfo.h - Private data used for TLCS900 ----*- C++ -*-=//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file declares the TLCS900 specific subclass of MachineFunctionInfo.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_TLCS900MACHINEFUNCTION_H
#define LLVM_LIB_TARGET_TLCS900_TLCS900MACHINEFUNCTION_H

#include "llvm/CodeGen/MachineFunction.h"

namespace llvm {

/// TLCS900FunctionInfo - This class is derived from MachineFunctionInfo and
/// contains private TLCS900 target-specific information for each MachineFunction.
class TLCS900FunctionInfo : public MachineFunctionInfo {
  virtual void anchor();

public:
  TLCS900FunctionInfo(const Function &F, const TargetSubtargetInfo *STI) {}

  MachineFunctionInfo *
  clone(BumpPtrAllocator &Allocator, MachineFunction &DestMF,
        const DenseMap<MachineBasicBlock *, MachineBasicBlock *> &Src2DstMBB)
      const override;
};

} // end of namespace llvm

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900MACHINEFUNCTION_H
