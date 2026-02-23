	.file	"test-memcpy.c"
	.text
	.globl	copy_large                      ; -- Begin function copy_large
	.type	copy_large,@function
copy_large:                             ; @copy_large
; %bb.0:                                ; %entry
	sub	xsp, 8
	ld	(xsp+4), xde
	ld	(xsp), xbc
	ld	xde, (xsp+4)
	ld	xhl, (xsp)
	ld	xbc, 100
	ldir	
	add	xsp, 8
	ret	
.Lfunc_end0:
	.size	copy_large, .Lfunc_end0-copy_large
                                        ; -- End function
	.globl	copy_dynamic                    ; -- Begin function copy_dynamic
	.type	copy_dynamic,@function
copy_dynamic:                           ; @copy_dynamic
; %bb.0:                                ; %entry
	sub	xsp, 12
	ld	(xsp+8), xde
	ld	(xsp+4), xbc
	ld	(xsp), xix
	ld	xde, (xsp+8)
	ld	xhl, (xsp+4)
	ld	xbc, (xsp)
	ldir	
	add	xsp, 12
	ret	
.Lfunc_end1:
	.size	copy_dynamic, .Lfunc_end1-copy_dynamic
                                        ; -- End function
	.globl	copy_struct                     ; -- Begin function copy_struct
	.type	copy_struct,@function
copy_struct:                            ; @copy_struct
; %bb.0:                                ; %entry
	sub	xsp, 8
	ld	(xsp+4), xde
	ld	(xsp), xbc
	ld	xde, (xsp+4)
	ld	xhl, (xsp)
	ld	xbc, 32
	ldir	
	add	xsp, 8
	ret	
.Lfunc_end2:
	.size	copy_struct, .Lfunc_end2-copy_struct
                                        ; -- End function
	.ident	"clang version 21.0.0git (https://github.com/felipesanches/llvm-project.git 52d80102e335ee4ea8bf3b8d99a1d25130614508)"
	.section	".note.GNU-stack","",@progbits
