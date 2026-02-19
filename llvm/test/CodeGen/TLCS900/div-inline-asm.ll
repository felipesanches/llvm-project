; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test that hardware DIV/DIVS instructions are accessible via inline asm.
; The TLCS-900/H provides 32÷16→16q+16r division, but i32 SDIV/UDIV/SREM/UREM
; use libcalls because the hardware only handles 32÷16, not general 32÷32.

define i32 @hw_div(i32 %dividend, i32 %divisor) {
; CHECK-LABEL: hw_div:
; CHECK:       div
; CHECK:       ret
  %result = call i32 asm "div $0, $1", "=r,r,0"(i32 %divisor, i32 %dividend)
  ret i32 %result
}

define i32 @hw_divs(i32 %dividend, i32 %divisor) {
; CHECK-LABEL: hw_divs:
; CHECK:       divs
; CHECK:       ret
  %result = call i32 asm "divs $0, $1", "=r,r,0"(i32 %divisor, i32 %dividend)
  ret i32 %result
}
