; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test 8-bit and 16-bit truncating stores

define void @store_byte(ptr %p, i32 %val) {
; CHECK-LABEL: store_byte:
; CHECK:       ld (xde), c
; CHECK:       ret
  %trunc = trunc i32 %val to i8
  store i8 %trunc, ptr %p
  ret void
}

define void @store_halfword(ptr %p, i32 %val) {
; CHECK-LABEL: store_halfword:
; CHECK:       ld (xde), bc
; CHECK:       ret
  %trunc = trunc i32 %val to i16
  store i16 %trunc, ptr %p
  ret void
}

define void @store_byte_imm(ptr %p) {
; CHECK-LABEL: store_byte_imm:
; CHECK:       ld
; CHECK:       ret
  store i8 42, ptr %p
  ret void
}

@global_byte = global i8 0

define void @store_global_byte(i32 %val) {
; CHECK-LABEL: store_global_byte:
; CHECK:       ld (global_byte
; CHECK:       ret
  %trunc = trunc i32 %val to i8
  store i8 %trunc, ptr @global_byte
  ret void
}
