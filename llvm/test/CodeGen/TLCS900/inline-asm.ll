; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test inline assembly constraints

; General register constraint 'r'
define i32 @test_asm_r(i32 %a) {
; CHECK-LABEL: test_asm_r:
; CHECK: nop
  %result = call i32 asm sideeffect "nop", "=r,r"(i32 %a)
  ret i32 %result
}

; Specific register constraint
define i32 @test_asm_specific_reg(i32 %a) {
; CHECK-LABEL: test_asm_specific_reg:
; CHECK: nop
  %result = call i32 asm sideeffect "nop", "={xwa},{xbc}"(i32 %a)
  ret i32 %result
}

; Immediate constraint
define void @test_asm_imm() {
; CHECK-LABEL: test_asm_imm:
; CHECK: nop
  call void asm sideeffect "nop", "i"(i32 42)
  ret void
}
