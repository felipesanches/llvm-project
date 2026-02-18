; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test materialization of stack object addresses (e.g., passing &local to a call)

declare void @use_ptr(ptr)

define void @pass_local_addr() {
; CHECK-LABEL: pass_local_addr:
; CHECK:       sub xsp,
; CHECK:       lda xde, (xsp
; CHECK:       call use_ptr
; CHECK:       add xsp,
; CHECK:       ret
  %x = alloca i32
  call void @use_ptr(ptr %x)
  ret void
}

define void @pass_two_local_addrs() {
; CHECK-LABEL: pass_two_local_addrs:
; CHECK:       sub xsp,
; CHECK:       lda {{xde|xbc}}, (xsp
; CHECK:       call use_ptr
; CHECK:       lda {{xde|xbc}}, (xsp
; CHECK:       call use_ptr
; CHECK:       add xsp,
; CHECK:       ret
  %x = alloca i32
  %y = alloca i32
  call void @use_ptr(ptr %x)
  call void @use_ptr(ptr %y)
  ret void
}
