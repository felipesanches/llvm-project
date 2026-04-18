# LLVM TLCS900 Backend Project Memory

## Strict Policies
- **(A)** Never build the code — user builds manually
- **(B)** Make frequent commits, keep working directory clean
- **(C)** New policies go in both memory and CLAUDE.md (progressive disclosure)

## Project Context
- Target: TMP94C241 (TLCS-900/H2) for Technics KN5000 keyboard
- Branch: `tlcs900_backend` — rebased onto modern `main`
- Reference docs: `/home/fsanches/compartilhado/kn5000-docs/`, `/home/fsanches/compartilhado/kn5000-roms-disasm/tmp94c241.inc`, `/home/fsanches/compartilhado/custom-kn5000-roms/anotherworld/src/includes/local_macros.inc`

## Key API Changes (old branch → modern main)
See [api-changes.md](api-changes.md) for full details.

## TLCS900 Register File
- 8-bit: W, A, B, C, D, E, H, L
- 16-bit: WA, BC, DE, HL, IX, IY, IZ, SP
- 32-bit: XWA, XBC, XDE, XHL, XIX, XIY, XIZ, XSP
- 24-bit PC, Status Register (SR)

## MCCodeEmitter Fixup Offsets (Critical Pattern)
- Fixup offsets in `encodeInstruction` MUST be instruction-relative, not fragment-relative
- `MCELFStreamer::emitInstToData` adjusts offsets by adding CodeOffset (instruction start pos)
- Capture `uint64_t StartByte = CB.size()` at start of encoding, then use `CB.size() - StartByte`
- Same pattern used by X86 backend: see `X86MCCodeEmitter::emitImmediate` with `StartByte`
- Bug symptom: "Invalid fixup offset!" crash in `applyFixup` when multiple functions in same fragment

## Instruction Encoding
See [encoding-reference.md](encoding-reference.md) for detailed opcode tables.
- Variable-length 1-7 bytes, prefix-based
- Register prefixes: 0xC8-CF (8-bit), 0xD8-DF (16-bit), 0xE8-EF (32-bit)
- Reference data from MAME (`/tmp/dasm900.cpp`) and Ghidra (`/tmp/ghidra_tlcs900h.sinc`)
