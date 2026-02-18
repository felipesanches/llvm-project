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

  // TLCS900 condition codes (matching hardware encoding).
  namespace TLCS900CC {
  enum CondCode {
    COND_F   = 0,   // False (never)
    COND_LT  = 1,   // Less than (signed)
    COND_LE  = 2,   // Less than or equal (signed)
    COND_ULT = 3,   // Unsigned less than (carry)
    COND_ULE = 4,   // Unsigned less than or equal
    COND_PE  = 5,   // Parity even (overflow)
    COND_MI  = 6,   // Minus (negative)
    COND_Z   = 7,   // Zero (equal)
    COND_T   = 8,   // True (always)
    COND_GE  = 9,   // Greater than or equal (signed)
    COND_GT  = 10,  // Greater than (signed)
    COND_UGE = 11,  // Unsigned greater than or equal
    COND_UGT = 12,  // Unsigned greater than
    COND_PO  = 13,  // Parity odd (no overflow)
    COND_PL  = 14,  // Plus (positive or zero)
    COND_NZ  = 15,  // Not zero (not equal)
  };
  } // namespace TLCS900CC

} // end namespace llvm;

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900_H
