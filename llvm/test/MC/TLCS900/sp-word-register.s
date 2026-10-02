; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s | llvm-objdump -d - | FileCheck --check-prefix=INST %s
;
; SP is the 16-bit register whose field is 7, in every 16-bit register field.
; GR16 -- the class 16-bit operands are typed with -- leaves SP out, because
; codegen must never allocate it, so the assembler refused `add sp, (8990:16)`
; while the decoder printed exactly that for d1 1e 23 87 (wave 3a V1 panel:
; 21,388 sweep probes failed the round trip this way, and those instructions
; had no spelling at all).  A second matching pass accepts SP for a GR16
; operand when nothing matched the first time, so every spelling that
; assembled before keeps its bytes.  Each encoding is MAME unidasm's reading.

; unidasm: d1 1e 23 87  add SP,(0x231e)
; CHECK: add sp, (8990:16)        ; encoding: [0xd1,0x1e,0x23,0x87]
; INST:  add sp, (8990:16)
add sp, (8990:16)
; unidasm: d5 01 27  ld SP,(XWA0+)
; CHECK: ld sp, (xwa0+)           ; encoding: [0xd5,0x01,0x27]
; INST:  ld sp, (xwa0+)
ld sp, (xwa0+)
; unidasm: 91 27  ld SP,(XBC)
; CHECK: ld sp, (xbc)             ; encoding: [0x91,0x27]
ld sp, (xbc)
; unidasm: 9f 04 27  ld SP,(XSP+0x04)
; CHECK: ld sp, (xsp+4)           ; encoding: [0x9f,0x04,0x27]
ld sp, (xsp+4)
; unidasm: b1 27  lda SP,XBC
; CHECK: lda sp, (xbc)            ; encoding: [0xb1,0x27]
; INST:  lda sp, (xbc)
lda sp, (xbc)
; unidasm: f1 1e 23 57  ld (0x231e),SP
; CHECK: ld (8990:16), sp         ; encoding: [0xf1,0x1e,0x23,0x57]
ld (8990:16), sp
; unidasm: df 03 05 00  ld SP,0x0005
; CHECK: ld sp, 5                 ; encoding: [0xdf,0x03,0x05,0x00]
ld sp, 5
; unidasm: df ad  ld SP,5
; CHECK: ld sp, 5:i3              ; encoding: [0xdf,0xad]
ld sp, 5:i3
; unidasm: df 08 34 12  mul SP,0x1234
; CHECK: mul sp, 4660             ; encoding: [0xdf,0x08,0x34,0x12]
mul sp, 4660
; unidasm: d9 87  add SP,BC
; CHECK: add sp, bc               ; encoding: [0xd9,0x87]
add sp, bc
; unidasm: df 80  add WA,SP
; CHECK: add wa, sp               ; encoding: [0xdf,0x80]
add wa, sp
; unidasm: df 61  inc 1,SP
; CHECK: inc 1, sp                ; encoding: [0xdf,0x61]
inc 1, sp
; unidasm: df cf 34 12  cp SP,0x1234
; CHECK: cp sp, 4660              ; encoding: [0xdf,0xcf,0x34,0x12]
cp sp, 0x1234
; unidasm: df 04  push SP   (the register-prefix form; `pushw sp` is 2f)
; CHECK: push sp                  ; encoding: [0xdf,0x04]
push sp
; unidasm: 2f  push SP   -- the short form keeps its own spelling and bytes
; CHECK: pushw sp                 ; encoding: [0x2f]
pushw sp
