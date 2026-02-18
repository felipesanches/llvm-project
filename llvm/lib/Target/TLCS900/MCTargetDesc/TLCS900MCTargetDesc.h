//===-- TLCS900MCTargetDesc.h - TLCS900 Target Descriptions ---------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file provides TLCS900 specific target descriptions.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCTARGETDESC_H
#define LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCTARGETDESC_H

#include "TLCS900BaseInfo.h"
#include <memory>

namespace llvm {
class MCAsmBackend;
class MCCodeEmitter;
class MCContext;
class MCInstrInfo;
class MCObjectTargetWriter;
class MCRegisterInfo;
class MCSubtargetInfo;
class MCTargetOptions;
class Target;

MCCodeEmitter *createTLCS900MCCodeEmitter(const MCInstrInfo &MCII,
                                          MCContext &Ctx);

MCAsmBackend *createTLCS900AsmBackend(const Target &T,
                                      const MCSubtargetInfo &STI,
                                      const MCRegisterInfo &MRI,
                                      const MCTargetOptions &Options);

std::unique_ptr<MCObjectTargetWriter>
createTLCS900ELFObjectWriter(uint8_t OSABI);

} // end namespace llvm

// Defines symbolic names for TLCS900 registers. This defines a mapping from
// register name to register number.
#define GET_REGINFO_ENUM
#include "TLCS900GenRegisterInfo.inc"

// Defines symbolic names for the TLCS900 instructions.
#define GET_INSTRINFO_ENUM
#include "TLCS900GenInstrInfo.inc"

#define GET_SUBTARGETINFO_ENUM
#include "TLCS900GenSubtargetInfo.inc"

#endif // end LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCTARGETDESC_H
