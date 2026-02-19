//=== TLCS900CallingConv.td - Calling Conventions for TLCS900 --*- tablegen -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
// This describes the calling conventions for TLCS900 architecture.
//===----------------------------------------------------------------------===//

def TLCS900_CCallingConv : CallingConv<[
  // Handles byval parameters. Tell LLVM what the size and alignment
  // requirements of each stack slot are
  CCIfByVal<CCPassByVal<4, 4>>,

  // Promote i8/i16 to i32
  CCIfType<[i1, i8, i16], CCPromoteToType<i32>>,

  // The first 4 arguments are passed in these regs:
  CCIfType<[i32], CCAssignToReg<[XDE, XBC, XIX, XIY]>>,

  // Integer values get stored in stack slots that are 4 bytes in size and
  // 4-byte aligned
  CCIfType<[i32], CCAssignToStack<4, 4>>
]>;

// TLCS900 Vararg Calling Convention — all args on stack (no register passing)
def TLCS900_VarargCC : CallingConv<[
  CCIfByVal<CCPassByVal<4, 4>>,

  // Promote i8/i16 to i32
  CCIfType<[i1, i8, i16], CCPromoteToType<i32>>,

  // All arguments go on the stack
  CCIfType<[i32], CCAssignToStack<4, 4>>
]>;

// TLCS900 C Return Convention
def TLCS900_CRetConv : CallingConv<[
  CCIfType<[i1, i8, i16], CCPromoteToType<i32>>,

  // i32 are returned in registers
  CCIfType<[i32], CCAssignToReg<[XDE, XBC, XIX, XIY]>>,

  // Integer values get stored in stack slots that are 4 bytes in size and
  // 4-byte aligned
  CCIfType<[i32], CCAssignToStack<4, 4>>
]>;

def TLCS900_CalleeSavedRegs : CalleeSavedRegs<(add XIX, XIY, XIZ)>;
