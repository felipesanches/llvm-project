; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test memory operations: loads, stores, addressing modes

; Simple 32-bit load
define i32 @load32(ptr %p) {
; CHECK-LABEL: load32:
; CHECK: ld {{.*}}, ({{.*}})
  %v = load i32, ptr %p
  ret i32 %v
}

; Simple 32-bit store
define void @store32(ptr %p, i32 %v) {
; CHECK-LABEL: store32:
; CHECK: ld ({{.*}}), {{.*}}
  store i32 %v, ptr %p
  ret void
}

; Store immediate to memory
define void @store_imm(ptr %p) {
; CHECK-LABEL: store_imm:
; CHECK: ld ({{.*}}), 42
  store i32 42, ptr %p
  ret void
}

; Truncating store i32 → i16
define void @trunc_store16(ptr %p, i32 %v) {
; CHECK-LABEL: trunc_store16:
; CHECK: ld
  %t = trunc i32 %v to i16
  store i16 %t, ptr %p
  ret void
}

; Truncating store i32 → i8
define void @trunc_store8(ptr %p, i32 %v) {
; CHECK-LABEL: trunc_store8:
; CHECK: ld
  %t = trunc i32 %v to i8
  store i8 %t, ptr %p
  ret void
}

; Zero-extending load i16 → i32
define i32 @zext_load16(ptr %p) {
; CHECK-LABEL: zext_load16:
; CHECK: ld
; CHECK: extz
  %v = load i16, ptr %p
  %ext = zext i16 %v to i32
  ret i32 %ext
}

; Sign-extending load i16 → i32
define i32 @sext_load16(ptr %p) {
; CHECK-LABEL: sext_load16:
; CHECK: ld
; CHECK: exts
  %v = load i16, ptr %p
  %ext = sext i16 %v to i32
  ret i32 %ext
}

; Load from stack (frame index addressing)
; Note: store-then-load from same alloca is constant-folded
define i32 @stack_load() {
; CHECK-LABEL: stack_load:
; CHECK: ld xde, 100
  %a = alloca i32
  store i32 100, ptr %a
  %v = load i32, ptr %a
  ret i32 %v
}

; Array indexing (base + offset)
define i32 @array_access(ptr %arr) {
; CHECK-LABEL: array_access:
; CHECK: ld
  %ptr = getelementptr i32, ptr %arr, i32 3
  %v = load i32, ptr %ptr
  ret i32 %v
}
