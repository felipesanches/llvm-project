//=== TLCS900MachineFunctionInfo.h - Private data used for TLCS900 ----*- C++ -*-=//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
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

/// TLCS900FunctionInfo - This class is derived from MachineFunction private
/// TLCS900 target-specific information for each MachineFunction.
class TLCS900FunctionInfo : public MachineFunctionInfo {
private:
  MachineFunction &MF;

public:
  TLCS900FunctionInfo(MachineFunction &MF) : MF(MF) {}
};

} // end of namespace llvm

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900MACHINEFUNCTION_H
