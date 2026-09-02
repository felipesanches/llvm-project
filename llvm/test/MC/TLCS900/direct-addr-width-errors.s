; RUN: not llvm-mc -triple tlcs900 -filetype=obj -o /dev/null %s 2>&1 | FileCheck %s
;
; An address that does not fit the requested direct-address form is REFUSED.
; Silently keeping the low bytes is the one unacceptable outcome: it points
; the instruction at a different address with no diagnostic.

; CHECK: error: direct address 0x1234 does not fit in the 8-bit form
cp (0x1234:8), 0x56

; CHECK: error: direct address 0x123456 does not fit in the 16-bit form
bit 1, (0x123456:16)

; CHECK: error: address width must be 8, 16 or 24
ld a, (0x9c:12)

; An immediate too wide for its field is refused too. `push 0x1234` used to
; assemble to [0x09,0x34].
; CHECK: error: immediate 0x1234 does not fit in the 8-bit field
push 0x1234

; `(Xrr+Rn)` is the register-indexed operand, a different encoding from
; `(Xrr+d16)`. Letting the expression parser have the index register turned it
; into an undefined symbol and silently produced the d16 form, so it was
; refused outright.
;
; ⚠ THAT REFUSAL IS GONE, and `ld wa, (xix+iz)` now assembles to the ROM's own
; d3 07 f0 f8 20 -- see reg-indexed-operand.s. The operand is a distinct parser
; kind, so an index register can no longer reach the displacement slot at all;
; the confusion is impossible rather than diagnosed. What is left is a plain
; operand-class mismatch on the forms that still have no definition -- the ALU
; and PUSH sub-opcodes of the R+R table -- and that is a loud rejection, never
; a byte.
; CHECK: error: invalid operand for instruction
add wa, (xix+iz)
; CHECK: error: invalid operand for instruction
push (xix+iz)
