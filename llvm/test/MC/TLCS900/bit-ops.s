; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test bit manipulation instructions: BIT, SET, RES for 8-bit and 16-bit
; registers. (32-bit bit ops are isCodeGenOnly and cannot be assembled.)

; ==========================================================================
; 8-bit BIT (C8+r, 0x33, bit#)
; ==========================================================================

; CHECK: bit 0, a           ; encoding: [0xc9,0x33,0x00]
bit 0, a
; CHECK: bit 3, a           ; encoding: [0xc9,0x33,0x03]
bit 3, a
; CHECK: bit 7, a           ; encoding: [0xc9,0x33,0x07]
bit 7, a
; CHECK: bit 0, b           ; encoding: [0xca,0x33,0x00]
bit 0, b
; CHECK: bit 4, c           ; encoding: [0xcb,0x33,0x04]
bit 4, c

; ==========================================================================
; 8-bit SET (C8+r, 0x31, bit#)
; ==========================================================================

; CHECK: set 0, a           ; encoding: [0xc9,0x31,0x00]
set 0, a
; CHECK: set 3, a           ; encoding: [0xc9,0x31,0x03]
set 3, a
; CHECK: set 7, a           ; encoding: [0xc9,0x31,0x07]
set 7, a
; CHECK: set 5, b           ; encoding: [0xca,0x31,0x05]
set 5, b

; ==========================================================================
; 8-bit RES (C8+r, 0x30, bit#)
; ==========================================================================

; CHECK: res 0, a           ; encoding: [0xc9,0x30,0x00]
res 0, a
; CHECK: res 3, a           ; encoding: [0xc9,0x30,0x03]
res 3, a
; CHECK: res 7, b           ; encoding: [0xca,0x30,0x07]
res 7, b

; ==========================================================================
; 16-bit BIT (D8+r, 0x33, bit#)
; ==========================================================================

; CHECK: bit 0, wa          ; encoding: [0xd8,0x33,0x00]
bit 0, wa
; CHECK: bit 3, wa          ; encoding: [0xd8,0x33,0x03]
bit 3, wa
; CHECK: bit 15, wa         ; encoding: [0xd8,0x33,0x0f]
bit 15, wa
; CHECK: bit 8, bc          ; encoding: [0xd9,0x33,0x08]
bit 8, bc

; ==========================================================================
; 16-bit SET (D8+r, 0x31, bit#)
; ==========================================================================

; CHECK: set 0, wa          ; encoding: [0xd8,0x31,0x00]
set 0, wa
; CHECK: set 3, wa          ; encoding: [0xd8,0x31,0x03]
set 3, wa
; CHECK: set 15, de         ; encoding: [0xda,0x31,0x0f]
set 15, de

; ==========================================================================
; 16-bit RES (D8+r, 0x30, bit#)
; ==========================================================================

; CHECK: res 0, wa          ; encoding: [0xd8,0x30,0x00]
res 0, wa
; CHECK: res 3, wa          ; encoding: [0xd8,0x30,0x03]
res 3, wa
; CHECK: res 12, hl         ; encoding: [0xdb,0x30,0x0c]
res 12, hl

; Note: CHG and TSET are not supported in the current LLVM backend.
; Note: 32-bit BIT/SET/RES are isCodeGenOnly (invalid in E8 prefix table).
