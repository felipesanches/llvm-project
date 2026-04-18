; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test compare and branch instructions

define i32 @max(i32 %a, i32 %b) {
; CHECK-LABEL: max:
; CHECK:       cp xde, xbc
; CHECK:       jr gt,
  %cmp = icmp sgt i32 %a, %b
  %sel = select i1 %cmp, i32 %a, i32 %b
  ret i32 %sel
}

define i32 @min(i32 %a, i32 %b) {
; CHECK-LABEL: min:
; CHECK:       cp xde, xbc
; CHECK:       jr lt,
  %cmp = icmp slt i32 %a, %b
  %sel = select i1 %cmp, i32 %a, i32 %b
  ret i32 %sel
}

define i32 @abs_val(i32 %a) {
; Optimizer transforms abs to branchless: sra + xor + sub
; CHECK-LABEL: abs_val:
; CHECK:       sra
; CHECK:       xor
; CHECK:       sub
; CHECK:       ret
  %neg = sub i32 0, %a
  %cmp = icmp slt i32 %a, 0
  %sel = select i1 %cmp, i32 %neg, i32 %a
  ret i32 %sel
}

define void @branch_eq(i32 %a, i32 %b, ptr %p) {
; CHECK-LABEL: branch_eq:
; CHECK:       cp xde, xbc
; CHECK:       jr nz,
entry:
  %cmp = icmp eq i32 %a, %b
  br i1 %cmp, label %if.then, label %if.end

if.then:
  store i32 1, ptr %p
  br label %if.end

if.end:
  ret void
}
