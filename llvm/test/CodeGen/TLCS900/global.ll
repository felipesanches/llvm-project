; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test global variable access

@g = global i32 0

define i32 @load_global() {
; CHECK-LABEL: load_global:
; CHECK:       ld {{x[a-z]+}}, g
; CHECK:       ld xde, ({{x[a-z]+}})
; CHECK:       ret
  %v = load i32, ptr @g
  ret i32 %v
}

define void @store_global(i32 %val) {
; CHECK-LABEL: store_global:
; CHECK:       ld {{x[a-z]+}}, g
; CHECK:       ld ({{x[a-z]+}}), xde
; CHECK:       ret
  store i32 %val, ptr @g
  ret void
}

@arr = global [4 x i32] zeroinitializer

define i32 @load_global_offset() {
; CHECK-LABEL: load_global_offset:
; Load from arr[2] (offset 8)
; CHECK:       ld {{x[a-z]+}}, arr
; CHECK:       ld xde, ({{x[a-z]+}}
; CHECK:       ret
  %ptr = getelementptr [4 x i32], ptr @arr, i32 0, i32 2
  %v = load i32, ptr %ptr
  ret i32 %v
}
