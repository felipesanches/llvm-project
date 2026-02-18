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
