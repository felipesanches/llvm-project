; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; A shift or rotate count (SLA/SRA/SLL/SRL and RLC/RRC/RL/RR on a register,
; prefix + E8..EF + count byte) is 1..16.  The CPU reads the count byte as
; `count & 0x0F`, 0 meaning 16 (TLCS-900 "#4 = 1-16"; MAME's CPU core
; `(s & 0x0f) ? (s & 0x0f) : 16`).  The byte used to be written verbatim:
; `srl xhl, 16` assembled eb ef 10 and `srl xhl, 17` eb ef 11 (a shift by 1),
; and the tree spelled the 16-bit shift `srl xhl, 0` -- MAME's disassembler's
; raw field.  16 is now encoded as 0 and 0 / 17.. are refused.  The rotates
; take a count too (`rlc h, 2`); they were the raw pseudos `rlc_i_8` ...
; MAME unidasm's reading of each encoding is quoted.

; unidasm: eb ef 00  srl 0x00,XHL
; CHECK: srl xhl, 16 {{.*}}encoding: [0xeb,0xef,0x00]
srl xhl, 16
; unidasm: c9 ec 00  sla 0x00,A
; CHECK: sla a, 16 {{.*}}encoding: [0xc9,0xec,0x00]
sla a, 16
; unidasm: d8 ed 0f  sra 0x0f,WA
; CHECK: sra wa, 15 {{.*}}encoding: [0xd8,0xed,0x0f]
sra wa, 15
; unidasm: ec ee 01  sll 0x01,XIX
; CHECK: sll xix, 1 {{.*}}encoding: [0xec,0xee,0x01]
sll xix, 1
; unidasm: ce e8 02  rlc 0x02,H
; CHECK: rlc h, 2 {{.*}}encoding: [0xce,0xe8,0x02]
rlc h, 2
; unidasm: c9 e9 00  rrc 0x00,A
; CHECK: rrc a, 16 {{.*}}encoding: [0xc9,0xe9,0x00]
rrc a, 16
; unidasm: d8 ea 03  rl 0x03,WA
; CHECK: rl wa, 3 {{.*}}encoding: [0xd8,0xea,0x03]
rl wa, 3
; unidasm: ea eb 04  rr 0x04,XDE
; CHECK: rr xde, 4 {{.*}}encoding: [0xea,0xeb,0x04]
rr xde, 4
; the one-operand rotate is the same bytes with count 1
; unidasm: ce e9 01  rrc 0x01,H
; CHECK: rrc h {{.*}}encoding: [0xce,0xe9,0x01]
rrc h
; CHECK: rrc h, 1 {{.*}}encoding: [0xce,0xe9,0x01]
rrc h, 1
; a control-register number shares the format and is NOT a count
; CHECK: ldc_cr32 xwa, 5 {{.*}}encoding: [0xe8,0x2e,0x05]
ldc_cr32 xwa, 5

.ifdef ERR
; ERR: error: 0 is not a shift/rotate count: the count is 1..16 (16 is encoded as 0; write `16`, not the raw field 0)
srl xhl, 0
; ERR: error: 17 is not a shift/rotate count: the count is 1..16 (16 is encoded as 0)
srl xhl, 17
; ERR: error: 19 is not a shift/rotate count
rrc l, 19
; ERR: error: a shift/rotate count lives in the opcode byte and must be a constant
sla wa, LATER
; ERR: error: unrecognized instruction mnemonic
rrc_i_8 a, 3
.equ LATER, 5
.endif
