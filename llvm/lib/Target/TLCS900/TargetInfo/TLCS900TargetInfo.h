//===---- TLCS900TargetInfo.h - TLCS900 Target Implementation -------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_TARGETINFO_TLCS900TARGETINFO_H
#define LLVM_LIB_TARGET_TLCS900_TARGETINFO_TLCS900TARGETINFO_H

namespace llvm {

class Target;

Target &getTheTLCS900Target();

} // namespace llvm

#endif // LLVM_LIB_TARGET_TLCS900_TARGETINFO_TLCS900TARGETINFO_H
