; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; The raw-operand pseudos write a bit number, a condition code or an 8-bit
; address as separate numbers; their encoders add the number into a
; sub-opcode or keep the low byte, so a value that did not fit became ANOTHER
; instruction in silence (wave 3a V1 re-verification).  MAME unidasm's
; reading of what each refused spelling used to assemble is quoted.

; CHECK: bit_dd8 3, 52 {{.*}}encoding: [0xf0,0x34,0xcb]
bit_dd8 3, 0x34
; CHECK: jp_dd8 15, 5 {{.*}}encoding: [0xf0,0x05,0xdf]
jp_dd8 15, 5
; CHECK: tset_dd16 7, 1, 251 {{.*}}encoding: [0xf1,0x01,0xfb,0xaf]
tset_dd16 7, 1, 0xfb
; a backward .equ is a constant where it is written
.equ BACK, 4
; CHECK: res_dd8 4, 52 {{.*}}encoding: [0xf0,0x34,0xb4]
res_dd8 BACK, 0x34

.ifdef ERR
; was f0 34 d0 = jp F,0x34
; ERR: error: 8 does not fit a bit number (must be 0..7)
bit_dd8 8, 0x34
; was f0 01 e8 = call T,0x01
; ERR: error: 48 does not fit a bit number (must be 0..7)
set_dd8 0x30, 1
; was f0 34 cb = bit 3,(0x34)
; ERR: error: 4660 does not fit an 8-bit direct address (must be 0..255)
bit_dd8 3, 0x1234
; was f0 05 e0 = call F,0x05
; ERR: error: 16 does not fit a condition code (must be 0..15)
jp_dd8 16, 5
; was f1 01 fb b0 = res 0,(0xfb01)
; ERR: error: 8 does not fit a bit number (must be 0..7)
tset_dd16 8, 1, 0xfb
; was b0 88 = orcf 0,(XWA)
; ERR: error: 8 does not fit a bit number (must be 0..7)
andcfn_ri xwa, 8
; was two bytes, b0 00
; ERR: error: 16 does not fit a condition code (must be 0..15)
ret_cc_ri xwa, 16
; a forward reference dropped the address byte (f0 b3) or asserted
; ERR: error: an 8-bit direct address of this raw-operand pseudo must be a constant known where it is written
res_dd8 3, FWD
.equ FWD, 5
.endif
