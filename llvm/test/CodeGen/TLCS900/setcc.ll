; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test SETCC lowering to CP + SCC (branchless boolean)

define i32 @eq(i32 %a, i32 %b) {
; CHECK-LABEL: eq:
; CHECK: cp
; CHECK: scc z
  %cmp = icmp eq i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @ne(i32 %a, i32 %b) {
; CHECK-LABEL: ne:
; CHECK: cp
; CHECK: scc nz
  %cmp = icmp ne i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @slt(i32 %a, i32 %b) {
; CHECK-LABEL: slt:
; CHECK: cp
; CHECK: scc lt
  %cmp = icmp slt i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @sge(i32 %a, i32 %b) {
; CHECK-LABEL: sge:
; CHECK: cp
; CHECK: scc ge
  %cmp = icmp sge i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @ult(i32 %a, i32 %b) {
; CHECK-LABEL: ult:
; CHECK: cp
; CHECK: scc c
  %cmp = icmp ult i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @uge(i32 %a, i32 %b) {
; CHECK-LABEL: uge:
; CHECK: cp
; CHECK: scc nc
  %cmp = icmp uge i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

; Test that SETCC result can feed into arithmetic
define i32 @setcc_add(i32 %a, i32 %b, i32 %c) {
; CHECK-LABEL: setcc_add:
; CHECK: cp
; CHECK: scc
; CHECK: add
  %cmp = icmp eq i32 %a, %b
  %ext = zext i1 %cmp to i32
  %r = add i32 %ext, %c
  ret i32 %r
}
