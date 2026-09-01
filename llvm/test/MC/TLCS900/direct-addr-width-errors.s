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
; into an undefined symbol and silently produced the d16 form.
; CHECK: error: register-indexed memory operand (Xrr+Rn) is not encodable yet
ld wa, (xix+iz)
