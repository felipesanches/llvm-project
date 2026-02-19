; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Comprehensive encoding verification for every TLCS-900 instruction form.
; Encodings verified against MAME's unidasm -arch tlcs900.

; ==========================================================================
; Single-byte instructions (no prefix, no operands)
; ==========================================================================

; CHECK: nop              ; encoding: [0x00]
nop

; CHECK: halt             ; encoding: [0x05]
halt

; CHECK: reti             ; encoding: [0x07]
reti

; CHECK: ret              ; encoding: [0x0e]
ret

; ==========================================================================
; EI / DI (0x06 + level byte)
; ==========================================================================

; DI is an alias for EI 0
; CHECK: di               ; encoding: [0x06,0x00]
di

; CHECK: ei 3             ; encoding: [0x06,0x03]
ei 3

; CHECK: ei 7             ; encoding: [0x06,0x07]
ei 7

; ==========================================================================
; SWI (0xF8 + num, embedded in opcode)
; ==========================================================================

; CHECK: swi 0            ; encoding: [0xf8]
swi 0

; CHECK: swi 3            ; encoding: [0xfb]
swi 3

; CHECK: swi 7            ; encoding: [0xff]
swi 7

; ==========================================================================
; RETD (0x0F + imm16 displacement)
; ==========================================================================

; CHECK: retd 0           ; encoding: [0x0f,0x00,0x00]
retd 0

; CHECK: retd 4           ; encoding: [0x0f,0x04,0x00]
retd 4

; CHECK: retd 256         ; encoding: [0x0f,0x00,0x01]
retd 256

; ==========================================================================
; 32-bit PUSH (0x38 + reg) / POP (0x58 + reg)
; ==========================================================================

; CHECK: push xwa         ; encoding: [0x38]
push xwa

; CHECK: push xbc         ; encoding: [0x39]
push xbc

; CHECK: push xde         ; encoding: [0x3a]
push xde

; CHECK: push xhl         ; encoding: [0x3b]
push xhl

; CHECK: push xsp         ; encoding: [0x3f]
push xsp

; CHECK: pop xwa          ; encoding: [0x58]
pop xwa

; CHECK: pop xbc          ; encoding: [0x59]
pop xbc

; CHECK: pop xde          ; encoding: [0x5a]
pop xde

; CHECK: pop xhl          ; encoding: [0x5b]
pop xhl

; ==========================================================================
; LD r32, #imm32 (0x40 + reg, imm32)
; ==========================================================================

; CHECK: ld xwa, 0        ; encoding: [0x40,0x00,0x00,0x00,0x00]
ld xwa, 0

; CHECK: ld xbc, 1        ; encoding: [0x41,0x01,0x00,0x00,0x00]
ld xbc, 1

; CHECK: ld xde, 255      ; encoding: [0x42,0xff,0x00,0x00,0x00]
ld xde, 255

; CHECK: ld xhl, 305419896 ; encoding: [0x43,0x78,0x56,0x34,0x12]
ld xhl, 0x12345678

; ==========================================================================
; 32-bit prefix (E8-EF) : Register-Register ALU
; ==========================================================================

; ADD rd, rs: E8+src, 0x80+dst
; CHECK: add xwa, xbc     ; encoding: [0xe9,0x80]
add xwa, xbc

; CHECK: add xde, xhl     ; encoding: [0xeb,0x82]
add xde, xhl

; CHECK: add xhl, xwa     ; encoding: [0xe8,0x83]
add xhl, xwa

; SUB rd, rs: E8+src, 0xA0+dst
; CHECK: sub xwa, xbc     ; encoding: [0xe9,0xa0]
sub xwa, xbc

; CHECK: sub xde, xwa     ; encoding: [0xe8,0xa2]
sub xde, xwa

; ADC rd, rs: E8+src, 0x90+dst
; CHECK: adc xwa, xbc     ; encoding: [0xe9,0x90]
adc xwa, xbc

; CHECK: adc xhl, xde     ; encoding: [0xea,0x93]
adc xhl, xde

; SBC rd, rs: E8+src, 0xB0+dst
; CHECK: sbc xde, xhl     ; encoding: [0xeb,0xb2]
sbc xde, xhl

; CHECK: sbc xwa, xde     ; encoding: [0xea,0xb0]
sbc xwa, xde

; AND rd, rs: E8+src, 0xC0+dst
; CHECK: and xwa, xbc     ; encoding: [0xe9,0xc0]
and xwa, xbc

; OR rd, rs: E8+src, 0xE0+dst
; CHECK: or xwa, xbc      ; encoding: [0xe9,0xe0]
or xwa, xbc

; CHECK: or xhl, xde      ; encoding: [0xea,0xe3]
or xhl, xde

; XOR rd, rs: E8+src, 0xD0+dst
; CHECK: xor xwa, xbc     ; encoding: [0xe9,0xd0]
xor xwa, xbc

; CHECK: xor xde, xhl     ; encoding: [0xeb,0xd2]
xor xde, xhl

; CP rd, rs: E8+src, 0xF0+dst
; CHECK: cp xwa, xbc      ; encoding: [0xe9,0xf0]
cp xwa, xbc

; CHECK: cp xhl, xde      ; encoding: [0xea,0xf3]
cp xhl, xde

; LD rd, rs: E8+src, 0x88+dst
; CHECK: ld xde, xbc      ; encoding: [0xe9,0x8a]
ld xde, xbc

; CHECK: ld xhl, xwa      ; encoding: [0xe8,0x8b]
ld xhl, xwa

; ==========================================================================
; 32-bit prefix: Register-Immediate ALU
; ==========================================================================

; ADD rd, #imm: E8+dst, 0xC8, imm32
; CHECK: add xwa, 42      ; encoding: [0xe8,0xc8,0x2a,0x00,0x00,0x00]
add xwa, 42

; CHECK: add xde, 100     ; encoding: [0xea,0xc8,0x64,0x00,0x00,0x00]
add xde, 100

; SUB rd, #imm: E8+dst, 0xCA, imm32
; CHECK: sub xwa, 1       ; encoding: [0xe8,0xca,0x01,0x00,0x00,0x00]
sub xwa, 1

; ADC rd, #imm: E8+dst, 0xC9, imm32
; CHECK: adc xwa, 100     ; encoding: [0xe8,0xc9,0x64,0x00,0x00,0x00]
adc xwa, 100

; SBC rd, #imm: E8+dst, 0xCB, imm32
; CHECK: sbc xde, 50      ; encoding: [0xea,0xcb,0x32,0x00,0x00,0x00]
sbc xde, 50

; AND rd, #imm: E8+dst, 0xCC, imm32
; CHECK: and xwa, 255     ; encoding: [0xe8,0xcc,0xff,0x00,0x00,0x00]
and xwa, 255

; OR rd, #imm: E8+dst, 0xCE, imm32
; CHECK: or xwa, 15       ; encoding: [0xe8,0xce,0x0f,0x00,0x00,0x00]
or xwa, 15

; XOR rd, #imm: E8+dst, 0xCD, imm32
; CHECK: xor xwa, 65535   ; encoding: [0xe8,0xcd,0xff,0xff,0x00,0x00]
xor xwa, 65535

; CP rd, #imm: E8+dst, 0xCF, imm32
; CHECK: cp xwa, 0        ; encoding: [0xe8,0xcf,0x00,0x00,0x00,0x00]
cp xwa, 0

; CHECK: cp xde, 1000     ; encoding: [0xea,0xcf,0xe8,0x03,0x00,0x00]
cp xde, 1000

; ==========================================================================
; 32-bit prefix: Unary instructions
; ==========================================================================

; INC n, rd: E8+r, 0x60+(n&7) — I3 field: 1→0x61, 2→0x62, ..., 7→0x67, 8→0x60
; CHECK: inc 1, xwa       ; encoding: [0xe8,0x61]
inc 1, xwa

; CHECK: inc 2, xbc       ; encoding: [0xe9,0x62]
inc 2, xbc

; CHECK: inc 4, xde       ; encoding: [0xea,0x64]
inc 4, xde

; CHECK: inc 8, xhl       ; encoding: [0xeb,0x60]
inc 8, xhl

; DEC n, rd: E8+r, 0x68+(n&7) — same I3 encoding as INC
; CHECK: dec 1, xwa       ; encoding: [0xe8,0x69]
dec 1, xwa

; CHECK: dec 3, xbc       ; encoding: [0xe9,0x6b]
dec 3, xbc

; CHECK: dec 8, xde       ; encoding: [0xea,0x68]
dec 8, xde

; EXTS rd: E8+r, 0x13
; CHECK: exts xwa         ; encoding: [0xe8,0x13]
exts xwa

; CHECK: exts xde         ; encoding: [0xea,0x13]
exts xde

; EXTZ rd: E8+r, 0x12
; CHECK: extz xwa         ; encoding: [0xe8,0x12]
extz xwa

; CHECK: extz xbc         ; encoding: [0xe9,0x12]
extz xbc

; ==========================================================================
; 32-bit prefix: Shift instructions
; ==========================================================================

; SLA rd, #n: E8+r, 0xEC, n
; CHECK: sla xwa, 1       ; encoding: [0xe8,0xec,0x01]
sla xwa, 1

; CHECK: sla xde, 4       ; encoding: [0xea,0xec,0x04]
sla xde, 4

; SRA rd, #n: E8+r, 0xED, n
; CHECK: sra xwa, 1       ; encoding: [0xe8,0xed,0x01]
sra xwa, 1

; CHECK: sra xbc, 4       ; encoding: [0xe9,0xed,0x04]
sra xbc, 4

; SRL rd, #n: E8+r, 0xEF, n
; CHECK: srl xwa, 8       ; encoding: [0xe8,0xef,0x08]
srl xwa, 8

; CHECK: srl xde, 1       ; encoding: [0xea,0xef,0x01]
srl xde, 1

; ==========================================================================
; 32-bit prefix: Rotate instructions (count=1 appended)
; ==========================================================================

; RLC rd: E8+r, 0xE8, 0x01
; CHECK: rlc xwa          ; encoding: [0xe8,0xe8,0x01]
rlc xwa

; RRC rd: E8+r, 0xE9, 0x01
; CHECK: rrc xbc          ; encoding: [0xe9,0xe9,0x01]
rrc xbc

; RL rd: E8+r, 0xEA, 0x01
; CHECK: rl xde           ; encoding: [0xea,0xea,0x01]
rl xde

; RR rd: E8+r, 0xEB, 0x01
; CHECK: rr xhl           ; encoding: [0xeb,0xeb,0x01]
rr xhl

; ==========================================================================
; Memory load: LD rd, (base) and LD rd, (base+d8)
; ==========================================================================

; LD rd, (Xrr): A0+base, 0x20+dst
; CHECK: ld xwa, (xsp)    ; encoding: [0xa7,0x20]
ld xwa, (xsp)

; CHECK: ld xde, (xhl)    ; encoding: [0xa3,0x22]
ld xde, (xhl)

; CHECK: ld xbc, (xix)    ; encoding: [0xa4,0x21]
ld xbc, (xix)

; LD rd, (Xrr+d8): A8+base, d8, 0x20+dst
; CHECK: ld xde, (xsp+4)  ; encoding: [0xaf,0x04,0x22]
ld xde, (xsp+4)

; CHECK: ld xbc, (xhl+100) ; encoding: [0xab,0x64,0x21]
ld xbc, (xhl+100)

; CHECK: ld xwa, (xix+127) ; encoding: [0xac,0x7f,0x20]
ld xwa, (xix+127)

; Negative displacement
; CHECK: ld xwa, (xsp-4)  ; encoding: [0xaf,0xfc,0x20]
ld xwa, (xsp-4)

; ==========================================================================
; Memory store: LD (base), rs and LD (base+d8), rs
; ==========================================================================

; LD (Xrr), rs: B0+base, 0x60+src
; CHECK: ld (xsp), xwa    ; encoding: [0xb7,0x60]
ld (xsp), xwa

; CHECK: ld (xhl), xde    ; encoding: [0xb3,0x62]
ld (xhl), xde

; LD (Xrr+d8), rs: B8+base, d8, 0x60+src
; CHECK: ld (xsp+8), xwa  ; encoding: [0xbf,0x08,0x60]
ld (xsp+8), xwa

; CHECK: ld (xiy+16), xde ; encoding: [0xbd,0x10,0x62]
ld (xiy+16), xde

; Negative displacement
; CHECK: ld (xsp-8), xde  ; encoding: [0xbf,0xf8,0x62]
ld (xsp-8), xde

; ==========================================================================
; Memory ALU: op (base), rs and op (base+d8), rs
; ==========================================================================

; ADD (Xrr), rs: A0+base, 0x88+src
; CHECK: add (xhl), xwa   ; encoding: [0xa3,0x88]
add (xhl), xwa

; SUB (Xrr+d8), rs: A8+base, d8, 0xA8+src
; CHECK: sub (xsp+4), xde ; encoding: [0xaf,0x04,0xaa]
sub (xsp+4), xde

; AND (Xrr), rs: A0+base, 0xC8+src
; CHECK: and (xix), xbc   ; encoding: [0xa4,0xc9]
and (xix), xbc

; OR (Xrr+d8), rs: A8+base, d8, 0xE8+src
; CHECK: or (xiy+8), xwa  ; encoding: [0xad,0x08,0xe8]
or (xiy+8), xwa

; XOR (Xrr+d8), rs: A8+base, d8, 0xD8+src
; CHECK: xor (xhl+2), xde ; encoding: [0xab,0x02,0xda]
xor (xhl+2), xde

; CP (Xrr), rs: A0+base, 0xF8+src
; CHECK: cp (xhl), xwa    ; encoding: [0xa3,0xf8]
cp (xhl), xwa

; ==========================================================================
; Load effective address: LDA rd, (base+d8)
; ==========================================================================

; LDA rd, (Xrr): B0+base, 0x30+dst (uses store-side memory prefix)
; CHECK: lda xde, (xhl)   ; encoding: [0xb3,0x32]
lda xde, (xhl)

; LDA rd, (Xrr+d8): B8+base, d8, 0x30+dst
; CHECK: lda xwa, (xsp+64) ; encoding: [0xbf,0x40,0x30]
lda xwa, (xsp+64)

; CHECK: lda xde, (xsp+16) ; encoding: [0xbf,0x10,0x32]
lda xde, (xsp+16)

; ==========================================================================
; Direct memory addressing (F2 prefix for store, E2 prefix for load)
; ==========================================================================

; LD (nn), rs: F2, addr24, 0x60+src (address emitted as fixup)
; CHECK: ld (0), xwa      ; encoding: [0xf2,A,A,A,0x60]
ld (0), xwa

; CHECK: ld (4660), xwa   ; encoding: [0xf2,A,A,A,0x60]
ld (0x1234), xwa

; LD rd, (nn): E2, addr24, 0x20+dst (address emitted as fixup)
; CHECK: ld xwa, (22136)  ; encoding: [0xe2,A,A,A,0x20]
ld xwa, (0x5678)

; ==========================================================================
; Block transfer instructions (0x80 prefix + sub-opcode)
; ==========================================================================

; CHECK: ldi              ; encoding: [0x80,0x10]
ldi

; CHECK: ldir             ; encoding: [0x80,0x11]
ldir

; CHECK: ldd              ; encoding: [0x80,0x12]
ldd

; CHECK: lddr             ; encoding: [0x80,0x13]
lddr

; CHECK: cpi              ; encoding: [0x80,0x14]
cpi

; CHECK: cpir             ; encoding: [0x80,0x15]
cpir

; CHECK: cpd              ; encoding: [0x80,0x16]
cpd

; CHECK: cpdr             ; encoding: [0x80,0x17]
cpdr

; ==========================================================================
; Branch instructions
; ==========================================================================

; JP nnn: 0x1B, addr24
; CHECK: jp 0             ; encoding: [0x1b,0x00,0x00,0x00]
jp 0

; CHECK: jp 1193046       ; encoding: [0x1b,0x56,0x34,0x12]
jp 0x123456

; ==========================================================================
; Call instructions
; ==========================================================================

; CALL nnn: 0x1D, addr24
; CHECK: call 0           ; encoding: [0x1d,0x00,0x00,0x00]
call 0

; CHECK: call 11259375    ; encoding: [0x1d,0xef,0xcd,0xab]
call 0xABCDEF

; CALR d16: 0x1E, disp16
; CHECK: calr 0           ; encoding: [0x1e,0x00,0x00]
calr 0

; ==========================================================================
; Indirect jump / call (via B0+reg memory prefix)
; ==========================================================================

; JP (Xrr): B0+reg, 0xD8
; CHECK: jp (xwa)         ; encoding: [0xb0,0xd8]
jp (xwa)

; CHECK: jp (xhl)         ; encoding: [0xb3,0xd8]
jp (xhl)

; CALL (Xrr): B0+reg, 0xE8
; CHECK: call (xwa)       ; encoding: [0xb0,0xe8]
call (xwa)

; CHECK: call (xhl)       ; encoding: [0xb3,0xe8]
call (xhl)

; ==========================================================================
; MUL / MULS / DIV / DIVS (16-bit prefix)
; ==========================================================================

; MUL rd, rs: D8+src, 0x40+dst_idx
; CHECK: mul xwa, xbc     ; encoding: [0xd9,0x40]
mul xwa, xbc

; CHECK: mul xde, xhl     ; encoding: [0xdb,0x42]
mul xde, xhl

; CHECK: mul xhl, xwa     ; encoding: [0xd8,0x43]
mul xhl, xwa

; MULS rd, rs: D8+src, 0x48+dst_idx
; CHECK: muls xwa, xbc    ; encoding: [0xd9,0x48]
muls xwa, xbc

; CHECK: muls xde, xwa    ; encoding: [0xd8,0x4a]
muls xde, xwa

; DIV rd, rs: D8+src, 0x50+dst_idx
; CHECK: div xwa, xbc     ; encoding: [0xd9,0x50]
div xwa, xbc

; DIVS rd, rs: D8+src, 0x58+dst_idx
; CHECK: divs xwa, xbc    ; encoding: [0xd9,0x58]
divs xwa, xbc

; ==========================================================================
; 16-bit PUSH / POP (D8+r prefix, 0x04/0x05)
; ==========================================================================

; PUSH rs16: D8+r, 0x04
; CHECK: push wa           ; encoding: [0xd8,0x04]
push wa

; CHECK: push bc           ; encoding: [0xd9,0x04]
push bc

; CHECK: push de           ; encoding: [0xda,0x04]
push de

; CHECK: push hl           ; encoding: [0xdb,0x04]
push hl

; POP rd16: D8+r, 0x05
; CHECK: pop wa            ; encoding: [0xd8,0x05]
pop wa

; CHECK: pop bc            ; encoding: [0xd9,0x05]
pop bc

; CHECK: pop de            ; encoding: [0xda,0x05]
pop de

; CHECK: pop hl            ; encoding: [0xdb,0x05]
pop hl

; ==========================================================================
; 16-bit register instructions (D8-DF prefix)
; ==========================================================================

; LD rd16, rs16: D8+src, 0x88+dst
; CHECK: ld wa, bc         ; encoding: [0xd9,0x88]
ld wa, bc

; CHECK: ld de, hl         ; encoding: [0xdb,0x8a]
ld de, hl

; LD rd16, #imm16: D8+rd, 0x03, imm16
; CHECK: ld wa, 0          ; encoding: [0xd8,0x03,0x00,0x00]
ld wa, 0

; CHECK: ld de, 1234       ; encoding: [0xda,0x03,0xd2,0x04]
ld de, 1234

; ADD rd16, rs16: D8+src, 0x80+dst
; CHECK: add wa, bc        ; encoding: [0xd9,0x80]
add wa, bc

; ADD rd16, #imm16: D8+dst, 0xC8, imm16
; CHECK: add wa, 42        ; encoding: [0xd8,0xc8,0x2a,0x00]
add wa, 42

; SUB rd16, rs16: D8+src, 0xA0+dst
; CHECK: sub de, hl        ; encoding: [0xdb,0xa2]
sub de, hl

; SUB rd16, #imm16: D8+dst, 0xCA, imm16
; CHECK: sub bc, 100       ; encoding: [0xd9,0xca,0x64,0x00]
sub bc, 100

; ADC rd16, rs16: D8+src, 0x90+dst
; CHECK: adc wa, bc        ; encoding: [0xd9,0x90]
adc wa, bc

; SBC rd16, rs16: D8+src, 0xB0+dst
; CHECK: sbc de, hl        ; encoding: [0xdb,0xb2]
sbc de, hl

; AND rd16, rs16: D8+src, 0xC0+dst
; CHECK: and wa, bc        ; encoding: [0xd9,0xc0]
and wa, bc

; AND rd16, #imm16: D8+dst, 0xCC, imm16
; CHECK: and wa, 255       ; encoding: [0xd8,0xcc,0xff,0x00]
and wa, 255

; OR rd16, rs16: D8+src, 0xE0+dst
; CHECK: or wa, de         ; encoding: [0xda,0xe0]
or wa, de

; OR rd16, #imm16: D8+dst, 0xCE, imm16
; CHECK: or bc, 15         ; encoding: [0xd9,0xce,0x0f,0x00]
or bc, 15

; XOR rd16, rs16: D8+src, 0xD0+dst
; CHECK: xor hl, bc        ; encoding: [0xd9,0xd3]
xor hl, bc

; XOR rd16, #imm16: D8+dst, 0xCD, imm16
; CHECK: xor de, 4096      ; encoding: [0xda,0xcd,0x00,0x10]
xor de, 4096

; CP rd16, rs16: D8+src, 0xF0+dst
; CHECK: cp wa, bc         ; encoding: [0xd9,0xf0]
cp wa, bc

; CP rd16, #imm16: D8+dst, 0xCF, imm16
; CHECK: cp de, 100        ; encoding: [0xda,0xcf,0x64,0x00]
cp de, 100

; NEG rd16: D8+r, 0x07
; CHECK: neg wa            ; encoding: [0xd8,0x07]
neg wa

; CHECK: neg bc            ; encoding: [0xd9,0x07]
neg bc

; CPL rd16: D8+r, 0x06
; CHECK: cpl bc            ; encoding: [0xd9,0x06]
cpl bc

; CHECK: cpl de            ; encoding: [0xda,0x06]
cpl de

; INC n, rd16: D8+r, 0x60+(n&7)
; CHECK: inc 1, wa         ; encoding: [0xd8,0x61]
inc 1, wa

; CHECK: inc 4, bc         ; encoding: [0xd9,0x64]
inc 4, bc

; DEC n, rd16: D8+r, 0x68+(n&7)
; CHECK: dec 1, wa         ; encoding: [0xd8,0x69]
dec 1, wa

; CHECK: dec 2, de         ; encoding: [0xda,0x6a]
dec 2, de

; EXTS rd16: D8+r, 0x13
; CHECK: exts wa           ; encoding: [0xd8,0x13]
exts wa

; EXTZ rd16: D8+r, 0x12
; CHECK: extz de           ; encoding: [0xda,0x12]
extz de

; SLA rd16, #n: D8+r, 0xEC, n
; CHECK: sla wa, 1         ; encoding: [0xd8,0xec,0x01]
sla wa, 1

; SRA rd16, #n: D8+r, 0xED, n
; CHECK: sra bc, 4         ; encoding: [0xd9,0xed,0x04]
sra bc, 4

; SRL rd16, #n: D8+r, 0xEF, n
; CHECK: srl de, 8         ; encoding: [0xda,0xef,0x08]
srl de, 8

; RLC rd16: D8+r, 0xE8, 0x01
; CHECK: rlc wa            ; encoding: [0xd8,0xe8,0x01]
rlc wa

; RRC rd16: D8+r, 0xE9, 0x01
; CHECK: rrc bc            ; encoding: [0xd9,0xe9,0x01]
rrc bc

; RL rd16: D8+r, 0xEA, 0x01
; CHECK: rl de             ; encoding: [0xda,0xea,0x01]
rl de

; RR rd16: D8+r, 0xEB, 0x01
; CHECK: rr hl             ; encoding: [0xdb,0xeb,0x01]
rr hl

; ==========================================================================
; 8-bit register instructions (C8-CF prefix)
; ==========================================================================

; LD rd8, rs8: C8+src, 0x88+dst
; CHECK: ld w, a           ; encoding: [0xc9,0x88]
ld w, a

; CHECK: ld b, c           ; encoding: [0xcb,0x8a]
ld b, c

; LD rd8, #imm8: C8+rd, 0x03, imm8
; CHECK: ld a, 0           ; encoding: [0xc9,0x03,0x00]
ld a, 0

; CHECK: ld b, 255         ; encoding: [0xca,0x03,0xff]
ld b, 255

; ADD rd8, rs8: C8+src, 0x80+dst
; CHECK: add a, b          ; encoding: [0xca,0x81]
add a, b

; ADD rd8, #imm8: C8+dst, 0xC8, imm8
; CHECK: add a, 42         ; encoding: [0xc9,0xc8,0x2a]
add a, 42

; SUB rd8, rs8: C8+src, 0xA0+dst
; CHECK: sub c, d          ; encoding: [0xcc,0xa3]
sub c, d

; SUB rd8, #imm8: C8+dst, 0xCA, imm8
; CHECK: sub a, 10         ; encoding: [0xc9,0xca,0x0a]
sub a, 10

; ADC rd8, rs8: C8+src, 0x90+dst
; CHECK: adc a, b          ; encoding: [0xca,0x91]
adc a, b

; SBC rd8, rs8: C8+src, 0xB0+dst
; CHECK: sbc c, d          ; encoding: [0xcc,0xb3]
sbc c, d

; AND rd8, rs8: C8+src, 0xC0+dst
; CHECK: and a, c          ; encoding: [0xcb,0xc1]
and a, c

; AND rd8, #imm8: C8+dst, 0xCC, imm8
; CHECK: and a, 15         ; encoding: [0xc9,0xcc,0x0f]
and a, 15

; OR rd8, rs8: C8+src, 0xE0+dst
; CHECK: or h, l           ; encoding: [0xcf,0xe6]
or h, l

; OR rd8, #imm8: C8+dst, 0xCE, imm8
; CHECK: or a, 128         ; encoding: [0xc9,0xce,0x80]
or a, 128

; XOR rd8, rs8: C8+src, 0xD0+dst
; CHECK: xor a, b          ; encoding: [0xca,0xd1]
xor a, b

; XOR rd8, #imm8: C8+dst, 0xCD, imm8
; CHECK: xor a, 255        ; encoding: [0xc9,0xcd,0xff]
xor a, 255

; CP rd8, rs8: C8+src, 0xF0+dst
; CHECK: cp a, b           ; encoding: [0xca,0xf1]
cp a, b

; CP rd8, #imm8: C8+dst, 0xCF, imm8
; CHECK: cp a, 0           ; encoding: [0xc9,0xcf,0x00]
cp a, 0

; NEG rd8: C8+r, 0x07
; CHECK: neg a             ; encoding: [0xc9,0x07]
neg a

; CPL rd8: C8+r, 0x06
; CHECK: cpl b             ; encoding: [0xca,0x06]
cpl b

; INC 1, rd8: C8+r, 0x61
; CHECK: inc 1, a          ; encoding: [0xc9,0x61]
inc 1, a

; DEC 1, rd8: C8+r, 0x69
; CHECK: dec 1, b          ; encoding: [0xca,0x69]
dec 1, b

; SLA rd8, #n: C8+r, 0xEC, n
; CHECK: sla a, 1          ; encoding: [0xc9,0xec,0x01]
sla a, 1

; SRA rd8, #n: C8+r, 0xED, n
; CHECK: sra a, 4          ; encoding: [0xc9,0xed,0x04]
sra a, 4

; SRL rd8, #n: C8+r, 0xEF, n
; CHECK: srl b, 8          ; encoding: [0xca,0xef,0x08]
srl b, 8

; RLC rd8: C8+r, 0xE8, 0x01
; CHECK: rlc a             ; encoding: [0xc9,0xe8,0x01]
rlc a

; RRC rd8: C8+r, 0xE9, 0x01
; CHECK: rrc b             ; encoding: [0xca,0xe9,0x01]
rrc b

; RL rd8: C8+r, 0xEA, 0x01
; CHECK: rl c              ; encoding: [0xcb,0xea,0x01]
rl c

; RR rd8: C8+r, 0xEB, 0x01
; CHECK: rr d              ; encoding: [0xcc,0xeb,0x01]
rr d
