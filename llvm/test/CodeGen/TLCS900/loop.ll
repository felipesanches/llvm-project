; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test loop code generation

define i32 @sum_to_n(i32 %n) {
; CHECK-LABEL: sum_to_n:
; Loop body with add/inc and branch back
; CHECK:       add
; CHECK:       inc
; CHECK:       cp
; CHECK:       jp
; CHECK:       ret
entry:
  br label %loop

loop:
  %i = phi i32 [0, %entry], [%i.next, %loop]
  %sum = phi i32 [0, %entry], [%sum.next, %loop]
  %sum.next = add i32 %sum, %i
  %i.next = add i32 %i, 1
  %cmp = icmp slt i32 %i.next, %n
  br i1 %cmp, label %loop, label %exit

exit:
  ret i32 %sum.next
}

define i32 @countdown(i32 %n) {
; CHECK-LABEL: countdown:
; Loop with decrement and branch
; CHECK:       dec
; CHECK:       cp
; CHECK:       jp
; CHECK:       ret
entry:
  br label %loop

loop:
  %i = phi i32 [%n, %entry], [%i.next, %loop]
  %i.next = sub i32 %i, 1
  %cmp = icmp sgt i32 %i.next, 0
  br i1 %cmp, label %loop, label %exit

exit:
  ret i32 %i.next
}

define void @memset_loop(ptr %dst, i32 %val, i32 %count) {
; CHECK-LABEL: memset_loop:
; CHECK:       cp
; CHECK:       jp
; Loop body
; CHECK:       ld (
; CHECK:       inc
; CHECK:       cp
; CHECK:       jp
; CHECK:       ret
entry:
  %cmp0 = icmp sgt i32 %count, 0
  br i1 %cmp0, label %loop, label %exit

loop:
  %i = phi i32 [0, %entry], [%i.next, %loop]
  %ptr = getelementptr i32, ptr %dst, i32 %i
  store i32 %val, ptr %ptr
  %i.next = add i32 %i, 1
  %cmp = icmp slt i32 %i.next, %count
  br i1 %cmp, label %loop, label %exit

exit:
  ret void
}
