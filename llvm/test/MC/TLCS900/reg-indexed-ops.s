; RUN: llvm-mc -triple tlcs900 -show-encoding %s | FileCheck %s
; RUN: not llvm-mc -triple tlcs900 -defsym ERR=1 %s 2>&1 | FileCheck --check-prefix=ERR %s
;
; The register-indexed operand (xrr+rr) on every source- and destination-memory
; operation, not only ld / lda / the stores / jp / call.  Each encoding is the
; one MAME unidasm reads back as quoted (the KN5000 trees held these as the raw
; pseudos cpib_sri, cpb_sri_rm, add_sril_rm, bit_dri, stib_ind, inc_sriw ...).

; CHECK: cp (xhl+iy), 123 ; encoding: [0xc3,0x07,0xec,0xf4,0x3f,0x7b]
	cp	(xhl+iy), 0x7b          ; cp (XHL+IY),0x7b
; CHECK: cpw (xwa+bc), 65535 ; encoding: [0xd3,0x07,0xe0,0xe4,0x3f,0xff,0xff]
	cpw	(xwa+bc), 0xffff        ; cp (XWA+BC),0xffff
; CHECK: cp hl, (xbc+de) ; encoding: [0xd3,0x07,0xe4,0xe8,0xf3]
	cp	hl, (xbc+de)
; CHECK: cp (xhl+de), a ; encoding: [0xc3,0x07,0xec,0xe8,0xf9]
	cp	(xhl+de), a
; CHECK: cp xwa, (xix+iy) ; encoding: [0xe3,0x07,0xf0,0xf4,0xf0]
	cp	xwa, (xix+iy)
; CHECK: add xde, (xwa+bc) ; encoding: [0xe3,0x07,0xe0,0xe4,0x82]
	add	xde, (xwa+bc)
; CHECK: add (xbc+de), a ; encoding: [0xc3,0x07,0xe4,0xe8,0x89]
	add	(xbc+de), a
; CHECK: and (xbc+wa), 143 ; encoding: [0xc3,0x07,0xe4,0xe0,0x3c,0x8f]
	and	(xbc+wa), 0x8f
; CHECK: sub (xwa+bc), 10 ; encoding: [0xc3,0x07,0xe0,0xe4,0x3a,0x0a]
	sub	(xwa+bc), 10
; CHECK: or de, (xbc+wa) ; encoding: [0xd3,0x07,0xe4,0xe0,0xe2]
	or	de, (xbc+wa)
; CHECK: ld (xiy+hl), 129 ; encoding: [0xf3,0x07,0xf4,0xec,0x00,0x81]
	ld	(xiy+hl), 0x81          ; ld (XIY+HL),0x81
; CHECK: ldw (xix+hl), 32639 ; encoding: [0xf3,0x07,0xf0,0xec,0x02,0x7f,0x7f]
	ldw	(xix+hl), 0x7f7f
; CHECK: bit 7, (xhl+iy) ; encoding: [0xf3,0x07,0xec,0xf4,0xcf]
	bit	7, (xhl+iy)
; CHECK: res 7, (xbc+wa) ; encoding: [0xf3,0x07,0xe4,0xe0,0xb7]
	res	7, (xbc+wa)
; CHECK: set 6, (xbc+wa) ; encoding: [0xf3,0x07,0xe4,0xe0,0xbe]
	set	6, (xbc+wa)
; CHECK: inc 1, (xwa+iz) ; encoding: [0xc3,0x07,0xe0,0xf8,0x61]
	inc	1, (xwa+iz)
; CHECK: incw 1, (xwa+bc) ; encoding: [0xd3,0x07,0xe0,0xe4,0x61]
	incw	1, (xwa+bc)
; inc 8 writes the field as 0 (MAME prints the raw field: inc 0,(XWA+BC))
; CHECK: inc 8, (xwa+bc) ; encoding: [0xc3,0x07,0xe0,0xe4,0x60]
	inc	8, (xwa+bc)
; CHECK: dec 1, (xbc+wa) ; encoding: [0xc3,0x07,0xe4,0xe0,0x69]
	dec	1, (xbc+wa)
; CHECK: pushw (xbc+wa) ; encoding: [0xd3,0x07,0xe4,0xe0,0x04]
	pushw	(xbc+wa)
; CHECK: ex (xiz+ix), wa ; encoding: [0xd3,0x07,0xf8,0xf0,0x30]
	ex	(xiz+ix), wa

.ifdef ERR
; ERR: error: 8 does not fit a bit number (must be 0..7)
	bit	8, (xhl+iy)
; ERR: error: 0 is not an INC/DEC count (must be 1..8)
	inc	0, (xwa+bc)
; ERR: error: 256 does not fit an 8-bit immediate (must be 0..255)
	cp	(xhl+iy), 256
.endif
