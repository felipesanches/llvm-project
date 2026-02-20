; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test dynamic stack allocation with frame pointer support.
; When alloca is variable-sized, XIZ is used as frame pointer.

define ptr @dynamic_alloca(i32 %n) {
; CHECK-LABEL: dynamic_alloca:
; CHECK:       push xiz
; CHECK-NEXT:  ld xiz, xsp
; Dynamic alloca: aligns size, computes new SP in a register, then sets SP
; CHECK:       ld xsp,
; Epilogue: restore frame pointer
; CHECK:       ld xsp, xiz
; CHECK-NEXT:  pop xiz
; CHECK-NEXT:  ret
  %p = alloca i8, i32 %n
  ret ptr %p
}

define i32 @alloca_with_local(i32 %n) {
; CHECK-LABEL: alloca_with_local:
; Prologue: save frame pointer
; CHECK:       push xiz
; CHECK-NEXT:  ld xiz, xsp
; Allocate space for locals
; CHECK-NEXT:  sub xsp, 4
; Local accessed via FP-relative addressing
; CHECK:       ld (xiz), xwa
; Epilogue: restore frame pointer
; CHECK:       ld xsp, xiz
; CHECK-NEXT:  pop xiz
; CHECK-NEXT:  ret
  %local = alloca i32
  %vla = alloca i8, i32 %n
  store i32 42, ptr %local
  %val = load i32, ptr %local
  ret i32 %val
}
