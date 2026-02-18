; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test stack-local variable access (SP+offset addressing)

define i32 @local_var() {
; CHECK-LABEL: local_var:
; Store-then-load from same alloca is constant-folded
; CHECK:       ld xde, 42
; CHECK:       ret
  %x = alloca i32
  store i32 42, ptr %x
  %val = load i32, ptr %x
  ret i32 %val
}

define i32 @multiple_locals(i32 %a, i32 %b) {
; CHECK-LABEL: multiple_locals:
; Stack allocation
; CHECK:       sub xsp,
; Multiple stores to different stack slots
; CHECK:       ld (xsp
; CHECK:       ld (xsp
; CHECK:       add xsp,
; CHECK:       ret
  %x = alloca i32
  %y = alloca i32
  store i32 %a, ptr %x
  store i32 %b, ptr %y
  %vx = load i32, ptr %x
  %vy = load i32, ptr %y
  %sum = add i32 %vx, %vy
  ret i32 %sum
}

define void @pass_stack_addr(i32 %val) {
; CHECK-LABEL: pass_stack_addr:
; CHECK:       sub xsp,
; CHECK:       ld (xsp
; CHECK:       call
; CHECK:       add xsp,
; CHECK:       ret
  %x = alloca i32
  store i32 %val, ptr %x
  call void @use_ptr(ptr %x)
  ret void
}

declare void @use_ptr(ptr)
