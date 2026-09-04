; RUN: not llvm-mc -triple tlcs900 -filetype=obj -o /dev/null %s 2>&1 | FileCheck %s
; RUN: not llvm-mc -triple tlcs900 -show-encoding %s 2>/dev/null \
; RUN:     | FileCheck --check-prefix=CTRL %s
;
; Every spelling the encoding selectors REJECT is a named error -- never a byte,
; and never a silent fall-back to the long form.  The CTRL lines are the
; controls that must keep assembling in the same file: the retired spellings
; (parse-only aliases), a symbolic `:opc` immediate (SingleByteRegImm emits a
; real fixup, so a symbol is legal there), and a numeric local label.

; A numeric `:N` is an ADDRESS WIDTH and belongs inside a direct address.
; CHECK: error: an encoding selector is an identifier such as ':i3'; a numeric ':N' is an ADDRESS WIDTH and is written inside the parentheses of a direct address, e.g. (0x2075:16)
cp a, 4:3

; `:s` was rejected by the design: `ld d, 4:i3` and `ld d, 4:opc` are both two
; bytes, so "short" names nothing.
; CHECK: error: unknown encoding selector ':s'; expected :i3, :opc or :io
cp a, 4:s

; CHECK: error: unknown encoding selector ':zz'; expected :i3, :opc or :io
cp a, 4:zz

; 9 does not fit three bits.  `cps a, 9` used to assemble to c9 d9 -- masked
; to 1 with no diagnostic.
; CHECK: error: 9 does not fit the 3-bit opcode field (must be 0..7)
cp a, 9:i3

; CHECK: error: -1 does not fit the 3-bit opcode field (must be 0..7)
cp a, -1:i3

; No relocation can reach an opcode field.  `cps a, SYMX` used to drop the
; symbol and emit c9 d8.
; CHECK: error: the 3-bit opcode field cannot hold a relocatable expression
ld hl, SYM:i3

; An unsuffixed `(n)` keeps its 24-bit default everywhere; the io short form
; needs the width written.
; CHECK: error: the I/O short form takes an 8-bit direct address, written (n:8)
ld (0x07), 0xff:io

; CHECK: error: the I/O short form takes an 8-bit direct address, written (n:8)
ld (0x07:16), 0xff:io

; `ldio 0x1ff, 0xff` used to emit 08 ff ff, the address truncated in silence.
; CHECK: error: 0x1ff does not fit an 8-bit direct address
ld (0x1ff:8), 0xff:io

; LdIoImm has no fixup at all; a symbol there would become 0x00.
; CHECK: error: the I/O short form cannot hold a relocatable expression; its encoder has no fixup
ld (7:8), SYMV:io

; CHECK: error: one encoding selector per operand
ld d, 4:opc:i3

; CHECK: error: an encoding selector is written directly after the ':', with no space
cp a, 4: i3

; A selector on an instruction that has no such encoding for these operands.
; CHECK: error: no encoding of 'jp' takes the ':i3' selector with these operands
jp 4:i3

; CHECK: error: no encoding of 'cp' takes the ':opc' selector with these operands
cp a, 4:opc

; CHECK: error: no encoding of 'ld' takes the ':i3' selector with these operands
ld (7:8), 4:i3

; A selector selects: `:i3` is the 3-bit field, so 8 never silently promotes
; to the long form.
; CHECK: error: 8 does not fit the 3-bit opcode field (must be 0..7)
ld hl, 8:i3

; ---- controls: these lines must assemble ---------------------------------
; CTRL: cp a, 4:i3                 ; encoding: [0xc9,0xdc]
cps a, 4
; CTRL: ld d, 4:opc                ; encoding: [0x24,0x04]
ldb d, 4
; CTRL: ld (7:8), 255:io           ; encoding: [0x08,0x07,0xff]
ldio 7, 255
; CTRL: ld b, SYMX:opc             ; encoding: [0x22,A]
; CTRL: fixup A - offset: 1, value: SYMX, kind: FK_Data_1
ld b, SYMX:opc
; CTRL: cp a, 4:i3                 ; encoding: [0xc9,0xdc]
1: cp a, 4:i3
; CTRL: jr
jr 1b
