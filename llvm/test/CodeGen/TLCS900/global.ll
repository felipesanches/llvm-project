; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s
; RUN: llc -mtriple=tlcs900 -filetype=obj < %s -o /dev/null

; Test global variable access (assembly and object emission)

@g = global i32 0

define i32 @load_global() {
; CHECK-LABEL: load_global:
; Direct memory addressing with global symbol
; CHECK:       ld xde, (g)
; CHECK:       ret
  %v = load i32, ptr @g
  ret i32 %v
}

define void @store_global(i32 %val) {
; CHECK-LABEL: store_global:
; Direct memory store to global symbol
; CHECK:       ld (g), xde
; CHECK:       ret
  store i32 %val, ptr @g
  ret void
}

@arr = global [4 x i32] zeroinitializer

define i32 @load_global_offset() {
; CHECK-LABEL: load_global_offset:
; Load from arr[2] (offset 8) using direct addressing
; CHECK:       ld xde, (arr+8)
; CHECK:       ret
  %ptr = getelementptr [4 x i32], ptr @arr, i32 0, i32 2
  %v = load i32, ptr %ptr
  ret i32 %v
}
