; RUN: llvm-mc --triple=tlcs900 --show-encoding %s | FileCheck %s
; RUN: llvm-mc --triple=tlcs900 --show-encoding %s | \
; RUN:   sed -n 's/.*encoding: \[\(.*\)\]/\1/p' | \
; RUN:   sed 's/,/ /g' | \
; RUN:   llvm-mc --triple=tlcs900 --disassemble | \
; RUN:   FileCheck %s --check-prefix=DISASM

; Test post-increment (SPI) and pre-decrement (SPD) addressing modes.
; SPI source: C5 (byte), D5 (word), E5 (long)
; SPD source: C4 (byte), D4 (word), E4 (long)
; DPI dest:   F5
; DPD dest:   F4

; ======= SPI Byte (prefix C5) =======

; --- Load ---
; CHECK: ld_spib a, 224 ; encoding: [0xc5,0xe0,0x21]
; DISASM: ld_spib a, 224
ld_spib A, 0xe0

; --- ALU reg,(mem) ---
; CHECK: add_spib c, 236 ; encoding: [0xc5,0xec,0x83]
; DISASM: add_spib c, 236
add_spib C, 0xec

; CHECK: adc_spib a, 224 ; encoding: [0xc5,0xe0,0x91]
; DISASM: adc_spib a, 224
adc_spib A, 0xe0

; CHECK: sub_spib a, 224 ; encoding: [0xc5,0xe0,0xa1]
; DISASM: sub_spib a, 224
sub_spib A, 0xe0

; CHECK: sbc_spib b, 228 ; encoding: [0xc5,0xe4,0xb2]
; DISASM: sbc_spib b, 228
sbc_spib B, 0xe4

; CHECK: and_spib a, 240 ; encoding: [0xc5,0xf0,0xc1]
; DISASM: and_spib a, 240
and_spib A, 0xf0

; CHECK: xor_spib a, 224 ; encoding: [0xc5,0xe0,0xd1]
; DISASM: xor_spib a, 224
xor_spib A, 0xe0

; CHECK: or_spib_rm a, 228 ; encoding: [0xc5,0xe4,0xe1]
; DISASM: or_spib_rm a, 228
or_spib_rm A, 0xe4

; CHECK: cp_spib a, 244 ; encoding: [0xc5,0xf4,0xf1]
; DISASM: cp_spib a, 244
cp_spib A, 0xf4

; --- ALU (mem),reg ---
; CHECK: add_spib_mr c, 228 ; encoding: [0xc5,0xe4,0x8b]
; DISASM: add_spib_mr c, 228
add_spib_mr C, 0xe4

; CHECK: sub_spib_mr a, 224 ; encoding: [0xc5,0xe0,0xa9]
; DISASM: sub_spib_mr a, 224
sub_spib_mr A, 0xe0

; CHECK: cp_spib_mr b, 236 ; encoding: [0xc5,0xec,0xfa]
; DISASM: cp_spib_mr b, 236
cp_spib_mr B, 0xec

; --- ALU (mem),#imm ---
; CHECK: cp_spib_im 224, 48 ; encoding: [0xc5,0xe0,0x3f,0x30]
; DISASM: cp_spib_im 224, 48
cp_spib_im 0xe0, 0x30

; CHECK: add_spib_im 224, 5 ; encoding: [0xc5,0xe0,0x38,0x05]
; DISASM: add_spib_im 224, 5
add_spib_im 0xe0, 0x05

; CHECK: and_spib_im 236, 15 ; encoding: [0xc5,0xec,0x3c,0x0f]
; DISASM: and_spib_im 236, 15
and_spib_im 0xec, 0x0f

; CHECK: or_spib_im 224, 128 ; encoding: [0xc5,0xe0,0x3e,0x80]
; DISASM: or_spib_im 224, 128
or_spib_im 0xe0, 0x80

; --- INC/DEC ---
; CHECK: inc_spib 3, 224 ; encoding: [0xc5,0xe0,0x63]
; DISASM: inc_spib 3, 224
inc_spib 3, 0xe0

; CHECK: dec_spib 1, 240 ; encoding: [0xc5,0xf0,0x69]
; DISASM: dec_spib 1, 240
dec_spib 1, 0xf0

; --- PUSH ---
; CHECK: push_spib 224 ; encoding: [0xc5,0xe0,0x04]
; DISASM: push_spib 224
push_spib 0xe0

; ======= SPI Word (prefix D5) =======

; CHECK: ld_spiw de, 237 ; encoding: [0xd5,0xed,0x22]
; DISASM: ld_spiw de, 237
ld_spiw DE, 0xed

; CHECK: add_spiw de, 225 ; encoding: [0xd5,0xe1,0x82]
; DISASM: add_spiw de, 225
add_spiw DE, 0xe1

; CHECK: cp_spiw wa, 224 ; encoding: [0xd5,0xe0,0xf0]
; DISASM: cp_spiw wa, 224
cp_spiw WA, 0xe0

; CHECK: cpm_spiw wa, 224 ; encoding: [0xd5,0xe0,0xf8]
; DISASM: cpm_spiw wa, 224
cpm_spiw WA, 0xe0

; CHECK: cp_spiw_im 224, 18, 52 ; encoding: [0xd5,0xe0,0x3f,0x12,0x34]
; DISASM: cp_spiw_im 224, 18, 52
cp_spiw_im 0xe0, 0x12, 0x34

; CHECK: add_spiw_mr de, 225 ; encoding: [0xd5,0xe1,0x8a]
; DISASM: add_spiw_mr de, 225
add_spiw_mr DE, 0xe1

; CHECK: inc_spiw 2, 224 ; encoding: [0xd5,0xe0,0x62]
; DISASM: inc_spiw 2, 224
inc_spiw 2, 0xe0

; CHECK: push_spiw 228 ; encoding: [0xd5,0xe4,0x04]
; DISASM: push_spiw 228
push_spiw 0xe4

; ======= SPI Long (prefix E5) =======

; CHECK: ld_spil xbc, 224 ; encoding: [0xe5,0xe0,0x21]
; DISASM: ld_spil xbc, 224
ld_spil XBC, 0xe0

; CHECK: add_spil xwa, 232 ; encoding: [0xe5,0xe8,0x80]
; DISASM: add_spil xwa, 232
add_spil XWA, 0xe8

; CHECK: cp_spil xbc, 224 ; encoding: [0xe5,0xe0,0xf1]
; DISASM: cp_spil xbc, 224
cp_spil XBC, 0xe0

; ======= SPD Byte (prefix C4) =======

; CHECK: ld_spdb a, 224 ; encoding: [0xc4,0xe0,0x21]
; DISASM: ld_spdb a, 224
ld_spdb A, 0xe0

; CHECK: cp_spdb a, 224 ; encoding: [0xc4,0xe0,0xf1]
; DISASM: cp_spdb a, 224
cp_spdb A, 0xe0

; CHECK: cp_spdb_im 224, 66 ; encoding: [0xc4,0xe0,0x3f,0x42]
; DISASM: cp_spdb_im 224, 66
cp_spdb_im 0xe0, 0x42

; CHECK: push_spdb 224 ; encoding: [0xc4,0xe0,0x04]
; DISASM: push_spdb 224
push_spdb 0xe0

; ======= SPD Word (prefix D4) =======

; CHECK: ld_spdw de, 224 ; encoding: [0xd4,0xe0,0x22]
; DISASM: ld_spdw de, 224
ld_spdw DE, 0xe0

; ======= DPI (prefix F5) =======

; CHECK: st_dpib a, 226 ; encoding: [0xf5,0xe2,0x31]
; DISASM: st_dpib a, 226
st_dpib A, 0xe2

; CHECK: st_dpiw ix, 237 ; encoding: [0xf5,0xed,0x54]
; DISASM: st_dpiw ix, 237
st_dpiw IX, 0xed

; CHECK: st_dpil xbc, 224 ; encoding: [0xf5,0xe0,0x61]
; DISASM: st_dpil xbc, 224
st_dpil XBC, 0xe0

; CHECK: lda_dpi xbc, 224 ; encoding: [0xf5,0xe0,0x41]
; DISASM: lda_dpi xbc, 224
lda_dpi XBC, 0xe0

; CHECK: stib_dpi 224, 42 ; encoding: [0xf5,0xe0,0x00,0x2a]
; DISASM: stib_dpi 224, 42
stib_dpi 0xe0, 0x2a

; CHECK: popb_dpi 224 ; encoding: [0xf5,0xe0,0x04]
; DISASM: popb_dpi 224
popb_dpi 0xe0

; CHECK: popw_dpi 224 ; encoding: [0xf5,0xe0,0x06]
; DISASM: popw_dpi 224
popw_dpi 0xe0

; ======= DPD (prefix F4) =======

; CHECK: st_dpdb a, 224 ; encoding: [0xf4,0xe0,0x31]
; DISASM: st_dpdb a, 224
st_dpdb A, 0xe0

; CHECK: st_dpdw wa, 224 ; encoding: [0xf4,0xe0,0x50]
; DISASM: st_dpdw wa, 224
st_dpdw WA, 0xe0

; CHECK: lda_dpd xwa, 228 ; encoding: [0xf4,0xe4,0x40]
; DISASM: lda_dpd xwa, 228
lda_dpd XWA, 0xe4

; CHECK: stib_dpd 224, 99 ; encoding: [0xf4,0xe0,0x00,0x63]
; DISASM: stib_dpd 224, 99
stib_dpd 0xe0, 0x63

; CHECK: popb_dpd 224 ; encoding: [0xf4,0xe0,0x04]
; DISASM: popb_dpd 224
popb_dpd 0xe0
