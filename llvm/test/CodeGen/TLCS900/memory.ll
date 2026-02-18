; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test memory load/store instructions

define i32 @load_ptr(ptr %p) {
; CHECK-LABEL: load_ptr:
; CHECK:       ld xde, (xde)
; CHECK:       ret
  %val = load i32, ptr %p
  ret i32 %val
}

define void @store_ptr(ptr %p, i32 %val) {
; CHECK-LABEL: store_ptr:
; CHECK:       ld (xde), xbc
; CHECK:       ret
  store i32 %val, ptr %p
  ret void
}

@global_var = global i32 0

define i32 @load_global() {
; CHECK-LABEL: load_global:
; CHECK:       ld xde, (global_var)
; CHECK:       ret
  %val = load i32, ptr @global_var
  ret i32 %val
}

define void @store_global(i32 %val) {
; CHECK-LABEL: store_global:
; CHECK:       ld (global_var), xde
; CHECK:       ret
  store i32 %val, ptr @global_var
  ret void
}

define i32 @array_access(ptr %arr, i32 %idx) {
; CHECK-LABEL: array_access:
; CHECK:       sla xbc,
; CHECK:       add xde, xbc
; CHECK:       ld xde, (xde)
; CHECK:       ret
  %ptr = getelementptr i32, ptr %arr, i32 %idx
  %val = load i32, ptr %ptr
  ret i32 %val
}
