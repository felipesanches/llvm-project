; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Verify binary encoding of TLCS-900 instructions.
; Each CHECK line verifies the encoding bytes emitted by the MCCodeEmitter.

; === Single-byte instructions ===

; CHECK: nop     ; encoding: [0x00]
nop

; CHECK: ret     ; encoding: [0x0e]
ret

; CHECK: halt    ; encoding: [0x06]
halt

; CHECK: di      ; encoding: [0x07]
di

; === Register-in-opcode instructions ===

; PUSH r32: 0x48 + reg_encoding
; CHECK: push xwa        ; encoding: [0x48]
push xwa

; CHECK: push xbc        ; encoding: [0x49]
push xbc

; CHECK: push xde        ; encoding: [0x4a]
push xde

; CHECK: push xhl        ; encoding: [0x4b]
push xhl

; CHECK: push xsp        ; encoding: [0x4f]
push xsp

; POP r32: 0x58 + reg_encoding
; CHECK: pop xwa         ; encoding: [0x58]
pop xwa

; CHECK: pop xbc         ; encoding: [0x59]
pop xbc

; === LD r32, #imm32 ===

; CHECK: ld xwa, 0       ; encoding: [0x40,0x00,0x00,0x00,0x00]
ld xwa, 0

; CHECK: ld xbc, 1       ; encoding: [0x41,0x01,0x00,0x00,0x00]
ld xbc, 1

; CHECK: ld xde, 255     ; encoding: [0x42,0xff,0x00,0x00,0x00]
ld xde, 255

; === Prefix + unary instructions (2 bytes: prefix + opcode) ===

; NEG r32: E8+r, 0x07
; CHECK: neg xwa         ; encoding: [0xe8,0x07]
neg xwa

; CHECK: neg xbc         ; encoding: [0xe9,0x07]
neg xbc

; CPL r32: E8+r, 0x06
; CHECK: cpl xwa         ; encoding: [0xe8,0x06]
cpl xwa

; EXTS r32: E8+r, 0x13
; CHECK: exts xwa        ; encoding: [0xe8,0x13]
exts xwa

; EXTZ r32: E8+r, 0x12
; CHECK: extz xwa        ; encoding: [0xe8,0x12]
extz xwa

; === Prefix + reg + reg instructions (2 bytes: src_prefix + opc|dst) ===

; ADD rd, rs: E8+src, 0x80+dst
; CHECK: add xwa, xbc    ; encoding: [0xe9,0x80]
add xwa, xbc

; CHECK: add xde, xhl    ; encoding: [0xeb,0x82]
add xde, xhl

; SUB rd, rs: E8+src, 0xA0+dst
; CHECK: sub xwa, xbc    ; encoding: [0xe9,0xa0]
sub xwa, xbc

; AND rd, rs: E8+src, 0xC0+dst
; CHECK: and xwa, xbc    ; encoding: [0xe9,0xc0]
and xwa, xbc

; OR rd, rs: E8+src, 0xE0+dst
; CHECK: or xwa, xbc     ; encoding: [0xe9,0xe0]
or xwa, xbc

; XOR rd, rs: E8+src, 0xD0+dst
; CHECK: xor xwa, xbc    ; encoding: [0xe9,0xd0]
xor xwa, xbc

; CP rd, rs: E8+rs2, 0xF0+rs1
; CHECK: cp xwa, xbc     ; encoding: [0xe9,0xf0]
cp xwa, xbc

; === Prefix + reg + imm instructions (prefix + opcode + imm32) ===

; ADD rd, #imm: E8+dst, 0xC8, imm32
; CHECK: add xwa, 42     ; encoding: [0xe8,0xc8,0x2a,0x00,0x00,0x00]
add xwa, 42

; SUB rd, #imm: E8+dst, 0xCA, imm32
; CHECK: sub xwa, 1      ; encoding: [0xe8,0xca,0x01,0x00,0x00,0x00]
sub xwa, 1

; CP rd, #imm: E8+rs1, 0xCF, imm32
; CHECK: cp xwa, 0       ; encoding: [0xe8,0xcf,0x00,0x00,0x00,0x00]
cp xwa, 0

; === INC/DEC (prefix + opcode|(count-1)) ===

; INC 1, rd: E8+r, 0x60+(1-1)=0x60
; CHECK: inc 1, xwa      ; encoding: [0xe8,0x60]
inc 1, xwa

; INC 3, rd: E8+r, 0x60+(3-1)=0x62
; CHECK: inc 3, xwa      ; encoding: [0xe8,0x62]
inc 3, xwa

; DEC 1, rd: E8+r, 0x68+(1-1)=0x68
; CHECK: dec 1, xwa      ; encoding: [0xe8,0x68]
dec 1, xwa

; === Shift instructions (prefix + opcode + amount) ===

; SLA rd, #imm: E8+r, 0xEC, amount
; CHECK: sla xwa, 1      ; encoding: [0xe8,0xec,0x01]
sla xwa, 1

; SRA rd, #imm: E8+r, 0xED, amount
; CHECK: sra xwa, 4      ; encoding: [0xe8,0xed,0x04]
sra xwa, 4

; SRL rd, #imm: E8+r, 0xEF, amount
; CHECK: srl xwa, 8      ; encoding: [0xe8,0xef,0x08]
srl xwa, 8
