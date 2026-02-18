//===-- TLCS900Schedule.td - TLCS900 Scheduling Definitions ----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// TLCS900 scheduling definitions. The TMP94C241 is a single-issue in-order
// processor, so scheduling is trivial. These definitions exist as placeholders
// for the scheduling infrastructure.
//
//===----------------------------------------------------------------------===//

/// Define scheduler resources associated with def operands.
def WriteIALU   : SchedWrite;    // Integer ALU operation
def WriteShift  : SchedWrite;    // Shift operation
def WriteIMul   : SchedWrite;    // Multiply
def WriteIDiv   : SchedWrite;    // Divide
def WriteJmp    : SchedWrite;    // Jump/Branch
def WriteLDW    : SchedWrite;    // Load word
def WriteSTW    : SchedWrite;    // Store word
def WritePush   : SchedWrite;    // Push to stack
def WritePop    : SchedWrite;    // Pop from stack
def WriteNop    : SchedWrite;    // NOP / system instructions

/// Define scheduler resources associated with use operands.
def ReadIALU    : SchedRead;
def ReadShift   : SchedRead;
def ReadIMul    : SchedRead;
def ReadIDiv    : SchedRead;
def ReadMemBase : SchedRead;
