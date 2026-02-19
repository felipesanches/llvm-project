; REQUIRES: tlcs900
; RUN: llvm-mc -filetype=obj -triple=tlcs900 -o %t.o %s
; RUN: ld.lld -o %t.exe --Tdata=0x2000 --Ttext=0x8000 -z separate-code %t.o
; RUN: llvm-objdump -s %t.exe | FileCheck %s

;; Check handling of basic TLCS900 relocation types.

  .text
  .global _start
_start:
  nop
  ret

  .data
;; R_TLCS900_LO16
  .short _start
;; R_TLCS900_32
  .long _start

; CHECK:      Contents of section .data:
; CHECK-NEXT: 2000 00800080 0000
