; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test trap/unreachable lowering

define void @test_trap() {
; CHECK-LABEL: test_trap:
; CHECK:       swi 0
  call void @llvm.trap()
  unreachable
}

; unreachable alone produces an empty block (no trap instruction)
define void @test_unreachable() {
; CHECK-LABEL: test_unreachable:
; CHECK-NOT:   call
  unreachable
}

declare void @llvm.trap()
