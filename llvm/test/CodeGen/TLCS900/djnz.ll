; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test DJNZ peephole: DEC + CP + JPcc NZ -> DJNZ for count-down loops.

; Simple count-down loop: decrement and branch if not zero.
define void @count_down(i32 %n) {
; CHECK-LABEL: count_down:
; CHECK: djnz
; CHECK: ret
entry:
  br label %loop
loop:
  %i = phi i32 [%n, %entry], [%dec, %loop]
  %dec = add i32 %i, -1
  %cmp = icmp ne i32 %dec, 0
  br i1 %cmp, label %loop, label %exit
exit:
  ret void
}

; Count-down loop with work in the body (store to memory).
define void @count_down_store(i32 %n, ptr %p) {
; CHECK-LABEL: count_down_store:
; CHECK: djnz
; CHECK: ret
entry:
  br label %loop
loop:
  %i = phi i32 [%n, %entry], [%dec, %loop]
  store volatile i32 %i, ptr %p
  %dec = add i32 %i, -1
  %cmp = icmp ne i32 %dec, 0
  br i1 %cmp, label %loop, label %exit
exit:
  ret void
}
