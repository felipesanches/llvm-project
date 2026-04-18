; RUN: llvm-mc -triple tlcs900 -filetype=obj < %s -o %t.o
; RUN: llvm-objdump -s -j .text %t.o | FileCheck %s
;
; Test that .hword (16-bit), .word (32-bit), and .dword (64-bit) data
; directives are recognized and emit correct little-endian bytes.

; CHECK: Contents of section .text:
; CHECK-NEXT: 0000 78563412 0000efbe adde0000 0000
.hword 0x5678
.word  0x1234
.dword 0xDEADBEEF
