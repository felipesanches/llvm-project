; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test boolean operations and select patterns

; Simple select (should use branch diamond)
define i32 @select_cc(i32 %a, i32 %b, i32 %x, i32 %y) {
; CHECK-LABEL: select_cc:
; CHECK: cp
; CHECK: jr
  %cmp = icmp slt i32 %a, %b
  %r = select i1 %cmp, i32 %x, i32 %y
  ret i32 %r
}

; Boolean AND: (a == b) & (c == d) — two SCC expansions + AND
; The two diamonds may be reordered by scheduling, so just check key elements.
define i32 @bool_and(i32 %a, i32 %b, i32 %c, i32 %d) {
; CHECK-LABEL: bool_and:
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr
; CHECK: ld {{.*}}, 0
; CHECK: and
  %c1 = icmp eq i32 %a, %b
  %c2 = icmp eq i32 %c, %d
  %r = and i1 %c1, %c2
  %ext = zext i1 %r to i32
  ret i32 %ext
}

; Boolean OR: (a != 0) | (b != 0) — may be optimized to (a|b) != 0
define i32 @bool_or(i32 %a, i32 %b) {
; CHECK-LABEL: bool_or:
; CHECK: or
; CHECK: cp
; CHECK: ld {{.*}}, 1
; CHECK: jr
; CHECK: ld {{.*}}, 0
  %c1 = icmp ne i32 %a, 0
  %c2 = icmp ne i32 %b, 0
  %r = or i1 %c1, %c2
  %ext = zext i1 %r to i32
  ret i32 %ext
}

; Min function using select
define i32 @min_signed(i32 %a, i32 %b) {
; CHECK-LABEL: min_signed:
; CHECK: cp
; CHECK: jr
  %cmp = icmp slt i32 %a, %b
  %r = select i1 %cmp, i32 %a, i32 %b
  ret i32 %r
}

; Clamp to range [0, 255]
define i32 @clamp_byte(i32 %x) {
; CHECK-LABEL: clamp_byte:
; CHECK: cp
  %neg = icmp slt i32 %x, 0
  %lo = select i1 %neg, i32 0, i32 %x
  %high = icmp sgt i32 %lo, 255
  %r = select i1 %high, i32 255, i32 %lo
  ret i32 %r
}
