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
;
; ★ UPDATE 17: these cases were written with the pseudo-instructions
; (ldb_spi, stb_dpi, ...), which are DELETED; each input is now the real
; instruction with a `(R+)` / `(-R)` operand, rewritten by kn5000-roms-disasm
; scripts/converters/wave3a_respell.py (autoinc) and keeping every encoding.
; Two of the pseudos were the WRONG instruction: `stb_dpi` (F5 0x30+r) is
; LDA r32 and `lda_dpi` (F5 0x40+r) is LD (mem),r8 -- see postinc-predec.s.

; ======= SPI Byte (prefix C5) =======

; --- Load ---
; CHECK: ld a, (xwa+) ; encoding: [0xc5,0xe0,0x21]
; DISASM: ld a, (xwa+)
ld A, (xwa+)

; --- ALU reg,(mem) ---
; CHECK: add c, (xhl+) ; encoding: [0xc5,0xec,0x83]
; DISASM: add c, (xhl+)
add C, (xhl+)

; CHECK: adc a, (xwa+) ; encoding: [0xc5,0xe0,0x91]
; DISASM: adc a, (xwa+)
adc A, (xwa+)

; CHECK: sub a, (xwa+) ; encoding: [0xc5,0xe0,0xa1]
; DISASM: sub a, (xwa+)
sub A, (xwa+)

; CHECK: sbc b, (xbc+) ; encoding: [0xc5,0xe4,0xb2]
; DISASM: sbc b, (xbc+)
sbc B, (xbc+)

; CHECK: and a, (xix+) ; encoding: [0xc5,0xf0,0xc1]
; DISASM: and a, (xix+)
and A, (xix+)

; CHECK: xor a, (xwa+) ; encoding: [0xc5,0xe0,0xd1]
; DISASM: xor a, (xwa+)
xor A, (xwa+)

; CHECK: or a, (xbc+) ; encoding: [0xc5,0xe4,0xe1]
; DISASM: or a, (xbc+)
or A, (xbc+)

; CHECK: cp a, (xiy+) ; encoding: [0xc5,0xf4,0xf1]
; DISASM: cp a, (xiy+)
cp A, (xiy+)

; --- ALU (mem),reg ---
; CHECK: add (xbc+), c ; encoding: [0xc5,0xe4,0x8b]
; DISASM: add (xbc+), c
add (xbc+), C

; CHECK: sub (xwa+), a ; encoding: [0xc5,0xe0,0xa9]
; DISASM: sub (xwa+), a
sub (xwa+), A

; CHECK: cp (xhl+), b ; encoding: [0xc5,0xec,0xfa]
; DISASM: cp (xhl+), b
cp (xhl+), B

; --- ALU (mem),#imm ---
; CHECK: cp (xwa+), 48 ; encoding: [0xc5,0xe0,0x3f,0x30]
; DISASM: cp (xwa+), 48
cp (xwa+), 0x30

; CHECK: add (xwa+), 5 ; encoding: [0xc5,0xe0,0x38,0x05]
; DISASM: add (xwa+), 5
add (xwa+), 0x05

; CHECK: and (xhl+), 15 ; encoding: [0xc5,0xec,0x3c,0x0f]
; DISASM: and (xhl+), 15
and (xhl+), 0x0f

; CHECK: or (xwa+), 128 ; encoding: [0xc5,0xe0,0x3e,0x80]
; DISASM: or (xwa+), 128
or (xwa+), 0x80

; --- INC/DEC ---
; CHECK: inc 3, (xwa+) ; encoding: [0xc5,0xe0,0x63]
; DISASM: inc 3, (xwa+)
inc 3, (xwa+)

; CHECK: dec 1, (xix+) ; encoding: [0xc5,0xf0,0x69]
; DISASM: dec 1, (xix+)
dec 1, (xix+)

; --- PUSH ---
; CHECK: push (xwa+) ; encoding: [0xc5,0xe0,0x04]
; DISASM: push (xwa+)
push (xwa+)

; ======= SPI Word (prefix D5) =======

; CHECK: ld de, (xhl+) ; encoding: [0xd5,0xed,0x22]
; DISASM: ld de, (xhl+)
ld DE, (xhl+)

; CHECK: add de, (xwa+) ; encoding: [0xd5,0xe1,0x82]
; DISASM: add de, (xwa+)
add DE, (xwa+)

; CHECK: cp wa, (xwa+:1) ; encoding: [0xd5,0xe0,0xf0]
; DISASM: cp wa, (xwa+:1)
cp WA, (xwa+:1)

; CHECK: cp (xwa+:1), wa ; encoding: [0xd5,0xe0,0xf8]
; DISASM: cp (xwa+:1), wa
cp (xwa+:1), WA

; CHECK: cpw (xwa+:1), 13330 ; encoding: [0xd5,0xe0,0x3f,0x12,0x34]
; DISASM: cpw (xwa+:1), 13330
cpw (xwa+:1), 0x3412

; CHECK: add (xwa+), de ; encoding: [0xd5,0xe1,0x8a]
; DISASM: add (xwa+), de
add (xwa+), DE

; CHECK: incw 2, (xwa+:1) ; encoding: [0xd5,0xe0,0x62]
; DISASM: incw 2, (xwa+:1)
incw 2, (xwa+:1)

; CHECK: pushw (xbc+:1) ; encoding: [0xd5,0xe4,0x04]
; DISASM: pushw (xbc+:1)
pushw (xbc+:1)

; ======= SPI Long (prefix E5) =======

; CHECK: ld xbc, (xwa+:1) ; encoding: [0xe5,0xe0,0x21]
; DISASM: ld xbc, (xwa+:1)
ld XBC, (xwa+:1)

; CHECK: add xwa, (xde+:1) ; encoding: [0xe5,0xe8,0x80]
; DISASM: add xwa, (xde+:1)
add XWA, (xde+:1)

; CHECK: cp xbc, (xwa+:1) ; encoding: [0xe5,0xe0,0xf1]
; DISASM: cp xbc, (xwa+:1)
cp XBC, (xwa+:1)

; ======= SPD Byte (prefix C4) =======

; CHECK: ld a, (-xwa) ; encoding: [0xc4,0xe0,0x21]
; DISASM: ld a, (-xwa)
ld A, (-xwa)

; CHECK: cp a, (-xwa) ; encoding: [0xc4,0xe0,0xf1]
; DISASM: cp a, (-xwa)
cp A, (-xwa)

; CHECK: cp (-xwa), 66 ; encoding: [0xc4,0xe0,0x3f,0x42]
; DISASM: cp (-xwa), 66
cp (-xwa), 0x42

; CHECK: push (-xwa) ; encoding: [0xc4,0xe0,0x04]
; DISASM: push (-xwa)
push (-xwa)

; ======= SPD Word (prefix D4) =======

; CHECK: ld de, (-xwa:1) ; encoding: [0xd4,0xe0,0x22]
; DISASM: ld de, (-xwa:1)
ld DE, (-xwa:1)

; ======= DPI (prefix F5) =======

; CHECK: lda xbc, (xwa+:4) ; encoding: [0xf5,0xe2,0x31]
; DISASM: lda xbc, (xwa+:4)
lda xbc, (xwa+:4)

; CHECK: ld (xhl+), ix ; encoding: [0xf5,0xed,0x54]
; DISASM: ld (xhl+), ix
ld (xhl+), IX

; CHECK: ld (xwa+:1), xbc ; encoding: [0xf5,0xe0,0x61]
; DISASM: ld (xwa+:1), xbc
ld (xwa+:1), XBC

; CHECK: ld (xwa+), a ; encoding: [0xf5,0xe0,0x41]
; DISASM: ld (xwa+), a
ld (xwa+), a

; CHECK: ld (xwa+), 42 ; encoding: [0xf5,0xe0,0x00,0x2a]
; DISASM: ld (xwa+), 42
ld (xwa+), 0x2a

; CHECK: pop (xwa+) ; encoding: [0xf5,0xe0,0x04]
; DISASM: pop (xwa+)
pop (xwa+)

; CHECK: popw (xwa+:1) ; encoding: [0xf5,0xe0,0x06]
; DISASM: popw (xwa+:1)
popw (xwa+:1)

; ======= DPD (prefix F4) =======

; CHECK: lda xbc, (-xwa:1) ; encoding: [0xf4,0xe0,0x31]
; DISASM: lda xbc, (-xwa:1)
lda xbc, (-xwa:1)

; CHECK: ld (-xwa:1), wa ; encoding: [0xf4,0xe0,0x50]
; DISASM: ld (-xwa:1), wa
ld (-xwa:1), WA

; CHECK: ld (-xbc), w ; encoding: [0xf4,0xe4,0x40]
; DISASM: ld (-xbc), w
ld (-xbc), w

; CHECK: ld (-xwa), 99 ; encoding: [0xf4,0xe0,0x00,0x63]
; DISASM: ld (-xwa), 99
ld (-xwa), 0x63

; CHECK: pop (-xwa) ; encoding: [0xf4,0xe0,0x04]
; DISASM: pop (-xwa)
pop (-xwa)
