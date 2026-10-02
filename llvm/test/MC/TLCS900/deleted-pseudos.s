; RUN: not llvm-mc -triple tlcs900 %s 2>&1 | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -show-encoding -defsym GOOD=1 %s | FileCheck --check-prefix=GOOD %s
;
; Pseudo-instructions whose text said something false about their bytes,
; DELETED in the wave 3a T1 fix round (the V1 panel's ENCODING-TRUTH lens).
; bcb142d6ee97 deleted the post-increment and GPR-typed direct-address
; families; these are the rest.  None had a source line left (the KN5000 /
; SX-WSA1R tree was respelled first, disasm 83a3b70d).  Each refused line
; names what MAME unidasm read from the bytes it used to assemble.

.ifndef GOOD
; --- a register of the WRONG WIDTH ---------------------------------------
; mulw_erp bc, 0xfa       -> d7 fa 41  mul XBC,QIZ
; CHECK: error: unrecognized instruction mnemonic
mulw_erp bc, 0xfa
; mul16_ri xbc, wa        -> 91 40     mul XWA,(XBC)
; CHECK: error: unrecognized instruction mnemonic
mul16_ri xbc, wa
; mul16_rid8 xsp, 8, wa   -> 9f 08 40  mul XWA,(XSP+0x08)
; CHECK: error: unrecognized instruction mnemonic
mul16_rid8 xsp, 8, wa
; divs16_rid8 xwa, 42, bc -> 98 2a 59  divs XBC,(XWA+0x2a)
; CHECK: error: unrecognized instruction mnemonic
divs16_rid8 xwa, 42, bc
; muls16_rid8 xwa, 44, bc -> 98 2c 49  muls XBC,(XWA+0x2c)
; CHECK: error: unrecognized instruction mnemonic
muls16_rid8 xwa, 44, bc
; mul8_ri xbc, b          -> 81 42     mul ??,(XBC)   (an even byte field)
; CHECK: error: unrecognized instruction mnemonic
mul8_ri xbc, b
; mul8_rid8 xwa, 0, a     -> 88 00 41  mul WA,(XWA+0x00)
; CHECK: error: unrecognized instruction mnemonic
mul8_rid8 xwa, 0, a
; lda_ri xbc, xsp         -> b1 27     lda SP,XBC
; CHECK: error: unrecognized instruction mnemonic
lda_ri xbc, xsp
; lda_rid8 xwa, 0xfb, xix -> b8 fb 24  lda IX,XWA+0xfb
; CHECK: error: unrecognized instruction mnemonic
lda_rid8 xwa, 0xfb, xix
; mul_sd16b 0, 5, 0x30    -> c1 05 30 40  mul ??,(0x3005)
; CHECK: error: unrecognized instruction mnemonic
mul_sd16b 0, 5, 0x30
; muls_sd16w 0, 0xda, 0xb7 -> d1 da b7 48 muls XWA,(0xb7da)  (raw field)
; CHECK: error: unrecognized instruction mnemonic
muls_sd16w 0, 0xda, 0xb7
; djnz xbc, 0             -> d9 1c     djnz BC  (a 16-bit decrement)
; CHECK: error: invalid operand for instruction
djnz xbc, 0
; --- a register-file LD read BACKWARDS ------------------------------------
; ld2_erpw_rr ix, 0xee    -> d7 ee 9c  ld QHL,IX  (a store of IX)
; CHECK: error: unrecognized instruction mnemonic
ld2_erpw_rr ix, 0xee
; --- ANOTHER OPERATION entirely -------------------------------------------
; incdd8 1, (30)          -> f1 1e 00 61     ld (0x001e),XBC
; CHECK: error: unrecognized instruction mnemonic
incdd8 1, (30)
; incdd16_24 1, (30)      -> f2 1e 00 00 61  ld (0x00001e),XBC
; CHECK: error: unrecognized instruction mnemonic
incdd16_24 1, (30)
; decdd8 1, (30)          -> f1 1e 00 69     db
; CHECK: error: unrecognized instruction mnemonic
decdd8 1, (30)
; tsetda 3, (30)          -> f1 1e 00 a3     stcf 3,(0x001e)
; CHECK: error: unrecognized instruction mnemonic
tsetda 3, (30)
; tsetda_24 3, (30)       -> f2 1e 00 00 a3  stcf 3,(0x00001e)
; CHECK: error: unrecognized instruction mnemonic
tsetda_24 3, (30)
; call_dd8 30             -> f0 1e 08        db
; CHECK: error: unrecognized instruction mnemonic
call_dd8 30
; cpl_erpw 0xe4           -> d7 e4 da        cp BC,2
; CHECK: error: unrecognized instruction mnemonic
cpl_erpw 0xe4
; neg_erpw 0xe4           -> d7 e4 dd        cp BC,5
; CHECK: error: unrecognized instruction mnemonic
neg_erpw 0xe4
; sla_erpw 0xe4           -> d7 e4 84        add IX,BC
; CHECK: error: unrecognized instruction mnemonic
sla_erpw 0xe4
; srl_a_erpw 0xe4         -> d7 e4 82        add DE,BC
; CHECK: error: unrecognized instruction mnemonic
srl_a_erpw 0xe4
; sll_a_erpw 0xe4         -> d7 e4 9c        ld BC,IX
; CHECK: error: unrecognized instruction mnemonic
sll_a_erpw 0xe4
; ldcf_erpb 0xe4          -> c7 e4 e6        or H,C
; CHECK: error: unrecognized instruction mnemonic
ldcf_erpb 0xe4
; xorcf_erpb 0xe4         -> c7 e4 e2        or B,C
; CHECK: error: unrecognized instruction mnemonic
xorcf_erpb 0xe4
.else
; --- the spellings that say it -------------------------------------------
; GOOD: mul xbc, qiz              ; encoding: [0xd7,0xfa,0x41]
mul xbc, qiz
; GOOD: mul xwa, (xbc)            ; encoding: [0x91,0x40]
mul xwa, (xbc)
; GOOD: mul xwa, (xsp+8)          ; encoding: [0x9f,0x08,0x40]
mul xwa, (xsp+8)
; GOOD: divs xbc, (xwa+42)        ; encoding: [0x98,0x2a,0x59]
divs xbc, (xwa+42)
; GOOD: lda sp, (xbc)             ; encoding: [0xb1,0x27]
lda sp, (xbc)
; GOOD: mul wa, (14726:16)        ; encoding: [0xc1,0x86,0x39,0x41]
mul wa, (0x3986:16)
; GOOD: muls xwa, (47066:16)      ; encoding: [0xd1,0xda,0xb7,0x48]
muls xwa, (0xb7da:16)
; GOOD: djnz bc, 0                ; encoding: [0xd9,0x1c,0x00]
djnz bc, 0
; GOOD: djnz16 bc, 0              ; encoding: [0xd9,0x1c,0x00]
djnz16 bc, 0
; GOOD: ld qhl, ix                ; encoding: [0xd7,0xee,0x9c]
ld qhl, ix
; GOOD: inc 1, (7710:16)          ; encoding: [0xc1,0x1e,0x1e,0x61]
inc 1, (0x1e1e:16)
.endif
