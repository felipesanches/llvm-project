; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s | llvm-objdump -d - | FileCheck --check-prefix=INST %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; MUL / MULS / DIV / DIVS name the register the CPU WRITES.  The register-
; register and memory forms produce a double-width result (MAME's reading of
; each encoding is quoted), and this backend used to print -- and accept only
; -- the operand-size names:
;     d9 50   `div xwa, xbc`   is  div XWA,BC   (the divisor is 16-bit)
;     ce 43   `mul8rr c, h`    is  mul BC,H     (the result is BC)
;     81 41   `mul a, (xbc)`   is  mul WA,(XBC)
;     91 40   `mul wa, (xbc)`  is  mul XWA,(XBC)
;     d7 fa 42 `mul de, qiz`   is  mul XDE,QIZ
; The old spellings are REFUSED, not aliased: `mul wa, (xbc)` is now the byte
; multiply (81 41), so an alias could not keep its old word meaning.  The
; immediate forms keep the prefix register, which is also what MAME prints
; (`c9 08 05` = mul A,0x05), so they do not move.

.ifndef ERR
; unidasm: d9 50  div XWA,BC
; CHECK: div xwa, bc              ; encoding: [0xd9,0x50]
; INST:  div xwa, bc
div xwa, bc
; unidasm: db 58  divs XWA,HL
; CHECK: divs xwa, hl             ; encoding: [0xdb,0x58]
divs xwa, hl
; unidasm: df 48  muls XWA,SP
; CHECK: muls xwa, sp             ; encoding: [0xdf,0x48]
muls xwa, sp
; unidasm: ce 43  mul BC,H
; CHECK: mul bc, h                ; encoding: [0xce,0x43]
; INST:  mul bc, h
mul bc, h
; unidasm: c9 41  mul WA,A
; CHECK: mul wa, a                ; encoding: [0xc9,0x41]
mul wa, a
; unidasm: 81 41  mul WA,(XBC)
; CHECK: mul wa, (xbc)            ; encoding: [0x81,0x41]
; INST:  mul wa, (xbc)
mul wa, (xbc)
; unidasm: 91 40  mul XWA,(XBC)
; CHECK: mul xwa, (xbc)           ; encoding: [0x91,0x40]
; INST:  mul xwa, (xbc)
mul xwa, (xbc)
; unidasm: c1 34 12 41  mul WA,(0x1234)
; CHECK: mul wa, (4660:16)        ; encoding: [0xc1,0x34,0x12,0x41]
mul wa, (0x1234:16)
; unidasm: d7 fa 42  mul XDE,QIZ
; CHECK: mul xde, qiz             ; encoding: [0xd7,0xfa,0x42]
; INST:  mul xde, qiz
mul xde, qiz
; immediate forms: unchanged (MAME: c9 08 05 = mul A,0x05; d8 08 05 00 =
; mul WA,0x0005)
; CHECK: mul a, 5                 ; encoding: [0xc9,0x08,0x05]
mul a, 5
; CHECK: mul wa, 5                ; encoding: [0xd8,0x08,0x05,0x00]
mul wa, 5
.else
; ERR: [[@LINE+1]]:{{[0-9]+}}: error: invalid operand for instruction
div xwa, xbc
; ERR: [[@LINE+1]]:{{[0-9]+}}: error: unrecognized instruction mnemonic
mul8rr c, h
; ERR: [[@LINE+1]]:{{[0-9]+}}: error: invalid operand for instruction
mul a, (xbc)
; ERR: [[@LINE+1]]:{{[0-9]+}}: error: invalid operand for instruction
mul de, qiz
; the even register field names no result pair (MAME: `mul ??,A`)
; ERR: [[@LINE+1]]:{{[0-9]+}}: error: invalid operand for instruction
mul w, a
.endif
