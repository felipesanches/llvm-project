; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test branch shortening: JP (4 bytes) -> JR (2 bytes) for small functions.
; JPcc (3 bytes, JRL cc) -> JRcc (2 bytes) when target is close.

; Simple conditional: should use short relative branch (jr) not jp.
define i32 @if_else(i32 %a) {
; CHECK-LABEL: if_else:
; CHECK: jr
; CHECK: ret
  %cmp = icmp eq i32 %a, 0
  br i1 %cmp, label %zero, label %nonzero
zero:
  ret i32 0
nonzero:
  ret i32 1
}

; Two-way branch with both paths returning: both branches should be short.
define i32 @two_way(i32 %a, i32 %b) {
; CHECK-LABEL: two_way:
; CHECK: jr
; CHECK: ret
  %cmp = icmp slt i32 %a, %b
  br i1 %cmp, label %less, label %geq
less:
  ret i32 -1
geq:
  ret i32 1
}

; Diamond control flow: conditional + unconditional branches should shorten.
define i32 @diamond(i32 %a, i32 %b) {
; CHECK-LABEL: diamond:
; CHECK: jr
; CHECK: ret
  %cmp = icmp sgt i32 %a, %b
  br i1 %cmp, label %then, label %else
then:
  %r1 = add i32 %a, 1
  br label %merge
else:
  %r2 = sub i32 %b, 1
  br label %merge
merge:
  %r = phi i32 [%r1, %then], [%r2, %else]
  ret i32 %r
}
