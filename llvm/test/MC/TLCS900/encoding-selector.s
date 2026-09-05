; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s | llvm-objdump -d - \
; RUN:     | FileCheck --check-prefix=INST %s
;
; The ENCODING SELECTORS `:i3` / `:opc` / `:io` (TLCS900EncodingForms.td), one
; row per member of every family in TLCS900EncodingFamilies.td, in BOTH
; directions: the bytes each spelling assembles to, and the text each byte
; string disassembles to.
;
; ⚠ THE UNTAGGED DEFAULT ROWS ARE THE LOAD-BEARING HALF OF THIS FILE.  The
; absence of a selector is itself an encoding decision, and for two families it
; is a decision no committed source exercises: `ldw (n:8), imm` occurs ZERO
; times in the kn5000-roms-disasm tree and `ld (n:8), imm` ten times.  Swapping
; which member of the LDWIO family is the default would pass every TableGen
; assert and the 13-image byte gate while silently changing
; `ldw (237:8), 0x8e00` from five bytes to four.  This file is the only
; instrument that sees it.
;
; The retired spellings (cps, lds8, lds, lds32, ldb, ldio, ldwio) no longer
; exist: their parse-only aliases were deleted once every source was converted,
; so only the selector forms and untagged defaults are testable here.

; ==========================================================================
; cp <GR8>, imm     default CP8ri (c9+r cf ii)   :i3 CP8_small (c9+r d8|n)
; ==========================================================================
; CHECK: cp a, 4                   ; encoding: [0xc9,0xcf,0x04]
; INST: cp a, 4
cp a, 4
; CHECK: cp a, 4:i3                ; encoding: [0xc9,0xdc]
; INST: cp a, 4:i3
cp a, 4:i3
; CHECK: cp a, 7:i3                ; encoding: [0xc9,0xdf]
; INST: cp a, 7:i3
cp a, 7:i3
; CHECK: cp a, 0:i3                ; encoding: [0xc9,0xd8]
; INST: cp a, 0:i3
cp a, 0:i3

; ==========================================================================
; cp <GR16>, imm    default CP16ri (d8+r cf iiii)   :i3 CP16_small (d8+r d8|n)
; ==========================================================================
; CHECK: cp hl, 4                  ; encoding: [0xdb,0xcf,0x04,0x00]
; INST: cp hl, 4
cp hl, 4
; CHECK: cp hl, 4:i3               ; encoding: [0xdb,0xdc]
; INST: cp hl, 4:i3
cp hl, 4:i3

; ==========================================================================
; cp <GPR>, imm     default CP32ri (e8+r cf iiiiiiii)   :i3 CP32_small (e8+r d8|n)
; v10/maincpu/file_io/single_load.s:361 is `cp xwa, 5`: six bytes, and must
; stay six bytes -- the short form has to be ASKED FOR.
; ==========================================================================
; CHECK: cp xwa, 5                 ; encoding: [0xe8,0xcf,0x05,0x00,0x00,0x00]
; INST: cp xwa, 5
cp xwa, 5
; CHECK: cp xwa, 5:i3              ; encoding: [0xe8,0xdd]
; INST: cp xwa, 5:i3
cp xwa, 5:i3

; ==========================================================================
; ld <GR8>, imm  -- THREE encodings, and the two short ones are the same length,
; so "the shortest that fits" is not even a function here.
;   default LD8ri_asm  (c8+r 03 ii)    3 bytes
;   :i3     LD8ri_small (c8+r a8|n)    2 bytes
;   :opc    LD8ri_short (20+r ii)      2 bytes
; ==========================================================================
; CHECK: ld d, 4                   ; encoding: [0xcc,0x03,0x04]
; INST: ld d, 4
ld d, 4
; CHECK: ld d, 4:i3                ; encoding: [0xcc,0xac]
; INST: ld d, 4:i3
ld d, 4:i3
; CHECK: ld d, 4:opc               ; encoding: [0x24,0x04]
; INST: ld d, 4:opc
ld d, 4:opc
; `:opc` keeps the whole 8-bit field: 255 is legal there and not for `:i3`.
; CHECK: ld d, 255:opc             ; encoding: [0x24,0xff]
; INST: ld d, 255:opc
ld d, 255:opc

; ==========================================================================
; ld <GR16>, imm    default LD16ri_asm (d8+r 03 iiii)   :i3 LD16ri_small (d8+r a8|n)
; ==========================================================================
; CHECK: ld hl, 0                  ; encoding: [0xdb,0x03,0x00,0x00]
; INST: ld hl, 0
ld hl, 0
; CHECK: ld hl, 0:i3               ; encoding: [0xdb,0xa8]
; INST: ld hl, 0:i3
ld hl, 0:i3

; ==========================================================================
; ld <GPR>, imm     default LD32ri (40+r iiiiiiii)   :i3 LD32ri_small (e8+r a8|n)
; Note the default here IS the dedicated-primary-opcode shape that is `:opc`
; at 8 bits: the vocabulary follows whichever form historically owned the
; plain spelling, and cannot be made uniform across sizes.
; ==========================================================================
; CHECK: ld xiz, 0                 ; encoding: [0x46,0x00,0x00,0x00,0x00]
; INST: ld xiz, 0
ld xiz, 0
; CHECK: ld xiz, 0:i3              ; encoding: [0xee,0xa8]
; INST: ld xiz, 0:i3
ld xiz, 0:i3

; ==========================================================================
; ld (n:8), imm     default LD8mi_dst (f0 nn 00 ii)   :io LDIO (08 nn ii)
; The untagged default is exercised by TEN committed sites; pin it here.
; ==========================================================================
; CHECK: ld (7:8), 255             ; encoding: [0xf0,0x07,0x00,0xff]
; INST: ld (7:8), 255
ld (7:8), 255
; CHECK: ld (7:8), 255:io          ; encoding: [0x08,0x07,0xff]
; INST: ld (7:8), 255:io
ld (7:8), 255:io
; CHECK: ld (255:8), 0:io          ; encoding: [0x08,0xff,0x00]
; INST: ld (255:8), 0:io
ld (0xff:8), 0:io

; ==========================================================================
; ldw (n:8), imm    default LD16mi_dst_02 (f0 nn 02 iiii)   :io LDWIO (0a nn iiii)
; The untagged default is exercised by NO committed site; this is the pin.
; ==========================================================================
; CHECK: ldw (237:8), 36352        ; encoding: [0xf0,0xed,0x02,0x00,0x8e]
; INST: ldw (237:8), 36352
ldw (237:8), 36352
; CHECK: ldw (237:8), 36352:io     ; encoding: [0x0a,0xed,0x00,0x8e]
; INST: ldw (237:8), 36352:io
ldw (237:8), 0x8e00:io

; ==========================================================================
; A numeric local label shares the `<int>:` shape with nothing here: the
; selector follows an OPERAND, a label starts a statement.
; ==========================================================================
; CHECK: cp a, 4:i3                ; encoding: [0xc9,0xdc]
; INST: cp a, 4:i3
1: cp a, 4:i3
; CHECK: jr
; INST: jr
jr 1b
