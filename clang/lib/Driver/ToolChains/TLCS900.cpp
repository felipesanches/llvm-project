//===--- TLCS900.cpp - TLCS900 ToolChain Implementations ----------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "TLCS900.h"
#include "CommonArgs.h"
#include "clang/Driver/Compilation.h"
#include "clang/Driver/Driver.h"
#include "clang/Driver/Options.h"
#include "llvm/Option/ArgList.h"

using namespace clang::driver;
using namespace clang::driver::toolchains;
using namespace clang;
using namespace llvm::opt;

TLCS900ToolChain::TLCS900ToolChain(const Driver &D, const llvm::Triple &Triple,
                                   const ArgList &Args)
    : ToolChain(D, Triple, Args) {}

bool TLCS900ToolChain::isPICDefault() const { return false; }
bool TLCS900ToolChain::isPIEDefault(const llvm::opt::ArgList &Args) const {
  return false;
}
bool TLCS900ToolChain::isPICDefaultForced() const { return false; }
bool TLCS900ToolChain::SupportsProfiling() const { return false; }
bool TLCS900ToolChain::hasBlocksRuntime() const { return false; }
