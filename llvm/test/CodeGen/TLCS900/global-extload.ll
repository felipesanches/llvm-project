; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test byte/word extending loads from global addresses.
; Direct memory addressing (E2 prefix) only supports 32-bit loads.
; Byte/word loads from globals must materialize the address into a register
; first, then use register-indirect addressing.

@g8 = external global i8
@g16 = external global i16

define i32 @load_zext_i8_global() {
; CHECK-LABEL: load_zext_i8_global:
; Should materialize address, then use register-indirect byte load
; CHECK:       ld [[REG:x[a-z]+]], g8
; CHECK:       ld {{[a-z]}}, ([[REG]])
; CHECK:       and
; CHECK:       ret
  %val = load i8, ptr @g8
  %ext = zext i8 %val to i32
  ret i32 %ext
}

define i32 @load_sext_i8_global() {
; CHECK-LABEL: load_sext_i8_global:
; Should materialize address, then use register-indirect byte load
; CHECK:       ld [[REG:x[a-z]+]], g8
; CHECK:       ld {{[a-z]}}, ([[REG]])
; CHECK:       sla
; CHECK:       sra
; CHECK:       ret
  %val = load i8, ptr @g8
  %ext = sext i8 %val to i32
  ret i32 %ext
}

define i32 @load_zext_i16_global() {
; CHECK-LABEL: load_zext_i16_global:
; Should materialize address, then use register-indirect word load
; CHECK:       ld [[REG:x[a-z]+]], g16
; CHECK:       ld {{[a-z]+}}, ([[REG]])
; CHECK:       extz
; CHECK:       ret
  %val = load i16, ptr @g16
  %ext = zext i16 %val to i32
  ret i32 %ext
}

define i32 @load_sext_i16_global() {
; CHECK-LABEL: load_sext_i16_global:
; Should materialize address, then use register-indirect word load
; CHECK:       ld [[REG:x[a-z]+]], g16
; CHECK:       ld {{[a-z]+}}, ([[REG]])
; CHECK:       exts
; CHECK:       ret
  %val = load i16, ptr @g16
  %ext = sext i16 %val to i32
  ret i32 %ext
}

; 32-bit loads from globals should still use direct memory addressing
define i32 @load_i32_global_still_direct() {
; CHECK-LABEL: load_i32_global_still_direct:
; CHECK-NOT:   ld {{x[a-z]+}}, g8
; CHECK:       ret
  %ptr = bitcast ptr @g8 to ptr
  %val = load i32, ptr %ptr
  ret i32 %val
}
