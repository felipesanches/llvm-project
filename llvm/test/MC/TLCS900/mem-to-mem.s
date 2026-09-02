; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s \
; RUN:     | llvm-objdump -d - | FileCheck --check-prefix=CHECK-INST %s
;
; MEMORY-TO-MEMORY: `ld (mem),(nn)` and `ld (nn),(mem)`.
;
; One register-indirect operand and one 16-bit DIRECT address -- an operand
; shape this backend had never had, and the largest remaining decoder refusal:
; 274 of the 294 samples still refused by the v10 sub-opcode census
; (kn5000-roms-disasm notes/lanes/llvmalumem-2026-09-02.md).  Those bytes could
; not be decoded to the raw-byte escapes the tree writes them as, because
; echoing bytes back conveys nothing -- and because the escapes name the WRONG
; INSTRUCTION.
;
; ⚠ `ldmi16` and `ldmw2` are store-immediate spellings sitting on sub-opcodes
; 0x14 and 0x16, which are not store-immediate at all.  MAME unidasm reads
; `b0 14 38 8d` as `ld (XWA),(0x8d38)` -- a memory-to-memory move whose
; trailing field is an ADDRESS, not a value.  The real store-immediate is
; sub-opcode 0x00 for a byte and 0x02 for a word.
;
; ⚠ NO EXISTING SPELLING IS RE-ENCODED.  `ldmi16`, `ldmw2` and the `mr*`
; prefix escapes still emit exactly the bytes they always did; committed source
; across the tree writes them.  What changes is that the correct instruction
; now exists and is what the DISASSEMBLER prints.
;
; ⚠ AND ONE NEAR MISS WORTH THE RULE IT PROVES.  The second operand was first
; given the existing `directaddr` class, which answers true to a BARE
; IMMEDIATE.  `ldw (xwa), 36152` -- a store-immediate written in hundreds of
; places -- promptly started matching `ldw (mem),(nn)` and moved from
; b0 02 38 8d to b0 16 38 8d, silently.  A form whose operand must be an
; ADDRESS has to reject a value: `daddr16` requires the parentheses.  The
; guards at the bottom pin it.
;
; Every line is REAL ROM BYTES; the comments name the dump, the offset, the
; source line that already frames them as an instruction, and unidasm's own
; reading -- a second decoder, because a round trip cannot tell an ADD called
; SUB from an ADD.  Regenerate from the kn5000-roms-disasm tree with:
;     python3 scripts/analysis/memtomem_test_sites.py --emit

; ⚠ ONE BYTE STRING IN THREE IMAGES IS DELIBERATELY ABSENT.
; `d3 f9 00 01 19 04 04` is `ldw (0x0404),(XIZ+0x0100)` -- an SRI (Xrr+d16)
; operand whose displacement is exactly 256.  It decodes correctly and unidasm
; agrees, but it cannot be written back: 256 is the ASSEMBLER'S SENTINEL for
; "force the 2-byte (Xrr+d8) form with displacement 0", so the line
; re-assembles to `9e 00 19 04 04`.  The sentinel steals a legal displacement
; (the 65536 sentinel one width up does not, being outside the field).  The
; three sites -- v7/v9/v10 kn5000_vN_program.s:741/744/744 -- are already
; written as raw bytes in the tree, which is why nothing was ever wrong; the
; defect is that no spelling exists.  memtomem_test_sites.py re-assembles every
; decode and reports it rather than letting a round-trip failure pass.

; v142/subcpu @0x02E10E (1 hit)  v142/subcpu/kn5000_subprogram_v142.s:57551  unidasm: ld (0x4a48),(XBC+0x01)
; CHECK: ld (19016), (xbc+1) ; encoding: [0x89,0x01,0x19,0x48,0x4a]
; CHECK-INST: ld (19016), (xbc+1)
ld (19016), (xbc+1)

; v7/maincpu @0x0F34B0 (1 hit)  v7/maincpu/boot/system_handlers.s:5560  unidasm: ldw (0x05de),(XBC+0x04)
; CHECK: ldw (1502), (xbc+4) ; encoding: [0x99,0x04,0x19,0xde,0x05]
; CHECK-INST: ldw (1502), (xbc+4)
ldw (1502), (xbc+4)

; v7/maincpu @0x1868C7 (1 hit)  v7/maincpu/demo/file_demo_proc.s:668  unidasm: ld (0x28a4),(XBC+WA)
; CHECK: ld (10404), (xbc+wa) ; encoding: [0xc3,0x07,0xe4,0xe0,0x19,0xa4,0x28]
; CHECK-INST: ld (10404), (xbc+wa)
ld (10404), (xbc+wa)

; v7/maincpu @0x1069F8 (1 hit)  v7/maincpu/audio/semenu_routines.s:1014  unidasm: ld (XWA),(0x065c)
; CHECK: ld (xwa), (1628) ; encoding: [0xb0,0x14,0x5c,0x06]
; CHECK-INST: ld (xwa), (1628)
ld (xwa), (1628)

; v7/maincpu @0x10936D (2 hits)  v7/maincpu/audio/semenu_routines.s:5048  unidasm: ld (0x06ac),(XBC)
; CHECK: ld (1708), (xbc) ; encoding: [0x81,0x19,0xac,0x06]
; CHECK-INST: ld (1708), (xbc)
ld (1708), (xbc)

; v7/maincpu @0x1360AD (1 hit)  v7/maincpu/sequencer/bmdredit_routines.s:257  unidasm: ldw (XWA),(0x27ba)
; CHECK: ldw (xwa), (10170) ; encoding: [0xb0,0x16,0xba,0x27]
; CHECK-INST: ldw (xwa), (10170)
ldw (xwa), (10170)

; v7/maincpu @0x1360B1 (1 hit)  v7/maincpu/sequencer/bmdredit_routines.s:258  unidasm: ldw (XWA+0x04),(0x27bc)
; CHECK: ldw (xwa+4), (10172) ; encoding: [0xb8,0x04,0x16,0xbc,0x27]
; CHECK-INST: ldw (xwa+4), (10172)
ldw (xwa+4), (10172)

; v7/maincpu @0x1361C2 (2 hits)  v7/maincpu/sequencer/bmdredit_routines.s:352  unidasm: ldw (0x27be),(XBC+WA)
; CHECK: ldw (10174), (xbc+wa) ; encoding: [0xd3,0x07,0xe4,0xe0,0x19,0xbe,0x27]
; CHECK-INST: ldw (10174), (xbc+wa)
ldw (10174), (xbc+wa)

; v7/maincpu @0x137721 (2 hits)  v7/maincpu/sequencer/bmdredit_routines.s:2584  unidasm: ld (XWA+0x02),(0x2786)
; CHECK: ld (xwa+2), (10118) ; encoding: [0xb8,0x02,0x14,0x86,0x27]
; CHECK-INST: ld (xwa+2), (10118)
ld (xwa+2), (10118)

; v7/maincpu @0x140580 (3 hits)  v7/maincpu/sequencer/seq_step_routines.s:218  unidasm: ldw (0x2887),(XWA)
; CHECK: ldw (10375), (xwa) ; encoding: [0x90,0x19,0x87,0x28]
; CHECK-INST: ldw (10375), (xwa)
ldw (10375), (xwa)

; v7/maincpu @0x13F05B (1 hit)  v7/maincpu/sequencer/sequencer_engine.s:10876  unidasm: ldw (XWA+0x0080),(0x2328)
; CHECK: ldw (xwa+128), (9000) ; encoding: [0xf3,0xe1,0x80,0x00,0x16,0x28,0x23]
; CHECK-INST: ldw (xwa+128), (9000)
ldw (xwa+128), (9000)

; v9/maincpu @0x1924B7 (1 hit)  v9/maincpu/file_io/medley.s:1067  unidasm: ld (XWA+IZ),(0x893a)
; CHECK: ld (xwa+iz), (35130) ; encoding: [0xf3,0x07,0xe0,0xf8,0x14,0x3a,0x89]
; CHECK-INST: ld (xwa+iz), (35130)
ld (xwa+iz), (35130)


; --- GUARDS: the store-immediate spellings are untouched -----------------
; A VALUE is still a value.  `ldw (mem), #imm16` is sub-opcode 0x02 and must
; never be pulled into the 0x16 memory-to-memory form by an operand class that
; accepts a bare number.
; CHECK: ldw (xwa), 36152 ; encoding: [0xb0,0x02,0x38,0x8d]
; CHECK-INST: ldw (xwa), 36152
ldw (xwa), 36152
; CHECK: ldmi16 (xwa), 36152 ; encoding: [0xb0,0x14,0x38,0x8d]
; CHECK-INST: ld (xwa), (36152)
ldmi16 (xwa), 36152
; CHECK: ldmw2 (xwa), 36152 ; encoding: [0xb0,0x16,0x38,0x8d]
; CHECK-INST: ldw (xwa), (36152)
ldmw2 (xwa), 36152
; CHECK: ld (xwa), 56 ; encoding: [0xb0,0x00,0x38]
; CHECK-INST: ld (xwa), 56
ld (xwa), 56
