; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test arithmetic instructions

define i32 @add_reg(i32 %a, i32 %b) {
; CHECK-LABEL: add_reg:
; CHECK:       add xde, xbc
; CHECK:       ret
  %c = add i32 %a, %b
  ret i32 %c
}

define i32 @sub_reg(i32 %a, i32 %b) {
; CHECK-LABEL: sub_reg:
; CHECK:       sub xde, xbc
; CHECK:       ret
  %c = sub i32 %a, %b
  ret i32 %c
}

define i32 @add_imm(i32 %a) {
; CHECK-LABEL: add_imm:
; CHECK:       add xde, 100
; CHECK:       ret
  %c = add i32 %a, 100
  ret i32 %c
}

define i32 @sub_imm(i32 %a) {
; CHECK-LABEL: sub_imm:
; CHECK:       add xde, -50
; CHECK:       ret
  %c = sub i32 %a, 50
  ret i32 %c
}

; INC/DEC patterns for small constants (1-8)

define i32 @inc_1(i32 %a) {
; CHECK-LABEL: inc_1:
; CHECK:       inc 1, xde
; CHECK:       ret
  %c = add i32 %a, 1
  ret i32 %c
}

define i32 @inc_4(i32 %a) {
; CHECK-LABEL: inc_4:
; CHECK:       inc 4, xde
; CHECK:       ret
  %c = add i32 %a, 4
  ret i32 %c
}

define i32 @inc_8(i32 %a) {
; CHECK-LABEL: inc_8:
; CHECK:       inc 8, xde
; CHECK:       ret
  %c = add i32 %a, 8
  ret i32 %c
}

define i32 @dec_1(i32 %a) {
; CHECK-LABEL: dec_1:
; CHECK:       dec 1, xde
; CHECK:       ret
  %c = sub i32 %a, 1
  ret i32 %c
}

define i32 @dec_3(i32 %a) {
; CHECK-LABEL: dec_3:
; CHECK:       dec 3, xde
; CHECK:       ret
  %c = sub i32 %a, 3
  ret i32 %c
}
