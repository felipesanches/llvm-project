//===-- TLCS900TargetInfo.cpp - TLCS900 Target Implementation -----------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "TargetInfo/TLCS900TargetInfo.h"
#include "llvm/MC/TargetRegistry.h"

using namespace llvm;

Target &llvm::getTheTLCS900Target() {
  static Target TheTLCS900Target;
  return TheTLCS900Target;
}

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900TargetInfo() {
  RegisterTarget<Triple::tlcs900> X(getTheTLCS900Target(), "tlcs900",
                                    "TOSHIBA TLCS-900/H2 Series 32-Bit Microcontroller (TMP94C241C)",
                                    "TLCS900");
}
