; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test that hardware DIV/DIVS instructions are accessible via inline asm.
; The TLCS-900/H provides 32÷16→16q+16r division, but i32 SDIV/UDIV/SREM/UREM
; use libcalls because the hardware only handles 32÷16, not general 32÷32.

define i32 @hw_div(i32 %dividend, i32 %divisor) {
; CHECK-LABEL: hw_div:
; CHECK:       div xwa, xbc
; CHECK:       ret
  %result = call i32 asm sideeffect "div xwa, xbc", "={xwa},{xwa},{xbc}"(i32 %dividend, i32 %divisor)
  ret i32 %result
}

define i32 @hw_divs(i32 %dividend, i32 %divisor) {
; CHECK-LABEL: hw_divs:
; CHECK:       divs xwa, xbc
; CHECK:       ret
  %result = call i32 asm sideeffect "divs xwa, xbc", "={xwa},{xwa},{xbc}"(i32 %dividend, i32 %divisor)
  ret i32 %result
}
