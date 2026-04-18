; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test 8-bit and 16-bit extending loads

define i32 @load_zext_i16(ptr %p) {
; CHECK-LABEL: load_zext_i16:
; Load 16-bit and zero-extend
; CHECK:       ld de, (xde
; CHECK:       extz xde
; CHECK:       ret
  %val = load i16, ptr %p
  %ext = zext i16 %val to i32
  ret i32 %ext
}

define i32 @load_sext_i16(ptr %p) {
; CHECK-LABEL: load_sext_i16:
; Load 16-bit and sign-extend
; CHECK:       ld de, (xde
; CHECK:       exts xde
; CHECK:       ret
  %val = load i16, ptr %p
  %ext = sext i16 %val to i32
  ret i32 %ext
}

define i32 @load_zext_i8(ptr %p) {
; CHECK-LABEL: load_zext_i8:
; Load 8-bit and zero-extend (AND with 255)
; CHECK:       ld e, (xde
; CHECK:       and xde, 255
; CHECK:       ret
  %val = load i8, ptr %p
  %ext = zext i8 %val to i32
  ret i32 %ext
}

define i32 @load_sext_i8(ptr %p) {
; CHECK-LABEL: load_sext_i8:
; Load 8-bit and sign-extend (shift pair)
; CHECK:       ld e, (xde
; CHECK:       sla xde, 24
; CHECK:       sra xde, 24
; CHECK:       ret
  %val = load i8, ptr %p
  %ext = sext i8 %val to i32
  ret i32 %ext
}
