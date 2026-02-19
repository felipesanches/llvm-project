; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test unary instructions: NEG and CPL
; NEG32 and CPL32 are invalid in the E8 (32-bit) prefix table.
; NEG is expanded to XOR with -1 then INC 1 (two's complement negate).
; CPL is expanded to XOR with -1 (bitwise NOT).

define i32 @negate(i32 %a) {
; CHECK-LABEL: negate:
; CHECK:       xor xde, -1
; CHECK:       inc 1, xde
; CHECK:       ret
  %r = sub i32 0, %a
  ret i32 %r
}

define i32 @complement(i32 %a) {
; CHECK-LABEL: complement:
; CHECK:       xor xde, -1
; CHECK:       ret
  %r = xor i32 %a, -1
  ret i32 %r
}
