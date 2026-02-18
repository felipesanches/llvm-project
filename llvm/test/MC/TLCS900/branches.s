; RUN: llvm-mc -triple tlcs900 < %s | FileCheck %s

; Test unconditional branch
; CHECK: jp	target
jp target

; Test conditional branches with all condition codes
; CHECK: jp	z, target
jp z, target

; CHECK: jp	nz, target
jp nz, target

; CHECK: jp	c, target
jp c, target

; CHECK: jp	nc, target
jp nc, target

; CHECK: jp	lt, target
jp lt, target

; CHECK: jp	ge, target
jp ge, target

; CHECK: jp	le, target
jp le, target

; CHECK: jp	gt, target
jp gt, target

; CHECK: jp	ule, target
jp ule, target

; CHECK: jp	ugt, target
jp ugt, target

; CHECK: jp	ov, target
jp ov, target

; CHECK: jp	nov, target
jp nov, target

; CHECK: jp	mi, target
jp mi, target

; CHECK: jp	pl, target
jp pl, target

; CHECK: jp	f, target
jp f, target

; CHECK: jp	t, target
jp t, target

; Test call instruction
; CHECK: call	func
call func

; Test relative jump/call (no isel patterns, but parseable)
; CHECK: jr	target
jr target

; CHECK: jrl	target
jrl target

; CHECK: calr	target
calr target

; Test set condition code
; CHECK: scc	z, xwa
scc z, xwa

; CHECK: scc	nc, xde
scc nc, xde

; Test DJNZ
; CHECK: djnz	xwa, target
djnz xwa, target
