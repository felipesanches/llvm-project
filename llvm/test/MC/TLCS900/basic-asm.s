; RUN: llvm-mc -triple tlcs900 < %s | FileCheck %s

; Test basic data transfer instructions
; CHECK: ld	xwa, 305419896
ld xwa, 305419896

; CHECK: ld	xde, xbc
ld xde, xbc

; CHECK: ld	xhl, (xsp)
ld xhl, (xsp)

; CHECK: ld	xwa, (xsp+8)
ld xwa, (xsp+8)

; CHECK: ld	(xsp), xde
ld (xsp), xde

; CHECK: ld	(xsp+4), xbc
ld (xsp+4), xbc

; Test arithmetic instructions
; CHECK: add	xde, xbc
add xde, xbc

; CHECK: add	xwa, 100
add xwa, 100

; CHECK: sub	xhl, xde
sub xhl, xde

; CHECK: sub	xbc, 50
sub xbc, 50

; CHECK: adc	xwa, xbc
adc xwa, xbc

; CHECK: sbc	xde, xhl
sbc xde, xhl

; Test logic instructions
; CHECK: and	xwa, xbc
and xwa, xbc

; CHECK: and	xde, 255
and xde, 255

; CHECK: or	xhl, xde
or xhl, xde

; CHECK: or	xwa, 15
or xwa, 15

; CHECK: xor	xbc, xde
xor xbc, xde

; CHECK: xor	xhl, 65535
xor xhl, 65535

; Test shift instructions
; CHECK: sla	xwa, xbc
sla xwa, xbc

; CHECK: sla	xde, 4
sla xde, 4

; CHECK: sra	xhl, xde
sra xhl, xde

; CHECK: sra	xwa, 1
sra xwa, 1

; CHECK: srl	xbc, xwa
srl xbc, xwa

; CHECK: srl	xde, 8
srl xde, 8

; Test unary instructions
; Note: 32-bit NEG/CPL are now isCodeGenOnly (invalid in E8 prefix table).
; 16-bit NEG/CPL are tested in the 16-bit section below.

; CHECK: inc	1, xwa
inc 1, xwa

; CHECK: inc	8, xbc
inc 8, xbc

; CHECK: dec	3, xhl
dec 3, xhl

; CHECK: exts	xwa
exts xwa

; CHECK: extz	xde
extz xde

; Test compare instructions
; CHECK: cp	xwa, xbc
cp xwa, xbc

; CHECK: cp	xde, 0
cp xde, 0

; Test system instructions
; CHECK: nop
nop

; CHECK: halt
halt

; DI is an alias for EI 0
; CHECK: ei	0
di

; CHECK: ei	3
ei 3

; CHECK: ret
ret

; CHECK: reti
reti

; Test stack instructions
; CHECK: push	xwa
push xwa

; CHECK: push	xde
push xde

; CHECK: pop	xbc
pop xbc

; CHECK: pop	xhl
pop xhl

; Test rotate instructions
; CHECK: rlc	xwa
rlc xwa

; CHECK: rrc	xde
rrc xde

; CHECK: rl	xbc
rl xbc

; CHECK: rr	xhl
rr xhl

; Note: 32-bit bit manipulation (BIT/SET/RES/CHG/TSET) is now isCodeGenOnly
; (invalid in E8 prefix table). Tested via 8/16-bit register forms.

; Test block transfer
; CHECK: ldi
ldi

; CHECK: ldir
ldir

; CHECK: ldd
ldd

; CHECK: lddr
lddr

; Test block compare
; CHECK: cpi
cpi

; CHECK: cpir
cpir

; CHECK: cpd
cpd

; CHECK: cpdr
cpdr

; Test exchange
; Note: 32-bit EX is now isCodeGenOnly (invalid in E8 prefix table).

; Test load effective address
; CHECK: lda	xde, (xsp+16)
lda xde, (xsp+16)

; Test SWI
; CHECK: swi	0
swi 0

; Test indirect jump
; CHECK: jp	(xwa)
jp (xwa)

; CHECK: jp	(xhl)
jp (xhl)

; === 16-bit register instructions ===

; CHECK: push	wa
push wa

; CHECK: push	bc
push bc

; CHECK: pop	de
pop de

; CHECK: pop	hl
pop hl

; CHECK: ld	wa, bc
ld wa, bc

; CHECK: ld	wa, 0
ld wa, 0

; CHECK: add	wa, bc
add wa, bc

; CHECK: add	wa, 42
add wa, 42

; CHECK: sub	de, hl
sub de, hl

; CHECK: and	wa, de
and wa, de

; CHECK: or	bc, hl
or bc, hl

; CHECK: xor	de, wa
xor de, wa

; CHECK: cp	wa, bc
cp wa, bc

; CHECK: cp	de, 100
cp de, 100

; CHECK: neg	wa
neg wa

; CHECK: cpl	bc
cpl bc

; CHECK: inc	1, wa
inc 1, wa

; CHECK: dec	3, de
dec 3, de

; CHECK: sla	wa, 1
sla wa, 1

; CHECK: sra	bc, 4
sra bc, 4

; CHECK: srl	de, 8
srl de, 8

; CHECK: rlc	wa
rlc wa

; CHECK: rrc	bc
rrc bc

; CHECK: exts	wa
exts wa

; CHECK: extz	de
extz de

; === 8-bit register instructions ===

; CHECK: ld	w, a
ld w, a

; CHECK: ld	a, 0
ld a, 0

; CHECK: add	a, b
add a, b

; CHECK: add	a, 42
add a, 42

; CHECK: sub	c, d
sub c, d

; CHECK: and	a, c
and a, c

; CHECK: or	h, l
or h, l

; CHECK: xor	a, b
xor a, b

; CHECK: cp	a, b
cp a, b

; CHECK: cp	a, 0
cp a, 0

; CHECK: neg	a
neg a

; CHECK: cpl	b
cpl b

; CHECK: inc	1, a
inc 1, a

; CHECK: dec	1, b
dec 1, b

; CHECK: sla	a, 1
sla a, 1

; CHECK: rlc	a
rlc a
