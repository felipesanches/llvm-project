; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Instruction forms that the KN5000 sub-CPU sound firmware contains and that
; had no spelling here.  Every encoding below is read off the ROM images in
; kn5000-roms-disasm (the v1.42 sub-CPU payload unless noted), with MAME's
; unidasm rendering quoted beside it, and is byte-for-byte what the assembler
; has to reproduce for those bytes to leave the source as instructions.

; ==========================================================================
; CP (mem), #imm8 -- sub-opcode 0x3F, the one member of the
; ADD/ADC/SUB/SBC/AND/XOR/OR/CP row (0x38..0x3F) with no def, in both the
; (Xrr) and the (Xrr+d8) prefix table.
; ==========================================================================

; unidasm: cp (XIZ),0x40
; CHECK: cp8_imm_ri xiz, 64             ; encoding: [0x86,0x3f,0x40]
cp8_imm_ri xiz, 0x40
; unidasm: cp (XWA),0x40
; CHECK: cp8_imm_ri xwa, 64             ; encoding: [0x80,0x3f,0x40]
cp8_imm_ri xwa, 0x40
; unidasm: cp (XWA+0x02),0x00
; CHECK: cp8_imm_rid8 xwa, 2, 0         ; encoding: [0x88,0x02,0x3f,0x00]
cp8_imm_rid8 xwa, 2, 0
; unidasm: cp (XSP+0x06),0x00
; CHECK: cp8_imm_rid8 xsp, 6, 0         ; encoding: [0x8f,0x06,0x3f,0x00]
cp8_imm_rid8 xsp, 6, 0

; ==========================================================================
; ALU r32, (mem) -- the r,(mem) direction of the LONG table (A0/A8) had no
; def at any sub-opcode.  All 25 sites are stack-frame arithmetic.
; ==========================================================================

; unidasm: add XWA,(XSP)
; CHECK: add32_src_ri xsp, xwa          ; encoding: [0xa7,0x80]
add32_src_ri xsp, xwa
; unidasm: add XWA,(XSP+0x04)
; CHECK: add32_src_rid8 xsp, 4, xwa     ; encoding: [0xaf,0x04,0x80]
add32_src_rid8 xsp, 4, xwa
; unidasm: add XIX,(XSP+0x04)
; CHECK: add32_src_rid8 xsp, 4, xix     ; encoding: [0xaf,0x04,0x84]
add32_src_rid8 xsp, 4, xix
; unidasm: cp IX,(XDE+0xfa)
; CHECK: cp16_src_rid8 xde, 250, ix     ; encoding: [0x9a,0xfa,0xf4]
cp16_src_rid8 xde, 0xfa, ix

; ==========================================================================
; Register-indexed (Xrr+Rn) with an immediate, and with a previous-bank index.
; ==========================================================================

; unidasm: or (XBC+WA),0x0008
; CHECK: or_rrw_im xbc, wa, 8, 0        ; encoding: [0xd3,0x07,0xe4,0xe0,0x3e,0x08,0x00]
or_rrw_im xbc, wa, 0x08, 0x00
; unidasm: lda XIZ,XBC+QWA
; CHECK: lda_rrq xiz, xbc, qwa          ; encoding: [0xf3,0x07,0xe4,0xe2,0x36]
lda_rrq xiz, xbc, qwa
; unidasm: lda XBC,XBC+QWA
; CHECK: lda_rrq xbc, xbc, qwa          ; encoding: [0xf3,0x07,0xe4,0xe2,0x31]
lda_rrq xbc, xbc, qwa

; ==========================================================================
; The 8-bit index register's FILE ADDRESS.  The register file is byte-
; addressed and little-endian, so a word register's low half is at offset 0:
; A=0xE0, W=0xE1.  This was emitted the other way round.  The KN5000 v10
; maincpu MIDI dispatcher indexes by A (it loads A, masks it and shifts it
; left one immediately before), and the ROM byte there is 0xE0.
; ==========================================================================

; unidasm: ld BC,(XIX+A)
; CHECK: ld_rr8w bc, xix, a             ; encoding: [0xd3,0x03,0xf0,0xe0,0x21]
ld_rr8w bc, xix, a
; unidasm: ld BC,(XIX+W)
; CHECK: ld_rr8w bc, xix, w             ; encoding: [0xd3,0x03,0xf0,0xe1,0x21]
ld_rr8w bc, xix, w
; unidasm: ld BC,(XIX+L)
; CHECK: ld_rr8w bc, xix, l             ; encoding: [0xd3,0x03,0xf0,0xec,0x21]
ld_rr8w bc, xix, l
; unidasm: ld BC,(XIX+H)
; CHECK: ld_rr8w bc, xix, h             ; encoding: [0xd3,0x03,0xf0,0xed,0x21]
ld_rr8w bc, xix, h
