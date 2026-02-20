; RUN: llvm-mc -triple tlcs900 -filetype=obj %s -o %t.o
; RUN: llvm-objdump -d %t.o | FileCheck %s
;
; ELF object round-trip: assemble to ELF, disassemble, verify instruction text.
; Tests the full ELF path (section layout, symbol handling, multi-byte encoding).

; === Single-byte instructions ===

; CHECK: nop
nop

; CHECK-NEXT: ret
ret

; CHECK-NEXT: halt
halt

; CHECK-NEXT: reti
reti

; === PUSH / POP (1 byte each) ===

; CHECK-NEXT: push xwa
push xwa

; CHECK-NEXT: push xbc
push xbc

; CHECK-NEXT: push xde
push xde

; CHECK-NEXT: pop xwa
pop xwa

; CHECK-NEXT: pop xhl
pop xhl

; === LD r32, #imm32 (5 bytes) ===

; CHECK-NEXT: ld xwa, 0
ld xwa, 0

; CHECK-NEXT: ld xbc, 255
ld xbc, 255

; CHECK-NEXT: ld xhl, 305419896
ld xhl, 0x12345678

; === 32-bit register-register ALU (2 bytes) ===

; CHECK-NEXT: add xwa, xbc
add xwa, xbc

; CHECK-NEXT: sub xde, xwa
sub xde, xwa

; CHECK-NEXT: and xwa, xbc
and xwa, xbc

; CHECK-NEXT: or xhl, xde
or xhl, xde

; CHECK-NEXT: xor xde, xhl
xor xde, xhl

; CHECK-NEXT: cp xwa, xbc
cp xwa, xbc

; CHECK-NEXT: ld xde, xbc
ld xde, xbc

; === 32-bit register-immediate ALU (6 bytes) ===

; CHECK-NEXT: add xwa, 42
add xwa, 42

; CHECK-NEXT: sub xbc, 1
sub xbc, 1

; CHECK-NEXT: and xde, 255
and xde, 255

; CHECK-NEXT: cp xwa, 1000
cp xwa, 1000

; === Unary / INC / DEC ===

; CHECK-NEXT: exts xwa
exts xwa

; CHECK-NEXT: extz xbc
extz xbc

; CHECK-NEXT: inc 1, xwa
inc 1, xwa

; CHECK-NEXT: dec 3, xbc
dec 3, xbc

; === Shifts (3 bytes) ===

; CHECK-NEXT: sla xwa, 1
sla xwa, 1

; CHECK-NEXT: sra xbc, 4
sra xbc, 4

; CHECK-NEXT: srl xde, 8
srl xde, 8

; === Rotates (3 bytes) ===

; CHECK-NEXT: rlc xwa
rlc xwa

; CHECK-NEXT: rrc xbc
rrc xbc

; CHECK-NEXT: rl xde
rl xde

; CHECK-NEXT: rr xhl
rr xhl

; === Block transfers (2 bytes) ===

; CHECK-NEXT: ldi
ldi

; CHECK-NEXT: ldir
ldir

; CHECK-NEXT: ldd
ldd

; CHECK-NEXT: lddr
lddr

; === Block compares (2 bytes) ===

; CHECK-NEXT: cpi
cpi

; CHECK-NEXT: cpir
cpir

; CHECK-NEXT: cpd
cpd

; CHECK-NEXT: cpdr
cpdr

; === Memory load / store ===

; CHECK-NEXT: ld xwa, (xsp)
ld xwa, (xsp)

; CHECK-NEXT: ld xde, (xhl)
ld xde, (xhl)

; CHECK-NEXT: ld xde, (xsp+4)
ld xde, (xsp+4)

; CHECK-NEXT: ld (xsp), xwa
ld (xsp), xwa

; CHECK-NEXT: ld (xhl), xde
ld (xhl), xde

; CHECK-NEXT: ld (xsp+8), xwa
ld (xsp+8), xwa

; === Memory ALU ===

; CHECK-NEXT: add (xhl), xwa
add (xhl), xwa

; CHECK-NEXT: sub (xsp+4), xde
sub (xsp+4), xde

; CHECK-NEXT: cp (xhl), xwa
cp (xhl), xwa

; === LDA ===

; CHECK-NEXT: lda xde, (xhl)
lda xde, (xhl)

; CHECK-NEXT: lda xwa, (xsp+64)
lda xwa, (xsp+64)

; === CALL/JP indirect ===

; CHECK-NEXT: call (xwa)
call (xwa)

; CHECK-NEXT: jp (xhl)
jp (xhl)

; === MUL / MULS ===

; CHECK-NEXT: mul xwa, xbc
mul xwa, xbc

; CHECK-NEXT: muls xwa, xbc
muls xwa, xbc

; === EI / DI / SWI / RETD ===

; CHECK-NEXT: di
di

; CHECK-NEXT: ei 3
ei 3

; CHECK-NEXT: swi 0
swi 0

; CHECK-NEXT: swi 7
swi 7

; CHECK-NEXT: retd 4
retd 4

; === 16-bit multiply (only 16-bit ops with disassembler support) ===

; CHECK-NEXT: mul xwa, xde
mul xwa, xde

; CHECK-NEXT: muls xde, xhl
muls xde, xhl
