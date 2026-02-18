//===-- TLCS900InstrInfo.cpp - TLCS900 Instruction Information ----------------===//
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

#include "TLCS900InstrInfo.h"

#include "TLCS900TargetMachine.h"
#include "TLCS900MachineFunction.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

#define DEBUG_TYPE "tlcs900-instrinfo"

#define GET_INSTRINFO_CTOR_DTOR
#include "TLCS900GenInstrInfo.inc"

TLCS900InstrInfo::TLCS900InstrInfo(const TLCS900Subtarget &STI)
    : TLCS900GenInstrInfo(TLCS900::ADJCALLSTACKDOWN, TLCS900::ADJCALLSTACKUP),
      Subtarget(STI)
{
}
