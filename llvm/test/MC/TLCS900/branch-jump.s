; RUN: llvm-mc -triple tlcs900 -show-encoding < %s | FileCheck %s
;
; Test branch and jump instructions: JR, JRL, JP, CALL, CALR, RET, RETI,
; RETD, DJNZ, SCC, with all condition codes.

; ==========================================================================
; JP (unconditional): 0x1B, addr24
; ==========================================================================

; CHECK: jp 0               ; encoding: [0x1b,0x00,0x00,0x00]
jp 0
; CHECK: jp 1193046         ; encoding: [0x1b,0x56,0x34,0x12]
jp 0x123456

; ==========================================================================
; JP cc, addr: conditional branch (emits as JRL cc, d16 — PC-relative)
; Numeric targets create PC-relative fixups.
; ==========================================================================

; CHECK: jp f, 0            ; encoding: [0x70,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp f, 0
; CHECK: jp lt, 0           ; encoding: [0x71,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp lt, 0
; CHECK: jp le, 0           ; encoding: [0x72,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp le, 0
; CHECK: jp ule, 0          ; encoding: [0x73,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp ule, 0
; CHECK: jp ov, 0           ; encoding: [0x74,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp ov, 0
; CHECK: jp mi, 0           ; encoding: [0x75,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp mi, 0
; CHECK: jp z, 0            ; encoding: [0x76,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp z, 0
; CHECK: jp c, 0            ; encoding: [0x77,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp c, 0
; CHECK: jp t, 0            ; encoding: [0x78,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp t, 0
; CHECK: jp ge, 0           ; encoding: [0x79,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp ge, 0
; CHECK: jp gt, 0           ; encoding: [0x7a,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp gt, 0
; CHECK: jp ugt, 0          ; encoding: [0x7b,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp ugt, 0
; CHECK: jp nov, 0          ; encoding: [0x7c,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp nov, 0
; CHECK: jp pl, 0           ; encoding: [0x7d,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp pl, 0
; CHECK: jp nz, 0           ; encoding: [0x7e,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp nz, 0
; CHECK: jp nc, 0           ; encoding: [0x7f,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jp nc, 0

; ==========================================================================
; JR cc, disp8: short conditional relative jump (0x60+cc, disp8)
; Numeric targets create PC-relative fixups (resolved at link time).
; ==========================================================================

; CHECK: jr f, 0            ; encoding: [0x60,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr f, 0
; CHECK: jr lt, 0           ; encoding: [0x61,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr lt, 0
; CHECK: jr le, 0           ; encoding: [0x62,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr le, 0
; CHECK: jr ule, 0          ; encoding: [0x63,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr ule, 0
; CHECK: jr ov, 0           ; encoding: [0x64,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr ov, 0
; CHECK: jr mi, 0           ; encoding: [0x65,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr mi, 0
; CHECK: jr z, 0            ; encoding: [0x66,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr z, 0
; CHECK: jr c, 0            ; encoding: [0x67,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr c, 0
; CHECK: jr t, 0            ; encoding: [0x68,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr t, 0
; CHECK: jr ge, 0           ; encoding: [0x69,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr ge, 0
; CHECK: jr gt, 0           ; encoding: [0x6a,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr gt, 0
; CHECK: jr ugt, 0          ; encoding: [0x6b,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr ugt, 0
; CHECK: jr nov, 0          ; encoding: [0x6c,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr nov, 0
; CHECK: jr pl, 0           ; encoding: [0x6d,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr pl, 0
; CHECK: jr nz, 0           ; encoding: [0x6e,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr nz, 0
; CHECK: jr nc, 0           ; encoding: [0x6f,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-1, kind: fixup_tlcs900_rel8
jr nc, 0

; ==========================================================================
; JRL cc, disp16: long conditional relative jump
; Numeric targets create PC-relative fixups (resolved at link time).
; ==========================================================================

; CHECK: jrl z, 0           ; encoding: [0x76,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jrl z, 0
; CHECK: jrl nz, 0          ; encoding: [0x7e,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jrl nz, 0
; CHECK: jrl c, 0           ; encoding: [0x77,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jrl c, 0
; CHECK: jrl nc, 0          ; encoding: [0x7f,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jrl nc, 0
; CHECK: jrl lt, 0          ; encoding: [0x71,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jrl lt, 0
; CHECK: jrl ge, 0          ; encoding: [0x79,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
jrl ge, 0

; ==========================================================================
; CALL nnn: 0x1D, addr24
; ==========================================================================

; CHECK: call 0             ; encoding: [0x1d,0x00,0x00,0x00]
call 0
; CHECK: call 11259375      ; encoding: [0x1d,0xef,0xcd,0xab]
call 0xABCDEF

; ==========================================================================
; CALR d16: 0x1E, disp16 (PC-relative, offset computed from end of insn)
; ==========================================================================

; Numeric target creates a PC-relative fixup (resolved by linker).
; CHECK: calr 0             ; encoding: [0x1e,A,A]
; CHECK:                    ;   fixup A - offset: 1, value: 0-2, kind: fixup_tlcs900_rel16
calr 0

; ==========================================================================
; CALL / JP indirect (B0+reg prefix)
; ==========================================================================

; JP (Xrr): B0+reg, 0xD8
; CHECK: jp (xwa)           ; encoding: [0xb0,0xd8]
jp (xwa)
; CHECK: jp (xhl)           ; encoding: [0xb3,0xd8]
jp (xhl)
; CHECK: jp (xix)           ; encoding: [0xb4,0xd8]
jp (xix)

; CALL (Xrr): B0+reg, 0xE8
; CHECK: call (xwa)         ; encoding: [0xb0,0xe8]
call (xwa)
; CHECK: call (xhl)         ; encoding: [0xb3,0xe8]
call (xhl)

; ==========================================================================
; RET (unconditional): 0x0E
; ==========================================================================

; CHECK: ret                ; encoding: [0x0e]
ret

; ==========================================================================
; RET cc: conditional return (B0, 0xF0+cc)
; All 12 non-trivial condition codes tested
; ==========================================================================

; CHECK: ret z              ; encoding: [0xb0,0xf6]
ret z
; CHECK: ret nz             ; encoding: [0xb0,0xfe]
ret nz
; CHECK: ret c              ; encoding: [0xb0,0xf7]
ret c
; CHECK: ret nc             ; encoding: [0xb0,0xff]
ret nc
; CHECK: ret lt             ; encoding: [0xb0,0xf1]
ret lt
; CHECK: ret ge             ; encoding: [0xb0,0xf9]
ret ge
; CHECK: ret le             ; encoding: [0xb0,0xf2]
ret le
; CHECK: ret gt             ; encoding: [0xb0,0xfa]
ret gt
; CHECK: ret ov             ; encoding: [0xb0,0xf4]
ret ov
; CHECK: ret nov            ; encoding: [0xb0,0xfc]
ret nov
; CHECK: ret mi             ; encoding: [0xb0,0xf5]
ret mi
; CHECK: ret pl             ; encoding: [0xb0,0xfd]
ret pl
; CHECK: ret ule            ; encoding: [0xb0,0xf3]
ret ule
; CHECK: ret ugt            ; encoding: [0xb0,0xfb]
ret ugt

; ==========================================================================
; RETI: 0x07
; ==========================================================================

; CHECK: reti               ; encoding: [0x07]
reti

; ==========================================================================
; RETD d16: 0x0F, disp16
; ==========================================================================

; CHECK: retd 0             ; encoding: [0x0f,0x00,0x00]
retd 0
; CHECK: retd 4             ; encoding: [0x0f,0x04,0x00]
retd 4
; CHECK: retd 256           ; encoding: [0x0f,0x00,0x01]
retd 256

; ==========================================================================
; DJNZ rd, disp: D8+r, 0x1C, disp8 (PC-relative)
; ==========================================================================

; CHECK: djnz xwa, 0        ; encoding: [0xd8,0x1c,A]
; CHECK:                     ;   fixup A - offset: 2, value: 0-1, kind: fixup_tlcs900_rel8
djnz xwa, 0

; Note: SCC is isCodeGenOnly (empty encoding), not tested here.
