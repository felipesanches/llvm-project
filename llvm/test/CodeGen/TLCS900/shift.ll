; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test shift instructions

; Variable shifts: copy count to XWA (A register), then use slaa/sraa/srla.
; Destination constrained to GPRnoXWA (XDE here since XWA holds the count).

define i32 @shl_reg(i32 %a, i32 %b) {
; CHECK-LABEL: shl_reg:
; CHECK:       ld xwa, xbc
; CHECK-NEXT:  slaa xde
; CHECK-NEXT:  ret
  %c = shl i32 %a, %b
  ret i32 %c
}

define i32 @sra_reg(i32 %a, i32 %b) {
; CHECK-LABEL: sra_reg:
; CHECK:       ld xwa, xbc
; CHECK-NEXT:  sraa xde
; CHECK-NEXT:  ret
  %c = ashr i32 %a, %b
  ret i32 %c
}

define i32 @srl_reg(i32 %a, i32 %b) {
; CHECK-LABEL: srl_reg:
; CHECK:       ld xwa, xbc
; CHECK-NEXT:  srla xde
; CHECK-NEXT:  ret
  %c = lshr i32 %a, %b
  ret i32 %c
}

; Shift-by-immediate tests (should use immediate form, not load+register)

define i32 @shl_imm(i32 %a) {
; CHECK-LABEL: shl_imm:
; CHECK:       sla xde, 4
; CHECK:       ret
  %c = shl i32 %a, 4
  ret i32 %c
}

define i32 @sra_imm(i32 %a) {
; CHECK-LABEL: sra_imm:
; CHECK:       sra xde, 8
; CHECK:       ret
  %c = ashr i32 %a, 8
  ret i32 %c
}

define i32 @srl_imm(i32 %a) {
; CHECK-LABEL: srl_imm:
; CHECK:       srl xde, 16
; CHECK:       ret
  %c = lshr i32 %a, 16
  ret i32 %c
}

define i32 @shl_1(i32 %a) {
; CHECK-LABEL: shl_1:
; CHECK:       sla xde, 1
; CHECK:       ret
  %c = shl i32 %a, 1
  ret i32 %c
}
