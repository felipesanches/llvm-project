//===-- TLCS900EncodingForms.td - Encoding selectors -------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// ENCODING SELECTORS
//
// Several TLCS-900 operations have more than one legal encoding for the same
// operands.  The assembler never chooses between them.  A source line names
// the encoding it wants with a SELECTOR written after the last operand
// (`cp a, 4:i3`), or writes none and gets the family's DEFAULT form.  Each
// selector names a MECHANISM that is visible in the bytes, and each is bound
// to exactly one encoder path:
//
//   :i3   the operand value is packed into the opcode byte's low three bits:
//         prefix+r, then 0xA8|n (LD) or 0xD8|n (CP).     encoder PrefixSmallImm
//   :opc  the operation's own dedicated primary-map opcode with the register
//         folded into it: 0x20+r.                        encoder SingleByteRegImm
//   :io   the dedicated I/O-space store opcode, 0x08 (byte) / 0x0A (word),
//         taking an 8-bit direct address.               encoders LdIoImm/LdIoImm16
//
// A selector is NOT a length, NOT "the other one" and NOT "the shortest that
// fits".  Measured with llvm-mc 850b013e... on 2026-09-04, `ld d, 4` has
// THREE legal encodings today:
//
//     ld d, 4          cc 03 04     3 bytes   (the untagged default, LD8ri_asm)
//     ld d, 4:i3       cc ac        2 bytes   (LD8ri_small)
//     ld d, 4:opc      24 04        2 bytes   (LD8ri_short)
//
// and the two short ones TIE, so "shortest" is not even a function here.
//
// MECHANISM.  The selector is spliced into the short def's AsmString as a
// literal token (`!strconcat("$rs1, ${imm}", FormI3.AsmTail)`), so that def's matchable
// carries one MORE asm operand than the default form's.  A line that writes no
// selector therefore cannot reach a short encoding, by ARITY: there is no
// priority field, no PreferSmallerInstructions and no arbitration to mis-tune.
// -gen-asm-writer emits the same token back, so the printer round-trips with
// no C++ for the register families.
//
// THE FAMILY TABLE in TLCS900EncodingFamilies.td (included after the defs it
// names) lists every family with its UNTAGGED DEFAULT as a named member.  The
// absence of a selector is itself an encoding decision, and because the
// default is whatever historically owned the plain spelling, the vocabulary is
// not uniform across sizes: 0x20+r is `:opc` at 8 bits but the untagged
// default at 32 bits (`ld xiz, 0` = 46 00 00 00 00, LD32ri).  An explicit
// selector for the default (`cp a, 4:l`) is deliberately not offered -- two
// spellings for one byte string would break the printer's injectivity, and
// re-disassembly would drop the tag anyway.
//
// CONVENTION.  The selector rides the LAST operand.  For the io family that
// operand is the value, although the fact selected is about the whole
// instruction; `ldw (237:8), 0x8e00:io` carries an address WIDTH inside the
// parentheses and an encoding SELECTOR after the value, two different kinds
// of statement, which is why a numeric `:N` after a bare operand is rejected.
//
//===----------------------------------------------------------------------===//

class EncForm<string suffix, string doc> {
  string Suffix = suffix;                                  // "" = the default
  string AsmTail = !if(!empty(suffix), "", ":" # suffix);  // spliced into AsmString
  string Doc = doc;
}

def FormDefault : EncForm<"",
  "written with no selector: the form that historically owned the plain spelling">;
def FormI3 : EncForm<"i3",
  "the value is packed into the opcode byte's low 3 bits: prefix+r, then 0xA8|n (LD) or 0xD8|n (CP)">;
def FormOpc : EncForm<"opc",
  "the operation's own primary-map opcode with the register folded in: 0x20+r">;
def FormIo : EncForm<"io",
  "the dedicated I/O-space store opcode 0x08 / 0x0A, with an 8-bit direct address">;

class FormOf<EncForm f, Instruction i> {
  EncForm Form = f;
  Instruction Inst = i;
}

// A group of defs that share a mnemonic and an operand shape and are told
// apart ONLY by the selector.  Adding an encoding to a family is a deliberate
// change: give it its own EncForm, list it here and bump NumForms.  The
// asserts catch a member list that disagrees with NumForms, a family with no
// (or two) default forms, and two members claiming one suffix.  They cannot
// see a def that never joined a family; llvm-tblgen's own ambiguity report
// (llvm/utils/tlcs900-ambiguity-baseline.sh, lit: TableGen/tlcs900-no-new-
// ambiguity.td) and the byte pins in MC/TLCS900/encoding-selector.s do.
class EncFamily<string name, int nforms, list<FormOf> members> {
  string Name = name;
  int NumForms = nforms;
  list<FormOf> Members = members;
  assert !eq(!size(members), nforms),
    "encoding family '" # name # "': member list and NumForms disagree";
  assert !eq(!size(!filter(m, members, !empty(m.Form.Suffix))), 1),
    "encoding family '" # name # "': exactly one member must carry FormDefault";
  assert !eq(!size(!filter(m, members,
               !eq(!size(!filter(n, members,
                                 !eq(n.Form.Suffix, m.Form.Suffix))), 1))),
             nforms),
    "encoding family '" # name # "': two members share a selector suffix";
}
