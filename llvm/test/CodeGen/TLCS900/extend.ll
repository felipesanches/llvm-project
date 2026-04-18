; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test sign/zero extension instructions

define i32 @sext_i16(i32 %a) {
; CHECK-LABEL: sext_i16:
; CHECK:       exts xde
; CHECK:       ret
  %trunc = trunc i32 %a to i16
  %ext = sext i16 %trunc to i32
  ret i32 %ext
}

define i32 @zext_i16(i32 %a) {
; CHECK-LABEL: zext_i16:
; CHECK:       extz xde
; CHECK:       ret
  %r = and i32 %a, 65535
  ret i32 %r
}

define i32 @zext_i8(i32 %a) {
; CHECK-LABEL: zext_i8:
; AND with 255 uses AND instruction (no hardware extz for 8-bit)
; CHECK:       and xde, 255
; CHECK:       ret
  %r = and i32 %a, 255
  ret i32 %r
}

define i32 @sext_i8(i32 %a) {
; CHECK-LABEL: sext_i8:
; i8 sign extend expands to shift pair (sla 24 / sra 24)
; CHECK:       sla xde,
; CHECK:       sra xde,
; CHECK:       ret
  %trunc = trunc i32 %a to i8
  %ext = sext i8 %trunc to i32
  ret i32 %ext
}
