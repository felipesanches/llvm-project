; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test LD, LDW, LDB, PUSH, POP instructions across register sizes and
; addressing modes (register, immediate, memory indirect, displacement).

; ==========================================================================
; 8-bit register-register LD (C8-CF prefix)
; ==========================================================================

; LD rd8, rs8: C8+src, 0x88+dst
; CHECK: ld w, a            ; encoding: [0xc9,0x88]
ld w, a
; CHECK: ld b, c            ; encoding: [0xcb,0x8a]
ld b, c
; CHECK: ld a, l            ; encoding: [0xcf,0x89]
ld a, l

; ==========================================================================
; 8-bit register-immediate LD
; ==========================================================================

; LD rd8, #imm8: C8+rd, 0x03, imm8
; CHECK: ld a, 0            ; encoding: [0xc9,0x03,0x00]
ld a, 0
; CHECK: ld b, 255          ; encoding: [0xca,0x03,0xff]
ld b, 255
; CHECK: ld c, 42           ; encoding: [0xcb,0x03,0x2a]
ld c, 42

; ==========================================================================
; Compact 8-bit LD (LDB): 2-byte form (0x20+reg, imm8)
; ==========================================================================

; CHECK: ldb a, 42          ; encoding: [0x21,0x2a]
ldb a, 42
; CHECK: ldb a, 0           ; encoding: [0x21,0x00]
ldb a, 0
; CHECK: ldb a, 255         ; encoding: [0x21,0xff]
ldb a, 255

; ==========================================================================
; 16-bit register-register LD (D8-DF prefix)
; ==========================================================================

; LD rd16, rs16: D8+src, 0x88+dst
; CHECK: ld wa, bc          ; encoding: [0xd9,0x88]
ld wa, bc
; CHECK: ld de, hl          ; encoding: [0xdb,0x8a]
ld de, hl
; CHECK: ld wa, ix          ; encoding: [0xdc,0x88]
ld wa, ix

; ==========================================================================
; 16-bit register-immediate LD
; ==========================================================================

; LD rd16, #imm16: D8+rd, 0x03, imm16
; CHECK: ld wa, 0           ; encoding: [0xd8,0x03,0x00,0x00]
ld wa, 0
; CHECK: ld de, 1234        ; encoding: [0xda,0x03,0xd2,0x04]
ld de, 1234
; CHECK: ld bc, 65535       ; encoding: [0xd9,0x03,0xff,0xff]
ld bc, 65535

; ==========================================================================
; Compact 16-bit LD (LDW): 3-byte form (0x30+reg, imm16)
; ==========================================================================

; CHECK: ldw wa, 100        ; encoding: [0x30,0x64,0x00]
ldw wa, 100
; CHECK: ldw wa, 0          ; encoding: [0x30,0x00,0x00]
ldw wa, 0

; ==========================================================================
; 32-bit register-register LD (E8-EF prefix)
; ==========================================================================

; LD rd, rs: E8+src, 0x88+dst
; CHECK: ld xde, xbc        ; encoding: [0xe9,0x8a]
ld xde, xbc
; CHECK: ld xhl, xwa        ; encoding: [0xe8,0x8b]
ld xhl, xwa
; CHECK: ld xwa, xix        ; encoding: [0xec,0x88]
ld xwa, xix

; ==========================================================================
; 32-bit register-immediate LD (0x40+reg, imm32)
; ==========================================================================

; CHECK: ld xwa, 0          ; encoding: [0x40,0x00,0x00,0x00,0x00]
ld xwa, 0
; CHECK: ld xbc, 1          ; encoding: [0x41,0x01,0x00,0x00,0x00]
ld xbc, 1
; CHECK: ld xde, 255        ; encoding: [0x42,0xff,0x00,0x00,0x00]
ld xde, 255
; CHECK: ld xhl, 305419896  ; encoding: [0x43,0x78,0x56,0x34,0x12]
ld xhl, 0x12345678

; ==========================================================================
; 32-bit PUSH / POP (1-byte compact: 0x38+reg / 0x58+reg)
; ==========================================================================

; CHECK: push xwa           ; encoding: [0x38]
push xwa
; CHECK: push xbc           ; encoding: [0x39]
push xbc
; CHECK: push xde           ; encoding: [0x3a]
push xde
; CHECK: push xhl           ; encoding: [0x3b]
push xhl
; CHECK: push xix           ; encoding: [0x3c]
push xix
; CHECK: push xiy           ; encoding: [0x3d]
push xiy
; CHECK: push xiz           ; encoding: [0x3e]
push xiz
; CHECK: push xsp           ; encoding: [0x3f]
push xsp

; CHECK: pop xwa            ; encoding: [0x58]
pop xwa
; CHECK: pop xbc            ; encoding: [0x59]
pop xbc
; CHECK: pop xde            ; encoding: [0x5a]
pop xde
; CHECK: pop xhl            ; encoding: [0x5b]
pop xhl
; CHECK: pop xix            ; encoding: [0x5c]
pop xix
; CHECK: pop xiy            ; encoding: [0x5d]
pop xiy
; CHECK: pop xiz            ; encoding: [0x5e]
pop xiz

; ==========================================================================
; 16-bit PUSH / POP (D8+r prefix: 0x04/0x05)
; ==========================================================================

; CHECK: push wa            ; encoding: [0xd8,0x04]
push wa
; CHECK: push bc            ; encoding: [0xd9,0x04]
push bc
; CHECK: push de            ; encoding: [0xda,0x04]
push de
; CHECK: push hl            ; encoding: [0xdb,0x04]
push hl
; CHECK: push ix            ; encoding: [0xdc,0x04]
push ix
; CHECK: push iy            ; encoding: [0xdd,0x04]
push iy

; CHECK: pop wa             ; encoding: [0xd8,0x05]
pop wa
; CHECK: pop bc             ; encoding: [0xd9,0x05]
pop bc
; CHECK: pop de             ; encoding: [0xda,0x05]
pop de
; CHECK: pop hl             ; encoding: [0xdb,0x05]
pop hl
; CHECK: pop ix             ; encoding: [0xdc,0x05]
pop ix
; CHECK: pop iz             ; encoding: [0xde,0x05]
pop iz

; ==========================================================================
; Compact 16-bit PUSHW / POPW (1-byte: 0x28+reg / 0x48+reg)
; ==========================================================================

; CHECK: pushw wa           ; encoding: [0x28]
pushw wa
; CHECK: pushw bc           ; encoding: [0x29]
pushw bc

; CHECK: popw wa            ; encoding: [0x48]
popw wa
; CHECK: popw bc            ; encoding: [0x49]
popw bc

; ==========================================================================
; PUSH immediate (0x09, imm8)
; ==========================================================================

; CHECK: push 42            ; encoding: [0x09,0x2a]
push 42
; CHECK: push 0             ; encoding: [0x09,0x00]
push 0

; ==========================================================================
; Memory immediate stores: LD (mem), #imm
; ==========================================================================

; 8-bit store: LD (Xrr), #imm8
; CHECK: ld (xhl), 42       ; encoding: [0xb3,0x00,0x2a]
ld (xhl), 42

; 16-bit store: LDW (Xrr), #imm16
; CHECK: ldw (xhl), 42      ; encoding: [0xb3,0x02,0x2a,0x00]
ldw (xhl), 42

; 8-bit store with displacement
; CHECK: ld (xsp+4), 0      ; encoding: [0xbf,0x04,0x00,0x00]
ld (xsp+4), 0

; 16-bit store with displacement
; CHECK: ldw (xsp+4), 0     ; encoding: [0xbf,0x04,0x02,0x00,0x00]
ldw (xsp+4), 0

; ==========================================================================
; Prevbank LD (D7 prefix — alternate register bank)
; ==========================================================================

; CHECK: ld qiz, wa         ; encoding: [0xd7,0xfa,0x98]
ld qiz, wa
; CHECK: ld wa, qiz         ; encoding: [0xd7,0xfa,0x88]
ld wa, qiz
; CHECK: ld bc, qiz         ; encoding: [0xd7,0xfa,0x89]
ld bc, qiz
