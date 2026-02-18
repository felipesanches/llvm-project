; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test basic return values

define i32 @return_const() {
; CHECK-LABEL: return_const:
; CHECK:       ld xde, 42
; CHECK-NEXT:  ret
  ret i32 42
}

define i32 @return_zero() {
; CHECK-LABEL: return_zero:
; CHECK:       ld xde, 0
; CHECK-NEXT:  ret
  ret i32 0
}

define i32 @return_arg(i32 %a) {
; CHECK-LABEL: return_arg:
; CHECK:       ret
  ret i32 %a
}
