; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test shift and rotate instructions: SLA, SRA, SRL, SLL, RLC, RRC, RL, RR
; across all register sizes (8/16/32-bit).

; ==========================================================================
; 8-bit shifts (C8-CF prefix)
; ==========================================================================

; SLA rd8, #n: C8+r, 0xEC, n
; CHECK: sla a, 1           ; encoding: [0xc9,0xec,0x01]
sla a, 1
; CHECK: sla a, 4           ; encoding: [0xc9,0xec,0x04]
sla a, 4
; CHECK: sla b, 1           ; encoding: [0xca,0xec,0x01]
sla b, 1

; SRA rd8, #n: C8+r, 0xED, n
; CHECK: sra a, 4           ; encoding: [0xc9,0xed,0x04]
sra a, 4
; CHECK: sra a, 1           ; encoding: [0xc9,0xed,0x01]
sra a, 1
; CHECK: sra b, 8           ; encoding: [0xca,0xed,0x08]
sra b, 8

; SRL rd8, #n: C8+r, 0xEF, n
; CHECK: srl b, 8           ; encoding: [0xca,0xef,0x08]
srl b, 8
; CHECK: srl a, 1           ; encoding: [0xc9,0xef,0x01]
srl a, 1

; SLL rd8, #n: C8+r, 0xEE, n
; CHECK: sll a, 1           ; encoding: [0xc9,0xee,0x01]
sll a, 1
; CHECK: sll a, 4           ; encoding: [0xc9,0xee,0x04]
sll a, 4

; ==========================================================================
; 8-bit rotates
; ==========================================================================

; RLC rd8: C8+r, 0xE8, 0x01
; CHECK: rlc a              ; encoding: [0xc9,0xe8,0x01]
rlc a

; RRC rd8: C8+r, 0xE9, 0x01
; CHECK: rrc b              ; encoding: [0xca,0xe9,0x01]
rrc b

; RL rd8: C8+r, 0xEA, 0x01
; CHECK: rl c               ; encoding: [0xcb,0xea,0x01]
rl c

; RR rd8: C8+r, 0xEB, 0x01
; CHECK: rr d               ; encoding: [0xcc,0xeb,0x01]
rr d

; ==========================================================================
; 16-bit shifts (D8-DF prefix)
; ==========================================================================

; SLA rd16, #n: D8+r, 0xEC, n
; CHECK: sla wa, 1          ; encoding: [0xd8,0xec,0x01]
sla wa, 1
; CHECK: sla bc, 4          ; encoding: [0xd9,0xec,0x04]
sla bc, 4

; SRA rd16, #n: D8+r, 0xED, n
; CHECK: sra bc, 4          ; encoding: [0xd9,0xed,0x04]
sra bc, 4
; CHECK: sra wa, 1          ; encoding: [0xd8,0xed,0x01]
sra wa, 1

; SRL rd16, #n: D8+r, 0xEF, n
; CHECK: srl de, 8          ; encoding: [0xda,0xef,0x08]
srl de, 8
; CHECK: srl wa, 1          ; encoding: [0xd8,0xef,0x01]
srl wa, 1

; SLL rd16, #n: D8+r, 0xEE, n
; CHECK: sll wa, 1          ; encoding: [0xd8,0xee,0x01]
sll wa, 1

; ==========================================================================
; 16-bit rotates
; ==========================================================================

; RLC rd16: D8+r, 0xE8, 0x01
; CHECK: rlc wa             ; encoding: [0xd8,0xe8,0x01]
rlc wa

; RRC rd16: D8+r, 0xE9, 0x01
; CHECK: rrc bc             ; encoding: [0xd9,0xe9,0x01]
rrc bc

; RL rd16: D8+r, 0xEA, 0x01
; CHECK: rl de              ; encoding: [0xda,0xea,0x01]
rl de

; RR rd16: D8+r, 0xEB, 0x01
; CHECK: rr hl              ; encoding: [0xdb,0xeb,0x01]
rr hl

; ==========================================================================
; 32-bit shifts (E8-EF prefix)
; ==========================================================================

; SLA rd, #n: E8+r, 0xEC, n
; CHECK: sla xwa, 1         ; encoding: [0xe8,0xec,0x01]
sla xwa, 1
; CHECK: sla xde, 4         ; encoding: [0xea,0xec,0x04]
sla xde, 4
; CHECK: sla xbc, 8         ; encoding: [0xe9,0xec,0x08]
sla xbc, 8

; SRA rd, #n: E8+r, 0xED, n
; CHECK: sra xwa, 1         ; encoding: [0xe8,0xed,0x01]
sra xwa, 1
; CHECK: sra xbc, 4         ; encoding: [0xe9,0xed,0x04]
sra xbc, 4

; SRL rd, #n: E8+r, 0xEF, n
; CHECK: srl xwa, 8         ; encoding: [0xe8,0xef,0x08]
srl xwa, 8
; CHECK: srl xde, 1         ; encoding: [0xea,0xef,0x01]
srl xde, 1

; SLL rd, #n: E8+r, 0xEE, n
; CHECK: sll xwa, 1         ; encoding: [0xe8,0xee,0x01]
sll xwa, 1

; ==========================================================================
; 32-bit rotates
; ==========================================================================

; RLC rd: E8+r, 0xE8, 0x01
; CHECK: rlc xwa            ; encoding: [0xe8,0xe8,0x01]
rlc xwa

; RRC rd: E8+r, 0xE9, 0x01
; CHECK: rrc xbc            ; encoding: [0xe9,0xe9,0x01]
rrc xbc

; RL rd: E8+r, 0xEA, 0x01
; CHECK: rl xde             ; encoding: [0xea,0xea,0x01]
rl xde

; RR rd: E8+r, 0xEB, 0x01
; CHECK: rr xhl             ; encoding: [0xeb,0xeb,0x01]
rr xhl
