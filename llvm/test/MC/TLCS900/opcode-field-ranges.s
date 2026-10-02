; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; Immediates that live in an OPCODE byte's low bits -- a bit number, an
; INC/DEC count, the extended-register 3-bit LD/CP value -- are range-checked
; and must be constants.  Their encoders keep only the low bits, so a value
; that did not fit became another value in silence (wave 3a V1 panel):
; `chg 8, (xbc)` assembled b1 c0 (chg 0), `bit 9, (xde+)` bit 1, `inc 9,
; (xbc)` inc 1, `inc 0x30, wa` inc 8, `ld qde, 8` ld QDE,0; a forward-
; referenced `bit LATER, (xwa)` assembled bit 0.
;
; An INC/DEC count is 1..8: the 3-bit field holds 1..7 and 0 MEANS 8
; (TLCS-900 "#3 = 1-8", MAME's CPU core `m_imm1 ? m_imm1 : 8`), so `inc 8`
; is the spelling and `inc 0` -- the raw field MAME's disassembler prints --
; is refused.  Every encoding below is MAME unidasm's reading of the bytes.

.ifndef ERR
; unidasm: 81 60  inc 0,(XBC)   (count field 0 = 8)
; CHECK: inc 8, (xbc)             ; encoding: [0x81,0x60]
inc 8, (xbc)
; unidasm: d8 61  inc 1,WA
; CHECK: inc 1, wa                ; encoding: [0xd8,0x61]
inc 1, wa
; unidasm: d8 68  dec 0,WA
; CHECK: dec 8, wa                ; encoding: [0xd8,0x68]
dec 8, wa
; unidasm: d7 e2 60  inc 0,QWA
; CHECK: inc 8, qwa               ; encoding: [0xd7,0xe2,0x60]
inc 8, qwa
; unidasm: b1 c7  chg 7,(XBC)
; CHECK: chg 7, (xbc)             ; encoding: [0xb1,0xc7]
chg 7, (xbc)
; unidasm: f5 e8 cf  bit 7,(XDE+)
; CHECK: bit 7, (xde+)            ; encoding: [0xf5,0xe8,0xcf]
bit 7, (xde+)
; unidasm: f1 34 12 bf  set 7,(0x1234)
; CHECK: set 7, (4660:16)         ; encoding: [0xf1,0x34,0x12,0xbf]
set 7, (0x1234:16)
; unidasm: d9 31 0f  set 0x0f,BC
; CHECK: set 15, bc               ; encoding: [0xd9,0x31,0x0f]
set 15, bc
; unidasm: d7 ea af  ld QDE,0x07
; CHECK: ld qde, 7                ; encoding: [0xd7,0xea,0xaf]
ld qde, 7
; unidasm: 06 07  ei 0x07
; CHECK: ei 7                     ; encoding: [0x06,0x07]
ei 7
; unidasm: ff  swi 7
; CHECK: swi 7                    ; encoding: [0xff]
swi 7
; a constant defined BEFORE its use is a constant where it is written
.equ BIT3, 3
; unidasm: b0 cb  bit 3,(XWA)
; CHECK: bit 3, (xwa)             ; encoding: [0xb0,0xcb]
bit BIT3, (xwa)
.else
; ERR: error: 8 does not fit a bit number here (must be 0..7)
chg 8, (xbc)
; ERR: error: 8 does not fit a bit number here (must be 0..7)
tset 8, (xbc)
; ERR: error: 9 does not fit a bit number here (must be 0..7)
bit 9, (xde+)
; ERR: error: 8 does not fit a bit number here (must be 0..7)
ldcf 8, (xbc)
; ERR: error: 8 does not fit a bit number here (must be 0..7)
set 8, (0x1234:16)
; ERR: error: 8 does not fit a bit number here (must be 0..7)
set 8, b
; ERR: error: 16 does not fit a bit number here (must be 0..15)
set 16, bc
; ERR: error: 9 is not an INC/DEC count: the count is 1..8 (8 is encoded as 0)
inc 9, (xbc)
; ERR: error: 0 is not an INC/DEC count: the count is 1..8 (8 is encoded as 0; write `8`, not the raw field 0)
inc 0, (xbc)
; ERR: error: 0 is not an INC/DEC count: the count is 1..8 (8 is encoded as 0; write `8`, not the raw field 0)
dec 0, wa
; ERR: error: 48 is not an INC/DEC count: the count is 1..8 (8 is encoded as 0)
inc 0x30, wa
; ERR: error: 0 is not an INC/DEC count: the count is 1..8 (8 is encoded as 0; write `8`, not the raw field 0)
incw 0, (xwa)
; ERR: error: 9 is not an INC/DEC count: the count is 1..8 (8 is encoded as 0)
inc 9, qwa
; ERR: error: 8 does not fit a 3-bit immediate here (must be 0..7)
ld qde, 8
; ERR: error: 8 does not fit a 3-bit immediate here (must be 0..7)
cp qwa, 8
; EI level / SWI number: 0..7 (`ei 8` assembled 06 08, run as ei 0 by the
; CPU, and decoded back as `ei 0`; `swi 8` assembled f8 = swi 0)
; ERR: error: 8 does not fit a 3-bit immediate here (must be 0..7)
ei 8
; ERR: error: -1 does not fit a 3-bit immediate here (must be 0..7)
ei -1
; ERR: error: 8 does not fit a 3-bit immediate here (must be 0..7)
swi 8
; ERR: error: a bit number lives in the opcode byte and must be a constant known where it is written (no relocation reaches an opcode field)
bit LATER, (xwa)
; ERR: error: an INC/DEC count lives in the opcode byte and must be a constant known where it is written (no relocation reaches an opcode field)
inc LATER, wa
.equ LATER, 5
.endif
