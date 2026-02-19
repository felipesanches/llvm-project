# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Strict Policies

- **(A) Never build the code.** The user builds manually.
- **(B) Make frequent commits**, always keeping the working directory clean.
- **(C) Store new policies** in both memory and this CLAUDE.md file. Use progressive disclosure when structuring information here.

## Project Goal

LLVM backend for the TLCS-900 family, targeting the **TMP94C241** CPU variant used in the **Technics KN5000** music keyboard (Toshiba TLCS-900/H2 series, 32-bit, 25MHz, 24-bit address bus, 16-bit external data bus, CISC with variable-length 1-7 byte instructions).

## Reference Materials

- **KN5000 docs**: `~/devel/kn5000-docs/` (cpu-subsystem.md, memory-map.md, hardware-architecture.md)
- **ROM disassembly**: `~/devel/kn5000-roms-disasm/` (includes `tmp94c241.inc` with instruction encoding macros)
- **Additional encoding macros**: `~/devel/custom-kn5000-roms/anotherworld/src/includes/local_macros.inc`
- **ASL assembler**: `~/devel/asl-current/asl` (reference output, but encoding not always accurate)

## Repository Overview

This is the LLVM compiler infrastructure monorepo. The active branch develops an experimental TLCS900 backend.

## Build Commands

### Configure and Build (TLCS900 backend focus)
```bash
# Full configure + build (uses the project's build script)
bash build_tlcs900.sh

# Or manually:
cmake -GNinja -Bbuild -Hllvm \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="TLCS900" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=true \
  -DLLVM_CCACHE_BUILD=true \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_ASM_COMPILER=clang

# Build (after configure)
ninja -Cbuild
```

### Incremental Build (after code changes)
```bash
ninja -Cbuild          # Rebuild everything that changed
ninja -Cbuild llc      # Build just the llc tool
ninja -Cbuild clang    # Build just clang
```

### Running Tests
```bash
ninja -Cbuild check-llvm           # All LLVM regression tests
ninja -Cbuild check-llvm-unit      # LLVM unit tests only
ninja -Cbuild check-clang          # Clang tests
ninja -Cbuild check-all            # All project tests

# Run a single lit test
build/bin/llvm-lit llvm/test/CodeGen/TLCS900/some_test.ll
# Run all tests in a directory
build/bin/llvm-lit llvm/test/CodeGen/TLCS900/
# Verbose output
build/bin/llvm-lit -v llvm/test/CodeGen/TLCS900/some_test.ll
```

### Testing TLCS900 Code Generation
```bash
# Compile LLVM IR to TLCS900 assembly
build/bin/llc -mtriple=tlcs900 input.ll -o output.s
```

## Code Formatting
- Style: LLVM (configured in `.clang-format` as `BasedOnStyle: LLVM`)
- Format code: `clang-format -i <file>`
- Naming: Classes are `CamelCase`, functions are `camelBack`, variables/parameters are `CamelCase` (see `.clang-tidy`)

## Architecture

### Compilation Pipeline
```
C/C++ → [Clang Frontend] → LLVM IR → [Opt Passes] → SelectionDAG → MachineInstr → [CodeGen Passes] → Assembly/Object
```

### Key Directories
- `llvm/lib/Target/<Name>/` — Backend implementations (one per architecture)
- `llvm/lib/CodeGen/` — Target-independent code generation
- `llvm/lib/Transforms/` — Optimization passes
- `llvm/lib/IR/` — LLVM IR implementation
- `llvm/lib/MC/` — Machine code emission layer
- `llvm/include/llvm/` — Public headers (mirrors `lib/` structure)
- `clang/lib/CodeGen/` — C/C++ to LLVM IR generation
- `llvm/test/CodeGen/<Target>/` — Regression tests per target

### Backend Structure (using TLCS900 as example)
Every backend in `llvm/lib/Target/<Name>/` follows this pattern:
- **`<Name>.td`** — Master TableGen file, includes all other `.td` files
- **`<Name>RegisterInfo.td`** — Register definitions and classes
- **`<Name>InstrInfo.td`** / **`<Name>InstrFormats.td`** — Instruction set definitions and encoding formats
- **`<Name>CallingConv.td`** — Calling convention rules
- **`<Name>Schedule.td`** — Instruction scheduling model
- **`<Name>TargetMachine.cpp`** — Central orchestrator, creates subtarget and pass pipeline
- **`<Name>Subtarget.cpp`** — Aggregates InstrInfo, RegisterInfo, FrameLowering, TargetLowering per CPU variant
- **`<Name>ISelLowering.cpp`** — Lowers LLVM IR DAG operations to legal target operations
- **`<Name>ISelDAGToDAG.cpp`** — Selects machine instructions from DAG patterns
- **`<Name>InstrInfo.cpp`** — Instruction properties and utilities (copyPhysReg, storeRegToStackSlot, etc.)
- **`<Name>RegisterInfo.cpp`** — Register allocation constraints, callee-saved registers, frame pointer
- **`<Name>FrameLowering.cpp`** — Stack frame layout, prologue/epilogue emission
- **`<Name>AsmPrinter.cpp`** — Machine instruction to assembly text
- **`MCTargetDesc/`** — MC layer: instruction encoding, object file emission
- **`TargetInfo/`** — Target registration with LLVM

### TableGen Code Generation
`.td` files are compiled by TableGen into `.inc` files (in the build directory) that get `#include`d into C++ sources. These generate instruction info tables, register descriptions, DAG pattern matchers, and subtarget features. When modifying `.td` files, the corresponding `.inc` files regenerate automatically during build.

### Pass Infrastructure
- Legacy pass manager: still used for CodeGen passes (register allocation, scheduling, frame lowering)
- New pass manager: used for IR-level optimization passes
- Passes registered in `llvm/lib/Passes/PassRegistry.def`
- CodeGen passes initialized in `llvm/lib/CodeGen/CodeGen.cpp`

### Writing Regression Tests
Tests use LLVM's `lit` test runner with `FileCheck` for output verification:
```llvm
; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

define i32 @add(i32 %a, i32 %b) {
; CHECK-LABEL: add:
; CHECK: add
  %c = add i32 %a, %b
  ret i32 %c
}
```
- `RUN:` lines define how to execute the test
- `CHECK:` / `CHECK-NEXT:` / `CHECK-NOT:` / `CHECK-DAG:` verify output
- `REQUIRES:` / `UNSUPPORTED:` constrain which platforms run the test
- Target-specific tests go in `llvm/test/CodeGen/<Target>/`
- Each target directory has a `lit.local.cfg` that skips tests when the target isn't built

### Adding a New Target to LLVM (Modern API)
Key registration points outside the target directory:
- `llvm/CMakeLists.txt` — Add to `LLVM_ALL_TARGETS` or `LLVM_ALL_EXPERIMENTAL_TARGETS`
- `llvm/include/llvm/TargetParser/Triple.h` — Add architecture enum (moved from `llvm/ADT/Triple.h`)
- `llvm/lib/TargetParser/Triple.cpp` — Triple string parsing (moved from `llvm/lib/Support/`)
- No more `LLVMBuild.txt` — fully replaced by CMake

### Modern LLVM API Notes (vs. the old fork point)
- `LLVMTargetMachine` → `CodeGenTargetMachineImpl`
- `#include "llvm/ADT/Triple.h"` → `#include "llvm/TargetParser/Triple.h"`
- `#include "llvm/Support/TargetRegistry.h"` → `#include "llvm/MC/TargetRegistry.h"`
- `Optional<T>` → `std::optional<T>`
- Subtarget constructor needs `TuneCPU` parameter
- `LLVMBuild.txt` files removed (CMake-only build system)
