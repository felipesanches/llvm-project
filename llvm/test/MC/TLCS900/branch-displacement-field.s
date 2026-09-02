; RUN: not llvm-mc -triple tlcs900 -show-encoding < %s \
; RUN:     | FileCheck --check-prefix=CHECK-ENC %s
; RUN: not llvm-mc -triple tlcs900 -filetype=obj -o /dev/null %s 2>&1 \
; RUN:     | FileCheck --check-prefix=CHECK-ERR %s
;
; JR / JRcc / DJNZ take the RAW DISPLACEMENT FIELD, not a target address.  An
; operand that fits it neither signed nor unsigned was silently masked to its
; low byte -- `jr 99832` assembled to [0x68,0xf8] and branched somewhere else
; entirely, with no diagnostic.  That is the same shape as `push 0x1234` ->
; [0x09,0x34] and `mul WA,(0x1234)` multiplying by the address, both of which
; became errors in 95f7f2d40428; JRL and CALR were covered there because they
; emit through emitImmediate, and JR/DJNZ were not.
;
; The bytes below are real ROM sites in the kn5000-roms-disasm tree, found by
; scripts/analysis/branch_displacement_field_audit.py -- 36 operands in 6 files
; did not fit, and every one of them is a displacement, not a target.

; --- The displacements those sites really hold ------------------------------
; kn5000_subprogram_v142.rom, PrevBank_RegHelper: `67 df` = jr c, -33.  The
; source said `jr c, 16777183` -- the field sign-extended to 24 bits by the
; disassembly that produced it, exactly the mistake 95f7f2d40428 found in 31
; `jrl` operands.  The only `67 df` in that image.
; CHECK-ENC: jr	c, -33 ; encoding: [0x67,0xdf]
jr c, -33

; Ten bytes later in the same routine: `68 fd` = jr t, -3, written as
; `jr t, 16777213`.
; CHECK-ENC: jr	t, -3 ; encoding: [0x68,0xfd]
jr t, -3

; wsa1_prom_a at FE42FE holds `68 4d`.  Its source line said `jr T,0xfe434d`,
; the TARGET address -- and got the right byte only because the instruction
; ends at 0xFE4300, so the target's low byte IS the displacement.  Two sites
; in prom_a were written that way.
; CHECK-ENC: jr	t, 77 ; encoding: [0x68,0x4d]
jr t, 0x4d

; wsa1_prom_a at FE51FE: `63 5a`, from `jr ULE,0xfe525a`.
; CHECK-ENC: jr	ule, 90 ; encoding: [0x63,0x5a]
jr ule, 0x5a

; The full unsigned and signed range of the field still assembles.
; CHECK-ENC: jr	-128 ; encoding: [0x68,0x80]
jr -128
; CHECK-ENC: jr	255 ; encoding: [0x68,0xff]
jr 255

; --- and the guards --------------------------------------------------------
; JRL and CALR are unchanged: they take a 16-bit field and always did refuse a
; value too wide for it.  Nothing here may narrow them to eight bits.
; CHECK-ENC: jrl	4660 ; encoding: [0x78,0x34,0x12]
jrl 0x1234
; CHECK-ENC: calr	4660 ; encoding: [0x1e,0x34,0x12]
calr 0x1234

; --- what is now refused ---------------------------------------------------
; ⚠ Both RUN lines use `not`: the refusals below make llvm-mc exit non-zero in
; -show-encoding mode too, and the encodings above are still printed in order,
; so CHECK-ENC matches them before the first bad line is reached.
; CHECK-ERR: error: immediate 0x185f8 does not fit in the 8-bit field
jr 99832
; CHECK-ERR: error: immediate 0xffffdf does not fit in the 8-bit field
jr c, 16777183
; CHECK-ERR: error: immediate 0xfe434d does not fit in the 8-bit field
jr t, 0xfe434d
; CHECK-ERR: error: immediate 0x185f8 does not fit in the 16-bit field
jrl 99832
; CHECK-ERR: error: immediate 0x185f8 does not fit in the 16-bit field
calr 99832
