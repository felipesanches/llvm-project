; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test a realistic iterative fibonacci function that exercises:
; - Function prologue/epilogue
; - Loop with PHI nodes
; - Conditional branch
; - Multiple register values
; - Return value

define i32 @fibonacci(i32 %n) {
; CHECK-LABEL: fibonacci:
; CHECK:       cp
; CHECK:       ret
entry:
  %cmp = icmp slt i32 %n, 2
  br i1 %cmp, label %return, label %loop

loop:
  %i = phi i32 [ 2, %entry ], [ %i.next, %loop ]
  %a = phi i32 [ 0, %entry ], [ %b, %loop ]
  %b = phi i32 [ 1, %entry ], [ %sum, %loop ]
  %sum = add i32 %a, %b
  %i.next = add i32 %i, 1
  %done = icmp eq i32 %i.next, %n
  br i1 %done, label %return, label %loop

return:
  %result = phi i32 [ %n, %entry ], [ %sum, %loop ]
  ret i32 %result
}

; Test a simple leaf function with no calls (should have minimal prologue)
define i32 @square(i32 %x) {
; CHECK-LABEL: square:
; CHECK-NOT:   push
; CHECK:       ret
  %r = mul i32 %x, %x
  ret i32 %r
}

; Test switch-like cascading branches
define i32 @classify(i32 %x) {
; CHECK-LABEL: classify:
; CHECK:       cp
; CHECK:       ret
entry:
  %neg = icmp slt i32 %x, 0
  br i1 %neg, label %ret_neg, label %check_zero

check_zero:
  %zero = icmp eq i32 %x, 0
  br i1 %zero, label %ret_zero, label %ret_pos

ret_neg:
  ret i32 -1

ret_zero:
  ret i32 0

ret_pos:
  ret i32 1
}
