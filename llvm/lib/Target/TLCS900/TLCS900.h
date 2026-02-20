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

  void initializeTLCS900DAGToDAGISelLegacyPass(PassRegistry &);

  FunctionPass *createTLCS900BranchShorteningPass();
  FunctionPass *createTLCS900BitManipOptPass();
  FunctionPass *createTLCS900DJNZOptPass();
  FunctionPass *createTLCS900RedundantCmpElimPass();

  // TLCS900 condition codes (matching hardware encoding from MAME/Toshiba docs).
  namespace TLCS900CC {
  enum CondCode {
    COND_F   = 0,   // False (never)
    COND_LT  = 1,   // Less than (signed)
    COND_LE  = 2,   // Less than or equal (signed)
    COND_ULE = 3,   // Unsigned less than or equal
    COND_OV  = 4,   // Overflow
    COND_MI  = 5,   // Minus (negative)
    COND_Z   = 6,   // Zero (equal)
    COND_C   = 7,   // Carry (unsigned less than)
    COND_T   = 8,   // True (always)
    COND_GE  = 9,   // Greater than or equal (signed)
    COND_GT  = 10,  // Greater than (signed)
    COND_UGT = 11,  // Unsigned greater than
    COND_NOV = 12,  // No overflow
    COND_PL  = 13,  // Plus (positive or zero)
    COND_NZ  = 14,  // Not zero (not equal)
    COND_NC  = 15,  // No carry (unsigned greater than or equal)
  };
  } // namespace TLCS900CC

} // end namespace llvm;

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900_H
