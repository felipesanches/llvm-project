; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test that rotates are correctly expanded to shift sequences.
; TLCS900 has hardware rotate-by-1 (RLC/RRC/RL/RR) but the backend
; uses Expand for ROTL/ROTR which generates shift-based code.

declare i32 @llvm.fshl.i32(i32, i32, i32)
declare i32 @llvm.fshr.i32(i32, i32, i32)

; Rotate left by variable amount
define i32 @rotl_var(i32 %a, i32 %b) {
; CHECK-LABEL: rotl_var:
; CHECK:       sla
; CHECK:       srl
; CHECK:       or
; CHECK:       ret
  %r = call i32 @llvm.fshl.i32(i32 %a, i32 %a, i32 %b)
  ret i32 %r
}

; Rotate right by variable amount
define i32 @rotr_var(i32 %a, i32 %b) {
; CHECK-LABEL: rotr_var:
; CHECK:       srl
; CHECK:       sla
; CHECK:       or
; CHECK:       ret
  %r = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 %b)
  ret i32 %r
}

; Rotate left by constant
define i32 @rotl_const(i32 %a) {
; CHECK-LABEL: rotl_const:
; CHECK:       srl
; CHECK:       sla
; CHECK:       or
; CHECK:       ret
  %r = call i32 @llvm.fshl.i32(i32 %a, i32 %a, i32 8)
  ret i32 %r
}
