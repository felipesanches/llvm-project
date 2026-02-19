; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test that a switch with enough cases generates a jump table
; rather than a chain of compare-and-branch.

define i32 @switch_jumptable(i32 %x) {
; CHECK-LABEL: switch_jumptable:
; CHECK: ld {{.*}}, .LJTI0_0
; CHECK: jp (
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

; CHECK: .LJTI0_0:
; CHECK-NEXT: .long
