; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test multiply/divide (currently expands to libcalls for i32)

define i32 @mul_i32(i32 %a, i32 %b) {
; CHECK-LABEL: mul_i32:
; CHECK:       call __mulsi3
; CHECK:       ret
  %r = mul i32 %a, %b
  ret i32 %r
}

define i32 @sdiv_i32(i32 %a, i32 %b) {
; CHECK-LABEL: sdiv_i32:
; CHECK:       call __divsi3
; CHECK:       ret
  %r = sdiv i32 %a, %b
  ret i32 %r
}

define i32 @udiv_i32(i32 %a, i32 %b) {
; CHECK-LABEL: udiv_i32:
; CHECK:       call __udivsi3
; CHECK:       ret
  %r = udiv i32 %a, %b
  ret i32 %r
}

define i32 @srem_i32(i32 %a, i32 %b) {
; CHECK-LABEL: srem_i32:
; CHECK:       call __modsi3
; CHECK:       ret
  %r = srem i32 %a, %b
  ret i32 %r
}
