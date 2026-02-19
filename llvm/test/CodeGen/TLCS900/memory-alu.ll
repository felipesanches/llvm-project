; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test read-modify-write folding into CISC memory-ALU instructions.
; Pattern: store(op(load(addr), val), addr) → OP (addr), val

define void @add_mem(ptr %ptr, i32 %val) {
; CHECK-LABEL: add_mem:
; CHECK: add (xde), xbc
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = add i32 %old, %val
  store i32 %new, ptr %ptr
  ret void
}

define void @sub_mem(ptr %ptr, i32 %val) {
; CHECK-LABEL: sub_mem:
; CHECK: sub (xde), xbc
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = sub i32 %old, %val
  store i32 %new, ptr %ptr
  ret void
}

define void @and_mem(ptr %ptr, i32 %val) {
; CHECK-LABEL: and_mem:
; CHECK: and (xde), xbc
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = and i32 %old, %val
  store i32 %new, ptr %ptr
  ret void
}

define void @or_mem(ptr %ptr, i32 %val) {
; CHECK-LABEL: or_mem:
; CHECK: or (xde), xbc
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = or i32 %old, %val
  store i32 %new, ptr %ptr
  ret void
}

define void @xor_mem(ptr %ptr, i32 %val) {
; CHECK-LABEL: xor_mem:
; CHECK: xor (xde), xbc
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = xor i32 %old, %val
  store i32 %new, ptr %ptr
  ret void
}

; Memory-immediate ADD/SUB are invalid in the 32-bit A0 table.
; ISel decomposes them to: LD tmp,(mem); ADD/SUB tmp,#imm; ST (mem),tmp.
define void @add_mem_imm(ptr %ptr) {
; CHECK-LABEL: add_mem_imm:
; CHECK: ld [[TMP:x[a-z]+]], (xde)
; CHECK: add [[TMP]], 42
; CHECK: ld (xde), [[TMP]]
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = add i32 %old, 42
  store i32 %new, ptr %ptr
  ret void
}

; DAG canonicalizes sub(x, 10) to add(x, -10).
define void @sub_mem_imm(ptr %ptr) {
; CHECK-LABEL: sub_mem_imm:
; CHECK: ld [[TMP:x[a-z]+]], (xde)
; CHECK: add [[TMP]], -10
; CHECK: ld (xde), [[TMP]]
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = sub i32 %old, 10
  store i32 %new, ptr %ptr
  ret void
}

; Test with base+offset addressing
define void @add_mem_offset(ptr %ptr, i32 %val) {
; CHECK-LABEL: add_mem_offset:
; CHECK: add (xde+8), xbc
; CHECK: ret
  %gep = getelementptr i32, ptr %ptr, i32 2
  %old = load i32, ptr %gep
  %new = add i32 %old, %val
  store i32 %new, ptr %gep
  ret void
}

; Test commutativity: val + load(addr) should still fold
define void @add_mem_commute(ptr %ptr, i32 %val) {
; CHECK-LABEL: add_mem_commute:
; CHECK: add (xde), xbc
; CHECK: ret
  %old = load i32, ptr %ptr
  %new = add i32 %val, %old
  store i32 %new, ptr %ptr
  ret void
}
