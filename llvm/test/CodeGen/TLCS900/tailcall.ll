; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test tail call optimization.
; When a function ends with a call whose result is immediately returned,
; it can be lowered to a jump instead of call+ret.

declare i32 @external_func(i32)
declare void @void_func(i32)

; Simple tail call: return value forwarded directly
define i32 @tail_call_simple(i32 %a) {
; CHECK-LABEL: tail_call_simple:
; CHECK:       jp external_func
  %r = tail call i32 @external_func(i32 %a)
  ret i32 %r
}

; Void tail call
define void @tail_call_void(i32 %a) {
; CHECK-LABEL: tail_call_void:
; CHECK:       jp void_func
  tail call void @void_func(i32 %a)
  ret void
}

; Non-tail call: result is used before return
define i32 @no_tail_call(i32 %a, i32 %b) {
; CHECK-LABEL: no_tail_call:
; CHECK:       call external_func
; CHECK:       add
; CHECK:       ret
  %r = call i32 @external_func(i32 %a)
  %sum = add i32 %r, %b
  ret i32 %sum
}

; Tail call to internal function
define internal i32 @helper(i32 %x) {
  %r = add i32 %x, 1
  ret i32 %r
}

define i32 @tail_call_internal(i32 %a) {
; CHECK-LABEL: tail_call_internal:
; CHECK:       jp helper
  %r = tail call i32 @helper(i32 %a)
  ret i32 %r
}
