; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test 8-bit direct addressing mode (D8 prefix).
; F0 = destination direct 8-bit, C0/D0/E0 = source direct 8-bit.
; These access the first 256 bytes of memory (internal RAM / I/O on TLCS-900).

; ==========================================================================
; Source 8-bit direct: LD rd, (addr8) — prefix C0 (byte)
; ==========================================================================

; CHECK: ld_sd8b a, 16           ; encoding: [0xc0,0x10,0x21]
ld_sd8b a, 16

; CHECK: ld_sd8b a, 255          ; encoding: [0xc0,0xff,0x21]
ld_sd8b a, 255

; ==========================================================================
; Source 8-bit direct: ALU operations — prefix C0
; ==========================================================================

; AND (addr8), #imm8: [C0, addr, 0x3C, imm]
; CHECK: and_sd8b_im 16, 255     ; encoding: [0xc0,0x10,0x3c,0xff]
and_sd8b_im 16, 255

; OR (addr8), #imm8: [C0, addr, 0x3E, imm]
; CHECK: or_sd8b_im 16, 128      ; encoding: [0xc0,0x10,0x3e,0x80]
or_sd8b_im 16, 128

; ==========================================================================
; Destination 8-bit direct: LDA rd, addr8 — prefix F0
; ==========================================================================

; LDA XBC, 0x0a: [F0, 0x0A, 0x31]
; CHECK: lda_dd8l xbc, 10        ; encoding: [0xf0,0x0a,0x31]
lda_dd8l xbc, 10

; LDA XWA, 0x08: [F0, 0x08, 0x30]
; CHECK: lda_dd8l xwa, 8         ; encoding: [0xf0,0x08,0x30]
lda_dd8l xwa, 8

; LDA XDE, 0xFF: [F0, 0xFF, 0x32]
; CHECK: lda_dd8l xde, 255       ; encoding: [0xf0,0xff,0x32]
lda_dd8l xde, 255

; ==========================================================================
; Destination 8-bit direct: Store register — prefix F0
; ==========================================================================

; ST_DD8B: LD (addr8), Rb: [F0, addr, 0x40+r]
; CHECK: st_dd8b a, 52           ; encoding: [0xf0,0x34,0x41]
st_dd8b a, 52

; ST_DD8W: LD (addr8), Rw: [F0, addr, 0x50+r]
; CHECK: st_dd8w wa, 52          ; encoding: [0xf0,0x34,0x50]
st_dd8w wa, 52

; CHECK: st_dd8w bc, 10          ; encoding: [0xf0,0x0a,0x51]
st_dd8w bc, 10

; ST_DD8L: LD (addr8), Rl: [F0, addr, 0x60+r]
; CHECK: st_dd8l xbc, 10         ; encoding: [0xf0,0x0a,0x61]
st_dd8l xbc, 10

; CHECK: st_dd8l xwa, 52         ; encoding: [0xf0,0x34,0x60]
st_dd8l xwa, 52

; ==========================================================================
; Destination 8-bit direct: Store immediate — prefix F0
; ==========================================================================

; STIB_DD8: LD (addr8), #imm8: [F0, addr, 0x00, imm]
; CHECK: stib_dd8 41, 64         ; encoding: [0xf0,0x29,0x00,0x40]
stib_dd8 41, 64

; CHECK: stib_dd8 0, 255         ; encoding: [0xf0,0x00,0x00,0xff]
stib_dd8 0, 255

; STIW_DD8: LD (addr8), #imm16: [F0, addr, 0x02, lo, hi]
; CHECK: stiw_dd8 41, 52, 18     ; encoding: [0xf0,0x29,0x02,0x34,0x12]
stiw_dd8 41, 52, 18

; ==========================================================================
; Destination 8-bit direct: Bit operations — prefix F0
; ==========================================================================

; RES bit, (addr8): [F0, addr, 0xB0+bit]
; CHECK: res_dd8 3, 52           ; encoding: [0xf0,0x34,0xb3]
res_dd8 3, 52

; SET bit, (addr8): [F0, addr, 0xB8+bit]
; CHECK: set_dd8 0, 52           ; encoding: [0xf0,0x34,0xb8]
set_dd8 0, 52

; CHECK: set_dd8 7, 255          ; encoding: [0xf0,0xff,0xbf]
set_dd8 7, 255

; BIT bit, (addr8): [F0, addr, 0xC8+bit]
; CHECK: bit_dd8 5, 100          ; encoding: [0xf0,0x64,0xcd]
bit_dd8 5, 100

; CHG bit, (addr8): [F0, addr, 0xC0+bit]
; CHECK: chg_dd8 2, 16           ; encoding: [0xf0,0x10,0xc2]
chg_dd8 2, 16

; TSET bit, (addr8): [F0, addr, 0xA8+bit]
; CHECK: tset_dd8 4, 32          ; encoding: [0xf0,0x20,0xac]
tset_dd8 4, 32

; STCF bit, (addr8): [F0, addr, 0xA0+bit]
; CHECK: stcf_dd8 1, 64          ; encoding: [0xf0,0x40,0xa1]
stcf_dd8 1, 64

; LDCF bit, (addr8): [F0, addr, 0x98+bit]
; CHECK: ldcf_dd8 6, 128         ; encoding: [0xf0,0x80,0x9e]
ldcf_dd8 6, 128

; ==========================================================================
; Destination 8-bit direct: Flag operations — prefix F0
; ==========================================================================

; ANDCF A, (addr8): [F0, addr, 0x28]
; CHECK: andcf_dd8 16            ; encoding: [0xf0,0x10,0x28]
andcf_dd8 16

; ORCF A, (addr8): [F0, addr, 0x29]
; CHECK: orcf_dd8 216            ; encoding: [0xf0,0xd8,0x29]
orcf_dd8 216

; XORCF A, (addr8): [F0, addr, 0x2A]
; CHECK: xorcf_dd8 7             ; encoding: [0xf0,0x07,0x2a]
xorcf_dd8 7

; CHECK: xorcf_dd8 78            ; encoding: [0xf0,0x4e,0x2a]
xorcf_dd8 78

; STCF A, (addr8): [F0, addr, 0x2C]
; CHECK: stcfa_dd8 32            ; encoding: [0xf0,0x20,0x2c]
stcfa_dd8 32

; ==========================================================================
; Destination 8-bit direct: Control flow — prefix F0
; ==========================================================================

; CALL (addr8): [F0, addr, 0x08]
; CHECK: call_dd8 8              ; encoding: [0xf0,0x08,0x08]
call_dd8 8

; JP cc, (addr8): [F0, addr, 0xD0+cc]
; CHECK: jp_dd8 8, 10            ; encoding: [0xf0,0x0a,0xd8]
jp_dd8 8, 10

; CHECK: jp_dd8 0, 255           ; encoding: [0xf0,0xff,0xd0]
jp_dd8 0, 255

; ==========================================================================
; Destination 8-bit direct: Stack operations — prefix F0
; ==========================================================================

; POP byte to (addr8): [F0, addr, 0x04]
; CHECK: popb_dd8 32             ; encoding: [0xf0,0x20,0x04]
popb_dd8 32

; POP word to (addr8): [F0, addr, 0x06]
; CHECK: popw_dd8 32             ; encoding: [0xf0,0x20,0x06]
popw_dd8 32
