; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: llvm-mc -triple tlcs900 -filetype=obj %s | llvm-objdump -d - | FileCheck --check-prefix=INST %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; LD between a named register R and the register-file register r the C7/D7
; prefix addresses: 0x88+R is LD R,r (R <- r) and 0x98+R is LD r,R (r <- R).
; The byte/word forms were spelled `stb_erp` / `ldb_erp` / `stw_erp` /
; `ldw_erp`, names that read backwards (`ldw_erp WA, 0x30` STORES WA into
; RWA3); they take the long form's names, ldto_* (load TO R) and ldfr_*
; (load FROM R).  MAME unidasm's reading quoted.

.ifndef ERR
; unidasm: c7 fb 89  ld A,QIZH
; CHECK: ldto_berp a, 251          ; encoding: [0xc7,0xfb,0x89]
; INST:  ldto_berp a, 251
ldto_berp a, 0xfb
; unidasm: c7 fb 99  ld QIZH,A
; CHECK: ldfr_berp a, 251          ; encoding: [0xc7,0xfb,0x99]
; INST:  ldfr_berp a, 251
ldfr_berp a, 0xfb
; unidasm: d7 30 88  ld WA,RWA3
; CHECK: ldto_werp wa, 48          ; encoding: [0xd7,0x30,0x88]
ldto_werp wa, 0x30
; unidasm: d7 30 98  ld RWA3,WA
; CHECK: ldfr_werp wa, 48          ; encoding: [0xd7,0x30,0x98]
ldfr_werp wa, 0x30
; the long forms always had the right names (unidasm: e7 e4 88 ld XWA,XBC)
; CHECK: ldto_lerp xwa, 228        ; encoding: [0xe7,0xe4,0x88]
ldto_lerp xwa, 0xe4
.else
; ERR: error: unrecognized instruction mnemonic
stb_erp a, 0xfb
; ERR: error: unrecognized instruction mnemonic
ldw_erp wa, 0x30
.endif
