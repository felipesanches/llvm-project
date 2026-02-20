; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test BIT test-bit-and-branch peephole optimization.
; AND32ri+CP32ri+JPcc → BIT16+JPcc for power-of-2 bits 0-15.

; BIT bit 3: if (x & 8)
define i32 @test_bit3_branch(i32 %x) {
; CHECK-LABEL: test_bit3_branch:
; CHECK:       bit 3, de
; CHECK-NEXT:  jr nz,
; CHECK:       ret
entry:
  %masked = and i32 %x, 8
  %cmp = icmp ne i32 %masked, 0
  br i1 %cmp, label %then, label %else
then:
  ret i32 1
else:
  ret i32 0
}

; BIT bit 0: if (x & 1)
define i32 @test_bit0_branch(i32 %x) {
; CHECK-LABEL: test_bit0_branch:
; CHECK:       bit 0, de
; CHECK-NEXT:  jr nz,
; CHECK:       ret
entry:
  %masked = and i32 %x, 1
  %cmp = icmp ne i32 %masked, 0
  br i1 %cmp, label %then, label %else
then:
  ret i32 1
else:
  ret i32 0
}

; BIT bit 15: if (x & 32768)
define i32 @test_bit15_branch(i32 %x) {
; CHECK-LABEL: test_bit15_branch:
; CHECK:       bit 15, de
; CHECK-NEXT:  jr nz,
; CHECK:       ret
entry:
  %masked = and i32 %x, 32768
  %cmp = icmp ne i32 %masked, 0
  br i1 %cmp, label %then, label %else
then:
  ret i32 1
else:
  ret i32 0
}

; Bit 16: too high for D8 prefix, stays as AND+CP+JP
define i32 @test_bit16_branch(i32 %x) {
; CHECK-LABEL: test_bit16_branch:
; CHECK-NOT:   bit
; CHECK:       and xde,
; CHECK:       ret
entry:
  %masked = and i32 %x, 65536
  %cmp = icmp ne i32 %masked, 0
  br i1 %cmp, label %then, label %else
then:
  ret i32 1
else:
  ret i32 0
}

; AND result used later: no optimization (kill flag not set on CP)
define i32 @test_bit_result_used(i32 %x) {
; CHECK-LABEL: test_bit_result_used:
; CHECK-NOT:   bit
; CHECK:       and xde,
; CHECK:       ret
entry:
  %masked = and i32 %x, 8
  %cmp = icmp eq i32 %masked, 0
  br i1 %cmp, label %zero, label %nonzero
zero:
  ret i32 0
nonzero:
  ret i32 %masked
}
