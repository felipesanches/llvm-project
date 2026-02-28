; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Bug #11: for-loop with uint16_t (i16) counter used to exit after 1 iteration.
; Root cause: EXTZ32 was declared with Defs=[SR] but does NOT set flags on
; TLCS-900/H hardware. The RedundantCmpElim pass would incorrectly remove
; the CP instruction, leaving the branch to use stale flags.
;
; This test verifies that the CP instruction is preserved after EXTZ.

; i16 counter version: must have a CP after EXTZ
define void @clear_vram_i16() {
; CHECK-LABEL: clear_vram_i16:
; CHECK: extz
; CHECK-NEXT: cp
; CHECK-NEXT: jr
entry:
  br label %loop

loop:
  %i = phi i16 [0, %entry], [%i.next, %loop]
  %ptr = phi ptr [inttoptr (i32 1703936 to ptr), %entry], [%ptr.next, %loop]
  store volatile i32 0, ptr %ptr
  %ptr.next = getelementptr i32, ptr %ptr, i32 1
  %i.next = add nuw i16 %i, 1
  %cmp = icmp ult i16 %i.next, 19200
  br i1 %cmp, label %loop, label %exit

exit:
  ret void
}

; i32 counter version: no EXTZ needed, CP directly after counter update
define void @clear_vram_i32() {
; CHECK-LABEL: clear_vram_i32:
; CHECK-NOT: extz
; CHECK: cp
; CHECK-NEXT: jr
entry:
  br label %loop

loop:
  %i = phi i32 [0, %entry], [%i.next, %loop]
  %ptr = phi ptr [inttoptr (i32 1703936 to ptr), %entry], [%ptr.next, %loop]
  store volatile i32 0, ptr %ptr
  %ptr.next = getelementptr i32, ptr %ptr, i32 1
  %i.next = add nuw i32 %i, 1
  %cmp = icmp ult i32 %i.next, 19200
  br i1 %cmp, label %loop, label %exit

exit:
  ret void
}
