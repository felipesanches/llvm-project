//===-- TLCS900Schedule.td - TLCS900 Scheduling Definitions ----*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Instruction scheduling model for the TMP94C241F (TLCS-900/H2).
//
// The TMP94C241F is a single-issue, in-order processor running at 16 MHz with
// no pipeline bypassing. Cycle counts are from the Toshiba TLCS-900/H
// datasheet.
//
// Key timing characteristics:
//   - Register-register ALU: 1-2 cycles
//   - Memory load (register indirect): 2-4 cycles (operand size dependent)
//   - Memory load with displacement: 3-5 cycles
//   - Multiply 16x16->32: 14 cycles
//   - Divide 32/16->16: 18 cycles
//   - Branch taken: 4 cycles, not taken: 2 cycles
//   - CALL: 6 cycles
//   - RET: 6 cycles
//   - PUSH/POP: 3-4 cycles
//   - Shift/rotate: 2 cycles per bit + 2 base cycles
//
//===----------------------------------------------------------------------===//

//===----------------------------------------------------------------------===//
// Processor resources
//===----------------------------------------------------------------------===//

// Single execution unit — no parallel execution on this CPU.
def ALU : ProcResource<1> { let BufferSize = 0; }
// Load/store unit shares the single execution pipeline.
def LSU : ProcResource<1> { let BufferSize = 0; }

//===----------------------------------------------------------------------===//
// SchedWrite definitions — one per instruction timing class
//===----------------------------------------------------------------------===//

// Integer ALU (register-register): ADD, SUB, AND, OR, XOR, CP, ADC, SBC,
// CPL, NEG, EXTS, EXTZ, DAA, INC, DEC, SCC, BIT, SET, RES, CHG, TSET, BS1B
def WriteIALU    : SchedWrite;

// Integer ALU with immediate operand (slightly longer due to imm fetch)
def WriteIALUImm : SchedWrite;

// Memory load (register indirect): LD reg, (mem)
def WriteLDW     : SchedWrite;

// Memory load with displacement: LD reg, (R+d8/d16)
def WriteLDDisp  : SchedWrite;

// Memory store (register indirect): LD (mem), reg
def WriteSTW     : SchedWrite;

// Memory store with immediate: LD (mem), imm
def WriteSTImm   : SchedWrite;

// Memory ALU (read-modify-write): ADD/SUB/AND/OR/XOR/CP (mem), reg/imm
def WriteMemALU  : SchedWrite;

// Shift/rotate by immediate (2 + 2*N cycles, using N=1 average)
def WriteShift   : SchedWrite;

// Shift/rotate by register (variable, using average estimate)
def WriteShiftVar : SchedWrite;

// Multiply 16x16->32: 14 cycles
def WriteIMul    : SchedWrite;

// Divide 32/16->16: 18 cycles
def WriteIDiv    : SchedWrite;

// Unconditional branch/jump: 4 cycles
def WriteJmp     : SchedWrite;

// Conditional branch (average of taken=4, not-taken=2): 3 cycles
def WriteJmpCond : SchedWrite;

// CALL (direct or indirect): 6 cycles
def WriteCall    : SchedWrite;

// RET/RETI/RETD: 6 cycles
def WriteRet     : SchedWrite;

// PUSH (register): 3-4 cycles
def WritePush    : SchedWrite;

// POP (register): 3-4 cycles
def WritePop     : SchedWrite;

// DJNZ (decrement-and-jump-if-not-zero): ~6 cycles
def WriteDJNZ    : SchedWrite;

// Block transfer (LDIR/LDDR): variable, 4 cycles per iteration
def WriteBlkXfer : SchedWrite;

// Block search (CPIR/CPDR): variable, 4 cycles per iteration
def WriteBlkSearch : SchedWrite;

// NOP, HALT, system instructions (EI, LDF, SWI, etc.)
def WriteNop     : SchedWrite;

// EX (register exchange): 2 cycles
def WriteExchange : SchedWrite;

// LDA (load effective address): 2 cycles
def WriteLDA     : SchedWrite;

// LINK/UNLK (frame setup/teardown): 6 cycles
def WriteLinkUnlk : SchedWrite;

// Condition flag manipulation (SCF, CCF, ZCF, RCF, ANDCF, ORCF, XORCF, LDCF, STCF)
def WriteFlagOp  : SchedWrite;

// LDC (load/store control register): 2 cycles
def WriteLDC     : SchedWrite;

// Direct addressing load/store (16-bit or 24-bit absolute address)
def WriteDirect  : SchedWrite;

// Memory-to-memory operations (LDMM): 5+ cycles
def WriteMemToMem : SchedWrite;

//===----------------------------------------------------------------------===//
// SchedRead definitions
//===----------------------------------------------------------------------===//

def ReadIALU    : SchedRead;
def ReadShift   : SchedRead;
def ReadIMul    : SchedRead;
def ReadIDiv    : SchedRead;
def ReadMemBase : SchedRead;

//===----------------------------------------------------------------------===//
// TMP94C241 scheduling model
//===----------------------------------------------------------------------===//

def TMP94C241Model : SchedMachineModel {
  let IssueWidth = 1;           // Single-issue in-order
  let MicroOpBufferSize = 0;    // No micro-op buffer (in-order)
  let LoopMicroOpBufferSize = 0; // No loop buffer
  let LoadLatency = 3;          // Default load latency (register indirect)
  let HighLatency = 14;         // Multiply is highest common latency
  let MispredictPenalty = 4;    // Branch misprediction = taken branch cost
  let PostRAScheduler = 1;      // Enable post-RA scheduling
  let CompleteModel = 0;        // Allow default for unrecognized opcodes
}

//===----------------------------------------------------------------------===//
// Write resource definitions with latencies
//===----------------------------------------------------------------------===//

let SchedModel = TMP94C241Model in {

// --- ALU operations ---
def : WriteRes<WriteIALU, [ALU]>     { let Latency = 1; }
def : WriteRes<WriteIALUImm, [ALU]>  { let Latency = 2; }

// --- Memory operations ---
def : WriteRes<WriteLDW, [LSU]>      { let Latency = 3; }
def : WriteRes<WriteLDDisp, [LSU]>   { let Latency = 4; }
def : WriteRes<WriteSTW, [LSU]>      { let Latency = 3; }
def : WriteRes<WriteSTImm, [LSU]>    { let Latency = 4; }
def : WriteRes<WriteMemALU, [LSU]>   { let Latency = 5; }

// --- Shifts/rotates ---
// Base 2 cycles + 2 per bit; using 4 as typical (1-bit shift)
def : WriteRes<WriteShift, [ALU]>    { let Latency = 4; }
def : WriteRes<WriteShiftVar, [ALU]> { let Latency = 8; }

// --- Multiply/divide ---
def : WriteRes<WriteIMul, [ALU]>     { let Latency = 14;
                                       let ReleaseAtCycles = [14]; }
def : WriteRes<WriteIDiv, [ALU]>     { let Latency = 18;
                                       let ReleaseAtCycles = [18]; }

// --- Control flow ---
def : WriteRes<WriteJmp, [ALU]>      { let Latency = 4; }
def : WriteRes<WriteJmpCond, [ALU]>  { let Latency = 3; }
def : WriteRes<WriteCall, [ALU]>     { let Latency = 6; }
def : WriteRes<WriteRet, [ALU]>      { let Latency = 6; }
def : WriteRes<WriteDJNZ, [ALU]>     { let Latency = 6; }

// --- Stack operations ---
def : WriteRes<WritePush, [LSU]>     { let Latency = 4; }
def : WriteRes<WritePop, [LSU]>      { let Latency = 4; }

// --- Block operations ---
// Per-iteration cost; actual cost is N * this. Use high latency as estimate.
def : WriteRes<WriteBlkXfer, [LSU]>  { let Latency = 10;
                                       let ReleaseAtCycles = [10]; }
def : WriteRes<WriteBlkSearch, [LSU]> { let Latency = 10;
                                        let ReleaseAtCycles = [10]; }

// --- Miscellaneous ---
def : WriteRes<WriteNop, [ALU]>      { let Latency = 1; }
def : WriteRes<WriteExchange, [ALU]> { let Latency = 2; }
def : WriteRes<WriteLDA, [ALU]>      { let Latency = 2; }
def : WriteRes<WriteLinkUnlk, [LSU]> { let Latency = 6; }
def : WriteRes<WriteFlagOp, [ALU]>   { let Latency = 1; }
def : WriteRes<WriteLDC, [ALU]>      { let Latency = 2; }
def : WriteRes<WriteDirect, [LSU]>   { let Latency = 4; }
def : WriteRes<WriteMemToMem, [LSU]> { let Latency = 6; }

// --- Read latencies (all operands available immediately) ---
def : ReadAdvance<ReadIALU, 0>;
def : ReadAdvance<ReadShift, 0>;
def : ReadAdvance<ReadIMul, 0>;
def : ReadAdvance<ReadIDiv, 0>;
def : ReadAdvance<ReadMemBase, 0>;

} // SchedModel = TMP94C241Model

// NOTE: Instruction-to-scheduling-class mappings (InstRW) are in
// TLCS900SchedInstRW.td, which is included after TLCS900InstrInfo.td
// so that instruction definitions are visible.
