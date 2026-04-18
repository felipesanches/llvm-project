//===-- TLCS900MCAsmInfo.cpp - TLCS900 Asm Properties -------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the declarations of the TLCS900MCAsmInfo properties.
//
//===----------------------------------------------------------------------===//

#include "TLCS900MCAsmInfo.h"

#include "llvm/TargetParser/Triple.h"

using namespace llvm;

void TLCS900MCAsmInfo::anchor() { }

TLCS900MCAsmInfo::TLCS900MCAsmInfo(const Triple &TheTriple) {
  // TLCS900 is little endian
  IsLittleEndian = true;

  AlignmentIsInBytes          = false;
  Data16bitsDirective         = "\t.hword\t";
  Data32bitsDirective         = "\t.word\t";
  Data64bitsDirective         = "\t.dword\t";

  PrivateGlobalPrefix         = ".L";
  PrivateLabelPrefix          = ".L";

  LabelSuffix                 = ":";

  CommentString               = ";";

  ZeroDirective               = "\t.zero\t";

  UseAssignmentForEHBegin     = true;

  SupportsDebugInformation    = true;
  ExceptionsType              = ExceptionHandling::DwarfCFI;
  DwarfRegNumForCFI           = true;
}
