//===-- TLCS900MCAsmInfo.h - TLCS900 Asm Info ------------------------*- C++ -*--===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains the declaration of the TLCS900MCAsmInfo class.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCASMINFO_H
#define LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCASMINFO_H

#include "llvm/MC/MCAsmInfoELF.h"

namespace llvm {
  class Triple;

namespace TLCS900 {
// `sym@hi16` / `sym@lo16`: the high / low 16 bits of a 32-bit address, as
// two 16-bit immediates (the firmware's C compiler passes a far pointer as
// `pushw hi; pushw lo`).  Resolved by the linker through R_TLCS900_HI16 /
// R_TLCS900_LO16.
enum Specifier : uint8_t { S_None = 0, S_HI16 = 1, S_LO16 = 2 };
} // namespace TLCS900

class TLCS900MCAsmInfo : public MCAsmInfoELF {
  void anchor() override;

public:
  explicit TLCS900MCAsmInfo(const Triple &TheTriple);
};

} // namespace llvm

#endif // end LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCASMINFO_H
