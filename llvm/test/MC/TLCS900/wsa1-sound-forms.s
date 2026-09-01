; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; The extended-register-prefix (C7) byte forms that the Technics SX-WSA1R's
; sound code depends on.  Every encoding below is read off wsa1_prom_a.ic12 in
; kn5000-roms-disasm, with MAME's unidasm rendering and the ROM address quoted
; beside it, and is byte-for-byte what the assembler has to reproduce for those
; bytes to leave the source as instructions.
;
; NONE of these needed a new def -- they are here as a REGRESSION GUARD.  The
; second operand is a raw REGISTER-FILE ADDRESS, and the file's layout is what
; 4149d0474bf8 had to correct on the index side: a word register's low half sits
; at offset 0, its high half at offset 1, and its PREVIOUS BANK at offsets 2 and
; 3.  The first two lines below are the only place in either tree that spells a
; previous-bank byte register as an ERP DESTINATION, so nothing else would
; notice if the +2/+3 half of that map were dropped.

; ==========================================================================
; LD (regfile), r8 -- sub-opcode 0x98 + reg.  GR8 order is W,A,B,C,D,E,H,L.
; ==========================================================================

; prom_a 0xF831FF, in sub_F831B3, which writes the DSP register file at
; 0x007F0000.  unidasm: ld QW,A -- 0xE3 = the PREVIOUS bank's W.
; CHECK: ldb_erp a, 227                 ; encoding: [0xc7,0xe3,0x99]
ldb_erp a, 0xe3
; prom_a 0xF83202, the next instruction.  unidasm: ld QA,A -- 0xE2 = the
; previous bank's A.  0xE0/0xE1 would be the CURRENT bank's A and W.
; CHECK: ldb_erp a, 226                 ; encoding: [0xc7,0xe2,0x99]
ldb_erp a, 0xe2
; prom_a 0xFE6254.  unidasm: ld QIZH,A
; CHECK: ldb_erp a, 251                 ; encoding: [0xc7,0xfb,0x99]
ldb_erp a, 0xfb
; prom_a 0xF819C2.  unidasm: ld RL3,A -- a banked register below 0xE0, which is
; why this operand is an address and not a register name.
; CHECK: ldb_erp a, 60                  ; encoding: [0xc7,0x3c,0x99]
ldb_erp a, 0x3c
; prom_a 0xFC9FF7.  unidasm: ld IYL,E
; CHECK: ldb_erp e, 244                 ; encoding: [0xc7,0xf4,0x9d]
ldb_erp e, 0xf4

; ==========================================================================
; LD r8, (regfile) -- the other direction, sub-opcode 0x88 + reg.
; ==========================================================================

; prom_a 0xF819D5.  unidasm: ld A,RL3
; CHECK: ld_erpb_rr a, 60               ; encoding: [0xc7,0x3c,0x89]
ld_erpb_rr a, 0x3c
; prom_a 0xF95A43.  unidasm: ld C,IYL
; CHECK: ld_erpb_rr c, 244              ; encoding: [0xc7,0xf4,0x8b]
ld_erpb_rr c, 0xf4
; prom_a 0xFE3735.  unidasm: ld A,IZL
; CHECK: ld_erpb_rr a, 248              ; encoding: [0xc7,0xf8,0x89]
ld_erpb_rr a, 0xf8
