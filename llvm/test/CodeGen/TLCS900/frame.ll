; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test stack frame with PUSH/POP for callee-saved registers

declare i32 @use(i32)

define i32 @needs_frame(i32 %a) {
; CHECK-LABEL: needs_frame:
; Callee-saved register is saved with PUSH
; CHECK:       push xix
; CHECK:       call use
; Restore with POP
; CHECK:       pop xix
; CHECK:       ret
  %b = call i32 @use(i32 %a)
  %c = add i32 %a, %b
  ret i32 %c
}

; Large stack frame: offset > 127 bytes uses d16 SRI prefix encoding
; (C3/D3/E3 for source memory, F3 for destination memory)
define i32 @large_frame(i32 %a) {
; CHECK-LABEL: large_frame:
; CHECK:       sub xsp,
; Stack access with large offset uses d16 displacement directly
; CHECK:       ld {{.*}}, (xsp+{{[0-9]+}})
; CHECK:       add xsp,
; CHECK:       ret
  %arr = alloca [64 x i32]
  store i32 %a, ptr %arr
  %p = getelementptr [64 x i32], ptr %arr, i32 0, i32 63
  %v = load i32, ptr %p
  ret i32 %v
}

define i32 @two_calls(i32 %a, i32 %b) {
; CHECK-LABEL: two_calls:
; Multiple callee-saved registers saved with PUSH
; CHECK:       push
; CHECK:       push
; CHECK:       call use
; CHECK:       call use
; Restore with POP (reverse order)
; CHECK:       pop
; CHECK:       pop
; CHECK:       ret
  %r1 = call i32 @use(i32 %a)
  %r2 = call i32 @use(i32 %b)
  %sum = add i32 %r1, %r2
  ret i32 %sum
}
