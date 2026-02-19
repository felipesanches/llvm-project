; RUN: llvm-mc -triple tlcs900 < %s | FileCheck %s

; Test memory operands with various displacements

; Zero displacement (base register only)
; CHECK: ld	xwa, (xsp)
ld xwa, (xsp)

; Positive displacement
; CHECK: ld	xde, (xsp+4)
ld xde, (xsp+4)

; CHECK: ld	xbc, (xhl+100)
ld xbc, (xhl+100)

; Large displacement
; CHECK: ld	xwa, (xix+32767)
ld xwa, (xix+32767)

; Store with displacement
; CHECK: ld	(xsp+8), xwa
ld (xsp+8), xwa

; CHECK: ld	(xiy+16), xde
ld (xiy+16), xde

; Memory-register arithmetic
; CHECK: add	(xhl), xwa
add (xhl), xwa

; CHECK: sub	(xsp+4), xde
sub (xsp+4), xde

; CHECK: and	(xix), xbc
and (xix), xbc

; CHECK: or	(xiy+8), xwa
or (xiy+8), xwa

; CHECK: xor	(xhl+2), xde
xor (xhl+2), xde

; Memory-register compare
; CHECK: cp	(xhl), xwa
cp (xhl), xwa

; Note: Memory-immediate CP/ADD/SUB are invalid in the 32-bit A0 table.
; These are now isCodeGenOnly and not testable in assembly.

; Load effective address
; CHECK: lda	xwa, (xsp+64)
lda xwa, (xsp+64)

; CHECK: lda	xde, (xhl)
lda xde, (xhl)

; Negative displacement
; CHECK: ld	xwa, (xsp-4)
ld xwa, (xsp-4)

; CHECK: ld	(xsp-8), xde
ld (xsp-8), xde

; === Direct memory addressing ===

; Store to absolute address
; CHECK: ld	(0), xwa
ld (0), xwa

; Store to hex address
; CHECK: ld	(4660), xwa
ld (0x1234), xwa

; Load effective address from direct memory
; CHECK: lda	xwa, (0)
lda xwa, (0)

; Store with .equ constant
.equ PORT, 0x200000
; CHECK: ld	(2097152), xde
ld (PORT), xde
