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

#include "TLCS900BaseInfo.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCInstrInfo.h"

namespace llvm {

class TLCS900MCCodeEmitter : public MCCodeEmitter {
  const MCInstrInfo &MCII;
  MCContext &Ctx;

  /// Get the 3-bit hardware encoding for a register operand.
  /// For 8-bit operations (OpSize8), if the operand contains a 32-bit parent
  /// register (from GPR_with_sub8), the sub_8bit sub-register's encoding is
  /// used instead (e.g. XWA→A=1, not XWA=0).
  unsigned getRegEncoding(const MCOperand &MO,
                          unsigned OpSize = TLCS900II::OpSize32) const;

  /// Emit a little-endian immediate of the given byte size.
  void emitImmediate(int64_t Value, unsigned NumBytes,
                     SmallVectorImpl<char> &CB) const;

  /// Emit a fixup for a symbolic operand (address/displacement).
  void emitFixup(const MCInst &MI, const MCOperand &MO, unsigned FixupOffset,
                 MCFixupKind Kind, SmallVectorImpl<char> &CB,
                 SmallVectorImpl<MCFixup> &Fixups) const;

  /// Emit the memory addressing prefix bytes for MEMri operands.
  /// IsDstMem selects destination memory prefix (B0, for stores) vs
  /// source memory prefix (size-dependent, for loads/ALU).
  /// OpSize selects the source memory prefix range (0=8-bit, 1=16-bit,
  /// 2=32-bit); ignored for destination memory.
  /// StartByte is the CB offset where the current instruction starts,
  /// used to compute instruction-relative fixup offsets.
  /// Returns the number of bytes emitted.
  unsigned emitMemPrefix(const MCInst &MI, unsigned BaseOpIdx,
                         unsigned DispOpIdx, bool IsDstMem, unsigned OpSize,
                         uint64_t StartByte, SmallVectorImpl<char> &CB,
                         SmallVectorImpl<MCFixup> &Fixups) const;

  /// Emit the direct addressing prefix bytes (prefix byte + address).
  /// IsDstMem: true → F1/F2 prefix; false → C1/D1/E1 or C2/D2/E2.
  /// OpSize: selects source prefix range (ignored for destination).
  /// Is24Bit: true → 24-bit address (3 bytes), false → 16-bit (2 bytes).
  void emitDirectAddrPrefix(const MCOperand &AddrOp, bool IsDstMem,
                            unsigned OpSize, bool Is24Bit,
                            uint64_t StartByte, SmallVectorImpl<char> &CB,
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
