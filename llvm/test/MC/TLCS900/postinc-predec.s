; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s | llvm-objdump -d - | FileCheck --check-prefix=INST %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; POST-INCREMENT `(R+)` and PRE-DECREMENT `(-R)` as a real operand.
;
; The prefixes C5/D5/E5 (source, byte/word/long), F5 (destination) and their
; pre-decrement twins C4/D4/E4/F4 are an ADDRESSING MODE of every memory
; instruction.  The byte after the prefix is a register-file address: bits 7-2
; name the 32-bit register, bits 1-0 the STEP (0 = 1, 1 = 2, 2 = 4).  Written
; without `:N` the step is the instruction's data size; LDA and JP/CALL move no
; data, so they must write it.  Every encoding below is MAME unidasm's reading
; of the same bytes.
;
; ⚠ Two traps this closes.  `ld (xde+),a` used to be a parse error, and
; `ld (+xde),a` / `ld (-xde),a` SILENTLY assembled the ABSOLUTE address of an
; undefined symbol `xde` -- `(+R)` is now a named error, `(-R)` a pre-decrement.

.ifndef ERR
; --- the two instructions whose pseudo names were SWAPPED -----------------
; unidasm: f5 e0 31  lda XBC,XWA+        (was printed `stb_dpi a, 224`)
; CHECK: lda xbc, (xwa+:1)         ; encoding: [0xf5,0xe0,0x31]
; INST:  lda xbc, (xwa+:1)
lda xbc, (xwa+:1)
; unidasm: f5 e8 41  ld (XDE+),A          (was printed `lda_dpi xbc, 232`)
; CHECK: ld (xde+), a              ; encoding: [0xf5,0xe8,0x41]
; INST:  ld (xde+), a
ld (xde+), a
; the byte-copy idiom they formed in the sequencer: ld A,(XBC+) / ld (XDE+),A
; unidasm: c5 e4 21  ld A,(XBC+)
; CHECK: ld a, (xbc+)              ; encoding: [0xc5,0xe4,0x21]
ld a, (xbc+)

; --- LDA with each step, and LDA r16 (no definition existed at all) --------
; unidasm: f5 e1 31  lda XBC,XWA+ ; f5 e2 31  lda XBC,XWA+ (step not shown)
; CHECK: lda xbc, (xwa+:2)         ; encoding: [0xf5,0xe1,0x31]
lda xbc, (xwa+:2)
; CHECK: lda xbc, (xwa+:4)         ; encoding: [0xf5,0xe2,0x31]
lda xbc, (xwa+:4)
; unidasm: f5 e0 21  lda BC,XWA+
; CHECK: lda bc, (xwa+:1)          ; encoding: [0xf5,0xe0,0x21]
; INST:  lda bc, (xwa+:1)
lda bc, (xwa+:1)
; unidasm: f4 e0 31  lda XBC,-XWA
; CHECK: lda xbc, (-xwa:1)         ; encoding: [0xf4,0xe0,0x31]
lda xbc, (-xwa:1)

; --- default step = data size; explicit step when it differs ------------
; unidasm: d5 e9 20  ld WA,(XDE+)
; CHECK: ld wa, (xde+)             ; encoding: [0xd5,0xe9,0x20]
ld wa, (xde+)
; unidasm: e5 ea 20  ld XWA,(XDE+)
; CHECK: ld xwa, (xde+)            ; encoding: [0xe5,0xea,0x20]
ld xwa, (xde+)
; unidasm: f5 e1 51  ld (XWA+),BC
; CHECK: ld (xwa+), bc             ; encoding: [0xf5,0xe1,0x51]
ld (xwa+), bc
; unidasm: f5 e2 61  ld (XWA+),XBC
; CHECK: ld (xwa+), xbc            ; encoding: [0xf5,0xe2,0x61]
ld (xwa+), xbc
; unidasm: f5 e9 41  ld (XDE+),A   -- a byte store stepping by 2
; CHECK: ld (xde+:2), a            ; encoding: [0xf5,0xe9,0x41]
; INST:  ld (xde+:2), a
ld (xde+:2), a

; --- pre-decrement --------------------------------------------------------
; unidasm: f4 e1 51  ld (-XWA),BC
; CHECK: ld (-xwa), bc             ; encoding: [0xf4,0xe1,0x51]
ld (-xwa), bc
; unidasm: c4 ec 21  ld A,(-XHL)
; CHECK: ld a, (-xhl)              ; encoding: [0xc4,0xec,0x21]
ld a, (-xhl)
; unidasm: d4 e1 f0  cp WA,(-XWA)
; CHECK: cp wa, (-xwa)             ; encoding: [0xd4,0xe1,0xf0]
cp wa, (-xwa)

; --- bank registers: the KN5000 SLIDE decompressor walks (XBC3+)/(XDE3+) ---
; unidasm: c5 34 25  ld E,(XBC3+)
; CHECK: ld e, (xbc3+)             ; encoding: [0xc5,0x34,0x25]
; INST:  ld e, (xbc3+)
ld e, (xbc3+)
; unidasm: f5 38 45  ld (XDE3+),E
; CHECK: ld (xde3+), e             ; encoding: [0xf5,0x38,0x45]
ld (xde3+), e

; --- the rest of the memory table reaches the mode for free ---------------
; unidasm: f5 e8 00 12  ld (XDE+),0x12
; CHECK: ld (xde+), 18             ; encoding: [0xf5,0xe8,0x00,0x12]
ld (xde+), 0x12
; unidasm: f5 e1 02 34 12  ld (XWA+),0x1234
; CHECK: ldw (xwa+), 4660          ; encoding: [0xf5,0xe1,0x02,0x34,0x12]
ldw (xwa+), 0x1234
; unidasm: c5 e8 3f 34  cp (XDE+),0x34
; CHECK: cp (xde+), 52             ; encoding: [0xc5,0xe8,0x3f,0x34]
cp (xde+), 0x34
; unidasm: f5 e8 04  pop (XDE+) ; c5 e8 04  push (XDE+)
; CHECK: pop (xde+)                ; encoding: [0xf5,0xe8,0x04]
pop (xde+)
; CHECK: push (xde+)               ; encoding: [0xc5,0xe8,0x04]
push (xde+)
; unidasm: f5 e8 14 34 12  ld (XDE+),(0x1234)
; CHECK: ld (xde+), (4660)         ; encoding: [0xf5,0xe8,0x14,0x34,0x12]
ld (xde+), (0x1234)
; unidasm: f5 e8 d8  jp T,XDE+  -- no data moves, so the step is written
; CHECK: jp t, (xde+:1)            ; encoding: [0xf5,0xe8,0xd8]
jp t, (xde+:1)
; unidasm: c5 e8 30  ex (XDE+),W
; CHECK: ex (xde+), w              ; encoding: [0xc5,0xe8,0x30]
ex (xde+), w

.else
; The pseudo spellings are DELETED -- two of them named the wrong
; instruction (`stb_dpi a, 224` was lda XBC,(XWA+)).
; ERR: error: unrecognized instruction mnemonic
stb_dpi a, 224
; ERR: error: unrecognized instruction mnemonic
lda_dpi xbc, 232
; ERR: error: unrecognized instruction mnemonic
ldb_spi a, 232
; ERR: error: '(+xde)' is not a TLCS-900 addressing mode: post-increment is written (xde+), pre-decrement (-xde)
ld (+xde), a
; ERR: error: '(xde-)' is not a TLCS-900 addressing mode: there is no post-decrement; pre-decrement is written (-xde)
ld (xde-), a
; ERR: error: the base of a post-increment / pre-decrement operand is a 32-bit register (xwa..xsp, or xwa0..xhl3 in banks 0-3), not 'de'
ld (de+), a
; ERR: error: a post-increment / pre-decrement step is 1, 2 or 4
ld (xde+:3), a
; ERR: error: this instruction moves no data through its post-increment / pre-decrement operand, so the step must be written: (R+:1), (R+:2) or (R+:4)
lda xbc, (xwa+)
; ERR: error: this instruction form (LD_SRIB_D16) has no post-increment / pre-decrement operand
ldb_sri0 a, (xde+)
.endif
