; RUN: llvm-mc -triple tlcs900 -show-encoding %s 2>&1 >/dev/null | FileCheck %s --check-prefix=WARN
; RUN: llvm-mc -triple tlcs900 -show-encoding %s 2>&1 >/dev/null | grep -c 'warning:' | FileCheck %s --check-prefix=WARNCOUNT
; RUN: llvm-mc -triple tlcs900 -show-encoding %s 2>/dev/null | FileCheck %s --check-prefix=ENC
;
; (Xrr+d8) is a SIGNED 8-bit field. A raw disp8 byte >= 0x80 written as its
; positive value (128..255) does not fit that field and falls through to the
; 5-byte (Xrr+d16) form -- a DIFFERENT, legitimate encoding, not a
; miscompile: +151 and -105 are different addresses, not one byte spelled
; two ways. This tree has hundreds of genuine (Xrr+d16) displacements in the
; 128..255 range, so this can only be flagged, never turned into an error or
; silently re-encoded as d8 -- either would change what an already-correct
; spelling assembles to, which this backend never does.
;
; Byte proof beyond this file's `encoding:` line (that field can be a
; shorter re-encode, not necessarily the assembled bytes): `llvm-mc
; -filetype=obj` + `llvm-objcopy -O binary --only-section=.text` + `cmp` on
; the two spellings below confirms
;   lda xhl, (xde+0x97)  -> f3 e9 97 00 33  (5 bytes, d16 form)
;   lda xhl, (xde-105)   -> ba 97 33        (3 bytes, d8 form)
; 0x97 and -105 are the same raw byte; +0x97 (== +151 decimal) is a
; different, larger displacement, not that byte's signed value.

; WARN: warning: displacement +151 (raw byte 0x97) does not fit the signed (Xrr+d8) field and assembles to the 5-byte (Xrr+d16) form; if you intended the raw disp8 byte 0x97 (i.e. the 2-byte d8 encoding), write the signed displacement -105 instead
; ENC: lda     xhl, (xde+151)                  ; encoding: [0xf3,0xe9,0x97,0x00,0x33]
lda xhl, (xde+0x97)

; The signed spelling of the SAME raw byte selects the 2-byte d8 form and
; gets no warning at all (checked by WARNCOUNT below: exactly 2 warnings
; total in this file, not 3).
; ENC: lda     xhl, (xde-105)                  ; encoding: [0xba,0x97,0x33]
lda xhl, (xde-105)

; A genuine large positive d16 displacement in the same 128..255 band is
; UNCHANGED by this fix -- still the correct, already-working 5-byte form --
; it just also gets the warning, because the assembler cannot tell this case
; apart from the mistake above by the integer value alone.
; WARN: warning: displacement +200 (raw byte 0xc8) does not fit the signed (Xrr+d8) field and assembles to the 5-byte (Xrr+d16) form; if you intended the raw disp8 byte 0xc8 (i.e. the 2-byte d8 encoding), write the signed displacement -56 instead
; ENC: ld      c, (xbc+200)                    ; encoding: [0xc3,0xe5,0xc8,0x00,0x23]
ld c, (xbc+200)

; WARNCOUNT: 2
