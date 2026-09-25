; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s | llvm-objdump -d - | FileCheck --check-prefix=INST %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
; RUN: not llvm-mc -triple tlcs900 -filetype=obj -o /dev/null -defsym ERR2=1 %s 2>&1 | FileCheck --check-prefix=ERR2 %s
;
; A register-indirect DISPLACEMENT WIDTH, `(xrr+D:8)` / `(xrr+D:16)`.
;
; (Xrr+d8) and (Xrr+d16) are both able to hold a small displacement, and the
; firmware uses both: bf 00 30 is lda XWA,(XSP+0) in the d8 form, and the v7
; ROM has `c3 f9 00 00` -- (XIZ+0) in the d16 form.  Left alone the assembler
; picks d8 for -128..127 and d16 otherwise; the width suffix states the other
; choice, the way `(0x8a:24)` states a direct-address width.  Bytes cross-
; checked with MAME's unidasm (quoted per line).
;
; ⚠ This replaces the SENTINEL 256, which meant "d8 carrying 0": a literal
; `(xsp+256)` assembled to bf 00 30 -- which is (xsp+0) -- with no diagnostic,
; and the ROM's real f3 fd 00 01 30 (lda XWA,XSP+0x0100) printed as the same
; text.  Once the tree stopped spelling it (TOOLCHAIN_VERSION UPDATE 17), 256
; became an ordinary displacement -- pinned below.

.ifdef ERR2
; the retired 65536 sentinel ("d16 carrying 0") is now just out of range
; (an encoder error, so it cannot share a run with the parser errors below)
; ERR2: error: displacement 65536 too large for d16 encoding
ld a, (xiz+65536)
.else
.ifndef ERR
; unidasm: bf 00 30  lda XWA,XSP+0x00
; CHECK: lda xwa, (xsp+0:8)   ; encoding: [0xbf,0x00,0x30]
; INST:  lda xwa, (xsp+0:8)
lda xwa, (xsp+0:8)

; unidasm: f3 fd 00 00 30  lda XWA,XSP+0x0000
; CHECK: lda xwa, (xsp+0:16)  ; encoding: [0xf3,0xfd,0x00,0x00,0x30]
; INST:  lda xwa, (xsp+0:16)
lda xwa, (xsp+0:16)

; unidasm: f3 fd 00 01 30  lda XWA,XSP+0x0100
; CHECK: lda xwa, (xsp+256:16)  ; encoding: [0xf3,0xfd,0x00,0x01,0x30]
; INST:  lda xwa, (xsp+256)
lda xwa, (xsp+256:16)

; unidasm: c3 f9 05 00 21  ld A,(XIZ+0x0005)
; CHECK: ld a, (xiz+5:16)     ; encoding: [0xc3,0xf9,0x05,0x00,0x21]
; INST:  ld a, (xiz+5:16)
ld a, (xiz+5:16)

; unidasm: c3 f9 fb ff 21  ld A,(XIZ+0xfffb)
; CHECK: ld a, (xiz-5:16)     ; encoding: [0xc3,0xf9,0xfb,0xff,0x21]
; INST:  ld a, (xiz-5:16)
ld a, (xiz-5:16)

; A width that is the default anyway changes nothing, and prints back plain.
; CHECK: ld a, (xiz+5:8)      ; encoding: [0x8e,0x05,0x21]
; INST:  ld a, (xiz+5)
ld a, (xiz+5:8)

; unidasm: 8e 80 21  ld A,(XIZ+0x80)
; CHECK: ld a, (xiz-128:8)    ; encoding: [0x8e,0x80,0x21]
; INST:  ld a, (xiz-128)
ld a, (xiz-128:8)

; destination and ALU-immediate tables, same operand
; CHECK: ld (xhl+0:8), a      ; encoding: [0xbb,0x00,0x41]
ld (xhl+0:8), a
; CHECK: cp (xix+0:8), 5      ; encoding: [0x8c,0x00,0x3f,0x05]
cp (xix+0:8), 5

; A literal +256 is a displacement like any other (d16).  It used to be the
; sentinel for d8+0 and assembled to bf 00 30 -- (xsp+0) -- in silence.
; unidasm: f3 fd 00 01 30  lda XWA,XSP+0x0100
; CHECK: lda xwa, (xsp+256)   ; encoding: [0xf3,0xfd,0x00,0x01,0x30]
; INST:  lda xwa, (xsp+256)
lda xwa, (xsp+256)
; CHECK: lda xwa, (xsp+256)   ; encoding: [0xf3,0xfd,0x00,0x01,0x30]
lda xwa, (xsp+0x0100)
.else
; ERR: error: displacement 128 does not fit the signed 8-bit (Xrr+d8) field
ld a, (xiz+128:8)
; ERR: error: displacement 40000 does not fit the signed 16-bit (Xrr+d16) field
ld a, (xiz+40000:16)
; ERR: error: a displacement whose width is written must be a constant
ld a, (xiz+sym:8)
; ERR: error: a register-indirect displacement width must be 8 or 16
ld a, (xiz+1:24)
; ERR: error: expected a displacement width of 8 or 16 after ':'
ld a, (xiz+1:x)

.endif
.endif
