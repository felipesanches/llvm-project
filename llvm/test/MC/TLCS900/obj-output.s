; RUN: llvm-mc -triple tlcs900 -filetype=obj < %s -o /dev/null
;
; Smoke test: verify the MCCodeEmitter and AsmBackend can produce an
; ELF object file without crashing. The encoding is placeholder (NOP
; bytes) but the infrastructure must handle all instruction types.

nop
ret
push xwa
pop xbc
add xde, xbc
sub xhl, 42
cp xwa, 0
ld xde, (xsp+4)
ld (xsp), xwa
