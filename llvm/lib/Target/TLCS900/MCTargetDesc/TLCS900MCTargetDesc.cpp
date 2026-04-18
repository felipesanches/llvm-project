//===-- TLCS900MCTargetDesc.cpp - TLCS900 Target Descriptions -----------------===//
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

#include "TLCS900MCTargetDesc.h"
#include "TLCS900InstPrinter.h"
#include "TLCS900MCAsmInfo.h"
#include "TargetInfo/TLCS900TargetInfo.h"
#include "llvm/MC/MCELFStreamer.h"
#include "llvm/MC/MCInstrAnalysis.h"
#include "llvm/MC/MCInstPrinter.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"

using namespace llvm;

#define GET_INSTRINFO_MC_DESC
#define GET_INSTRINFO_MC_HELPERS
#include "TLCS900GenInstrInfo.inc"

#define GET_SUBTARGETINFO_MC_DESC
#include "TLCS900GenSubtargetInfo.inc"

#define GET_REGINFO_MC_DESC
#include "TLCS900GenRegisterInfo.inc"

static MCInstrInfo *createTLCS900MCInstrInfo() {
  MCInstrInfo *X = new MCInstrInfo();
  InitTLCS900MCInstrInfo(X);
  return X;
}

static MCRegisterInfo *createTLCS900MCRegisterInfo(const Triple &TT) {
  MCRegisterInfo *X = new MCRegisterInfo();
  InitTLCS900MCRegisterInfo(X, TLCS900::PC);
  return X;
}

static MCSubtargetInfo *
createTLCS900MCSubtargetInfo(const Triple &TT, StringRef CPU, StringRef FS) {
  std::string CPUName(CPU);
  if (CPUName.empty())
    CPUName = "generic";
  return createTLCS900MCSubtargetInfoImpl(TT, CPUName, /*TuneCPU*/ CPUName, FS);
}

static MCInstPrinter *createTLCS900MCInstPrinter(const Triple &T,
                                               unsigned SyntaxVariant,
                                               const MCAsmInfo &MAI,
                                               const MCInstrInfo &MII,
                                               const MCRegisterInfo &MRI) {
  return new TLCS900InstPrinter(MAI, MII, MRI);
}

static MCAsmInfo *createTLCS900MCAsmInfo(const MCRegisterInfo &MRI,
                                       const Triple &TT,
                                       const MCTargetOptions &Options) {
  MCAsmInfo *MAI = new TLCS900MCAsmInfo(TT);

  unsigned WP = MRI.getDwarfRegNum(TLCS900::XSP, true);
  MCCFIInstruction Inst = MCCFIInstruction::cfiDefCfa(nullptr, WP, 0);
  MAI->addInitialFrameState(Inst);

  return MAI;
}

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900TargetMC() {
  for (Target *T : {&getTheTLCS900Target()}) {
    // Register the MC asm info.
    TargetRegistry::RegisterMCAsmInfo(*T, createTLCS900MCAsmInfo);

    // Register the MC instruction info.
    TargetRegistry::RegisterMCInstrInfo(*T, createTLCS900MCInstrInfo);

    // Register the MC register info.
    TargetRegistry::RegisterMCRegInfo(*T, createTLCS900MCRegisterInfo);

    // Register the MC subtarget info.
    TargetRegistry::RegisterMCSubtargetInfo(*T, createTLCS900MCSubtargetInfo);

    // Register the MCInstPrinter.
    TargetRegistry::RegisterMCInstPrinter(*T, createTLCS900MCInstPrinter);

    // Register the MC code emitter.
    TargetRegistry::RegisterMCCodeEmitter(*T, createTLCS900MCCodeEmitter);

    // Register the asm backend.
    TargetRegistry::RegisterMCAsmBackend(*T, createTLCS900AsmBackend);
  }
}
