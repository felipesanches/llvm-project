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

; CHECK: ld	(xsp), 42
ld (xsp), 42

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
; CHECK: neg	xwa
neg xwa

; CHECK: cpl	xde
cpl xde

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

; CHECK: di
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

; Test bit manipulation
; CHECK: bit	7, xwa
bit 7, xwa

; CHECK: set	3, xde
set 3, xde

; CHECK: res	0, xbc
res 0, xbc

; CHECK: chg	15, xhl
chg 15, xhl

; CHECK: tset	4, xwa
tset 4, xwa

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
; CHECK: ex	xwa, xbc
ex xwa, xbc

; Test load effective address
; CHECK: lda	xde, (xsp+16)
lda xde, (xsp+16)

; Test SWI
; CHECK: swi	0
swi 0
