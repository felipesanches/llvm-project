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

; CHECK: reti    ; encoding: [0x0b]
reti

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

; === Rotate instructions (PrefixRotate: prefix + rotate_opcode + 0x01) ===

; RLC rd: E8+r, 0xE8, 0x01
; CHECK: rlc xwa         ; encoding: [0xe8,0xe8,0x01]
rlc xwa

; RRC rd: E8+r, 0xE9, 0x01
; CHECK: rrc xbc         ; encoding: [0xe9,0xe9,0x01]
rrc xbc

; RL rd: E8+r, 0xEA, 0x01
; CHECK: rl xde          ; encoding: [0xea,0xea,0x01]
rl xde

; RR rd: E8+r, 0xEB, 0x01
; CHECK: rr xhl          ; encoding: [0xeb,0xeb,0x01]
rr xhl

; === Bit manipulation instructions (PrefixBit: prefix + bit_opcode + bit_num) ===

; SET bit, rd: E8+rd, 0x31, bit
; CHECK: set 3, xde      ; encoding: [0xea,0x31,0x03]
set 3, xde

; RES bit, rd: E8+rd, 0x30, bit
; CHECK: res 7, xwa      ; encoding: [0xe8,0x30,0x07]
res 7, xwa

; CHG bit, rd: E8+rd, 0x32, bit
; CHECK: chg 0, xbc      ; encoding: [0xe9,0x32,0x00]
chg 0, xbc

; BIT bit, rs: E8+rs, 0x33, bit
; CHECK: bit 5, xhl      ; encoding: [0xeb,0x33,0x05]
bit 5, xhl

; TSET bit, rd: E8+rd, 0x34, bit
; CHECK: tset 1, xwa     ; encoding: [0xe8,0x34,0x01]
tset 1, xwa

; === Memory load instructions (MemLoad) ===

; LD rd, (Xrr): A0+base, 0x20+dst
; CHECK: ld xwa, (xsp)   ; encoding: [0xa7,0x20]
ld xwa, (xsp)

; CHECK: ld xde, (xhl)   ; encoding: [0xa3,0x22]
ld xde, (xhl)

; LD rd, (Xrr+d8): A8+base, d8, 0x20+dst
; CHECK: ld xde, (xsp+4) ; encoding: [0xaf,0x04,0x22]
ld xde, (xsp+4)

; CHECK: ld xbc, (xhl+100) ; encoding: [0xab,0x64,0x21]
ld xbc, (xhl+100)

; === Memory store instructions (MemStore) ===

; LD (Xrr), rs: A0+base, 0x40+src
; CHECK: ld (xsp), xwa   ; encoding: [0xa7,0x40]
ld (xsp), xwa

; LD (Xrr+d8), rs: A8+base, d8, 0x40+src
; CHECK: ld (xsp+8), xwa ; encoding: [0xaf,0x08,0x40]
ld (xsp+8), xwa

; LD (Xrr), #imm: A0+base, 0x08, imm32
; CHECK: ld (xhl), 255   ; encoding: [0xa3,0x08,0xff,0x00,0x00,0x00]
ld (xhl), 255

; === Memory ALU instructions (MemALU) ===

; ADD (Xrr), rs: A0+base, 0x80+src
; CHECK: add (xhl), xwa  ; encoding: [0xa3,0x80]
add (xhl), xwa

; ADD (Xrr), #imm: A0+base, 0xC8, imm32
; CHECK: add (xhl), 1    ; encoding: [0xa3,0xc8,0x01,0x00,0x00,0x00]
add (xhl), 1

; SUB (Xrr+d8), rs: A8+base, d8, 0xA0+src
; CHECK: sub (xsp+4), xde ; encoding: [0xaf,0x04,0xa2]
sub (xsp+4), xde

; CP (Xrr), rs: A0+base, 0xF0+src
; CHECK: cp (xhl), xwa   ; encoding: [0xa3,0xf0]
cp (xhl), xwa

; CP (Xrr+d8), #imm: A8+base, d8, 0xCF, imm32
; CHECK: cp (xsp+4), 100 ; encoding: [0xaf,0x04,0xcf,0x64,0x00,0x00,0x00]
cp (xsp+4), 100

; === Block transfer instructions (BlockTransfer: single opcode byte) ===

; CHECK: ldi              ; encoding: [0x10]
ldi
; CHECK: ldir             ; encoding: [0x11]
ldir
; CHECK: ldd              ; encoding: [0x12]
ldd
; CHECK: lddr             ; encoding: [0x13]
lddr
; CHECK: cpi              ; encoding: [0x14]
cpi
; CHECK: cpir             ; encoding: [0x15]
cpir
; CHECK: cpd              ; encoding: [0x16]
cpd
; CHECK: cpdr             ; encoding: [0x17]
cpdr

; === SingleByteImm8 (immediate encoded in opcode byte) ===

; EI level: 0x08 + level
; CHECK: ei 0             ; encoding: [0x08]
ei 0

; CHECK: ei 3             ; encoding: [0x0b]
ei 3

; SWI num: 0xF8 + num
; CHECK: swi 0            ; encoding: [0xf8]
swi 0

; CHECK: swi 7            ; encoding: [0xff]
swi 7

; RETD d16: 0x0F, d16 (little-endian)
; CHECK: retd 8           ; encoding: [0x0f,0x08,0x00]
retd 8

; === Call indirect (CallIndirect: B0+reg, 0x1F) ===

; CHECK: call (xwa)       ; encoding: [0xb0,0x1f]
call (xwa)

; CHECK: call (xhl)       ; encoding: [0xb3,0x1f]
call (xhl)

; === Jump indirect (CallIndirect: B0+reg, 0x1C) ===

; CHECK: jp (xwa)         ; encoding: [0xb0,0x1c]
jp (xwa)

; CHECK: jp (xhl)         ; encoding: [0xb3,0x1c]
jp (xhl)

; === DAA instruction (PrefixUnary: E8+r, 0x10) ===

; CHECK: daa xwa          ; encoding: [0xe8,0x10]
daa xwa

; === Call with immediate address ===

; CALL nnn: 0x1D, addr24
; CHECK: call 0           ; encoding: [0x1d,0x00,0x00,0x00]
call 0

; CALR d16: 0x1E, d16
; CHECK: calr 0           ; encoding: [0x1e,0x00,0x00]
calr 0
