; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test load-folding into compare instructions (CISC memory-register compare)

; Compare value in memory with a register
define i32 @cmp_mem_reg(ptr %p, i32 %val) {
; CHECK-LABEL: cmp_mem_reg:
; The load from %p should be folded into the compare:
; CHECK:       cp ({{x[a-z]+}}), {{x[a-z]+}}
; CHECK:       ret
  %loaded = load i32, ptr %p
  %cmp = icmp eq i32 %loaded, %val
  %r = select i1 %cmp, i32 1, i32 0
  ret i32 %r
}

; Compare value in memory with an immediate
; CP32mi is invalid in the A0 (32-bit) table, so this expands to LD + CP.
define i32 @cmp_mem_imm(ptr %p) {
; CHECK-LABEL: cmp_mem_imm:
; CHECK:       ld [[TMP:x[a-z]+]], ({{x[a-z]+}})
; CHECK:       cp [[TMP]], 42
; CHECK:       ret
  %loaded = load i32, ptr %p
  %cmp = icmp eq i32 %loaded, 42
  %r = select i1 %cmp, i32 1, i32 0
  ret i32 %r
}
