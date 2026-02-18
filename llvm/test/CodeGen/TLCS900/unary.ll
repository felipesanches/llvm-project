; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test unary instructions: NEG and CPL

define i32 @negate(i32 %a) {
; CHECK-LABEL: negate:
; CHECK:       neg xde
; CHECK:       ret
  %r = sub i32 0, %a
  ret i32 %r
}

define i32 @complement(i32 %a) {
; CHECK-LABEL: complement:
; CHECK:       cpl xde
; CHECK:       ret
  %r = xor i32 %a, -1
  ret i32 %r
}
