; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test register spilling — force spill by using more values than registers.
; TLCS-900 has 7 allocatable GPRs (XWA, XBC, XDE, XHL, XIX, XIY, XIZ; XSP reserved).
; With callee-saved (XIX, XIY, XIZ), 4 are caller-saved.

declare i32 @use(i32)

; This function has enough live values to force spills to the stack.
define i32 @needs_spill(i32 %a, i32 %b, i32 %c, i32 %d) {
; CHECK-LABEL: needs_spill:
; Should see callee-saved register saves and function call
; CHECK:       push
; CHECK:       call use
; CHECK:       pop
; CHECK:       ret
entry:
  %v1 = add i32 %a, 1
  %v2 = add i32 %b, 2
  %v3 = add i32 %c, 3
  %v4 = add i32 %d, 4
  %v5 = add i32 %a, %b
  %v6 = add i32 %c, %d
  %v7 = add i32 %v1, %v2
  %v8 = add i32 %v3, %v4
  ; Call a function to clobber caller-saved registers
  %r = call i32 @use(i32 %v5)
  ; Use all values after the call — forces spills
  %s1 = add i32 %v1, %v6
  %s2 = add i32 %s1, %v7
  %s3 = add i32 %s2, %v8
  %s4 = add i32 %s3, %r
  ret i32 %s4
}
