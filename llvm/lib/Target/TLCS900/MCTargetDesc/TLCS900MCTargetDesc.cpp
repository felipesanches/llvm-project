// Transitional stub providing LLVMInitializeTLCS900TargetMC so the LLVM build
// can link while the TLCS-900 MC layer is progressively introduced.
// Replaced with the full implementation in a later commit.

#include "llvm/Support/Compiler.h"

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900TargetMC() {}
