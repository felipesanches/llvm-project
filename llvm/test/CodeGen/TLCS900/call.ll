; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test function call conventions

declare i32 @external_func(i32)

define i32 @call_one_arg(i32 %a) {
; CHECK-LABEL: call_one_arg:
; CHECK:       call external_func
; CHECK:       ret
  %result = call i32 @external_func(i32 %a)
  ret i32 %result
}

declare i32 @two_args(i32, i32)

define i32 @call_two_args(i32 %a, i32 %b) {
; CHECK-LABEL: call_two_args:
; CHECK:       call two_args
; CHECK:       ret
  %result = call i32 @two_args(i32 %a, i32 %b)
  ret i32 %result
}

define i32 @call_with_stack_args(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e) {
; CHECK-LABEL: call_with_stack_args:
; The 5th arg should be accessed from the stack
; CHECK:       ret
  %sum1 = add i32 %a, %b
  %sum2 = add i32 %sum1, %c
  %sum3 = add i32 %sum2, %d
  %sum4 = add i32 %sum3, %e
  ret i32 %sum4
}
