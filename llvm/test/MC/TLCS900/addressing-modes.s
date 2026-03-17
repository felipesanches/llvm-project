; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test addressing modes: (R), (R+d8), (R+d16), (N) direct, with all
; operand sizes (8/16/32-bit) for loads, stores, and ALU operations.

; ==========================================================================
; 32-bit register indirect: LD rd32, (Xrr)
; ==========================================================================

; A0+base, 0x20+dst
; CHECK: ld xwa, (xsp)      ; encoding: [0xa7,0x20]
ld xwa, (xsp)
; CHECK: ld xde, (xhl)      ; encoding: [0xa3,0x22]
ld xde, (xhl)
; CHECK: ld xbc, (xix)      ; encoding: [0xa4,0x21]
ld xbc, (xix)

; ==========================================================================
; 32-bit register indirect + d8: LD rd32, (Xrr+d8)
; ==========================================================================

; A8+base, d8, 0x20+dst
; CHECK: ld xde, (xsp+4)    ; encoding: [0xaf,0x04,0x22]
ld xde, (xsp+4)
; CHECK: ld xbc, (xhl+100)  ; encoding: [0xab,0x64,0x21]
ld xbc, (xhl+100)
; CHECK: ld xwa, (xix+127)  ; encoding: [0xac,0x7f,0x20]
ld xwa, (xix+127)

; Negative displacement (signed d8)
; CHECK: ld xwa, (xsp-4)    ; encoding: [0xaf,0xfc,0x20]
ld xwa, (xsp-4)
; CHECK: ld xwa, (xsp-128)  ; encoding: [0xaf,0x80,0x20]
ld xwa, (xsp-128)

; ==========================================================================
; 32-bit register indirect + d16: LD rd32, (Xrr+d16)
; Uses SRI prefix: E3/D3/C3 for 32/16/8 bit
; ==========================================================================

; CHECK: ld xwa, (xix+1000) ; encoding: [0xe3,0xf1,0xe8,0x03,0x20]
ld xwa, (xix+1000)

; ==========================================================================
; 32-bit store: LD (Xrr), rs32 and LD (Xrr+d8), rs32
; ==========================================================================

; B0+base, 0x60+src
; CHECK: ld (xsp), xwa      ; encoding: [0xb7,0x60]
ld (xsp), xwa
; CHECK: ld (xhl), xde      ; encoding: [0xb3,0x62]
ld (xhl), xde

; B8+base, d8, 0x60+src
; CHECK: ld (xsp+8), xwa    ; encoding: [0xbf,0x08,0x60]
ld (xsp+8), xwa
; CHECK: ld (xiy+16), xde   ; encoding: [0xbd,0x10,0x62]
ld (xiy+16), xde

; Negative displacement
; CHECK: ld (xsp-8), xde    ; encoding: [0xbf,0xf8,0x62]
ld (xsp-8), xde

; ==========================================================================
; 32-bit store + d16
; ==========================================================================

; CHECK: ld (xsp+1000), xwa ; encoding: [0xf3,0xfd,0xe8,0x03,0x60]
ld (xsp+1000), xwa

; ==========================================================================
; 8-bit memory load: LD rd8, (Xrr) and LD rd8, (Xrr+d8)
; ==========================================================================

; 0x80+base (byte src prefix), 0x20+dst_enc
; CHECK: ld a, (xhl)        ; encoding: [0x83,0x21]
ld a, (xhl)
; CHECK: ld c, (xde)        ; encoding: [0x82,0x23]
ld c, (xde)
; CHECK: ld w, (xbc)        ; encoding: [0x81,0x20]
ld w, (xbc)

; 0x88+base (byte src d8 prefix), d8, 0x20+dst_enc
; CHECK: ld e, (xsp+4)      ; encoding: [0x8f,0x04,0x25]
ld e, (xsp+4)
; CHECK: ld a, (xix+10)     ; encoding: [0x8c,0x0a,0x21]
ld a, (xix+10)

; ==========================================================================
; 8-bit memory load + d16
; ==========================================================================

; CHECK: ld a, (xhl+256)    ; encoding: [0x8b,0x00,0x21]
ld a, (xhl+256)
; CHECK: ld a, (xhl+1000)   ; encoding: [0xc3,0xed,0xe8,0x03,0x21]
ld a, (xhl+1000)

; ==========================================================================
; 8-bit memory store: LD (Xrr), rd8 and LD (Xrr+d8), rd8
; ==========================================================================

; B0+base, 0x40+src_enc
; CHECK: ld (xhl), a        ; encoding: [0xb3,0x41]
ld (xhl), a
; CHECK: ld (xde), c        ; encoding: [0xb2,0x43]
ld (xde), c

; B8+base, d8, 0x40+src_enc
; CHECK: ld (xsp+8), l      ; encoding: [0xbf,0x08,0x47]
ld (xsp+8), l
; CHECK: ld (xiy+10), b     ; encoding: [0xbd,0x0a,0x42]
ld (xiy+10), b

; ==========================================================================
; 8-bit memory store + d16
; ==========================================================================

; CHECK: ld (xhl+1000), a   ; encoding: [0xf3,0xed,0xe8,0x03,0x41]
ld (xhl+1000), a

; ==========================================================================
; 16-bit memory load: LD rd16, (Xrr) and LD rd16, (Xrr+d8)
; ==========================================================================

; 0x90+base (word src prefix), 0x20+dst_enc
; CHECK: ld de, (xhl)       ; encoding: [0x93,0x22]
ld de, (xhl)
; CHECK: ld wa, (xsp+4)     ; encoding: [0x9f,0x04,0x20]
ld wa, (xsp+4)

; ==========================================================================
; 16-bit memory load + d16
; ==========================================================================

; CHECK: ld wa, (xhl+1000)  ; encoding: [0xd3,0xed,0xe8,0x03,0x20]
ld wa, (xhl+1000)

; ==========================================================================
; 16-bit memory store: LD (Xrr), rd16 and LD (Xrr+d8), rd16
; ==========================================================================

; B0+base, 0x50+src_enc
; CHECK: ld (xhl), bc       ; encoding: [0xb3,0x51]
ld (xhl), bc
; CHECK: ld (xsp+8), de     ; encoding: [0xbf,0x08,0x52]
ld (xsp+8), de

; ==========================================================================
; 16-bit memory store + d16
; ==========================================================================

; CHECK: ld (xhl+1000), wa  ; encoding: [0xf3,0xed,0xe8,0x03,0x50]
ld (xhl+1000), wa

; ==========================================================================
; Direct memory addressing (absolute address)
; ==========================================================================

; LD (nn), rs32: F2, addr24, 0x60+src
; CHECK: ld (0), xwa        ; encoding: [0xf2,A,A,A,0x60]
ld (0), xwa
; CHECK: ld (4660), xwa     ; encoding: [0xf2,A,A,A,0x60]
ld (0x1234), xwa

; LD rd32, (nn): E2, addr24, 0x20+dst
; CHECK: ld xwa, (22136)    ; encoding: [0xe2,A,A,A,0x20]
ld xwa, (0x5678)

; ==========================================================================
; Load effective address: LDA rd, (Xrr) / LDA rd, (Xrr+d8)
; ==========================================================================

; LDA rd, (Xrr): B0+base, 0x30+dst
; CHECK: lda xde, (xhl)     ; encoding: [0xb3,0x32]
lda xde, (xhl)

; LDA rd, (Xrr+d8): B8+base, d8, 0x30+dst
; CHECK: lda xwa, (xsp+64)  ; encoding: [0xbf,0x40,0x30]
lda xwa, (xsp+64)
; CHECK: lda xde, (xsp+16)  ; encoding: [0xbf,0x10,0x32]
lda xde, (xsp+16)

; LDA rd, (nn): F2, addr24, 0x30+dst
; CHECK: lda xwa, (1193046) ; encoding: [0xf2,A,A,A,0x30]
lda xwa, (0x123456)

; ==========================================================================
; Memory ALU (32-bit): op (Xrr), rs32
; ==========================================================================

; ADD (Xrr), rs: A0+base, 0x88+src
; CHECK: add (xhl), xwa     ; encoding: [0xa3,0x88]
add (xhl), xwa

; SUB (Xrr+d8), rs: A8+base, d8, 0xA8+src
; CHECK: sub (xsp+4), xde   ; encoding: [0xaf,0x04,0xaa]
sub (xsp+4), xde

; AND (Xrr), rs: A0+base, 0xC8+src
; CHECK: and (xix), xbc     ; encoding: [0xa4,0xc9]
and (xix), xbc

; OR (Xrr+d8), rs: A8+base, d8, 0xE8+src
; CHECK: or (xiy+8), xwa    ; encoding: [0xad,0x08,0xe8]
or (xiy+8), xwa

; XOR (Xrr+d8), rs: A8+base, d8, 0xD8+src
; CHECK: xor (xhl+2), xde   ; encoding: [0xab,0x02,0xda]
xor (xhl+2), xde

; CP (Xrr), rs: A0+base, 0xF8+src
; CHECK: cp (xhl), xwa      ; encoding: [0xa3,0xf8]
cp (xhl), xwa

; ==========================================================================
; Memory ALU (8-bit): op (Xrr), rd8
; ==========================================================================

; CHECK: add (xhl), a       ; encoding: [0x83,0x89]
add (xhl), a
; CHECK: sub (xhl), a       ; encoding: [0x83,0xa9]
sub (xhl), a
; CHECK: and (xhl), a       ; encoding: [0x83,0xc9]
and (xhl), a
; CHECK: or (xhl), a        ; encoding: [0x83,0xe9]
or (xhl), a
; CHECK: xor (xhl), a       ; encoding: [0x83,0xd9]
xor (xhl), a
; CHECK: cp (xhl), a        ; encoding: [0x83,0xf9]
cp (xhl), a

; ==========================================================================
; Memory ALU (16-bit): op (Xrr), rd16
; ==========================================================================

; CHECK: add (xhl), wa      ; encoding: [0x93,0x88]
add (xhl), wa
; CHECK: sub (xhl), wa      ; encoding: [0x93,0xa8]
sub (xhl), wa
; CHECK: cp (xhl), wa       ; encoding: [0x93,0xf8]
cp (xhl), wa

; ==========================================================================
; Memory compare with immediate (8-bit only)
; ==========================================================================

; CP (Xrr), #imm8: 0x83 src prefix, 0x3F, imm8
; CHECK: cp (xhl), 42       ; encoding: [0x83,0x3f,0x2a]
cp (xhl), 42

; ANDMI8 — AND memory immediate (8-bit)
; CHECK: andmi8 (xhl), 42   ; encoding: [0x83,0x3c,0x2a]
andmi8 (xhl), 42
