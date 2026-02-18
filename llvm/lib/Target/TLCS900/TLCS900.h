//=== TLCS900.h - Top-level interface for TLCS900 representation ----*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the entry points for global functions defined in
// the LLVM TLCS900 backend.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_TLCS900_H
#define LLVM_LIB_TARGET_TLCS900_TLCS900_H

#include "MCTargetDesc/TLCS900MCTargetDesc.h"
#include "llvm/Target/TargetMachine.h"

namespace llvm {
  class FunctionPass;
  class PassRegistry;

  // Declare functions to create passes here!

  void initializeTLCS900DAGToDAGISelLegacyPass(PassRegistry &);

} // end namespace llvm;

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900_H
