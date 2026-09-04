//===-- TLCS900EncodingFamilies.td - The selector family table -*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// One row per family, the UNTAGGED DEFAULT listed as a named member.  Bytes
// verified with llvm-mc 850b013e... (2026-09-04); every row, default and
// tagged, is pinned in llvm/test/MC/TLCS900/encoding-selector.s.
//
//   cp  <GR8>,  imm   default CP8ri          c9 cf 04           :i3 CP8_small     c9 dc
//   cp  <GR16>, imm   default CP16ri         db cf 04 00        :i3 CP16_small    db dc
//   cp  <GPR>,  imm   default CP32ri         e8 cf 05 00 00 00  :i3 CP32_small    e8 dd
//   ld  <GR8>,  imm   default LD8ri_asm      cc 03 04           :i3 LD8ri_small   cc ac
//                                                               :opc LD8ri_short  24 04
//   ld  <GR16>, imm   default LD16ri_asm     db 03 00 00        :i3 LD16ri_small  db a8
//   ld  <GPR>,  imm   default LD32ri         46 00 00 00 00     :i3 LD32ri_small  ee a8
//   ld  (n:8),  imm   default LD8mi_dst      f0 07 00 ff        :io LDIO          08 07 ff
//   ldw (n:8),  imm   default LD16mi_dst_02  f0 ed 02 00 8e     :io LDWIO         0a ed 00 8e
//
// `ld <GR16>, imm` has a THIRD encoding, 0x30+r (LD16ri_short, `ldw wa, 4` =
// 30 04 00), still spelled by its own mnemonic; it is outside the selector
// vocabulary and outside this table.
//
//===----------------------------------------------------------------------===//

def EF_cp_r8   : EncFamily<"cp.r8.imm",     2, [FormOf<FormDefault, CP8ri>,
                                                FormOf<FormI3, CP8_small>]>;
def EF_cp_r16  : EncFamily<"cp.r16.imm",    2, [FormOf<FormDefault, CP16ri>,
                                                FormOf<FormI3, CP16_small>]>;
def EF_cp_r32  : EncFamily<"cp.r32.imm",    2, [FormOf<FormDefault, CP32ri>,
                                                FormOf<FormI3, CP32_small>]>;
def EF_ld_r8   : EncFamily<"ld.r8.imm",     3, [FormOf<FormDefault, LD8ri_asm>,
                                                FormOf<FormI3, LD8ri_small>,
                                                FormOf<FormOpc, LD8ri_short>]>;
def EF_ld_r16  : EncFamily<"ld.r16.imm",    2, [FormOf<FormDefault, LD16ri_asm>,
                                                FormOf<FormI3, LD16ri_small>]>;
def EF_ld_r32  : EncFamily<"ld.r32.imm",    2, [FormOf<FormDefault, LD32ri>,
                                                FormOf<FormI3, LD32ri_small>]>;
def EF_ld_io   : EncFamily<"ld.da8.imm8",   2, [FormOf<FormDefault, LD8mi_dst>,
                                                FormOf<FormIo, LDIO>]>;
def EF_ldw_io  : EncFamily<"ldw.da8.imm16", 2, [FormOf<FormDefault, LD16mi_dst_02>,
                                                FormOf<FormIo, LDWIO>]>;
