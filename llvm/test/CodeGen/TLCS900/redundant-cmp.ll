; RUN: llc -mtriple=tlcs900 < %s | FileCheck %s

; Test redundant compare elimination:
; When an arithmetic/logic op sets Z/S flags, a following "cp rd, 0"
; is redundant for branches that only test Z/NZ/MI/PL.

; ADD sets Z flag — cp with 0 for eq/ne is redundant
define i32 @add_branch_eq(i32 %a, i32 %b) {
; CHECK-LABEL: add_branch_eq:
; CHECK:       add
; CHECK-NOT:   cp
; CHECK:       jr z,
entry:
  %sum = add i32 %a, %b
  %cmp = icmp eq i32 %sum, 0
  br i1 %cmp, label %then, label %else

then:
  ret i32 1

else:
  ret i32 0
}

; SUB sets Z flag — cp with 0 for ne is redundant
define i32 @sub_branch_ne(i32 %a, i32 %b) {
; CHECK-LABEL: sub_branch_ne:
; CHECK:       sub
; CHECK-NOT:   cp
; CHECK:       jr nz,
entry:
  %diff = sub i32 %a, %b
  %cmp = icmp ne i32 %diff, 0
  br i1 %cmp, label %then, label %else

then:
  ret i32 1

else:
  ret i32 0
}

; AND sets Z flag — cp with 0 for eq is redundant
define i32 @and_branch_eq(i32 %a, i32 %b) {
; CHECK-LABEL: and_branch_eq:
; CHECK:       and
; CHECK-NOT:   cp
; CHECK:       jr z,
entry:
  %val = and i32 %a, %b
  %cmp = icmp eq i32 %val, 0
  br i1 %cmp, label %then, label %else

then:
  ret i32 1

else:
  ret i32 0
}

; Sign test: SUB sets S flag — cp with 0 for slt is NOT eliminated
; (slt uses overflow flag, not just S)
define i32 @sub_branch_slt(i32 %a, i32 %b) {
; CHECK-LABEL: sub_branch_slt:
; CHECK:       sub
; CHECK:       cp
; CHECK:       jr lt,
entry:
  %diff = sub i32 %a, %b
  %cmp = icmp slt i32 %diff, 0
  br i1 %cmp, label %then, label %else

then:
  ret i32 1

else:
  ret i32 0
}
