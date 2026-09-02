; RUN: llvm-mc -triple tlcs900 -show-encoding < %s \
; RUN:     | FileCheck -check-prefixes=CHECK,CHECK-ENC %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s \
; RUN:     | llvm-objdump -d - | FileCheck --check-prefix=CHECK-INST %s
;
; Five LEADING opcode bytes that this backend could ASSEMBLE but could not
; DISASSEMBLE.  Every one of them was rejected as "invalid instruction
; encoding" no matter what followed it -- verified over 393,216 operand
; continuations each in the kn5000-roms-disasm tree by
; scripts/analysis/leading_byte_reserved_probe.py -- while MAME's unidasm, that
; project's standing decode authority, renders all five as real TLCS-900/H
; instructions.
;
;     0x01  normal
;     0x04  max
;     0x17  ldf 0xnn
;     0x1a  jp 0xnnnn      16-bit absolute jump
;     0x1c  call 0xnnnn    16-bit absolute call
;
; The assembler side already worked (the defs and the encoder have been there
; since JP16/CALL16/NORMAL/MAX/LDF were added); only the decoder's top-level
; byte dispatch was missing the five cases.  This test pins both directions so
; the gap cannot reopen silently -- and a decoder gap IS silent: a tool that
; cannot disassemble a region reports nothing there rather than reporting a
; problem.
;
; PROVENANCE OF THE BYTES BELOW.  Each encoding is a byte sequence read out of a
; committed ROM dump, at the file offset named beside it, with unidasm's
; rendering quoted.  scripts/analysis/blind_byte_rom_sites.py --check re-reads
; every one of these ten offsets from the dumps and fails if any byte differs,
; so the offsets are verifiable rather than asserted.
;
; ⚠ WHAT THE OFFSETS DO *NOT* CLAIM.  None of these sites is corroborated as
; EXECUTED CODE.  The bytes are certainly in the dumps at those offsets, and
; unidasm certainly renders them so, but every site examined sits in a byte
; ramp, a mask table, a pointer table, a string, or a DSP parameter block --
; regions a linear disassembly sweep walked through.  That is the honest status:
; these are real ROM BYTES, used here as encoding fixtures, not proof that any
; firmware executes `max` or `jp 0xnnnn`.  See blind_byte_rom_sites.py.

; ==========================================================================
; NORMAL / MAX -- single-byte MIN/MAX mode selection.
; ==========================================================================

; kn5000_v10_program.rom +0x00150c (rom 0xe0150c) -- unidasm: normal
; CHECK: normal
; CHECK-ENC: encoding: [0x01]
; CHECK-INST: normal
normal

; kn5000_v10_program.rom +0x001698 (rom 0xe01698) -- unidasm: max
; CHECK: max
; CHECK-ENC: encoding: [0x04]
; CHECK-INST: max
max

; ==========================================================================
; LDF #n -- select the register-bank frame.
;
; ⚠ The operand byte is NOT masked on the way back out.  Only the low bits are
; architecturally meaningful, but the encoder writes the immediate verbatim, so
; masking in the decoder would make a byte with a non-zero upper nibble
; reassemble to a DIFFERENT byte.  The 0xc7 case below is the regression guard
; for exactly that: it is a real ROM byte pair, and `ldf 199` must come back.
; ==========================================================================

; kn5000_v10_program.rom +0x001531 (rom 0xe01531) -- unidasm: ldf 0x01
; CHECK: ldf 1
; CHECK-ENC: encoding: [0x17,0x01]
; CHECK-INST: ldf 1
ldf 1

; wsa1_prom_c.ic28 +0x04e9ce (rom 0xfce9ce) -- unidasm: ldf 0xc7
; CHECK: ldf 199
; CHECK-ENC: encoding: [0x17,0xc7]
; CHECK-INST: ldf 199
ldf 199

; ==========================================================================
; JP nn / CALL nn -- 16-bit ABSOLUTE control flow, opcodes 0x1a and 0x1c.
;
; ⚠ These are DIFFERENT INSTRUCTIONS from the 0x1b / 0x1d addr24 forms, not
; narrower spellings of them.  The width is requested by the source mnemonic and
; is never inferred from whether the value fits: the KN5000 firmware contains
; 24-bit forms holding 8-bit addresses at hundreds of sites, and a
; narrowest-form-that-fits rule would silently rewrite all of them.  The two
; guards at the bottom of this file pin that.
; ==========================================================================

; kn5000_v10_program.rom +0x002059 (rom 0xe02059) -- unidasm: jp 0x00e0
; CHECK: jp16 224
; CHECK-ENC: encoding: [0x1a,0xe0,0x00]
; CHECK-INST: jp16 224
jp16 0x00e0

; kn5000_subprogram_v142.rom +0x000461 (rom 0x00f361) -- unidasm: jp 0x01a0
; CHECK: jp16 416
; CHECK-ENC: encoding: [0x1a,0xa0,0x01]
; CHECK-INST: jp16 416
jp16 0x01a0

; wsa1_prom_a.ic12 +0x006ea8 (rom 0xf86ea8) -- unidasm: jp 0xb012
; CHECK: jp16 45074
; CHECK-ENC: encoding: [0x1a,0x12,0xb0]
; CHECK-INST: jp16 45074
jp16 0xb012

; wsa1_prom_a.ic12 +0x03055c (rom 0xfb055c) -- unidasm: call 0x7f06
; CHECK: call16 32518
; CHECK-ENC: encoding: [0x1c,0x06,0x7f]
; CHECK-INST: call16 32518
call16 0x7f06

; wsa1_prom_c.ic28 +0x04d34a (rom 0xfcd34a) -- unidasm: call 0x0124
; CHECK: call16 292
; CHECK-ENC: encoding: [0x1c,0x24,0x01]
; CHECK-INST: call16 292
call16 0x0124

; kn5000_subprogram_v142.rom +0x0033be (rom 0x0122be) -- unidasm: call 0x382a
; CHECK: call16 14378
; CHECK-ENC: encoding: [0x1c,0x2a,0x38]
; CHECK-INST: call16 14378
call16 0x382a

; ==========================================================================
; GUARD: the 24-bit forms keep their own opcodes and their own width.
; A value that would fit in 16 bits must STILL encode as 0x1b / 0x1d with a
; 24-bit address field.  If either of these ever picks up the new short opcode,
; hundreds of existing sources change bytes.
; ==========================================================================

; CHECK: jp 8309
; CHECK-ENC: encoding: [0x1b,0x75,0x20,0x00]
; CHECK-INST: jp 8309
jp 0x2075

; CHECK: call 8309
; CHECK-ENC: encoding: [0x1d,0x75,0x20,0x00]
; CHECK-INST: call 8309
call 0x2075
