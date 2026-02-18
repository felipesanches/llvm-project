; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test ALU patterns: INC/DEC, NEG, CPL, bit manipulation, extend

; INC optimization: add by 1
define i32 @inc1(i32 %a) {
; CHECK-LABEL: inc1:
; CHECK: inc 1
  %r = add i32 %a, 1
  ret i32 %r
}

; INC optimization: add by 5
define i32 @inc5(i32 %a) {
; CHECK-LABEL: inc5:
; CHECK: inc 5
  %r = add i32 %a, 5
  ret i32 %r
}

; DEC optimization: subtract 1 (add -1)
define i32 @dec1(i32 %a) {
; CHECK-LABEL: dec1:
; CHECK: dec 1
  %r = add i32 %a, -1
  ret i32 %r
}

; DEC optimization: subtract 8 (add -8)
define i32 @dec8(i32 %a) {
; CHECK-LABEL: dec8:
; CHECK: dec 8
  %r = add i32 %a, -8
  ret i32 %r
}

; NEG: negate
define i32 @negate(i32 %a) {
; CHECK-LABEL: negate:
; CHECK: neg
  %r = sub i32 0, %a
  ret i32 %r
}

; CPL: bitwise NOT
define i32 @bitwise_not(i32 %a) {
; CHECK-LABEL: bitwise_not:
; CHECK: cpl
  %r = xor i32 %a, -1
  ret i32 %r
}

; EXTS: sign extend i16 to i32
define i32 @sext_i16(i32 %a) {
; CHECK-LABEL: sext_i16:
; CHECK: exts
  %t = trunc i32 %a to i16
  %r = sext i16 %t to i32
  ret i32 %r
}

; EXTZ: zero extend low 16 bits
define i32 @zext_i16(i32 %a) {
; CHECK-LABEL: zext_i16:
; CHECK: extz
  %r = and i32 %a, 65535
  ret i32 %r
}

; SET bit: OR with power of 2
define i32 @set_bit3(i32 %a) {
; CHECK-LABEL: set_bit3:
; CHECK: set 3
  %r = or i32 %a, 8
  ret i32 %r
}

; RES bit: AND with ~(power of 2)
define i32 @res_bit5(i32 %a) {
; CHECK-LABEL: res_bit5:
; CHECK: res 5
  %r = and i32 %a, -33
  ret i32 %r
}

; CHG bit: XOR with power of 2
define i32 @chg_bit7(i32 %a) {
; CHECK-LABEL: chg_bit7:
; CHECK: xor
  %r = xor i32 %a, 128
  ret i32 %r
}

; Shift left immediate
define i32 @shl_imm(i32 %a) {
; CHECK-LABEL: shl_imm:
; CHECK: sla
  %r = shl i32 %a, 4
  ret i32 %r
}

; Arithmetic shift right immediate
define i32 @sra_imm(i32 %a) {
; CHECK-LABEL: sra_imm:
; CHECK: sra
  %r = ashr i32 %a, 8
  ret i32 %r
}

; Logical shift right immediate
define i32 @srl_imm(i32 %a) {
; CHECK-LABEL: srl_imm:
; CHECK: srl
  %r = lshr i32 %a, 16
  ret i32 %r
}
