//===-- TLCS900SelectionDAGInfo.cpp - TLCS900 SelectionDAG Info ------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements the TLCS900SelectionDAGInfo class.
//
//===----------------------------------------------------------------------===//

#include "TLCS900SelectionDAGInfo.h"
#include "TLCS900ISelLowering.h"
#include "MCTargetDesc/TLCS900MCTargetDesc.h"
#include "llvm/CodeGen/SelectionDAG.h"

using namespace llvm;

SDValue TLCS900SelectionDAGInfo::EmitTargetCodeForMemcpy(
    SelectionDAG &DAG, const SDLoc &dl, SDValue Chain, SDValue Dst,
    SDValue Src, SDValue Size, Align Alignment, bool isVolatile,
    bool AlwaysInline, MachinePointerInfo DstPtrInfo,
    MachinePointerInfo SrcPtrInfo) const {
  // Don't handle volatile copies — fall back to libcall.
  if (isVolatile)
    return SDValue();

  // Use LDIR: set up XDE = dst, XHL = src, XBC = byte count, then repeat.
  // LDIR copies one byte per iteration (alignment doesn't matter).
  SDValue InGlue;
  Chain = DAG.getCopyToReg(Chain, dl, TLCS900::XDE, Dst, InGlue);
  InGlue = Chain.getValue(1);
  Chain = DAG.getCopyToReg(Chain, dl, TLCS900::XHL, Src, InGlue);
  InGlue = Chain.getValue(1);
  Chain = DAG.getCopyToReg(Chain, dl, TLCS900::XBC, Size, InGlue);
  InGlue = Chain.getValue(1);

  SDVTList Tys = DAG.getVTList(MVT::Other, MVT::Glue);
  return DAG.getNode(TLCS900ISD::LDIR, dl, Tys, Chain, InGlue);
}

SDValue TLCS900SelectionDAGInfo::EmitTargetCodeForMemmove(
    SelectionDAG &DAG, const SDLoc &dl, SDValue Chain, SDValue Dst,
    SDValue Src, SDValue Size, Align Alignment, bool isVolatile,
    MachinePointerInfo DstPtrInfo, MachinePointerInfo SrcPtrInfo) const {
  // Don't handle volatile moves — fall back to libcall.
  if (isVolatile)
    return SDValue();

  // Use MEMMOVE_PSEUDO: runtime direction check + LDIR or LDDR.
  // Set up XDE = dst, XHL = src, XBC = byte count via CopyToReg + glue.
  SDValue InGlue;
  Chain = DAG.getCopyToReg(Chain, dl, TLCS900::XDE, Dst, InGlue);
  InGlue = Chain.getValue(1);
  Chain = DAG.getCopyToReg(Chain, dl, TLCS900::XHL, Src, InGlue);
  InGlue = Chain.getValue(1);
  Chain = DAG.getCopyToReg(Chain, dl, TLCS900::XBC, Size, InGlue);
  InGlue = Chain.getValue(1);

  SDVTList Tys = DAG.getVTList(MVT::Other, MVT::Glue);
  return DAG.getNode(TLCS900ISD::MEMMOVE, dl, Tys, Chain, InGlue);
}
