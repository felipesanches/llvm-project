//===-- TLCS900InstrInfo.h - TLCS900 Instruction Information ----------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the TLCS900 implementation of the TargetInstrInfo class.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_TLCS900INSTRINFO_H
#define LLVM_LIB_TARGET_TLCS900_TLCS900INSTRINFO_H

#include "TLCS900.h"
#include "TLCS900RegisterInfo.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/TargetInstrInfo.h"

#define GET_INSTRINFO_HEADER
#include "TLCS900GenInstrInfo.inc"

namespace llvm {

class TLCS900InstrInfo : public TLCS900GenInstrInfo {
public:
  explicit TLCS900InstrInfo(const TLCS900Subtarget &STI);

protected:
  const TLCS900Subtarget &Subtarget;
};
}

#endif // end LLVM_LIB_TARGET_TLCS900_TLCS900INSTRINFO_H
