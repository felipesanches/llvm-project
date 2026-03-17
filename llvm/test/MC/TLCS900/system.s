; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test system and miscellaneous instructions: NOP, HALT, EI, DI, SWI, RETI,
; NORMAL, MAX, flag operations (CCF, SCF, RCF, ZCF), MUL, MULS, DIV, DIVS,
; INC, DEC, NEG, CPL, EXTS, EXTZ, DJNZ.

; ==========================================================================
; Single-byte system instructions
; ==========================================================================

; CHECK: nop                ; encoding: [0x00]
nop

; CHECK: normal             ; encoding: [0x01]
normal

; CHECK: max                ; encoding: [0x04]
max

; CHECK: halt               ; encoding: [0x05]
halt

; CHECK: reti               ; encoding: [0x07]
reti

; CHECK: ret                ; encoding: [0x0e]
ret

; ==========================================================================
; EI / DI (0x06, level)
; ==========================================================================

; DI is an alias for EI 0
; CHECK: di                 ; encoding: [0x06,0x00]
di

; CHECK: ei 1               ; encoding: [0x06,0x01]
ei 1
; CHECK: ei 3               ; encoding: [0x06,0x03]
ei 3
; CHECK: ei 7               ; encoding: [0x06,0x07]
ei 7

; ==========================================================================
; SWI (0xF8 + num)
; ==========================================================================

; CHECK: swi 0              ; encoding: [0xf8]
swi 0
; CHECK: swi 1              ; encoding: [0xf9]
swi 1
; CHECK: swi 3              ; encoding: [0xfb]
swi 3
; CHECK: swi 7              ; encoding: [0xff]
swi 7

; ==========================================================================
; Flag manipulation (single-byte)
; ==========================================================================

; CHECK: rcf                ; encoding: [0x10]
rcf
; CHECK: scf                ; encoding: [0x11]
scf
; CHECK: ccf                ; encoding: [0x12]
ccf
; CHECK: zcf                ; encoding: [0x13]
zcf

; ==========================================================================
; NEG / CPL (8-bit and 16-bit only; 32-bit is isCodeGenOnly)
; ==========================================================================

; 8-bit NEG: C8+r, 0x07
; CHECK: neg a              ; encoding: [0xc9,0x07]
neg a
; CHECK: neg b              ; encoding: [0xca,0x07]
neg b

; 8-bit CPL: C8+r, 0x06
; CHECK: cpl a              ; encoding: [0xc9,0x06]
cpl a
; CHECK: cpl b              ; encoding: [0xca,0x06]
cpl b

; 16-bit NEG: D8+r, 0x07
; CHECK: neg wa             ; encoding: [0xd8,0x07]
neg wa
; CHECK: neg bc             ; encoding: [0xd9,0x07]
neg bc

; 16-bit CPL: D8+r, 0x06
; CHECK: cpl bc             ; encoding: [0xd9,0x06]
cpl bc
; CHECK: cpl de             ; encoding: [0xda,0x06]
cpl de

; ==========================================================================
; INC / DEC with I3 encoding (8/16/32-bit)
; I3: 1→0x61, 2→0x62, 3→0x63, 4→0x64, 5→0x65, 6→0x66, 7→0x67, 8→0x60
; ==========================================================================

; 8-bit INC: C8+r, 0x60+(n&7)
; CHECK: inc 1, a           ; encoding: [0xc9,0x61]
inc 1, a
; CHECK: inc 1, b           ; encoding: [0xca,0x61]
inc 1, b

; 8-bit DEC: C8+r, 0x68+(n&7)
; CHECK: dec 1, b           ; encoding: [0xca,0x69]
dec 1, b

; 16-bit INC: D8+r, 0x60+(n&7)
; CHECK: inc 1, wa          ; encoding: [0xd8,0x61]
inc 1, wa
; CHECK: inc 4, bc          ; encoding: [0xd9,0x64]
inc 4, bc

; 16-bit DEC: D8+r, 0x68+(n&7)
; CHECK: dec 1, wa          ; encoding: [0xd8,0x69]
dec 1, wa
; CHECK: dec 2, de          ; encoding: [0xda,0x6a]
dec 2, de

; 32-bit INC: E8+r, 0x60+(n&7)
; CHECK: inc 1, xwa         ; encoding: [0xe8,0x61]
inc 1, xwa
; CHECK: inc 2, xbc         ; encoding: [0xe9,0x62]
inc 2, xbc
; CHECK: inc 4, xde         ; encoding: [0xea,0x64]
inc 4, xde
; CHECK: inc 8, xhl         ; encoding: [0xeb,0x60]
inc 8, xhl

; 32-bit DEC: E8+r, 0x68+(n&7)
; CHECK: dec 1, xwa         ; encoding: [0xe8,0x69]
dec 1, xwa
; CHECK: dec 3, xbc         ; encoding: [0xe9,0x6b]
dec 3, xbc
; CHECK: dec 8, xde         ; encoding: [0xea,0x68]
dec 8, xde

; ==========================================================================
; EXTS / EXTZ (sign/zero extend)
; ==========================================================================

; 16-bit EXTS: D8+r, 0x13
; CHECK: exts wa            ; encoding: [0xd8,0x13]
exts wa

; 16-bit EXTZ: D8+r, 0x12
; CHECK: extz de            ; encoding: [0xda,0x12]
extz de
; CHECK: extz bc            ; encoding: [0xd9,0x12]
extz bc

; 32-bit EXTS: E8+r, 0x13
; CHECK: exts xwa           ; encoding: [0xe8,0x13]
exts xwa
; CHECK: exts xde           ; encoding: [0xea,0x13]
exts xde

; 32-bit EXTZ: E8+r, 0x12
; CHECK: extz xwa           ; encoding: [0xe8,0x12]
extz xwa
; CHECK: extz xbc           ; encoding: [0xe9,0x12]
extz xbc

; ==========================================================================
; MUL / MULS (16x16 -> 32, uses D8+src prefix)
; ==========================================================================

; MUL rd, rs: D8+src, 0x40+dst_idx
; CHECK: mul xwa, xbc       ; encoding: [0xd9,0x40]
mul xwa, xbc
; CHECK: mul xde, xhl       ; encoding: [0xdb,0x42]
mul xde, xhl
; CHECK: mul xhl, xwa       ; encoding: [0xd8,0x43]
mul xhl, xwa

; MULS rd, rs: D8+src, 0x48+dst_idx
; CHECK: muls xwa, xbc      ; encoding: [0xd9,0x48]
muls xwa, xbc
; CHECK: muls xde, xwa      ; encoding: [0xd8,0x4a]
muls xde, xwa

; ==========================================================================
; DIV / DIVS (32/16 -> 16, uses D8+src prefix)
; ==========================================================================

; DIV rd, rs: D8+src, 0x50+dst_idx
; CHECK: div xwa, xbc       ; encoding: [0xd9,0x50]
div xwa, xbc
; CHECK: div xde, xhl       ; encoding: [0xdb,0x52]
div xde, xhl

; DIVS rd, rs: D8+src, 0x58+dst_idx
; CHECK: divs xwa, xbc      ; encoding: [0xd9,0x58]
divs xwa, xbc
; CHECK: divs xhl, xwa      ; encoding: [0xd8,0x5b]
divs xhl, xwa

; ==========================================================================
; DJNZ (decrement and jump if not zero)
; ==========================================================================

; DJNZ rd, disp8: D8+r, 0x1C, disp8 (PC-relative)
; CHECK: djnz xwa, 0        ; encoding: [0xd8,0x1c,A]
; CHECK:                     ;   fixup A - offset: 2, value: 0-1, kind: fixup_tlcs900_rel8
djnz xwa, 0
