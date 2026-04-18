; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test that a switch with enough cases generates a jump table
; rather than a chain of compare-and-branch. The backend uses
; custom BR_JT lowering: scale index by 4, load table base,
; add offset, load target address, jp (reg).

; Test 1: Simple return values — verifies basic jump table structure
define i32 @switch_jumptable(i32 %x) {
; CHECK-LABEL: switch_jumptable:
; Bounds check: compare and branch past table for out-of-range
; CHECK: cp
; Jump table dispatch sequence:
; CHECK: sla {{.*}}, 2
; CHECK: ld {{.*}}, .LJTI0_0
; CHECK: add
; CHECK: ld {{.*}}, (
; CHECK: jp (
; Verify no compare-and-branch chain
; CHECK-NOT: cp {{.*}}, 1
; CHECK-NOT: cp {{.*}}, 2
entry:
  switch i32 %x, label %default [
    i32 0, label %bb0
    i32 1, label %bb1
    i32 2, label %bb2
    i32 3, label %bb3
    i32 4, label %bb4
    i32 5, label %bb5
  ]

bb0:
  ret i32 10
bb1:
  ret i32 20
bb2:
  ret i32 30
bb3:
  ret i32 40
bb4:
  ret i32 50
bb5:
  ret i32 60
default:
  ret i32 0
}

; Verify jump table data section with 32-bit entries
; CHECK: .LJTI0_0:
; CHECK-NEXT: .word
; CHECK-NEXT: .word
; CHECK-NEXT: .word
; CHECK-NEXT: .word
; CHECK-NEXT: .word
; CHECK-NEXT: .word

; Test 2: Switch with side effects (function calls) — can't be optimized
; to arithmetic, must use a real jump table
declare void @handler0()
declare void @handler1()
declare void @handler2()
declare void @handler3()
declare void @handler4()
declare void @handler5()
declare void @handler6()
declare void @handler7()

define void @switch_dispatch(i32 %cmd) {
; CHECK-LABEL: switch_dispatch:
; CHECK: sla {{.*}}, 2
; CHECK: ld {{.*}}, .LJTI1_0
; CHECK: jp (
entry:
  switch i32 %cmd, label %exit [
    i32 0, label %case0
    i32 1, label %case1
    i32 2, label %case2
    i32 3, label %case3
    i32 4, label %case4
    i32 5, label %case5
    i32 6, label %case6
    i32 7, label %case7
  ]

case0:
  call void @handler0()
  br label %exit
case1:
  call void @handler1()
  br label %exit
case2:
  call void @handler2()
  br label %exit
case3:
  call void @handler3()
  br label %exit
case4:
  call void @handler4()
  br label %exit
case5:
  call void @handler5()
  br label %exit
case6:
  call void @handler6()
  br label %exit
case7:
  call void @handler7()
  br label %exit
exit:
  ret void
}

; Verify second jump table
; CHECK: .LJTI1_0:
; CHECK-NEXT: .word
