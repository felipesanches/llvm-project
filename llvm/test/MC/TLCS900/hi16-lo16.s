; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s -o %t.o
; RUN: llvm-objdump -dr %t.o | FileCheck --check-prefix=OBJ %s
; RUN: not llvm-mc -triple tlcs900 -filetype=obj -defsym ERR=1 %s -o /dev/null 2>&1 | FileCheck --check-prefix=ERR %s
;
; `sym@hi16` / `sym@lo16`: the high / low 16 bits of a 32-bit address in a
; 16-bit immediate.  The firmware's C compiler passes a far pointer as two
; word pushes, high half first -- `pushw 0x00e4 / pushw 0x5126` is the pointer
; 0xe45126 -- so the disassembly can now write `pushw Str@hi16 / pushw
; Str@lo16` instead of the two numbers.  A label becomes R_TLCS900_HI16 /
; R_TLCS900_LO16 (ld.lld writes (S+A)>>16 / (S+A)&0xffff); an absolute
; .set/.equ symbol is folded by the assembler.  An addend applies before the
; split: `sym@hi16 + 1` is the high half of sym+1.

	.set	AbsPtr, 0xe45126

f:
; CHECK: pushw	Str@hi16          ; encoding: [0x0b,A,A]
; CHECK-NEXT: fixup A - offset: 1, value: Str@hi16, kind: fixup_tlcs900_hi16
; OBJ: 0b 00 00 pushw 0
; OBJ-NEXT: R_TLCS900_HI16 .text+0x
	pushw	Str@hi16
; CHECK: pushw	Str@lo16          ; encoding: [0x0b,A,A]
; CHECK-NEXT: fixup A - offset: 1, value: Str@lo16, kind: fixup_tlcs900_lo16
; OBJ: R_TLCS900_LO16 .text+0x
	pushw	Str@lo16
; OBJ: R_TLCS900_HI16 Ext{{$}}
	pushw	Ext@HI16
; OBJ: R_TLCS900_LO16 Ext+0x2
	pushw	Ext@lo16 + 2
; A 16-bit register load takes the same immediate.
; CHECK: ld	wa, Str@lo16
; OBJ: d8 03 00 00 ld wa, 0
; OBJ-NEXT: R_TLCS900_LO16 .text+0x
	ld	wa, Str@lo16
; An absolute symbol is folded: 0xe45126 -> 0x00e4 / 0x5126.
; OBJ: 0b e4 00 pushw 228
; OBJ: 0b 26 51 pushw 20774
	pushw	AbsPtr@hi16
	pushw	AbsPtr@lo16
	ret
Str:	.asciz	"A:\\"

.ifdef ERR
; ERR: error: @hi16/@lo16 is only valid in a 16-bit immediate
	call	Str@hi16
; ERR: error: @hi16/@lo16 is only valid in a 16-bit immediate
	ld	a, Str@lo16
; ERR: error: @hi16/@lo16 is only valid in a 16-bit immediate
	ld	xwa, Str@lo16
.endif
