; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test conditional select (SELECT_CC lowering to branch diamond)

define i32 @select_eq(i32 %a, i32 %b, i32 %x, i32 %y) {
; CHECK-LABEL: select_eq:
; CHECK:       cp xde, xbc
; CHECK:       jr z,
; CHECK:       ret
  %cmp = icmp eq i32 %a, %b
  %sel = select i1 %cmp, i32 %x, i32 %y
  ret i32 %sel
}

define i32 @select_ne(i32 %a, i32 %b, i32 %x, i32 %y) {
; CHECK-LABEL: select_ne:
; CHECK:       cp xde, xbc
; CHECK:       jr nz,
; CHECK:       ret
  %cmp = icmp ne i32 %a, %b
  %sel = select i1 %cmp, i32 %x, i32 %y
  ret i32 %sel
}

define i32 @select_unsigned(i32 %a, i32 %b, i32 %x, i32 %y) {
; CHECK-LABEL: select_unsigned:
; CHECK:       cp xde, xbc
; CHECK:       jr ugt,
; CHECK:       ret
  %cmp = icmp ugt i32 %a, %b
  %sel = select i1 %cmp, i32 %x, i32 %y
  ret i32 %sel
}

define i32 @clamp_positive(i32 %a) {
; CHECK-LABEL: clamp_positive:
; CHECK:       cp
; CHECK:       jr
; CHECK:       ret
  %cmp = icmp sgt i32 %a, 0
  %sel = select i1 %cmp, i32 %a, i32 0
  ret i32 %sel
}
