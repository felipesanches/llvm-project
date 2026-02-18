; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test function calls with various argument counts

declare i32 @one_arg(i32)
declare i32 @four_args(i32, i32, i32, i32)
declare i32 @five_args(i32, i32, i32, i32, i32)

; Single argument: passed in XDE
define i32 @call_one(i32 %x) {
; CHECK-LABEL: call_one:
; CHECK:       call one_arg
; CHECK:       ret
  %r = call i32 @one_arg(i32 %x)
  ret i32 %r
}

; Four arguments: all in registers (XDE, XBC, XIX, XIY)
define i32 @call_four(i32 %a, i32 %b, i32 %c, i32 %d) {
; CHECK-LABEL: call_four:
; CHECK:       call four_args
; CHECK:       ret
  %r = call i32 @four_args(i32 %a, i32 %b, i32 %c, i32 %d)
  ret i32 %r
}

; Five arguments: first four in registers, fifth on stack
define i32 @call_five(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e) {
; CHECK-LABEL: call_five:
; CHECK:       call five_args
; CHECK:       ret
  %r = call i32 @five_args(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e)
  ret i32 %r
}

; Receiving five arguments: first four in registers, fifth from stack
define i32 @receive_five(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e) {
; CHECK-LABEL: receive_five:
; CHECK:       add xde,
; CHECK:       ret
  %sum1 = add i32 %a, %b
  %sum2 = add i32 %sum1, %c
  %sum3 = add i32 %sum2, %d
  %sum4 = add i32 %sum3, %e
  ret i32 %sum4
}
