// +tbl-rmi required for RIPA*/RVA*
// +xs required for *NXS

// RUN: not llvm-mc -triple aarch64 -mattr=+d128,+tlb-rmi,+xs -show-encoding %s -o - 2>&1 | FileCheck %s --check-prefix=ERRORS
// RUN: llvm-mc -triple=aarch64 -filetype=obj -mattr=+d128 < %s \
// RUN:   | llvm-objdump -d --mattr=+d128 --no-print-imm-hex - \
// RUN:   | FileCheck %s --check-prefix=DISASM

// sysp #<op1>, <Cn>, <Cm>, #<op2>{, <Xt1>, <Xt2>}
// registers with 128-bit formats (op0, op1, Cn, Cm, op2)
// For sysp, op0 is 0

sysp #0, c8, c0, #0, x0, x2
// ERRORS: error: expected second odd register of a consecutive same-size even/odd register pair
sysp #0, c8, c0, #0, x0
// ERRORS: error: expected comma
sysp #0, c8, c0, #0, x1, x2
// ERRORS: error: expected first even register of a consecutive same-size even/odd register pair
sysp #0, c8, c0, #0, x31, x0
// ERRORS: error: xzr must be followed by xzr
sysp #0, c8, c0, #0, xzr, x30
// ERRORS: error: xzr must be followed by xzr
sysp #0, c8, c0, #0, xzr
// ERRORS: error: expected comma
sysp #0, c8, c0, #0, xzr,
// ERRORS: error: expected register operand

// Ensure invalid SYSP encodings are not printed as TLBIP aliases.

// op1 = 7 (outside architecturally valid SYSP range for op1)
// Cn = 8, Cm = 0, op2 = 0, Rt = 0 (x0, x1)
.inst 0xd54f8000

// Cn = 0 (outside architecturally valid SYSP range for Cn)
.inst 0xd5480000

// Cm = 8 (outside architecturally valid SYSP range for Cm)
.inst 0xd5488800

// DISASM-NOT: tlbip
// DISASM: <unknown>
// DISASM: <unknown>
// DISASM: <unknown>


tlbip RVAE3IS
// ERRORS: error: expected comma
tlbip RVAE3IS,
// ERRORS: error: expected register identifier
tlbip VAE3,
// ERRORS: error: expected register identifier
tlbip IPAS2E1, x4, x8
// ERRORS: error: specified tlbip op requires a pair of registers
tlbip RVAE3, x11, x11
// ERRORS: error: specified tlbip op requires a pair of registers
