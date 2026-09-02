; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s \
; RUN:     | llvm-objdump -d - | FileCheck --check-prefix=CHECK-INST %s
;
; `(Xrr+Rn)` -- THE REGISTER-INDEXED MEMORY OPERAND, MODELLED.
;
; This addressing mode had an encoding but no OPERAND: it could only be written
; by naming its bytes -- `ldb_sri L, 0x07, 0xE8, 0xE4`, where 0x07 is the mode
; byte and 0xE8/0xE4 are register-FILE ADDRESSES.  TOOLCHAIN_VERSION UPDATE 8
; made the obvious spelling `ld wa,(xix+iz)` a DIAGNOSTIC rather than let it go
; on silently assembling to the (Xrr+d16) form with the index register
; swallowed as an undefined symbol: d3 f1 00 00 20 where the ROM has
; d3 07 f0 f8 20.  The operand is now its own parser kind, so an index register
; can no longer reach the displacement slot at all -- the confusion is
; structurally impossible rather than diagnosed.
;
; ⚠ Nothing here changes an existing encoding.  `(Xrr+d16)` still needs its
; displacement written as a number and still emits the d16 form; the two guards
; at the bottom pin that.
;
; Every line is REAL ROM BYTES.  Each comment names the committed dump, the
; file offset the bytes sit at, the tree source line that already frames them
; as this instruction, and MAME unidasm's own reading -- a second decoder,
; because a round trip cannot tell an ADD called SUB from an ADD.  Regenerate
; the site list from the kn5000-roms-disasm tree with:
;     python3 scripts/analysis/regindexed_convergence.py --emit
;
; CHECK-INST is what the DISASSEMBLER prints.  It still uses the `*_rr` names
; for the forms that already had them -- no decoder output that existed is
; changed here -- except for the three that previously did not decode at all:
;   * a PREVIOUS-BANK index on the LOAD and STORE sides.  The decoder said "no
;     previous-bank source form exists"; `c3 07 e0 fa 21` is `ld A,(XWA+QIZ)`
;     in unidasm, and hdae5000_utilities.s carries that rendering in a comment.
;   * LDA with an 8-BIT index (mode byte 0x03), which fell out of the R+R
;     decoder: its five bytes came back as three instructions,
;     `<unknown>` + `pop sr` + `st_dpdb`, desynchronising everything after.

; v142/subcpu @0x01AF56 (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:20601  unidasm: jp T,XIX+HL
; CHECK: jp t, (xix+hl) ; encoding: [0xf3,0x07,0xf0,0xec,0xd8]
; CHECK-INST: jp_rr 8, xix, hl
jp t, (xix+hl)

; v142/subcpu @0x028CFD (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:48789  unidasm: ld A,(XWA+QIZ)
; CHECK: ld a, (xwa+qiz) ; encoding: [0xc3,0x07,0xe0,0xfa,0x21]
; CHECK-INST: ld a, (xwa+qiz)
ld a, (xwa+qiz)

; hdae5000 @0x01B0F4 (1 hit)  hdae5000/hdae5000_utilities.s:242  unidasm: ld (XWA+QIZ),C
; CHECK: ld (xwa+qiz), c ; encoding: [0xf3,0x07,0xe0,0xfa,0x43]
; CHECK-INST: ld (xwa+qiz), c
ld (xwa+qiz), c

; subcpu/boot @0x018BF2 (1 hit)  subcpu/boot/kn5000_subcpu_boot.s:2200  unidasm: ld L,(XDE+BC)
; CHECK: ld l, (xde+bc) ; encoding: [0xc3,0x07,0xe8,0xe4,0x27]
; CHECK-INST: ld_rrb l, xde, bc
ld l, (xde+bc)

; v142/subcpu @0x012492 (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:3395  unidasm: ld (XDE+BC),W
; CHECK: ld (xde+bc), w ; encoding: [0xf3,0x07,0xe8,0xe4,0x40]
; CHECK-INST: st_rrb w, xde, bc
ld (xde+bc), w

; v7/maincpu @0x155FE9 (1 hit)  v7/maincpu/sequencer/accompaniment_engine.s:684  unidasm: ld W,(XHL+W)
; CHECK: ld w, (xhl+w) ; encoding: [0xc3,0x03,0xec,0xe1,0x20]
; CHECK-INST: ld_rr8b w, xhl, w
ld w, (xhl+w)

; v7/maincpu @0x164816 (1 hit)  v7/maincpu/sequencer/accompaniment_engine.s:20961  unidasm: ld (XIX+L),H
; CHECK: ld (xix+l), h ; encoding: [0xf3,0x03,0xf0,0xec,0x46]
; CHECK-INST: st_rr8b h, xix, l
ld (xix+l), h

; subcpu/boot @0x018458 (1 hit)  subcpu/boot/kn5000_subcpu_boot.s:755  unidasm: ld XBC,(XDE+BC)
; CHECK: ld xbc, (xde+bc) ; encoding: [0xe3,0x07,0xe8,0xe4,0x21]
; CHECK-INST: ld_rrl xbc, xde, bc
ld xbc, (xde+bc)

; v142/subcpu @0x01C429 (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:23179  unidasm: ld (XIZ+0x0114),XWA
; CHECK: ld (xiz+276), xwa ; encoding: [0xf3,0xf9,0x14,0x01,0x60]
; CHECK-INST: ld (xiz+276), xwa
ld (xiz+276), xwa

; v7/maincpu @0x15910C (1 hit)  v7/maincpu/sequencer/accompaniment_engine.s:5083  unidasm: ld XWA,(XHL+W)
; CHECK: ld xwa, (xhl+w) ; encoding: [0xe3,0x03,0xec,0xe1,0x20]
; CHECK-INST: ld_rr8l xwa, xhl, w
ld xwa, (xhl+w)

; v142/subcpu @0x0132EC (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:4892  unidasm: ld WA,(XIX+HL)
; CHECK: ld wa, (xix+hl) ; encoding: [0xd3,0x07,0xf0,0xec,0x20]
; CHECK-INST: ld_rrw wa, xix, hl
ld wa, (xix+hl)

; v142/subcpu @0x024A98 (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:38987  unidasm: ld (XWA+DE),HL
; CHECK: ld (xwa+de), hl ; encoding: [0xf3,0x07,0xe0,0xe8,0x53]
; CHECK-INST: st_rrw hl, xwa, de
ld (xwa+de), hl

; v9/maincpu @0x155C05 (1 hit)  v9/maincpu/sequencer/accompaniment_engine.s:56  unidasm: ld HL,(XWA+L)
; CHECK: ld hl, (xwa+l) ; encoding: [0xd3,0x03,0xe0,0xec,0x23]
; CHECK-INST: ld_rr8w hl, xwa, l
ld hl, (xwa+l)

; hdae5000 @0x01B339 (1 hit)  hdae5000/hdae5000_utilities.s:478  unidasm: lda XWA,XHL+QIZ
; CHECK: lda xwa, (xhl+qiz) ; encoding: [0xf3,0x07,0xec,0xfa,0x30]
; CHECK-INST: lda_rrq xwa, xhl, qiz
lda xwa, (xhl+qiz)

; subcpu/boot @0x018A15 (1 hit)  subcpu/boot/kn5000_subcpu_boot.s:1784  unidasm: lda XDE,XBC+WA
; CHECK: lda xde, (xbc+wa) ; encoding: [0xf3,0x07,0xe4,0xe0,0x32]
; CHECK-INST: lda_rr xde, xbc, wa
lda xde, (xbc+wa)

; v7/maincpu @0x154CBD (1 hit)  v7/maincpu/sequencer/rhythm_routines.s:461  unidasm: lda XIY,XIY+A
; CHECK: lda xiy, (xiy+a) ; encoding: [0xf3,0x03,0xf4,0xe0,0x35]
; CHECK-INST: lda xiy, (xiy+a)
lda xiy, (xiy+a)

; TOOLCHAIN_VERSION UPDATE 8's own example -- was d3 f1 00 00 20, the (Xrr+d16) form with `iz` swallowed as an undefined symbol
; CHECK: ld wa, (xix+iz) ; encoding: [0xd3,0x07,0xf0,0xf8,0x20]
; CHECK-INST: ld_rrw wa, xix, iz
ld wa, (xix+iz)

; --- GUARDS: the (Xrr+d16) operand is untouched --------------------------
; A DISPLACEMENT is still a displacement.  These encode the mode byte
; 0xE0+base*4+1 and a 16-bit field, and must never become the 0x07 form.
; CHECK: ld xwa, (xsp+276) ; encoding: [0xe3,0xfd,0x14,0x01,0x20]
; CHECK-INST: ld xwa, (xsp+276)
ld xwa, (xsp+276)
; CHECK: lda xwa, (xsp+276) ; encoding: [0xf3,0xfd,0x14,0x01,0x30]
; CHECK-INST: lda xwa, (xsp+276)
lda xwa, (xsp+276)
; CHECK: ld (xsp+276), xwa ; encoding: [0xf3,0xfd,0x14,0x01,0x60]
; CHECK-INST: ld (xsp+276), xwa
ld (xsp+276), xwa
