; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test multi-operation sequences to exercise register allocation

; Simple expression: (a + b) * 2 via shift
define i32 @add_and_shift(i32 %a, i32 %b) {
; CHECK-LABEL: add_and_shift:
; CHECK:       add xde, xbc
; CHECK:       sla xde, 1
; CHECK:       ret
  %sum = add i32 %a, %b
  %result = shl i32 %sum, 1
  ret i32 %result
}

; abs(a) = (a < 0) ? -a : a
; Branchless abs: mask = sra(a, 31); result = (a ^ mask) - mask
define i32 @abs_manual(i32 %a) {
; CHECK-LABEL: abs_manual:
; CHECK:       sra {{x[a-z]+}}, 31
; CHECK:       xor
; CHECK:       sub
; CHECK:       ret
  %cmp = icmp slt i32 %a, 0
  %neg = sub i32 0, %a
  %result = select i1 %cmp, i32 %neg, i32 %a
  ret i32 %result
}

; min(a, b)
define i32 @min_signed(i32 %a, i32 %b) {
; CHECK-LABEL: min_signed:
; CHECK:       cp
; CHECK:       ret
  %cmp = icmp slt i32 %a, %b
  %result = select i1 %cmp, i32 %a, i32 %b
  ret i32 %result
}

; Chained arithmetic: a + b - c
define i32 @chain_arith(i32 %a, i32 %b, i32 %c) {
; CHECK-LABEL: chain_arith:
; CHECK:       add
; CHECK:       sub
; CHECK:       ret
  %sum = add i32 %a, %b
  %result = sub i32 %sum, %c
  ret i32 %result
}

; Bitwise operations: (a & mask) | (b & ~mask)
define i32 @bit_merge(i32 %a, i32 %b, i32 %mask) {
; CHECK-LABEL: bit_merge:
; CHECK:       and
; CHECK:       ret
  %amasked = and i32 %a, %mask
  %notmask = xor i32 %mask, -1
  %bmasked = and i32 %b, %notmask
  %result = or i32 %amasked, %bmasked
  ret i32 %result
}
