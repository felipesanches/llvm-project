; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test bit manipulation patterns
; SET32/RES32/CHG32 are invalid in the E8 (32-bit) prefix table.
; ISel now uses the generic OR32ri/AND32ri/XOR32ri immediate forms.

; SET: or with power-of-2 → or immediate
define i32 @set_bit3(i32 %a) {
; CHECK-LABEL: set_bit3:
; CHECK:       or xde, 8
; CHECK:       ret
  %r = or i32 %a, 8
  ret i32 %r
}

define i32 @set_bit0(i32 %a) {
; CHECK-LABEL: set_bit0:
; CHECK:       or xde, 1
; CHECK:       ret
  %r = or i32 %a, 1
  ret i32 %r
}

define i32 @set_bit31(i32 %a) {
; CHECK-LABEL: set_bit31:
; CHECK:       or xde, -2147483648
; CHECK:       ret
  %r = or i32 %a, -2147483648
  ret i32 %r
}

; RES: and with ~power-of-2 → and immediate
define i32 @clear_bit3(i32 %a) {
; CHECK-LABEL: clear_bit3:
; CHECK:       and xde, -9
; CHECK:       ret
  %r = and i32 %a, -9
  ret i32 %r
}

define i32 @clear_bit0(i32 %a) {
; CHECK-LABEL: clear_bit0:
; CHECK:       and xde, -2
; CHECK:       ret
  %r = and i32 %a, -2
  ret i32 %r
}

; CHG: xor with power-of-2 → xor immediate
define i32 @toggle_bit4(i32 %a) {
; CHECK-LABEL: toggle_bit4:
; CHECK:       xor xde, 16
; CHECK:       ret
  %r = xor i32 %a, 16
  ret i32 %r
}

define i32 @toggle_bit7(i32 %a) {
; CHECK-LABEL: toggle_bit7:
; CHECK:       xor xde, 128
; CHECK:       ret
  %r = xor i32 %a, 128
  ret i32 %r
}

; Non-power-of-2: should use generic OR/AND/XOR
define i32 @or_nonpow2(i32 %a) {
; CHECK-LABEL: or_nonpow2:
; CHECK:       or xde, 5
; CHECK:       ret
  %r = or i32 %a, 5
  ret i32 %r
}

define i32 @and_nonpow2(i32 %a) {
; CHECK-LABEL: and_nonpow2:
; CHECK:       and xde, -6
; CHECK:       ret
  %r = and i32 %a, -6
  ret i32 %r
}

define i32 @xor_nonpow2(i32 %a) {
; CHECK-LABEL: xor_nonpow2:
; CHECK:       xor xde, 3
; CHECK:       ret
  %r = xor i32 %a, 3
  ret i32 %r
}
