; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test stack frame and callee-saved registers

declare i32 @use(i32)

define i32 @needs_frame(i32 %a) {
; CHECK-LABEL: needs_frame:
; CHECK:       sub xsp,
; Callee-saved register is spilled to stack
; CHECK:       ld (xsp), xix
; CHECK:       call use
; Restore callee-saved register
; CHECK:       ld xix, (xsp)
; CHECK:       add xsp,
; CHECK:       ret
  %b = call i32 @use(i32 %a)
  %c = add i32 %a, %b
  ret i32 %c
}

define i32 @two_calls(i32 %a, i32 %b) {
; CHECK-LABEL: two_calls:
; CHECK:       sub xsp,
; CHECK:       call use
; CHECK:       call use
; CHECK:       add xsp,
; CHECK:       ret
  %r1 = call i32 @use(i32 %a)
  %r2 = call i32 @use(i32 %b)
  %sum = add i32 %r1, %r2
  ret i32 %sum
}
