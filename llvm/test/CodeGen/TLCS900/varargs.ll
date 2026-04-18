; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test varargs support for TLCS900

declare void @llvm.va_start(ptr)
declare void @llvm.va_end(ptr)

; Test that a variadic function receives args on the stack (not in registers)
; and that va_start works correctly.
define i32 @variadic_sum(i32 %count, ...) {
; CHECK-LABEL: variadic_sum:
; va_start computes the address of the first vararg
; CHECK:       lda xwa, (xsp+
; Named arg (count) is loaded from stack too (vararg CC)
; CHECK:       ld xwa, (xsp+
; CHECK:       add xde,
; CHECK:       ret
entry:
  %ap = alloca ptr, align 4
  call void @llvm.va_start(ptr %ap)
  %arg = va_arg ptr %ap, i32
  call void @llvm.va_end(ptr %ap)
  %sum = add i32 %count, %arg
  ret i32 %sum
}

; Test calling a variadic function — all args should go on the stack
declare i32 @my_printf(ptr, ...)

define i32 @call_variadic(ptr %fmt, i32 %val) {
; CHECK-LABEL: call_variadic:
; Allocate stack space for args
; CHECK:       sub xsp, 8
; Args stored to stack (not passed in registers)
; CHECK-DAG:   ld (xwa+4), xbc
; CHECK-DAG:   ld (xwa), xde
; CHECK:       call my_printf
; CHECK:       add xsp, 8
; CHECK:       ret
  %r = call i32 (ptr, ...) @my_printf(ptr %fmt, i32 %val)
  ret i32 %r
}

; Test that non-variadic calls still use register passing
declare i32 @normal_func(i32, i32)

define i32 @call_normal(i32 %a, i32 %b) {
; CHECK-LABEL: call_normal:
; Non-variadic: no stack allocation for args, direct call
; CHECK-NOT:   sub xsp
; CHECK:       call normal_func
; CHECK:       ret
  %r = call i32 @normal_func(i32 %a, i32 %b)
  ret i32 %r
}
