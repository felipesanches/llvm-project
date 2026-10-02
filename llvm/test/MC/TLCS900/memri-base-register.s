; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; The BASE of a register-indirect operand is a 32-bit register, and a register
; name is never a symbol.
;
; Both were silent before (wave 3a V1 panel, TREE-TRUTH and ENCODING-TRUTH):
;  * any register was accepted as the base and encoded BY INDEX -- `ld a, (a)`
;    assembled 81 21, which is ld A,(XBC); `ld a, (qiz+0:8)` 8e 00 21, which is
;    (XIZ+0); `(h-1)` (XIZ-1);
;  * a bank register written anywhere but (R+)/(-R) parsed as an undefined
;    SYMBOL, so `ld a, (xbc3)` assembled c2 00 00 00 21 -- a 24-bit DIRECT
;    address with a relocation against `xbc3` -- and `(5+xsp)` likewise.
; Every positive encoding below is MAME unidasm's reading of the same bytes.

.ifndef ERR
; unidasm: 81 21  ld A,(XBC)
; CHECK: ld a, (xbc)              ; encoding: [0x81,0x21]
ld a, (xbc)
; unidasm: 89 05 21  ld A,(XBC+0x05)
; CHECK: ld a, (xbc+5)            ; encoding: [0x89,0x05,0x21]
ld a, (xbc+5)
; unidasm: 8e 00 21  ld A,(XIZ+0x00)
; CHECK: ld a, (xiz+0:8)          ; encoding: [0x8e,0x00,0x21]
ld a, (xiz+0:8)
; unidasm: c5 34 21  ld A,(XBC3+)  -- the one place a bank register is a base
; CHECK: ld a, (xbc3+)            ; encoding: [0xc5,0x34,0x21]
ld a, (xbc3+)
; unidasm: c3 07 f0 f8 21  ld A,(XIX+IZ)  -- a 16-bit INDEX is fine
; CHECK: ld a, (xix+iz)           ; encoding: [0xc3,0x07,0xf0,0xf8,0x21]
ld a, (xix+iz)
; unidasm: b4 d8  jp T,XIX
; CHECK: jp (xix)                 ; encoding: [0xb4,0xd8]
jp (xix)
.else
; --- an 8-bit, 16-bit or previous-bank register as the base ---------------
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'a'
ld a, (a)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'a'
ld a, (a+0:8)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'qiz'
ld a, (qiz+0:8)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'qiz'
lda xwa, (qiz)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'iz'
ld a, (iz+5)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'wa'
ld a, (wa)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'h'
ld a, (h-1)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'hl'
ld a, (hl+3:16)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'b'
inc 1, (b)
; ERR: error: the base of a register-indirect operand is a 32-bit register (xwa..xsp), not 'iz'
ld a, (iz+ix)
; --- a register name where an address or a value is expected -------------
; ERR: error: 'xbc3' is a bank register; the only operands that take one are (xbc3+) and (-xbc3)
ld a, (xbc3)
; ERR: error: 'xwa3' is a bank register; the only operands that take one are (xwa3+) and (-xwa3)
ld a, (xwa3+5)
; ERR: error: 'xhl0' is a bank register; the only operands that take one are (xhl0+) and (-xhl0)
ld a, (xhl0+0:8)
; ERR: error: 'xbc3' is a bank register; the only operands that take one are (xbc3+) and (-xbc3)
ld a, (xbc3+5:16)
; ERR: error: 'xbc3' is a bank register; the only operands that take one are (xbc3+) and (-xbc3)
lda xwa, (xbc3+4)
; ERR: error: 'xsp' is a register, not a symbol: a register is written first inside the parentheses, (xsp+d)
ld a, (5+xsp)
; ERR: error: 'xsp' is a register, not a symbol: a register is written first inside the parentheses, (xsp+d)
ld a, (5+xsp:8)
; ERR: error: 'xde' is a register, not a symbol: a register is written first inside the parentheses, (xde+d)
ld a, (xbc+1+xde)
; ERR: error: 'xbc3' is a bank register; the only operands that take one are (xbc3+) and (-xbc3)
ld xwa, xbc3
.endif
