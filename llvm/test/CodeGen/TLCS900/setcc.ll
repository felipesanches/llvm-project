; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test SETCC lowering to CP + branch-based boolean materialization
; SCC32 pseudo is expanded to: ld 1 / jp cc / ld 0 / PHI

define i32 @eq(i32 %a, i32 %b) {
; CHECK-LABEL: eq:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr z,
; CHECK: ld {{.*}}, 0
  %cmp = icmp eq i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @ne(i32 %a, i32 %b) {
; CHECK-LABEL: ne:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr nz,
; CHECK: ld {{.*}}, 0
  %cmp = icmp ne i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @slt(i32 %a, i32 %b) {
; CHECK-LABEL: slt:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr lt,
; CHECK: ld {{.*}}, 0
  %cmp = icmp slt i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @sge(i32 %a, i32 %b) {
; CHECK-LABEL: sge:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr ge,
; CHECK: ld {{.*}}, 0
  %cmp = icmp sge i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @ult(i32 %a, i32 %b) {
; CHECK-LABEL: ult:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr c,
; CHECK: ld {{.*}}, 0
  %cmp = icmp ult i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

define i32 @uge(i32 %a, i32 %b) {
; CHECK-LABEL: uge:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr nc,
; CHECK: ld {{.*}}, 0
  %cmp = icmp uge i32 %a, %b
  %r = zext i1 %cmp to i32
  ret i32 %r
}

; Test that SETCC result can feed into arithmetic
define i32 @setcc_add(i32 %a, i32 %b, i32 %c) {
; CHECK-LABEL: setcc_add:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr
; CHECK: ld {{.*}}, 0
; CHECK: add
  %cmp = icmp eq i32 %a, %b
  %ext = zext i1 %cmp to i32
  %r = add i32 %ext, %c
  ret i32 %r
}
