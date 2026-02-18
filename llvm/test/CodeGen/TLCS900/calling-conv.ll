; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test calling convention: register args, stack args, return values

; First 4 args in registers (XDE, XBC, XIX, XIY)
define i32 @four_args(i32 %a, i32 %b, i32 %c, i32 %d) {
; CHECK-LABEL: four_args:
; CHECK: add
; CHECK: add
; CHECK: add
  %ab = add i32 %a, %b
  %abc = add i32 %ab, %c
  %abcd = add i32 %abc, %d
  ret i32 %abcd
}

; Fifth arg goes on stack
define i32 @five_args(i32 %a, i32 %b, i32 %c, i32 %d, i32 %e) {
; CHECK-LABEL: five_args:
; CHECK: add
  %sum = add i32 %a, %e
  ret i32 %sum
}

; Simple function call
declare i32 @external_func(i32)

define i32 @test_call(i32 %x) {
; CHECK-LABEL: test_call:
; CHECK: call external_func
  %r = call i32 @external_func(i32 %x)
  ret i32 %r
}

; Call with multiple args
declare i32 @multi_arg(i32, i32, i32)

define i32 @test_multi_call(i32 %a, i32 %b) {
; CHECK-LABEL: test_multi_call:
; CHECK: call multi_arg
  %r = call i32 @multi_arg(i32 %a, i32 %b, i32 100)
  ret i32 %r
}

; Leaf function (no calls, no frame needed for small functions)
define i32 @leaf_add(i32 %a, i32 %b) {
; CHECK-LABEL: leaf_add:
; CHECK: add
; CHECK: ret
  %r = add i32 %a, %b
  ret i32 %r
}

; Return void
define void @return_void() {
; CHECK-LABEL: return_void:
; CHECK: ret
  ret void
}
