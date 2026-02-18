; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test logic instructions

define i32 @and_reg(i32 %a, i32 %b) {
; CHECK-LABEL: and_reg:
; CHECK:       and xde, xbc
; CHECK:       ret
  %c = and i32 %a, %b
  ret i32 %c
}

define i32 @or_reg(i32 %a, i32 %b) {
; CHECK-LABEL: or_reg:
; CHECK:       or xde, xbc
; CHECK:       ret
  %c = or i32 %a, %b
  ret i32 %c
}

define i32 @xor_reg(i32 %a, i32 %b) {
; CHECK-LABEL: xor_reg:
; CHECK:       xor xde, xbc
; CHECK:       ret
  %c = xor i32 %a, %b
  ret i32 %c
}

define i32 @and_imm(i32 %a) {
; CHECK-LABEL: and_imm:
; CHECK:       and xde, 255
; CHECK:       ret
  %c = and i32 %a, 255
  ret i32 %c
}

define i32 @or_imm(i32 %a) {
; CHECK-LABEL: or_imm:
; CHECK:       set 7, xde
; CHECK:       ret
  %c = or i32 %a, 128
  ret i32 %c
}

define i32 @xor_imm(i32 %a) {
; CHECK-LABEL: xor_imm:
; CPL is used for xor with -1 (bitwise NOT)
; CHECK:       cpl xde
; CHECK:       ret
  %c = xor i32 %a, -1
  ret i32 %c
}
