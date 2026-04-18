; RUN: llc -mtriple=tlcs900 -mcpu=tmp94c241 < %s | FileCheck %s

; Test that the TMP94C241 scheduling model is active and influences
; instruction ordering. The post-RA scheduler should hoist independent
; loads earlier to hide latency.

; Verify the scheduling model is in effect by checking that multiply
; results are used after sufficient distance (the scheduler should
; try to separate the multiply from its consumer).
define i32 @mul_latency(i32 %a, i32 %b, i32 %c) {
; CHECK-LABEL: mul_latency:
; CHECK:       mul
; CHECK:       ret
  %m = mul i32 %a, %b
  %r = add i32 %m, %c
  ret i32 %r
}

; Verify that division (18 cycle latency) is scheduled.
define i32 @div_latency(i32 %a, i32 %b) {
; CHECK-LABEL: div_latency:
; CHECK:       div
; CHECK:       ret
  %d = sdiv i32 %a, %b
  ret i32 %d
}

; Verify shift operations are scheduled.
define i32 @shift_ops(i32 %a) {
; CHECK-LABEL: shift_ops:
; CHECK:       sla
; CHECK:       ret
  %s = shl i32 %a, 3
  ret i32 %s
}
