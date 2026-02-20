; RUN: llvm-mc -triple tlcs900 -show-encoding %s \
; RUN:     | FileCheck -check-prefixes=CHECK,CHECK-ENC %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s \
; RUN:     | llvm-objdump -d - | FileCheck --check-prefix=CHECK-INST %s
;
; Round-trip test: verify assembly → encoding → disassembly produces
; the same instruction text. Only includes instructions that can be
; encoded and disassembled without relocations.

; === Single-byte instructions ===

; CHECK: nop
; CHECK-ENC: encoding: [0x00]
; CHECK-INST: nop
nop

; CHECK: halt
; CHECK-ENC: encoding: [0x05]
; CHECK-INST: halt
halt

; CHECK: reti
; CHECK-ENC: encoding: [0x07]
; CHECK-INST: reti
reti

; CHECK: ret
; CHECK-ENC: encoding: [0x0e]
; CHECK-INST: ret
ret

; === EI / DI ===

; CHECK: di
; CHECK-ENC: encoding: [0x06,0x00]
; CHECK-INST: di
di

; CHECK: ei 3
; CHECK-ENC: encoding: [0x06,0x03]
; CHECK-INST: ei 3
ei 3

; === SWI ===

; CHECK: swi 0
; CHECK-ENC: encoding: [0xf8]
; CHECK-INST: swi 0
swi 0

; CHECK: swi 7
; CHECK-ENC: encoding: [0xff]
; CHECK-INST: swi 7
swi 7

; === RETD ===

; CHECK: retd 4
; CHECK-ENC: encoding: [0x0f,0x04,0x00]
; CHECK-INST: retd 4
retd 4

; === PUSH / POP ===

; CHECK: push xwa
; CHECK-ENC: encoding: [0x38]
; CHECK-INST: push xwa
push xwa

; CHECK: push xbc
; CHECK-ENC: encoding: [0x39]
; CHECK-INST: push xbc
push xbc

; CHECK: pop xwa
; CHECK-ENC: encoding: [0x58]
; CHECK-INST: pop xwa
pop xwa

; CHECK: pop xhl
; CHECK-ENC: encoding: [0x5b]
; CHECK-INST: pop xhl
pop xhl

; === LD r32, #imm32 ===

; CHECK: ld xwa, 0
; CHECK-ENC: encoding: [0x40,0x00,0x00,0x00,0x00]
; CHECK-INST: ld xwa, 0
ld xwa, 0

; CHECK: ld xbc, 1
; CHECK-ENC: encoding: [0x41,0x01,0x00,0x00,0x00]
; CHECK-INST: ld xbc, 1
ld xbc, 1

; CHECK: ld xhl, 305419896
; CHECK-ENC: encoding: [0x43,0x78,0x56,0x34,0x12]
; CHECK-INST: ld xhl, 305419896
ld xhl, 0x12345678

; === 32-bit register-register ALU ===

; CHECK: add xwa, xbc
; CHECK-ENC: encoding: [0xe9,0x80]
; CHECK-INST: add xwa, xbc
add xwa, xbc

; CHECK: sub xde, xwa
; CHECK-ENC: encoding: [0xe8,0xa2]
; CHECK-INST: sub xde, xwa
sub xde, xwa

; CHECK: adc xhl, xde
; CHECK-ENC: encoding: [0xea,0x93]
; CHECK-INST: adc xhl, xde
adc xhl, xde

; CHECK: sbc xwa, xde
; CHECK-ENC: encoding: [0xea,0xb0]
; CHECK-INST: sbc xwa, xde
sbc xwa, xde

; CHECK: and xwa, xbc
; CHECK-ENC: encoding: [0xe9,0xc0]
; CHECK-INST: and xwa, xbc
and xwa, xbc

; CHECK: or xhl, xde
; CHECK-ENC: encoding: [0xea,0xe3]
; CHECK-INST: or xhl, xde
or xhl, xde

; CHECK: xor xde, xhl
; CHECK-ENC: encoding: [0xeb,0xd2]
; CHECK-INST: xor xde, xhl
xor xde, xhl

; CHECK: cp xwa, xbc
; CHECK-ENC: encoding: [0xe9,0xf0]
; CHECK-INST: cp xwa, xbc
cp xwa, xbc

; CHECK: ld xde, xbc
; CHECK-ENC: encoding: [0xe9,0x8a]
; CHECK-INST: ld xde, xbc
ld xde, xbc

; === 32-bit register-immediate ALU ===

; CHECK: add xwa, 42
; CHECK-ENC: encoding: [0xe8,0xc8,0x2a,0x00,0x00,0x00]
; CHECK-INST: add xwa, 42
add xwa, 42

; CHECK: sub xwa, 1
; CHECK-ENC: encoding: [0xe8,0xca,0x01,0x00,0x00,0x00]
; CHECK-INST: sub xwa, 1
sub xwa, 1

; CHECK: and xwa, 255
; CHECK-ENC: encoding: [0xe8,0xcc,0xff,0x00,0x00,0x00]
; CHECK-INST: and xwa, 255
and xwa, 255

; CHECK: cp xde, 1000
; CHECK-ENC: encoding: [0xea,0xcf,0xe8,0x03,0x00,0x00]
; CHECK-INST: cp xde, 1000
cp xde, 1000

; === 32-bit unary instructions ===

; CHECK: neg xwa
; CHECK-ENC: encoding: [0xe8,0x07]
; CHECK-INST: neg xwa
neg xwa

; CHECK: cpl xbc
; CHECK-ENC: encoding: [0xe9,0x06]
; CHECK-INST: cpl xbc
cpl xbc

; CHECK: exts xwa
; CHECK-ENC: encoding: [0xe8,0x13]
; CHECK-INST: exts xwa
exts xwa

; CHECK: extz xbc
; CHECK-ENC: encoding: [0xe9,0x12]
; CHECK-INST: extz xbc
extz xbc

; === INC / DEC ===

; CHECK: inc 1, xwa
; CHECK-ENC: encoding: [0xe8,0x61]
; CHECK-INST: inc 1, xwa
inc 1, xwa

; CHECK: inc 8, xhl
; CHECK-ENC: encoding: [0xeb,0x60]
; CHECK-INST: inc 8, xhl
inc 8, xhl

; CHECK: dec 1, xwa
; CHECK-ENC: encoding: [0xe8,0x69]
; CHECK-INST: dec 1, xwa
dec 1, xwa

; CHECK: dec 3, xbc
; CHECK-ENC: encoding: [0xe9,0x6b]
; CHECK-INST: dec 3, xbc
dec 3, xbc

; === Shifts ===

; CHECK: sla xwa, 1
; CHECK-ENC: encoding: [0xe8,0xec,0x01]
; CHECK-INST: sla xwa, 1
sla xwa, 1

; CHECK: sra xbc, 4
; CHECK-ENC: encoding: [0xe9,0xed,0x04]
; CHECK-INST: sra xbc, 4
sra xbc, 4

; CHECK: srl xde, 8
; CHECK-ENC: encoding: [0xea,0xef,0x08]
; CHECK-INST: srl xde, 8
srl xde, 8

; === Rotates ===

; CHECK: rlc xwa
; CHECK-ENC: encoding: [0xe8,0xe8,0x01]
; CHECK-INST: rlc xwa
rlc xwa

; CHECK: rrc xbc
; CHECK-ENC: encoding: [0xe9,0xe9,0x01]
; CHECK-INST: rrc xbc
rrc xbc

; CHECK: rl xde
; CHECK-ENC: encoding: [0xea,0xea,0x01]
; CHECK-INST: rl xde
rl xde

; CHECK: rr xhl
; CHECK-ENC: encoding: [0xeb,0xeb,0x01]
; CHECK-INST: rr xhl
rr xhl

; === Memory loads (A0+base, 0x20+dst) ===

; CHECK: ld xwa, (xsp)
; CHECK-ENC: encoding: [0xa7,0x20]
; CHECK-INST: ld xwa, (xsp)
ld xwa, (xsp)

; CHECK: ld xde, (xhl)
; CHECK-ENC: encoding: [0xa3,0x22]
; CHECK-INST: ld xde, (xhl)
ld xde, (xhl)

; CHECK: ld xde, (xsp+4)
; CHECK-ENC: encoding: [0xaf,0x04,0x22]
; CHECK-INST: ld xde, (xsp+4)
ld xde, (xsp+4)

; === Memory stores (B0+base, 0x60+src) ===

; CHECK: ld (xsp), xwa
; CHECK-ENC: encoding: [0xb7,0x60]
; CHECK-INST: ld (xsp), xwa
ld (xsp), xwa

; CHECK: ld (xhl), xde
; CHECK-ENC: encoding: [0xb3,0x62]
; CHECK-INST: ld (xhl), xde
ld (xhl), xde

; CHECK: ld (xsp+8), xwa
; CHECK-ENC: encoding: [0xbf,0x08,0x60]
; CHECK-INST: ld (xsp+8), xwa
ld (xsp+8), xwa

; === MemALU register ops (A0+base, 0x88+src for ADD, etc.) ===

; CHECK: add (xhl), xwa
; CHECK-ENC: encoding: [0xa3,0x88]
; CHECK-INST: add (xhl), xwa
add (xhl), xwa

; CHECK: sub (xsp+4), xde
; CHECK-ENC: encoding: [0xaf,0x04,0xaa]
; CHECK-INST: sub (xsp+4), xde
sub (xsp+4), xde

; CHECK: cp (xhl), xwa
; CHECK-ENC: encoding: [0xa3,0xf8]
; CHECK-INST: cp (xhl), xwa
cp (xhl), xwa

; === LDA (B0+base, 0x30+dst) ===

; CHECK: lda xde, (xhl)
; CHECK-ENC: encoding: [0xb3,0x32]
; CHECK-INST: lda xde, (xhl)
lda xde, (xhl)

; CHECK: lda xwa, (xsp+64)
; CHECK-ENC: encoding: [0xbf,0x40,0x30]
; CHECK-INST: lda xwa, (xsp+64)
lda xwa, (xsp+64)

; === CALL/JP indirect (B0+reg, 0xE8/0xD8) ===

; CHECK: call (xwa)
; CHECK-ENC: encoding: [0xb0,0xe8]
; CHECK-INST: call (xwa)
call (xwa)

; CHECK: jp (xhl)
; CHECK-ENC: encoding: [0xb3,0xd8]
; CHECK-INST: jp (xhl)
jp (xhl)

; === Block transfers (0x80 prefix) ===

; CHECK: ldi
; CHECK-ENC: encoding: [0x80,0x10]
; CHECK-INST: ldi
ldi

; CHECK: ldir
; CHECK-ENC: encoding: [0x80,0x11]
; CHECK-INST: ldir
ldir

; CHECK: ldd
; CHECK-ENC: encoding: [0x80,0x12]
; CHECK-INST: ldd
ldd

; CHECK: lddr
; CHECK-ENC: encoding: [0x80,0x13]
; CHECK-INST: lddr
lddr

; === MUL / MULS (D8+src, 0x40/0x48+dst) ===

; CHECK: mul xwa, xbc
; CHECK-ENC: encoding: [0xd9,0x40]
; CHECK-INST: mul xwa, xbc
mul xwa, xbc

; CHECK: muls xwa, xbc
; CHECK-ENC: encoding: [0xd9,0x48]
; CHECK-INST: muls xwa, xbc
muls xwa, xbc
