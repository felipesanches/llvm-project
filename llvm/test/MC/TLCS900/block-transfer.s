; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test block transfer and block compare instructions.
; All are 2-byte: 0x80 prefix + sub-opcode.

; ==========================================================================
; Block transfer instructions
; ==========================================================================

; LDI: 0x80, 0x10
; CHECK: ldi                ; encoding: [0x80,0x10]
ldi

; LDIR: 0x80, 0x11
; CHECK: ldir               ; encoding: [0x80,0x11]
ldir

; LDD: 0x80, 0x12
; CHECK: ldd                ; encoding: [0x80,0x12]
ldd

; LDDR: 0x80, 0x13
; CHECK: lddr               ; encoding: [0x80,0x13]
lddr

; ==========================================================================
; Block compare instructions
; ==========================================================================

; CPI: 0x80, 0x14
; CHECK: cpi                ; encoding: [0x80,0x14]
cpi

; CPIR: 0x80, 0x15
; CHECK: cpir               ; encoding: [0x80,0x15]
cpir

; CPD: 0x80, 0x16
; CHECK: cpd                ; encoding: [0x80,0x16]
cpd

; CPDR: 0x80, 0x17
; CHECK: cpdr               ; encoding: [0x80,0x17]
cpdr
