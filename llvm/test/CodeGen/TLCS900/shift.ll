; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test shift instructions

define i32 @shl_reg(i32 %a, i32 %b) {
; CHECK-LABEL: shl_reg:
; CHECK:       sla xde, xbc
; CHECK:       ret
  %c = shl i32 %a, %b
  ret i32 %c
}

define i32 @sra_reg(i32 %a, i32 %b) {
; CHECK-LABEL: sra_reg:
; CHECK:       sra xde, xbc
; CHECK:       ret
  %c = ashr i32 %a, %b
  ret i32 %c
}

define i32 @srl_reg(i32 %a, i32 %b) {
; CHECK-LABEL: srl_reg:
; CHECK:       srl xde, xbc
; CHECK:       ret
  %c = lshr i32 %a, %b
  ret i32 %c
}
