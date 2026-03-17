; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Verify binary encoding of TLCS-900 instructions.
; Each CHECK line verifies the encoding bytes emitted by the MCCodeEmitter.

; === Single-byte instructions ===

; CHECK: nop     ; encoding: [0x00]
nop

; CHECK: ret     ; encoding: [0x0e]
ret

; CHECK: halt    ; encoding: [0x05]
halt

; DI is an alias for EI 0 (prints back as "di")
; CHECK: di      ; encoding: [0x06,0x00]
di

; CHECK: reti    ; encoding: [0x07]
reti

; === Register-in-opcode instructions ===

; PUSH r32: 0x38 + reg_encoding
; CHECK: push xwa        ; encoding: [0x38]
push xwa

; CHECK: push xbc        ; encoding: [0x39]
push xbc

; CHECK: push xde        ; encoding: [0x3a]
push xde

; CHECK: push xhl        ; encoding: [0x3b]
push xhl

; CHECK: push xsp        ; encoding: [0x3f]
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

; Note: NEG and CPL are invalid in E8 (32-bit) prefix table.
; 32-bit NEG/CPL are now isCodeGenOnly. Only 8/16-bit versions tested here.

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

; === INC/DEC (prefix + opcode|(n&7)) — I3: 1→1, 2→2, ..., 7→7, 8→0 ===

; INC 1, rd: E8+r, 0x60+1=0x61
; CHECK: inc 1, xwa      ; encoding: [0xe8,0x61]
inc 1, xwa

; INC 3, rd: E8+r, 0x60+3=0x63
; CHECK: inc 3, xwa      ; encoding: [0xe8,0x63]
inc 3, xwa

; DEC 1, rd: E8+r, 0x68+1=0x69
; CHECK: dec 1, xwa      ; encoding: [0xe8,0x69]
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

; Note: 32-bit bit manipulation (SET/RES/CHG/BIT/TSET) is invalid in E8 table.
; These instructions are now isCodeGenOnly for 32-bit.
; 8/16-bit versions are still tested via their respective prefix tables.

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

; LD (Xrr), rs: B0+base, 0x60+src
; CHECK: ld (xsp), xwa   ; encoding: [0xb7,0x60]
ld (xsp), xwa

; LD (Xrr+d8), rs: B8+base, d8, 0x60+src
; CHECK: ld (xsp+8), xwa ; encoding: [0xbf,0x08,0x60]
ld (xsp+8), xwa

; === Memory ALU instructions (MemALU) ===

; ADD (Xrr), rs: A0+base, 0x88+src
; CHECK: add (xhl), xwa  ; encoding: [0xa3,0x88]
add (xhl), xwa

; Note: ADD/SUB/CP (mem), #imm are invalid in 32-bit A0 table.
; These are now isCodeGenOnly and not testable in assembly.

; SUB (Xrr+d8), rs: A8+base, d8, 0xA8+src
; CHECK: sub (xsp+4), xde ; encoding: [0xaf,0x04,0xaa]
sub (xsp+4), xde

; CP (Xrr), rs: A0+base, 0xF8+src
; CHECK: cp (xhl), xwa   ; encoding: [0xa3,0xf8]
cp (xhl), xwa

; === Block transfer instructions (BlockTransfer: 0x80 prefix + sub-opcode) ===

; CHECK: ldi              ; encoding: [0x80,0x10]
ldi
; CHECK: ldir             ; encoding: [0x80,0x11]
ldir
; CHECK: ldd              ; encoding: [0x80,0x12]
ldd
; CHECK: lddr             ; encoding: [0x80,0x13]
lddr
; CHECK: cpi              ; encoding: [0x80,0x14]
cpi
; CHECK: cpir             ; encoding: [0x80,0x15]
cpir
; CHECK: cpd              ; encoding: [0x80,0x16]
cpd
; CHECK: cpdr             ; encoding: [0x80,0x17]
cpdr

; === SingleByteImm8 (immediate encoded in opcode byte) ===

; EI level: 0x06, level
; EI 0 prints as "di" due to InstAlias
; CHECK: di               ; encoding: [0x06,0x00]
ei 0

; CHECK: ei 3             ; encoding: [0x06,0x03]
ei 3

; SWI num: 0xF8 + num
; CHECK: swi 0            ; encoding: [0xf8]
swi 0

; CHECK: swi 7            ; encoding: [0xff]
swi 7

; RETD d16: 0x0F, d16 (little-endian)
; CHECK: retd 8           ; encoding: [0x0f,0x08,0x00]
retd 8

; === Call indirect (CallIndirect: B0+reg, 0xE8 = CALL T) ===

; CHECK: call (xwa)       ; encoding: [0xb0,0xe8]
call (xwa)

; CHECK: call (xhl)       ; encoding: [0xb3,0xe8]
call (xhl)

; === Jump indirect (CallIndirect: B0+reg, 0xD8 = JP T) ===

; CHECK: jp (xwa)         ; encoding: [0xb0,0xd8]
jp (xwa)

; CHECK: jp (xhl)         ; encoding: [0xb3,0xd8]
jp (xhl)

; Note: 32-bit DAA is invalid in E8 table (only valid in C8 = 8-bit).
; DAA32 is now isCodeGenOnly.

; === 16-bit prefix: MUL/MULS (16×16→32 multiply) ===

; MUL rd, rs: D8+src, 0x40+dst (unsigned 16×16→32)
; CHECK: mul xwa, xbc     ; encoding: [0xd9,0x40]
mul xwa, xbc

; CHECK: mul xde, xhl     ; encoding: [0xdb,0x42]
mul xde, xhl

; CHECK: mul xhl, xwa     ; encoding: [0xd8,0x43]
mul xhl, xwa

; MULS rd, rs: D8+src, 0x48+dst (signed 16×16→32)
; CHECK: muls xwa, xbc    ; encoding: [0xd9,0x48]
muls xwa, xbc

; CHECK: muls xde, xwa    ; encoding: [0xd8,0x4a]
muls xde, xwa

; === Call with immediate address ===

; CALL nnn: 0x1D, addr24
; CHECK: call 0           ; encoding: [0x1d,0x00,0x00,0x00]
call 0

; CALR d16: 0x1E, d16 (PC-relative)
; CHECK: calr 0           ; encoding: [0x1e,A,A]
; CHECK:                  ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
calr 0

; === 16-bit PUSH/POP (PrefixPush/PrefixPop: D8+r, opcode) ===

; PUSH rs16: D8+r, 0x04
; CHECK: push wa           ; encoding: [0xd8,0x04]
push wa

; CHECK: push bc           ; encoding: [0xd9,0x04]
push bc

; CHECK: push hl           ; encoding: [0xdb,0x04]
push hl

; POP rd16: D8+r, 0x05
; CHECK: pop wa            ; encoding: [0xd8,0x05]
pop wa

; CHECK: pop de            ; encoding: [0xda,0x05]
pop de

; CHECK: pop ix            ; encoding: [0xdc,0x05]
pop ix

; === 16-bit register instructions (D8-DF prefix) ===

; LD rd16, rs16: D8+src, 0x88+dst
; CHECK: ld wa, bc          ; encoding: [0xd9,0x88]
ld wa, bc

; LD rd16, #imm16: D8+rd, 0x03, imm16
; CHECK: ld wa, 0           ; encoding: [0xd8,0x03,0x00,0x00]
ld wa, 0

; CHECK: ld de, 1234        ; encoding: [0xda,0x03,0xd2,0x04]
ld de, 1234

; ADD rd16, rs16: D8+src, 0x80+dst
; CHECK: add wa, bc         ; encoding: [0xd9,0x80]
add wa, bc

; ADD rd16, #imm16: D8+dst, 0xC8, imm16
; CHECK: add wa, 42         ; encoding: [0xd8,0xc8,0x2a,0x00]
add wa, 42

; SUB rd16, rs16: D8+src, 0xA0+dst
; CHECK: sub de, hl         ; encoding: [0xdb,0xa2]
sub de, hl

; SUB rd16, #imm16: D8+dst, 0xCA, imm16
; CHECK: sub bc, 100        ; encoding: [0xd9,0xca,0x64,0x00]
sub bc, 100

; AND rd16, rs16: D8+src, 0xC0+dst
; CHECK: and wa, bc         ; encoding: [0xd9,0xc0]
and wa, bc

; OR rd16, rs16: D8+src, 0xE0+dst
; CHECK: or wa, de          ; encoding: [0xda,0xe0]
or wa, de

; XOR rd16, rs16: D8+src, 0xD0+dst
; CHECK: xor hl, bc         ; encoding: [0xd9,0xd3]
xor hl, bc

; CP rd16, rs16: D8+rs2, 0xF0+rs1
; CHECK: cp wa, bc          ; encoding: [0xd9,0xf0]
cp wa, bc

; CP rd16, #imm16: D8+rs1, 0xCF, imm16
; CHECK: cp de, 0           ; encoding: [0xda,0xcf,0x00,0x00]
cp de, 0

; NEG rd16: D8+r, 0x07
; CHECK: neg wa             ; encoding: [0xd8,0x07]
neg wa

; CPL rd16: D8+r, 0x06
; CHECK: cpl bc             ; encoding: [0xd9,0x06]
cpl bc

; INC 1, rd16: D8+r, 0x61
; CHECK: inc 1, wa          ; encoding: [0xd8,0x61]
inc 1, wa

; DEC 2, rd16: D8+r, 0x6a
; CHECK: dec 2, de          ; encoding: [0xda,0x6a]
dec 2, de

; SLA rd16, #imm: D8+r, 0xEC, amount
; CHECK: sla wa, 1          ; encoding: [0xd8,0xec,0x01]
sla wa, 1

; SRA rd16, #imm: D8+r, 0xED, amount
; CHECK: sra bc, 4          ; encoding: [0xd9,0xed,0x04]
sra bc, 4

; SRL rd16, #imm: D8+r, 0xEF, amount
; CHECK: srl de, 8          ; encoding: [0xda,0xef,0x08]
srl de, 8

; RLC rd16: D8+r, 0xE8, 0x01
; CHECK: rlc wa             ; encoding: [0xd8,0xe8,0x01]
rlc wa

; RRC rd16: D8+r, 0xE9, 0x01
; CHECK: rrc bc             ; encoding: [0xd9,0xe9,0x01]
rrc bc

; RL rd16: D8+r, 0xEA, 0x01
; CHECK: rl de              ; encoding: [0xda,0xea,0x01]
rl de

; RR rd16: D8+r, 0xEB, 0x01
; CHECK: rr hl              ; encoding: [0xdb,0xeb,0x01]
rr hl

; EXTS rd16: D8+r, 0x13
; CHECK: exts wa            ; encoding: [0xd8,0x13]
exts wa

; EXTZ rd16: D8+r, 0x12
; CHECK: extz bc            ; encoding: [0xd9,0x12]
extz bc

; ADC rd16, rs16: D8+src, 0x90+dst
; CHECK: adc wa, bc         ; encoding: [0xd9,0x90]
adc wa, bc

; SBC rd16, rs16: D8+src, 0xB0+dst
; CHECK: sbc de, hl         ; encoding: [0xdb,0xb2]
sbc de, hl

; === 8-bit register instructions (C8-CF prefix) ===

; LD rd8, rs8: C8+src, 0x88+dst
; CHECK: ld w, a            ; encoding: [0xc9,0x88]
ld w, a

; LD rd8, #imm8: C8+rd, 0x03, imm8
; CHECK: ld a, 0            ; encoding: [0xc9,0x03,0x00]
ld a, 0

; CHECK: ld b, 255          ; encoding: [0xca,0x03,0xff]
ld b, 255

; ADD rd8, rs8: C8+src, 0x80+dst
; CHECK: add a, b           ; encoding: [0xca,0x81]
add a, b

; ADD rd8, #imm8: C8+dst, 0xC8, imm8
; CHECK: add a, 42          ; encoding: [0xc9,0xc8,0x2a]
add a, 42

; SUB rd8, rs8: C8+src, 0xA0+dst (D=4, so C8+4=CC)
; CHECK: sub c, d           ; encoding: [0xcc,0xa3]
sub c, d

; AND rd8, rs8: C8+src, 0xC0+dst
; CHECK: and a, c           ; encoding: [0xcb,0xc1]
and a, c

; OR rd8, rs8: C8+src, 0xE0+dst
; CHECK: or h, l            ; encoding: [0xcf,0xe6]
or h, l

; XOR rd8, rs8: C8+src, 0xD0+dst
; CHECK: xor a, b           ; encoding: [0xca,0xd1]
xor a, b

; CP rd8, rs8: C8+rs2, 0xF0+rs1
; CHECK: cp a, b            ; encoding: [0xca,0xf1]
cp a, b

; CP rd8, #imm8: C8+rs1, 0xCF, imm8
; CHECK: cp a, 0            ; encoding: [0xc9,0xcf,0x00]
cp a, 0

; NEG rd8: C8+r, 0x07
; CHECK: neg a              ; encoding: [0xc9,0x07]
neg a

; CPL rd8: C8+r, 0x06
; CHECK: cpl b              ; encoding: [0xca,0x06]
cpl b

; INC 1, rd8: C8+r, 0x61
; CHECK: inc 1, a           ; encoding: [0xc9,0x61]
inc 1, a

; DEC 1, rd8: C8+r, 0x69
; CHECK: dec 1, b           ; encoding: [0xca,0x69]
dec 1, b

; SLA rd8, #imm: C8+r, 0xEC, amount
; CHECK: sla a, 1           ; encoding: [0xc9,0xec,0x01]
sla a, 1

; RLC rd8: C8+r, 0xE8, 0x01
; CHECK: rlc a              ; encoding: [0xc9,0xe8,0x01]
rlc a

; RRC rd8: C8+r, 0xE9, 0x01
; CHECK: rrc b              ; encoding: [0xca,0xe9,0x01]
rrc b
