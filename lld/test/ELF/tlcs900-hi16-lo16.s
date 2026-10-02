; REQUIRES: tlcs900
; RUN: llvm-mc -filetype=obj -triple=tlcs900 -o %t.o %s
; RUN: ld.lld -o %t.exe --Ttext=0xe45100 -z separate-code %t.o
; RUN: llvm-objdump -s --section=.text %t.exe | FileCheck %s

;; R_TLCS900_HI16 / R_TLCS900_LO16 from `sym@hi16` / `sym@lo16`: a far pointer
;; pushed as two words, high half first.  Str is at 0xe4510d.

  .text
  .global _start
_start:
  pushw Str@hi16
  pushw Str@lo16
  pushw Str@hi16 + 0xfffff4
  pushw Str@lo16 + 0xfffff4
  ret
Str:
  .asciz "A:\\"

;; 0b e400 / 0b 0d51 / hi16(0xe4510d+0xfffff4 = 0x1e45101) = 0x01e4, lo16 = 0x5101
; CHECK:      Contents of section .text:
; CHECK-NEXT: e45100 0be4000b 0d510be4 010b0151 0e413a5c
