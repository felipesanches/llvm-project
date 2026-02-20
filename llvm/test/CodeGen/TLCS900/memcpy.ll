; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

declare void @llvm.memcpy.p0.p0.i32(ptr nocapture writeonly, ptr nocapture readonly, i32, i1 immarg)

; Large constant-size memcpy should use LDIR.
define void @memcpy_large(ptr %dst, ptr %src) {
; CHECK-LABEL: memcpy_large:
; CHECK-DAG:   ld xbc, 100
; CHECK:       ldir
; CHECK:       ret
  call void @llvm.memcpy.p0.p0.i32(ptr %dst, ptr %src, i32 100, i1 false)
  ret void
}

; Dynamic-size memcpy should use LDIR.
define void @memcpy_dynamic(ptr %dst, ptr %src, i32 %n) {
; CHECK-LABEL: memcpy_dynamic:
; CHECK:       ldir
; CHECK:       ret
  call void @llvm.memcpy.p0.p0.i32(ptr %dst, ptr %src, i32 %n, i1 false)
  ret void
}

; Small constant-size (8 bytes = 2 stores) should be inlined, not LDIR.
define void @memcpy_small(ptr %dst, ptr %src) {
; CHECK-LABEL: memcpy_small:
; CHECK-NOT:   ldir
; CHECK:       ret
  call void @llvm.memcpy.p0.p0.i32(ptr %dst, ptr %src, i32 8, i1 false)
  ret void
}

; Volatile copies should NOT use LDIR (fall back to libcall).
define void @memcpy_volatile(ptr %dst, ptr %src) {
; CHECK-LABEL: memcpy_volatile:
; CHECK-NOT:   ldir
; CHECK:       ret
  call void @llvm.memcpy.p0.p0.i32(ptr %dst, ptr %src, i32 100, i1 true)
  ret void
}
