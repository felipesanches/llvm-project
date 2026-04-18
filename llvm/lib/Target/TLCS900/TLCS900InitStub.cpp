// Transitional stub that lets the LLVM build link while the TLCS-900
// backend is progressively introduced. Removed in the commit that adds
// the full TargetMachine, which provides the real LLVMInitializeTLCS900Target.

#include "llvm/Support/Compiler.h"

extern "C" LLVM_EXTERNAL_VISIBILITY void LLVMInitializeTLCS900Target() {}
