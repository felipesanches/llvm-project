; ModuleID = 'test-memcpy.bc'
source_filename = "test-memcpy.c"
target datalayout = "e-m:e-p:32:32-i64:64-n8:16:32-S16"
target triple = "tlcs900"

; Function Attrs: noinline nounwind optnone
define dso_local void @copy_large(ptr noundef %dst, ptr noundef %src) #0 {
entry:
  %dst.addr = alloca ptr, align 4
  %src.addr = alloca ptr, align 4
  store ptr %dst, ptr %dst.addr, align 4
  store ptr %src, ptr %src.addr, align 4
  %0 = load ptr, ptr %dst.addr, align 4
  %1 = load ptr, ptr %src.addr, align 4
  call void @llvm.memcpy.p0.p0.i32(ptr align 1 %0, ptr align 1 %1, i32 100, i1 false)
  ret void
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i32(ptr noalias writeonly captures(none), ptr noalias readonly captures(none), i32, i1 immarg) #1

; Function Attrs: noinline nounwind optnone
define dso_local void @copy_dynamic(ptr noundef %dst, ptr noundef %src, i32 noundef %n) #0 {
entry:
  %dst.addr = alloca ptr, align 4
  %src.addr = alloca ptr, align 4
  %n.addr = alloca i32, align 4
  store ptr %dst, ptr %dst.addr, align 4
  store ptr %src, ptr %src.addr, align 4
  store i32 %n, ptr %n.addr, align 4
  %0 = load ptr, ptr %dst.addr, align 4
  %1 = load ptr, ptr %src.addr, align 4
  %2 = load i32, ptr %n.addr, align 4
  call void @llvm.memcpy.p0.p0.i32(ptr align 1 %0, ptr align 1 %1, i32 %2, i1 false)
  ret void
}

; Function Attrs: noinline nounwind optnone
define dso_local void @copy_struct(ptr noundef %dst, ptr noundef %src) #0 {
entry:
  %dst.addr = alloca ptr, align 4
  %src.addr = alloca ptr, align 4
  store ptr %dst, ptr %dst.addr, align 4
  store ptr %src, ptr %src.addr, align 4
  %0 = load ptr, ptr %dst.addr, align 4
  %1 = load ptr, ptr %src.addr, align 4
  call void @llvm.memcpy.p0.p0.i32(ptr align 4 %0, ptr align 4 %1, i32 32, i1 false)
  ret void
}

attributes #0 = { noinline nounwind optnone "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" }
attributes #1 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}

!0 = !{i32 1, !"wchar_size", i32 4}
!1 = !{i32 7, !"frame-pointer", i32 2}
!2 = !{!"clang version 21.0.0git (https://github.com/felipesanches/llvm-project.git 52d80102e335ee4ea8bf3b8d99a1d25130614508)"}
