# LLVM API Changes: Old Fork Point → Current Main

## Build System
- LLVMBuild.txt completely removed — CMake only
- Use `add_llvm_component_library` in CMakeLists.txt with `LINK_COMPONENTS` and `ADD_TO_COMPONENT`

## Headers Moved
- `llvm/ADT/Triple.h` → `llvm/TargetParser/Triple.h`
- `llvm/Support/TargetRegistry.h` → `llvm/MC/TargetRegistry.h`
- `llvm/lib/Support/Triple.cpp` → `llvm/lib/TargetParser/Triple.cpp`

## Class Changes
- `LLVMTargetMachine` → `CodeGenTargetMachineImpl` (base class for targets with codegen)
- `Optional<T>` → `std::optional<T>` (LLVM's Optional removed)

## Method Signature Changes
- `hasFP(const MachineFunction &)` → `hasFPImpl(const MachineFunction &)` (renamed virtual)
- `CanLowerReturn` gained 6th param: `const Type *RetTy`
- `emitPseudoExpansionLowering(MCStreamer&, const MachineInstr*)` → `lowerPseudoInstExpansion(const MachineInstr*, MCInst&)`
- `copyPhysReg(..., MCRegister Dst, MCRegister Src, bool Kill)` → `copyPhysReg(..., Register Dst, Register Src, bool Kill, bool RenamableDest=false, bool RenamableSrc=false)` (Register type + 2 extra bools)
- `countTrailingOnes<T>` → `llvm::countr_one<T>`

## Constructor Signatures
- `createXXXMCSubtargetInfoImpl(TT, CPU, FS)` → `createXXXMCSubtargetInfoImpl(TT, CPU, /*TuneCPU*/ CPU, FS)` (added TuneCPU parameter)
- `XXXGenSubtargetInfo(TT, CPU, FS)` → `XXXGenSubtargetInfo(TT, CPU, /*TuneCPU*/ CPU, FS)`

## Target Registration
- Targets listed in `llvm/CMakeLists.txt` under `LLVM_ALL_TARGETS` or `LLVM_ALL_EXPERIMENTAL_TARGETS`
- Triple enum in `llvm/include/llvm/TargetParser/Triple.h`
