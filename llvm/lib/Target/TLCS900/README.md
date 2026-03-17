# TLCS-900 Backend

LLVM backend for the Toshiba TLCS-900 CPU family, targeting the **TMP94C241F**
(TLCS-900/H2 series) used in the Technics KN5000 music keyboard.

## Architecture Overview

- **Type:** 32-bit CISC with 24-bit address bus and 16-bit external data bus
- **Instructions:** Variable-length, 1-7 bytes, prefix-based encoding
- **Endianness:** Little-endian
- **Clock:** Up to 25 MHz (KN5000 runs at 16 MHz)

### Register File

Three register widths share a single physical bank:

| 32-bit | 16-bit (lo) | 8-bit (hi/lo) |
|--------|-------------|----------------|
| XWA    | WA          | W, A           |
| XBC    | BC          | B, C           |
| XDE    | DE          | D, E           |
| XHL    | HL          | H, L           |
| XIX    | IX          | —              |
| XIY    | IY          | —              |
| XIZ    | IZ          | —              |
| XSP    | SP          | —              |

A **previous bank** (accessed via the `D7` prefix byte) provides a second set of
registers (QWA, QBC, QDE, QHL, QIX, QIY, QIZ). This is used by the firmware for
fast context switching but is not used by the C compiler.

### Addressing Modes

- Register direct: `xwa`, `bc`, `a`
- Immediate: `#imm8/16/32`
- Memory direct: `(0x1A0000)` — 8/16/24-bit addresses
- Register indirect: `(xhl)`, `(xix)`
- Register + displacement: `(xix + 0x10)` (d8), `(xix + 0x1234)` (d16)
- Auto-increment/decrement: `(xhl+)`, `(-xhl)`
- PC-relative: branches use signed 8-bit or 16-bit offsets

### Subtarget Features

| Feature    | Description                    | Processors         |
|------------|--------------------------------|--------------------|
| `hwmul`    | Hardware MUL/MULS/DIV/DIVS    | 900/H and later    |
| `minmax`   | MIN/MAX instructions           | 900/H2 and later   |
| `mdma`     | Micro-DMA controller           | (defined, unused)  |

Defined processors: `generic`, `tlcs900h`, `tlcs900h1`, `tlcs900h2`, `tmp94c241`.

## Calling Convention

- **Arguments:** XDE (1st), XBC (2nd), XIX (3rd), XIY (4th); remaining on stack
- **Return value:** XDE (first return register)
- **Callee-saved:** XIX, XIY, XIZ
- **Frame pointer:** XIZ (when needed — variable-sized alloca, setjmp, etc.)
- **Promotion:** i1/i8/i16 promoted to i32
- **Varargs:** All arguments passed on the stack (no register passing)

## Backend Structure

### TableGen Definitions (`*.td`)

| File | Purpose |
|------|---------|
| `TLCS900.td` | Top-level: includes all `.td` files, defines target and processor models |
| `TLCS900RegisterInfo.td` | Register hierarchy (8/16/32-bit), sub-register indices, register classes |
| `TLCS900InstrInfo.td` | Instruction definitions, DAG patterns, operand types |
| `TLCS900InstrFormats.td` | Encoding format classes (prefix bytes, operand layout, addressing modes) |
| `TLCS900CallingConv.td` | Calling convention rules (arg/ret register assignment) |
| `TLCS900Schedule.td` | Scheduling model (currently `NoSchedModel`) |

### Code Generation (`*.cpp` / `*.h`)

| File | Purpose |
|------|---------|
| `TLCS900TargetMachine.*` | Target registration, pass pipeline setup |
| `TLCS900Subtarget.*` | Subtarget features, aggregates all target info objects |
| `TLCS900ISelLowering.*` | DAG lowering: custom lowering for operations not natively supported |
| `TLCS900ISelDAGToDAG.*` | Instruction selection: DAG pattern matching to machine instructions |
| `TLCS900InstrInfo.*` | Instruction utilities: `copyPhysReg`, `storeRegToStackSlot`, branch analysis |
| `TLCS900RegisterInfo.*` | Register constraints, `eliminateFrameIndex`, callee-saved regs |
| `TLCS900FrameLowering.*` | Prologue/epilogue emission, stack frame layout |
| `TLCS900SelectionDAGInfo.*` | Custom memcpy (LDIR) and memmove (LDDR) lowering |
| `TLCS900AsmPrinter.cpp` | Machine instruction to assembly text |
| `TLCS900MachineFunction.*` | Per-function target state |
| `TLCS900TargetObjectFile.*` | ELF object file configuration |
| `TLCS900BaseInfo.h` | Shared enums and constants |

### Peephole Optimization Passes

| File | Pass | Description |
|------|------|-------------|
| `TLCS900BitTestOpt.cpp` | BIT test | Converts AND + CP + JPcc into BIT + JPcc for single-bit tests |
| `TLCS900BitManipOpt.cpp` | SET/RES/CHG | Converts OR/AND/XOR with power-of-2 immediates into bit manipulation |
| `TLCS900DJNZOpt.cpp` | DJNZ | Converts DEC + JP NZ loops into DJNZ (decrement-and-jump-if-not-zero) |
| `TLCS900IncDecOpt.cpp` | INC/DEC | Converts ADD/SUB with small immediates (1-8) into compact INC/DEC |
| `TLCS900BranchShortening.cpp` | Branch shortening | Replaces long JP/CALL with short JR/CALR when displacement fits |
| `TLCS900FixLargeDisp.cpp` | Large displacement | Rewrites d8 frame offsets exceeding -128..+127 into LDA + register-indirect |
| `TLCS900RedundantCmpElim.cpp` | Redundant CP | Removes compare instructions when flags are already set by a preceding ALU op |

### MC Layer (`MCTargetDesc/`)

| File | Purpose |
|------|---------|
| `TLCS900MCCodeEmitter.*` | Encodes machine instructions to bytes (handles prefix-based encoding) |
| `TLCS900AsmBackend.*` | Relaxation, fixup application, object file writing |
| `TLCS900ELFObjectWriter.cpp` | ELF relocation types and emission |
| `TLCS900FixupKinds.h` | Target-specific fixup type definitions |
| `TLCS900InstPrinter.*` | Instruction pretty-printing for assembly output |
| `TLCS900MCAsmInfo.*` | Assembly syntax configuration (comment char, directive behavior) |
| `TLCS900MCTargetDesc.*` | MC component registration and creation |

### Assembly Parser (`AsmParser/`)

`TLCS900AsmParser.cpp` — Parses TLCS-900 assembly syntax, resolves operand
types and addressing modes, feeds into the MC layer.

### Disassembler (`Disassembler/`)

`TLCS900Disassembler.cpp` — Decodes byte sequences back into MCInst. Handles
the prefix-based encoding (register prefixes `C8-EF`, `D7` previous bank,
source/destination memory prefixes).

### Target Registration (`TargetInfo/`)

Registers the TLCS-900 target with LLVM's target registry.

## Known Limitations

These are inherent to the current backend, not bugs:

- **No jump table lowering:** Switch statements compile to if-else chains. The
  architecture's indirect jump (`JP (mem)`) exists but ISel pattern is not implemented.
- **i8/i16 promotion to i32:** All sub-32-bit values are promoted and operated on
  as 32-bit, even though the hardware has native 8-bit and 16-bit operations.
  This produces correct but sometimes verbose code.
- **Boolean materialization is verbose:** `setcc` results in multi-instruction
  sequences (CP + conditional SET/RES) rather than a single flag-to-register move.
- **No scheduling model:** All instructions are treated as single-cycle. The
  `TLCS900Schedule.td` uses `NoSchedModel`.
- **No compact encodings in ISel:** The assembler supports compact forms
  (`ldb`, `ldw`, `pushw`) but the compiler's instruction selector does not emit them.
  Hand-written assembly can use these for smaller code.

## Building

```bash
# Configure (first time or after CMake changes)
cd /mnt/shared/llvm-project
bash build_tlcs900.sh

# Incremental build
ninja -Cbuild

# Build specific tools
ninja -Cbuild llc         # Compiler backend
ninja -Cbuild clang       # C/C++ compiler
ninja -Cbuild llvm-mc     # Assembler / disassembler
ninja -Cbuild lld          # Linker
```

## Testing

```bash
# Run all TLCS-900 CodeGen tests
build/bin/llvm-lit llvm/test/CodeGen/TLCS900/

# Run all TLCS-900 MC tests (assembly/disassembly)
build/bin/llvm-lit llvm/test/MC/TLCS900/

# Run a single test (verbose)
build/bin/llvm-lit -v llvm/test/CodeGen/TLCS900/calling-conv.ll

# Compile LLVM IR to TLCS-900 assembly
build/bin/llc -mtriple=tlcs900 -mcpu=tmp94c241 input.ll -o output.s

# Assemble to object file
build/bin/llvm-mc -triple=tlcs900 -filetype=obj input.s -o output.o

# Disassemble raw bytes
echo "0xd8 0xaa 0x12" | build/bin/llvm-mc --triple=tlcs900 --disassemble

# Show instruction encoding
build/bin/llvm-mc --triple=tlcs900 --show-encoding input.s
```

### Test Inventory

- `llvm/test/CodeGen/TLCS900/` — 47 IR-level tests covering arithmetic, memory,
  calling convention, branches, loops, shifts, selects, i64, memcpy/memmove, etc.
- `llvm/test/MC/TLCS900/` — 19 MC-level tests covering instruction encoding,
  addressing modes, assembly/disassembly round-trips, ELF output.
