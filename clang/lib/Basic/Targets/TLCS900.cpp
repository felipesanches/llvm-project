//===--- TLCS900.cpp - Implement TLCS900 target feature support ---------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements TLCS900TargetInfo objects.
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "clang/Basic/MacroBuilder.h"

using namespace clang;
using namespace clang::targets;

static const char *const GCCRegNames[] = {
    // 8-bit registers
    "w", "a", "b", "c", "d", "e", "h", "l",
    // 16-bit registers
    "wa", "bc", "de", "hl", "ix", "iy", "iz", "sp",
    // 32-bit registers
    "xwa", "xbc", "xde", "xhl", "xix", "xiy", "xiz", "xsp",
};

ArrayRef<const char *> TLCS900TargetInfo::getGCCRegNames() const {
  return llvm::ArrayRef(GCCRegNames);
}

void TLCS900TargetInfo::getTargetDefines(const LangOptions &Opts,
                                         MacroBuilder &Builder) const {
  Builder.defineMacro("__TLCS900__");
}
