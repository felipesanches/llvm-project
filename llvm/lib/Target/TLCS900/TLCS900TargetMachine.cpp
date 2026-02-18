//===-- TLCS900TargetMachine.cpp - Define TargetMachine for TLCS900 -------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Implements the info about TLCS900 target spec.
//
//===----------------------------------------------------------------------===//

#include "TLCS900TargetMachine.h"
#include "TLCS900ISelDAGToDAG.h"
#include "TLCS900Subtarget.h"
#include "TLCS900TargetObjectFile.h"
#include "TargetInfo/TLCS900TargetInfo.h"
#include "llvm/CodeGen/Passes.h"
#include "llvm/CodeGen/TargetPassConfig.h"
#include "llvm/MC/TargetRegistry.h"

using namespace llvm;

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900Target() {
  // Register the target.
  //- Little endian Target Machine
  RegisterTargetMachine<TLCS900TargetMachine> X(getTheTLCS900Target());

  auto &PR = *PassRegistry::getPassRegistry();
  initializeTLCS900DAGToDAGISelLegacyPass(PR);
}

static std::string computeDataLayout() {
  std::string Ret = "";

  // Little endian
  Ret += "e";

  // ELF name mangling
  Ret += "-m:e";

  // 32-bit pointers, 32-bit aligned
  Ret += "-p:32:32";

  // 64-bit integers, 64 bit aligned
  Ret += "-i64:64";

  // Native integer widths: 8, 16, and 32-bit
  Ret += "-n8:16:32";

  // 16-bit stack alignment (TLCS900 has 16-bit external data bus)
  Ret += "-S16";

  return Ret;
}

static Reloc::Model getEffectiveRelocModel(std::optional<CodeModel::Model> CM,
                                           std::optional<Reloc::Model> RM) {
  if (!RM.has_value())
    return Reloc::Static;
  return *RM;
}

TLCS900TargetMachine::TLCS900TargetMachine(const Target &T, const Triple &TT,
                                       StringRef CPU, StringRef FS,
                                       const TargetOptions &Options,
                                       std::optional<Reloc::Model> RM,
                                       std::optional<CodeModel::Model> CM,
                                       CodeGenOptLevel OL,
                                       bool JIT)
    : CodeGenTargetMachineImpl(T, computeDataLayout(), TT, CPU, FS, Options,
                        getEffectiveRelocModel(CM, RM),
                        getEffectiveCodeModel(CM, CodeModel::Medium), OL),
      TLOF(std::make_unique<TLCS900TargetObjectFile>()) {
  // initAsmInfo will display features by llc -march=tlcs900 on 3.7
  initAsmInfo();
}

const TLCS900Subtarget *
TLCS900TargetMachine::getSubtargetImpl(const Function &F) const {
  Attribute CPUAttr = F.getFnAttribute("target-cpu");
  Attribute FSAttr = F.getFnAttribute("target-features");

  std::string CPU =
      CPUAttr.isValid() ? CPUAttr.getValueAsString().str() : TargetCPU;
  std::string FS =
      FSAttr.isValid() ? FSAttr.getValueAsString().str() : TargetFS;

  auto &I = SubtargetMap[CPU + FS];
  if (!I) {
    // This needs to be done before we create a new subtarget since any
    // creation will depend on the TM and the code generation flags on the
    // function that reside in TargetOptions.
    resetTargetOptions(F);
    I = std::make_unique<TLCS900Subtarget>(TargetTriple, CPU, FS, *this);
  }
  return I.get();
}

namespace {
class TLCS900PassConfig : public TargetPassConfig {
public:
  TLCS900PassConfig(TLCS900TargetMachine &TM, PassManagerBase &PM)
    : TargetPassConfig(TM, PM) {}

  TLCS900TargetMachine &getTLCS900TargetMachine() const {
    return getTM<TLCS900TargetMachine>();
  }

  bool addInstSelector() override;
  void addPreEmitPass() override;
};
}

TargetPassConfig *TLCS900TargetMachine::createPassConfig(PassManagerBase &PM) {
  return new TLCS900PassConfig(*this, PM);
}

// Install an instruction selector pass using
// the ISelDag to gen TLCS900 code.
bool TLCS900PassConfig::addInstSelector() {
  addPass(createTLCS900ISelDag(getTLCS900TargetMachine(), getOptLevel()));
  return false;
}

// Implemented by targets that want to run passes immediately before
// machine code is emitted. return true if -print-machineinstrs should
// print out the code after the passes.
void TLCS900PassConfig::addPreEmitPass() {
}
