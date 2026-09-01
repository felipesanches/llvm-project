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
