; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

declare void @llvm.memmove.p0.p0.i32(ptr nocapture, ptr nocapture readonly, i32, i1 immarg)

; Dynamic-size memmove should use runtime direction check + LDIR/LDDR.
; Backward block (LDDR) is the fall-through; forward block (LDIR) is the branch target.
define void @memmove_dynamic(ptr %dst, ptr %src, i32 %n) {
; CHECK-LABEL: memmove_dynamic:
; CHECK:       cp xde, xhl
; CHECK:       add xde, xbc
; CHECK:       add xhl, xbc
; CHECK:       dec 1, xde
; CHECK:       dec 1, xhl
; CHECK:       lddr
; CHECK:       ldir
; CHECK:       ret
  call void @llvm.memmove.p0.p0.i32(ptr %dst, ptr %src, i32 %n, i1 false)
  ret void
}

; Large constant-size memmove should also use runtime direction check.
define void @memmove_large(ptr %dst, ptr %src) {
; CHECK-LABEL: memmove_large:
; CHECK:       cp xde, xhl
; CHECK:       lddr
; CHECK:       ldir
; CHECK:       ret
  call void @llvm.memmove.p0.p0.i32(ptr %dst, ptr %src, i32 100, i1 false)
  ret void
}

; Small aligned memmove should be inlined as stores (no LDIR/LDDR).
define void @memmove_small(ptr %dst, ptr %src) {
; CHECK-LABEL: memmove_small:
; CHECK-NOT:   ldir
; CHECK-NOT:   lddr
; CHECK:       ret
  call void @llvm.memmove.p0.p0.i32(ptr align 4 %dst, ptr align 4 %src, i32 8, i1 false)
  ret void
}

; Volatile memmove should fall back to libcall.
define void @memmove_volatile(ptr %dst, ptr %src) {
; CHECK-LABEL: memmove_volatile:
; CHECK-NOT:   ldir
; CHECK-NOT:   lddr
; CHECK:       ret
  call void @llvm.memmove.p0.p0.i32(ptr %dst, ptr %src, i32 100, i1 true)
  ret void
}
