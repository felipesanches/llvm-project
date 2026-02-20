; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test bit manipulation peephole optimization.
; SET16/RES16/CHG16 replace OR32ri/AND32ri/XOR32ri for power-of-2 bits 0-15.

; SET: or with power-of-2 (bit < 16) → set
define i32 @set_bit3(i32 %a) {
; CHECK-LABEL: set_bit3:
; CHECK:       set 3, de
; CHECK:       ret
  %r = or i32 %a, 8
  ret i32 %r
}

define i32 @set_bit0(i32 %a) {
; CHECK-LABEL: set_bit0:
; CHECK:       set 0, de
; CHECK:       ret
  %r = or i32 %a, 1
  ret i32 %r
}

; SET: bit 31 is >= 16, stays as or
define i32 @set_bit31(i32 %a) {
; CHECK-LABEL: set_bit31:
; CHECK:       or xde, -2147483648
; CHECK:       ret
  %r = or i32 %a, -2147483648
  ret i32 %r
}

; RES: and with ~power-of-2 (bit < 16) → res
define i32 @clear_bit3(i32 %a) {
; CHECK-LABEL: clear_bit3:
; CHECK:       res 3, de
; CHECK:       ret
  %r = and i32 %a, -9
  ret i32 %r
}

define i32 @clear_bit0(i32 %a) {
; CHECK-LABEL: clear_bit0:
; CHECK:       res 0, de
; CHECK:       ret
  %r = and i32 %a, -2
  ret i32 %r
}

; CHG: xor with power-of-2 (bit < 16) → chg
define i32 @toggle_bit4(i32 %a) {
; CHECK-LABEL: toggle_bit4:
; CHECK:       chg 4, de
; CHECK:       ret
  %r = xor i32 %a, 16
  ret i32 %r
}

define i32 @toggle_bit7(i32 %a) {
; CHECK-LABEL: toggle_bit7:
; CHECK:       chg 7, de
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
