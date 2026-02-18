//===-- TLCS900BaseInfo.h - Top level definitions for TLCS900 MC ----*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains small standalone enum definitions for the TLCS900 target
// useful for the compiler back-end and the MC libraries.
//
//===----------------------------------------------------------------------===//
#ifndef LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900BASEINFO_H
#define LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900BASEINFO_H

#include "llvm/MC/MCInstrDesc.h"

namespace llvm {

// TLCS900II - This namespace holds all of the target specific flags that
// instruction info tracks.
namespace TLCS900II {
enum {
  InstFormatPseudo = 0,

  InstFormatMask = 31
};

} // namespace TLCS900II

} // namespace llvm

#endif
