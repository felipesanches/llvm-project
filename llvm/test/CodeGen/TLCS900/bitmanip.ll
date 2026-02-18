; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test bit manipulation patterns

define i32 @set_bit(i32 %a) {
; CHECK-LABEL: set_bit:
; CHECK:       or xde, 8
; CHECK:       ret
  %r = or i32 %a, 8
  ret i32 %r
}

define i32 @clear_bit(i32 %a) {
; CHECK-LABEL: clear_bit:
; CHECK:       and xde, -9
; CHECK:       ret
  %r = and i32 %a, -9
  ret i32 %r
}

define i32 @toggle_bit(i32 %a) {
; CHECK-LABEL: toggle_bit:
; CHECK:       xor xde, 16
; CHECK:       ret
  %r = xor i32 %a, 16
  ret i32 %r
}

define i1 @test_bit(i32 %a) {
; CHECK-LABEL: test_bit:
; CHECK:       and
; CHECK:       ret
  %masked = and i32 %a, 4
  %r = icmp ne i32 %masked, 0
  ret i1 %r
}
