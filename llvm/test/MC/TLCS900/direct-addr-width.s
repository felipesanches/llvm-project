; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj -o /dev/null < %s
;
; Direct memory operands `(addr)` and the `:8` / `:16` / `:24` address-width
; suffix.
;
; The TLCS-900 encodes the address width in the low two bits of the memory
; prefix, and the width is NOT a function of the address value: shipped
; firmware writes `set 7,(0x00008a)` as F2 8A 00 00 BF, the 24-bit form, for
; an address that fits in eight bits.  So the assembler never picks a width by
; looking at the number.  Without a suffix an operand keeps the 24-bit form,
; which is also the only width a relocation can use.
;
; Every expected byte string below is the encoding the Technics KN5000 /
; SX-WSA1R firmware uses for that instruction, taken from
; kn5000-roms-disasm/wsa1/include/tlcs900_mem_ops.inc.

; ==========================================================================
; Destination table (F0/F1/F2): bit operations
; ==========================================================================
; CHECK: bitm 1, (8309:16) ; encoding: [0xf1,0x75,0x20,0xc9]
bit 1, (0x2075:16)
; CHECK: bitm 1, (8309) ; encoding: [0xf2,0x75,0x20,0x00,0xc9]
bit 1, (0x2075)
; CHECK: setm 7, (138:24) ; encoding: [0xf2,0x8a,0x00,0x00,0xbf]
set 7, (0x8a:24)
; CHECK: setm 3, (4660:16) ; encoding: [0xf1,0x34,0x12,0xbb]
set 3, (0x1234:16)
; CHECK: resm 0, (156:8) ; encoding: [0xf0,0x9c,0xb0]
res 0, (0x9c:8)

; ==========================================================================
; Source table: the prefix carries the operand size AND the address width.
; byte C0/C1/C2, word D0/D1/D2, long E0/E1/E2.
; ==========================================================================
; CHECK: cp (156:8), 165 ; encoding: [0xc0,0x9c,0x3f,0xa5]
cp (0x9c:8), 0xa5
; CHECK: cp (4660:16), 86 ; encoding: [0xc1,0x34,0x12,0x3f,0x56]
cp (0x1234:16), 0x56
; CHECK: andmi8 (4660:16), 86 ; encoding: [0xc1,0x34,0x12,0x3c,0x56]
and (0x1234:16), 0x56
; CHECK: ormi8 (156:8), 86 ; encoding: [0xc0,0x9c,0x3e,0x56]
or (0x9c:8), 0x56
; CHECK: ld wa, (4660:16) ; encoding: [0xd1,0x34,0x12,0x20]
ld wa, (0x1234:16)
; CHECK: ld a, (156:8) ; encoding: [0xc0,0x9c,0x21]
ld a, (0x9c:8)
; CHECK: ld xwa, (1193046) ; encoding: [0xe2,0x56,0x34,0x12,0x20]
ld xwa, (0x123456)

; ==========================================================================
; PUSH from memory.  `push (0x1234)` used to assemble to [0x09,0x34] -- the
; parenthesised address was read as an 8-bit immediate and its high byte was
; dropped with no diagnostic.
; ==========================================================================
; CHECK: push (4660:16) ; encoding: [0xc1,0x34,0x12,0x04]
push (0x1234:16)
; CHECK: push (4660) ; encoding: [0xc2,0x34,0x12,0x00,0x04]
push (0x1234)
; CHECK: pushm (4660:16) ; encoding: [0xd1,0x34,0x12,0x04]
pushw (0x1234:16)
; CHECK: popw (4660:16) ; encoding: [0xf1,0x34,0x12,0x06]
popw (0x1234:16)

; ==========================================================================
; MUL/MULS/DIV/DIVS from memory.  `mul wa,(0x1234)` used to assemble to
; [0xd8,0x08,0x34,0x12] -- MUL by the IMMEDIATE 0x1234, not by the contents
; of address 0x1234.
; ==========================================================================
; CHECK: mul wa, (4660:16) ; encoding: [0xd1,0x34,0x12,0x40]
mul wa, (0x1234:16)
; CHECK: muls wa, (4660:16) ; encoding: [0xd1,0x34,0x12,0x48]
muls wa, (0x1234:16)
; CHECK: div wa, (4660:16) ; encoding: [0xd1,0x34,0x12,0x50]
div wa, (0x1234:16)
; CHECK: divs wa, (4660:16) ; encoding: [0xd1,0x34,0x12,0x58]
divs wa, (0x1234:16)

; ==========================================================================
; The rest of the forms this suffix unlocks.
; ==========================================================================
; CHECK: incm8 1, (156:8) ; encoding: [0xc0,0x9c,0x61]
inc 1, (0x9c:8)
; CHECK: incm 2, (4660:16) ; encoding: [0xd1,0x34,0x12,0x62]
incw 2, (0x1234:16)
; CHECK: rlc (156:8) ; encoding: [0xc0,0x9c,0x78]
rlc (0x9c:8)
; CHECK: slaw (4660:16) ; encoding: [0xd1,0x34,0x12,0x7c]
slaw (0x1234:16)
; CHECK: ex (4660:16), wa ; encoding: [0xd1,0x34,0x12,0x30]
ex (0x1234:16), wa
; CHECK: andcf a, (156:8) ; encoding: [0xf0,0x9c,0x28]
andcf a, (0x9c:8)
; CHECK: ldcf a, (156:8) ; encoding: [0xf0,0x9c,0x2b]
ldcf a, (0x9c:8)
; CHECK: jp z, (4660:16) ; encoding: [0xf1,0x34,0x12,0xd6]
jp z, (0x1234:16)
; CHECK: call z, (4660:16) ; encoding: [0xf1,0x34,0x12,0xe6]
call z, (0x1234:16)
; CHECK: ldw (4660:16), 22136 ; encoding: [0xf1,0x34,0x12,0x02,0x78,0x56]
ldw (0x1234:16), 0x5678
; CHECK: ld (4660:16), wa ; encoding: [0xf1,0x34,0x12,0x50]
ld (0x1234:16), wa
; CHECK: lda xwa, (4660:16) ; encoding: [0xf1,0x34,0x12,0x30]
lda xwa, (0x1234:16)

; ==========================================================================
; The old internal spellings still assemble: hundreds of files use them.
; ==========================================================================
; CHECK: ormi8 (156:8), 86 ; encoding: [0xc0,0x9c,0x3e,0x56]
ormi8 (0x9c:8), 0x56
; CHECK: pushm (xix+16) ; encoding: [0x9c,0x10,0x04]
pushm (xix+0x10)
; CHECK: incm8 1, (xhl) ; encoding: [0x83,0x61]
incm8 1, (xhl)
