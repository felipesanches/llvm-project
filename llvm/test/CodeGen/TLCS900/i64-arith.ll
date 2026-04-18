; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test 64-bit arithmetic on 32-bit target.
; i64 add/sub use ADC/SBC for the high word carry propagation.
; i64 logic ops (and/or/xor) split into independent 32-bit halves.

define i64 @add64(i64 %a, i64 %b) {
; CHECK-LABEL: add64:
; CHECK: add xde, xix
; CHECK: adc xbc, xiy
; CHECK: ret
  %c = add i64 %a, %b
  ret i64 %c
}

define i64 @sub64(i64 %a, i64 %b) {
; CHECK-LABEL: sub64:
; CHECK: sub xde, xix
; CHECK: sbc xbc, xiy
; CHECK: ret
  %c = sub i64 %a, %b
  ret i64 %c
}

define i64 @and64(i64 %a, i64 %b) {
; CHECK-LABEL: and64:
; CHECK: and xde, xix
; CHECK: and xbc, xiy
; CHECK: ret
  %c = and i64 %a, %b
  ret i64 %c
}

define i64 @or64(i64 %a, i64 %b) {
; CHECK-LABEL: or64:
; CHECK: or xde, xix
; CHECK: or xbc, xiy
; CHECK: ret
  %c = or i64 %a, %b
  ret i64 %c
}

define i64 @xor64(i64 %a, i64 %b) {
; CHECK-LABEL: xor64:
; CHECK: xor xde, xix
; CHECK: xor xbc, xiy
; CHECK: ret
  %c = xor i64 %a, %b
  ret i64 %c
}

; Test i64 add with an immediate (only low word is non-zero).
define i64 @add64_imm(i64 %a) {
; CHECK-LABEL: add64_imm:
; CHECK: add xde, 100
; CHECK: adc xbc, 0
; CHECK: ret
  %c = add i64 %a, 100
  ret i64 %c
}
