; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test constant materialization

define i32 @const_zero() {
; CHECK-LABEL: const_zero:
; CHECK:       lds32 xde, 0
; CHECK:       ret
  ret i32 0
}

define i32 @const_one() {
; CHECK-LABEL: const_one:
; CHECK:       lds32 xde, 1
; CHECK:       ret
  ret i32 1
}

define i32 @const_neg_one() {
; CHECK-LABEL: const_neg_one:
; CHECK:       ld xde, -1
; CHECK:       ret
  ret i32 -1
}

define i32 @const_large() {
; CHECK-LABEL: const_large:
; CHECK:       ld xde, 305419896
; CHECK:       ret
  ret i32 305419896  ; 0x12345678
}

define i32 @const_max() {
; CHECK-LABEL: const_max:
; CHECK:       ld xde, 2147483647
; CHECK:       ret
  ret i32 2147483647  ; 0x7FFFFFFF
}
