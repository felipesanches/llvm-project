//===-- TLCS900FixupKinds.h - TLCS900 Specific Fixup Entries --------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900FIXUPKINDS_H
#define LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900FIXUPKINDS_H

#include "llvm/MC/MCFixup.h"

namespace llvm {
namespace TLCS900 {

enum Fixups {
  // 24-bit absolute address (JP, CALL targets).
  fixup_tlcs900_24 = FirstTargetFixupKind,
  // 8-bit PC-relative displacement (JR targets).
  fixup_tlcs900_rel8,
  // 16-bit PC-relative displacement (JRL, CALR targets).
  fixup_tlcs900_rel16,
  // 8-bit displacement for base+d8 addressing.
  fixup_tlcs900_disp8,
  // 16-bit displacement for base+d16 addressing.
  fixup_tlcs900_disp16,
  // 8-bit branch displacement expression (user-computed, contains ".").
  // Uses FKF_IsTarget so the backend can resolve same-section differences.
  fixup_tlcs900_branch_expr8,
  // 16-bit branch displacement expression (user-computed, contains ".").
  // Uses FKF_IsTarget so the backend can resolve same-section differences.
  fixup_tlcs900_branch_expr16,

  // Marker.
  fixup_tlcs900_invalid,
  NumTargetFixupKinds = fixup_tlcs900_invalid - FirstTargetFixupKind
};

} // namespace TLCS900
} // namespace llvm

#endif // LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900FIXUPKINDS_H
