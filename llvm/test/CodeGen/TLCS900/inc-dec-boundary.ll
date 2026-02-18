; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test INC/DEC boundary conditions: INC handles add 1-8, DEC handles sub 1-8.
; Values outside this range must use ADD/SUB with immediate.

define i32 @inc_boundary_8(i32 %a) {
; CHECK-LABEL: inc_boundary_8:
; CHECK:       inc 8, xde
; CHECK:       ret
  %c = add i32 %a, 8
  ret i32 %c
}

define i32 @add_9(i32 %a) {
; CHECK-LABEL: add_9:
; CHECK:       add xde, 9
; CHECK:       ret
  %c = add i32 %a, 9
  ret i32 %c
}

define i32 @dec_boundary_8(i32 %a) {
; CHECK-LABEL: dec_boundary_8:
; CHECK:       dec 8, xde
; CHECK:       ret
  %c = sub i32 %a, 8
  ret i32 %c
}

; sub 9 is outside DEC range, should use add with negative
define i32 @sub_9(i32 %a) {
; CHECK-LABEL: sub_9:
; CHECK:       add xde, -9
; CHECK:       ret
  %c = sub i32 %a, 9
  ret i32 %c
}

; Large constant subtraction
define i32 @sub_large(i32 %a) {
; CHECK-LABEL: sub_large:
; CHECK:       add xde, -1000
; CHECK:       ret
  %c = sub i32 %a, 1000
  ret i32 %c
}
