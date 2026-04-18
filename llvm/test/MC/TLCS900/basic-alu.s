; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test ALU instructions (ADD, ADC, SUB, SBC, AND, OR, XOR, CP) across
; all register sizes (8/16/32-bit) with both register and immediate operands.

; ==========================================================================
; 8-bit register-register ALU (C8-CF prefix)
; ==========================================================================

; ADD rd8, rs8: C8+src, 0x80+dst
; CHECK: add a, b           ; encoding: [0xca,0x81]
add a, b
; CHECK: add c, d           ; encoding: [0xcc,0x83]
add c, d
; CHECK: add w, a           ; encoding: [0xc9,0x80]
add w, a

; ADC rd8, rs8: C8+src, 0x90+dst
; CHECK: adc a, b           ; encoding: [0xca,0x91]
adc a, b
; CHECK: adc c, d           ; encoding: [0xcc,0x93]
adc c, d

; SUB rd8, rs8: C8+src, 0xA0+dst
; CHECK: sub c, d           ; encoding: [0xcc,0xa3]
sub c, d
; CHECK: sub a, w           ; encoding: [0xc8,0xa1]
sub a, w

; SBC rd8, rs8: C8+src, 0xB0+dst
; CHECK: sbc c, d           ; encoding: [0xcc,0xb3]
sbc c, d
; CHECK: sbc a, l           ; encoding: [0xcf,0xb1]
sbc a, l

; AND rd8, rs8: C8+src, 0xC0+dst
; CHECK: and a, c           ; encoding: [0xcb,0xc1]
and a, c
; CHECK: and h, l           ; encoding: [0xcf,0xc6]
and h, l

; OR rd8, rs8: C8+src, 0xE0+dst
; CHECK: or h, l            ; encoding: [0xcf,0xe6]
or h, l
; CHECK: or a, b            ; encoding: [0xca,0xe1]
or a, b

; XOR rd8, rs8: C8+src, 0xD0+dst
; CHECK: xor a, b           ; encoding: [0xca,0xd1]
xor a, b
; CHECK: xor c, a           ; encoding: [0xc9,0xd3]
xor c, a

; CP rd8, rs8: C8+src, 0xF0+dst
; CHECK: cp a, b            ; encoding: [0xca,0xf1]
cp a, b
; CHECK: cp c, d            ; encoding: [0xcc,0xf3]
cp c, d

; ==========================================================================
; 8-bit register-immediate ALU
; ==========================================================================

; ADD rd8, #imm8: C8+dst, 0xC8, imm8
; CHECK: add a, 42          ; encoding: [0xc9,0xc8,0x2a]
add a, 42
; CHECK: add a, 0           ; encoding: [0xc9,0xc8,0x00]
add a, 0
; CHECK: add a, 255         ; encoding: [0xc9,0xc8,0xff]
add a, 255

; SUB rd8, #imm8: C8+dst, 0xCA, imm8
; CHECK: sub a, 10          ; encoding: [0xc9,0xca,0x0a]
sub a, 10

; AND rd8, #imm8: C8+dst, 0xCC, imm8
; CHECK: and a, 15          ; encoding: [0xc9,0xcc,0x0f]
and a, 15

; OR rd8, #imm8: C8+dst, 0xCE, imm8
; CHECK: or a, 128          ; encoding: [0xc9,0xce,0x80]
or a, 128

; XOR rd8, #imm8: C8+dst, 0xCD, imm8
; CHECK: xor a, 255         ; encoding: [0xc9,0xcd,0xff]
xor a, 255

; CP rd8, #imm8: C8+dst, 0xCF, imm8
; CHECK: cp a, 0            ; encoding: [0xc9,0xcf,0x00]
cp a, 0
; CHECK: cp a, 255          ; encoding: [0xc9,0xcf,0xff]
cp a, 255

; ==========================================================================
; 16-bit register-register ALU (D8-DF prefix)
; ==========================================================================

; ADD rd16, rs16: D8+src, 0x80+dst
; CHECK: add wa, bc         ; encoding: [0xd9,0x80]
add wa, bc
; CHECK: add de, hl         ; encoding: [0xdb,0x82]
add de, hl

; ADC rd16, rs16: D8+src, 0x90+dst
; CHECK: adc wa, bc         ; encoding: [0xd9,0x90]
adc wa, bc
; CHECK: adc de, hl         ; encoding: [0xdb,0x92]
adc de, hl

; SUB rd16, rs16: D8+src, 0xA0+dst
; CHECK: sub de, hl         ; encoding: [0xdb,0xa2]
sub de, hl
; CHECK: sub wa, bc         ; encoding: [0xd9,0xa0]
sub wa, bc

; SBC rd16, rs16: D8+src, 0xB0+dst
; CHECK: sbc de, hl         ; encoding: [0xdb,0xb2]
sbc de, hl

; AND rd16, rs16: D8+src, 0xC0+dst
; CHECK: and wa, bc         ; encoding: [0xd9,0xc0]
and wa, bc

; OR rd16, rs16: D8+src, 0xE0+dst
; CHECK: or wa, de          ; encoding: [0xda,0xe0]
or wa, de

; XOR rd16, rs16: D8+src, 0xD0+dst
; CHECK: xor hl, bc         ; encoding: [0xd9,0xd3]
xor hl, bc

; CP rd16, rs16: D8+src, 0xF0+dst
; CHECK: cp wa, bc          ; encoding: [0xd9,0xf0]
cp wa, bc
; CHECK: cp de, wa          ; encoding: [0xd8,0xf2]
cp de, wa

; ==========================================================================
; 16-bit register-immediate ALU
; ==========================================================================

; ADD rd16, #imm16: D8+dst, 0xC8, imm16
; CHECK: add wa, 42         ; encoding: [0xd8,0xc8,0x2a,0x00]
add wa, 42

; SUB rd16, #imm16: D8+dst, 0xCA, imm16
; CHECK: sub bc, 100        ; encoding: [0xd9,0xca,0x64,0x00]
sub bc, 100

; AND rd16, #imm16: D8+dst, 0xCC, imm16
; CHECK: and wa, 255        ; encoding: [0xd8,0xcc,0xff,0x00]
and wa, 255

; OR rd16, #imm16: D8+dst, 0xCE, imm16
; CHECK: or bc, 15          ; encoding: [0xd9,0xce,0x0f,0x00]
or bc, 15

; XOR rd16, #imm16: D8+dst, 0xCD, imm16
; CHECK: xor de, 4096       ; encoding: [0xda,0xcd,0x00,0x10]
xor de, 4096

; CP rd16, #imm16: D8+dst, 0xCF, imm16
; CHECK: cp de, 0           ; encoding: [0xda,0xcf,0x00,0x00]
cp de, 0
; CHECK: cp de, 100         ; encoding: [0xda,0xcf,0x64,0x00]
cp de, 100

; ==========================================================================
; 32-bit register-register ALU (E8-EF prefix)
; ==========================================================================

; ADD rd, rs: E8+src, 0x80+dst
; CHECK: add xwa, xbc       ; encoding: [0xe9,0x80]
add xwa, xbc
; CHECK: add xde, xhl       ; encoding: [0xeb,0x82]
add xde, xhl
; CHECK: add xhl, xwa       ; encoding: [0xe8,0x83]
add xhl, xwa

; ADC rd, rs: E8+src, 0x90+dst
; CHECK: adc xwa, xbc       ; encoding: [0xe9,0x90]
adc xwa, xbc
; CHECK: adc xhl, xde       ; encoding: [0xea,0x93]
adc xhl, xde

; SUB rd, rs: E8+src, 0xA0+dst
; CHECK: sub xwa, xbc       ; encoding: [0xe9,0xa0]
sub xwa, xbc
; CHECK: sub xde, xwa       ; encoding: [0xe8,0xa2]
sub xde, xwa

; SBC rd, rs: E8+src, 0xB0+dst
; CHECK: sbc xde, xhl       ; encoding: [0xeb,0xb2]
sbc xde, xhl
; CHECK: sbc xwa, xde       ; encoding: [0xea,0xb0]
sbc xwa, xde

; AND rd, rs: E8+src, 0xC0+dst
; CHECK: and xwa, xbc       ; encoding: [0xe9,0xc0]
and xwa, xbc

; OR rd, rs: E8+src, 0xE0+dst
; CHECK: or xwa, xbc        ; encoding: [0xe9,0xe0]
or xwa, xbc
; CHECK: or xhl, xde        ; encoding: [0xea,0xe3]
or xhl, xde

; XOR rd, rs: E8+src, 0xD0+dst
; CHECK: xor xwa, xbc       ; encoding: [0xe9,0xd0]
xor xwa, xbc
; CHECK: xor xde, xhl       ; encoding: [0xeb,0xd2]
xor xde, xhl

; CP rd, rs: E8+src, 0xF0+dst
; CHECK: cp xwa, xbc        ; encoding: [0xe9,0xf0]
cp xwa, xbc
; CHECK: cp xhl, xde        ; encoding: [0xea,0xf3]
cp xhl, xde

; ==========================================================================
; 32-bit register-immediate ALU
; ==========================================================================

; ADD rd, #imm: E8+dst, 0xC8, imm32
; CHECK: add xwa, 42        ; encoding: [0xe8,0xc8,0x2a,0x00,0x00,0x00]
add xwa, 42
; CHECK: add xde, 100       ; encoding: [0xea,0xc8,0x64,0x00,0x00,0x00]
add xde, 100

; ADC rd, #imm: E8+dst, 0xC9, imm32
; CHECK: adc xwa, 100       ; encoding: [0xe8,0xc9,0x64,0x00,0x00,0x00]
adc xwa, 100

; SUB rd, #imm: E8+dst, 0xCA, imm32
; CHECK: sub xwa, 1         ; encoding: [0xe8,0xca,0x01,0x00,0x00,0x00]
sub xwa, 1

; SBC rd, #imm: E8+dst, 0xCB, imm32
; CHECK: sbc xde, 50        ; encoding: [0xea,0xcb,0x32,0x00,0x00,0x00]
sbc xde, 50

; AND rd, #imm: E8+dst, 0xCC, imm32
; CHECK: and xwa, 255       ; encoding: [0xe8,0xcc,0xff,0x00,0x00,0x00]
and xwa, 255

; OR rd, #imm: E8+dst, 0xCE, imm32
; CHECK: or xwa, 15         ; encoding: [0xe8,0xce,0x0f,0x00,0x00,0x00]
or xwa, 15

; XOR rd, #imm: E8+dst, 0xCD, imm32
; CHECK: xor xwa, 65535     ; encoding: [0xe8,0xcd,0xff,0xff,0x00,0x00]
xor xwa, 65535

; CP rd, #imm: E8+dst, 0xCF, imm32
; CHECK: cp xwa, 0          ; encoding: [0xe8,0xcf,0x00,0x00,0x00,0x00]
cp xwa, 0
; CHECK: cp xde, 1000       ; encoding: [0xea,0xcf,0xe8,0x03,0x00,0x00]
cp xde, 1000
