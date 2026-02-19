//===-- TLCS900MCCodeEmitter.h - Convert TLCS900 Code to Machine Code --*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines the TLCS900MCCodeEmitter class.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCCODEEMITTER_H
#define LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCCODEEMITTER_H

#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCInstrInfo.h"

namespace llvm {

class TLCS900MCCodeEmitter : public MCCodeEmitter {
  const MCInstrInfo &MCII;
  MCContext &Ctx;

  /// Get the 3-bit hardware encoding for a register operand.
  unsigned getRegEncoding(const MCOperand &MO) const;

  /// Emit a little-endian immediate of the given byte size.
  void emitImmediate(int64_t Value, unsigned NumBytes,
                     SmallVectorImpl<char> &CB) const;

  /// Emit a fixup for a symbolic operand (address/displacement).
  void emitFixup(const MCInst &MI, const MCOperand &MO, unsigned FixupOffset,
                 MCFixupKind Kind, SmallVectorImpl<char> &CB,
                 SmallVectorImpl<MCFixup> &Fixups) const;

  /// Emit the memory addressing prefix bytes for MEMri operands.
  /// IsDstMem selects destination memory prefix (B0, for stores) vs
  /// source memory prefix (A0, for loads/ALU).
  /// Returns the number of bytes emitted.
  unsigned emitMemPrefix(const MCInst &MI, unsigned BaseOpIdx,
                         unsigned DispOpIdx, bool IsDstMem,
                         SmallVectorImpl<char> &CB,
                         SmallVectorImpl<MCFixup> &Fixups) const;

public:
  TLCS900MCCodeEmitter(const MCInstrInfo &MCII, MCContext &Ctx)
      : MCII(MCII), Ctx(Ctx) {}

  void encodeInstruction(const MCInst &MI, SmallVectorImpl<char> &CB,
                         SmallVectorImpl<MCFixup> &Fixups,
                         const MCSubtargetInfo &STI) const override;

  unsigned getMachineOpValue(const MCInst &MI, const MCOperand &MO,
                             SmallVectorImpl<MCFixup> &Fixups,
                             const MCSubtargetInfo &STI) const;
};

} // end namespace llvm

#endif // LLVM_LIB_TARGET_TLCS900_MCTARGETDESC_TLCS900MCCODEEMITTER_H
