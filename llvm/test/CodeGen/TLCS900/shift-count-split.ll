; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s
;
; One TLCS-900 shift moves 1..16 bits: the CPU reads the count byte as
; `count & 0x0F`, 0 meaning 16.  `x << 24` used to select `sla xde, 24`,
; which assembled ee ec 18 and shifted by 8.  Constant shifts of 17..31 are
; now two shifts.

; CHECK-LABEL: shl24:
; CHECK:       sla xde, 16
; CHECK-NEXT:  sla xde, 8
define i32 @shl24(i32 %x) {
  %r = shl i32 %x, 24
  ret i32 %r
}

; CHECK-LABEL: lshr20:
; CHECK:       srl xde, 16
; CHECK-NEXT:  srl xde, 4
define i32 @lshr20(i32 %x) {
  %r = lshr i32 %x, 20
  ret i32 %r
}

; CHECK-LABEL: ashr31:
; CHECK:       sra xde, 16
; CHECK-NEXT:  sra xde, 15
define i32 @ashr31(i32 %x) {
  %r = ashr i32 %x, 31
  ret i32 %r
}

; CHECK-LABEL: lshr16:
; CHECK:       srl xde, 16
; CHECK-NEXT:  ret
define i32 @lshr16(i32 %x) {
  %r = lshr i32 %x, 16
  ret i32 %r
}
