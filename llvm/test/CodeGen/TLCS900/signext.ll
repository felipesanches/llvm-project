; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test sign/zero extension patterns

; EXTS: sign extend i16 to i32
define i32 @sext_i16_to_i32(i32 %a) {
; CHECK-LABEL: sext_i16_to_i32:
; CHECK:       exts xde
; CHECK:       ret
  %trunc = trunc i32 %a to i16
  %ext = sext i16 %trunc to i32
  ret i32 %ext
}

; EXTZ: zero extend i16 to i32 (AND with 0xFFFF)
define i32 @zext_i16_to_i32(i32 %a) {
; CHECK-LABEL: zext_i16_to_i32:
; CHECK:       extz xde
; CHECK:       ret
  %masked = and i32 %a, 65535
  ret i32 %masked
}

; Zero extend i8 to i32 (AND with 0xFF)
define i32 @zext_i8_to_i32(i32 %a) {
; CHECK-LABEL: zext_i8_to_i32:
; CHECK:       and xde, 255
; CHECK:       ret
  %masked = and i32 %a, 255
  ret i32 %masked
}

; Sign extend i8 to i32 (shift pair: SLA 24 + SRA 24)
define i32 @sext_i8_to_i32(i32 %a) {
; CHECK-LABEL: sext_i8_to_i32:
; CHECK:       sla xde, 24
; CHECK-NEXT:  sra xde, 24
; CHECK:       ret
  %trunc = trunc i32 %a to i8
  %ext = sext i8 %trunc to i32
  ret i32 %ext
}
