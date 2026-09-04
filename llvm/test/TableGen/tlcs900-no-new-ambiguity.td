// REQUIRES: asserts
// RUN: llvm-tblgen -gen-asm-matcher -debug-only=ambiguous_instrs \
// RUN:     -I %p/../../lib/Target/TLCS900 -I %p/../../include \
// RUN:     %p/../../lib/Target/TLCS900/TLCS900.td -o /dev/null 2>&1 \
// RUN:     | FileCheck %s
//
// The TLCS900 asm-matcher ambiguity report must not grow.
//
// Two TLCS900 matchables (instruction defs or InstAliases) that share a
// mnemonic and an operand-class list are chosen between by TABLE ORDER, and a
// normal build says nothing: AsmMatcherEmitter computes exactly this
// (MatchableInfo::couldMatchAmbiguouslyWith) but reports it only under
// -debug-only=ambiguous_instrs, so an assertions build is required.
//
// This is the guard behind the encoding selectors (TLCS900EncodingForms.td).
// A def that joins a family WITHOUT its selector -- `def CP8_tiny :
// PrefixSmallImmInst<0xD8, (outs), (ins GR8:$rs1, i8imm:$imm), "cp",
// "$rs1, $imm", []>` -- has the same shape as CP8ri and is reported here as
// ambiguous with it; a spelling-keyed checker would not see it.  Deleting the
// selector tail from an existing short def (CP8_small) is reported the same way.
//
// BASELINE, measured 2026-09-04: ONE pair, LINK / LINK32r -- `link <GPR>,
// <imm>` is served by two defs.  That is a pre-existing defect, not fixed here
// and not to be masked: fixing it must update this test deliberately.
// llvm/utils/tlcs900-ambiguity-baseline.sh runs the same check from a shell.

// CHECK: warning: ambiguous matchables:
// CHECK-NEXT: LINK{{(32r)?}} -- flattened:
// CHECK: is incomparable with:
// CHECK-NEXT: LINK{{(32r)?}} -- flattened:
// CHECK: warning: 1 ambiguous matchables!
