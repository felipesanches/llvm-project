# TLCS-900/H Instruction Encoding Reference

## Encoding Scheme
Variable-length 1-7 byte instructions. Two categories:
1. **Single-byte basic instructions** (opcodes 0x00-0xDF)
2. **Extended instructions** with prefix (opcodes 0xE0-0xFE are prefixes)

## Prefix Bytes (First Byte)
The prefix byte specifies one operand (or addressing mode):

### Register Prefixes
- `0xC8-0xCF`: 8-bit register (C8=W, C9=A, CA=B, CB=C, CC=D, CD=E, CE=H, CF=L)
- `0xD8-0xDF`: 16-bit register (D8=WA, D9=BC, DA=DE, DB=HL, DC=IX, DD=IY, DE=IZ, DF=SP)
- `0xE8-0xEF`: 32-bit register (E8=XWA, E9=XBC, EA=XDE, EB=XHL, EC=XIX, ED=XIY, EE=XIZ, EF=XSP)

### Memory Addressing Prefixes
- `0x80-0x87`: (Xrr) 8-bit mem via 32-bit register
- `0x88-0x8F`: (Xrr+d8) 8-bit mem with 8-bit displacement
- `0x90-0x97`: (Xrr) 16-bit mem
- `0x98-0x9F`: (Xrr+d8) 16-bit mem with 8-bit displacement
- `0xA0-0xA7`: (Xrr) 32-bit mem
- `0xA8-0xAF`: (Xrr+d8) 32-bit mem with 8-bit displacement
- `0xB0-0xB7`: (Xrr) destination mem
- `0xB8-0xBF`: (Xrr+d8) destination mem with displacement
- `0xF0`: (n) 8-bit address
- `0xF1`: (nn) 16-bit address
- `0xF2`: (nnn) 24-bit address
- `0xF3`: complex addressing (reg+d16, reg+reg)

### Register encoding within prefix (bits 0-2):
0=XWA/WA/W, 1=XBC/BC/A, 2=XDE/DE/B, 3=XHL/HL/C, 4=XIX/IX/D, 5=XIY/IY/E, 6=XIZ/IZ/H, 7=XSP/SP/L

## Second Byte (Operation Code) — for register prefix (0xC8-0xEF)
- `0x03`: LD R, #imm
- `0x04`: PUSH R
- `0x05`: POP R
- `0x06`: CPL R
- `0x07`: NEG R
- `0x08`: MUL R, #imm
- `0x09`: MULS R, #imm
- `0x0A`: DIV R, #imm
- `0x0B`: DIVS R, #imm
- `0x12`: EXTZ R (32-bit only)
- `0x13`: EXTS R (32-bit only, via pattern)
- `0x1C`: DJNZ R, d8
- `0x30-0x37`: RES #bit, R / SET #bit, R / CHG #bit, R / BIT #bit, R / TSET #bit, R
- `0x40-0x5F`: MUL/MULS/DIV/DIVS with MC16 operand
- `0x60-0x67`: INC #n, R (n = bits 0-2)
- `0x68-0x6F`: DEC #n, R
- `0x80-0x87`: ADD C, R
- `0x88-0x8F`: LD C, R
- `0x90-0x97`: ADC C, R
- `0x98-0x9F`: LD R, C
- `0xA0-0xA7`: SUB C, R
- `0xA8-0xAF`: LD R, #n (small immediate)
- `0xB0-0xB7`: SBC C, R
- `0xC0-0xC7`: AND C, R
- `0xC8`: ADD R, #imm
- `0xC9`: ADC R, #imm
- `0xCA`: SUB R, #imm
- `0xCB`: SBC R, #imm
- `0xCC`: AND R, #imm
- `0xCD`: XOR R, #imm
- `0xCE`: OR R, #imm
- `0xCF`: CP R, #imm
- `0xD0-0xD7`: XOR C, R
- `0xE0-0xE7`: OR C, R
- `0xE8`: RLC #n, R
- `0xE9`: RRC #n, R
- `0xEA`: RL #n, R
- `0xEB`: RR #n, R
- `0xEC`: SLA #n, R
- `0xED`: SRA #n, R
- `0xEE`: SLL #n, R
- `0xEF`: SRL #n, R
- `0xF0-0xF7`: CP C, R
- `0xF8`: RLC A, R
- `0xF9`: RRC A, R
- `0xFA`: RL A, R
- `0xFB`: RR A, R
- `0xFC`: SLA A, R
- `0xFD`: SRA A, R
- `0xFE`: SLL A, R
- `0xFF`: SRL A, R

## Single-Byte Instructions (no prefix)
- `0x00`: NOP
- `0x01`: NORMAL (select normal mode)
- `0x02`: PUSH SR
- `0x03`: POP SR
- `0x06`: HALT
- `0x07`: DI
- `0x0A`: PUSH F
- `0x0B`: PUSH #word_imm
- `0x0E`: RET
- `0x0F`: RETD #imm16
- `0x10`: RCF
- `0x11`: SCF
- `0x12`: CCF
- `0x13`: ZCF
- `0x14`: PUSH A
- `0x15`: POP A
- `0x16`: EX F, F'
- `0x17`: LDF #imm8
- `0x18`: PUSH F
- `0x19`: POP F
- `0x1A`: JP #nn (16-bit absolute)
- `0x1B`: JP #nnn (24-bit absolute)
- `0x1C`: CALL #nn (16-bit absolute)
- `0x1D`: CALL #nnn (24-bit absolute)
- `0x1E`: CALR d16
- `0x20-0x27`: LD r8, #imm8 (direct 8-bit register load)
- `0x28-0x2F`: PUSH r8
- `0x30-0x37`: LD r16, #imm16
- `0x38-0x3F`: PUSH r16
- `0x40-0x47`: LD r32, #imm32
- `0x48-0x4F`: PUSH r32
- `0x58-0x5F`: POP r32
- `0x60-0x6F`: JR cc, d8
- `0x70-0x7F`: JRL cc, d16
- `0xF8-0xFF`: SWI #n (software interrupt, n = bits 0-2)

## Condition Codes (for JP cc, JR cc, etc.)
Encoded in bits 0-3 of the opcode byte:
- 0: F (false/never)
- 1: LT (less than, signed)
- 2: LE (less or equal, signed)
- 3: ULE (unsigned less or equal)
- 4: OV (overflow)
- 5: MI (minus/negative)
- 6: Z/EQ (zero/equal)
- 7: ULT/C (unsigned less than / carry)
- 8: T (true/always)
- 9: GE (greater or equal, signed)
- 10: GT (greater than, signed)
- 11: UGT (unsigned greater than)
- 12: NOV (no overflow)
- 13: PL (plus/positive)
- 14: NZ/NE (not zero/not equal)
- 15: UGE/NC (unsigned greater or equal / no carry)

## Reference Files
- MAME disassembler: `/tmp/dasm900.cpp`, `/tmp/900tbl.hxx`, `/tmp/900htbl.hxx`
- Ghidra SLEIGH: `/tmp/ghidra_tlcs900h.sinc`, `/tmp/ghidra_src_mem.sinc`, `/tmp/ghidra_dst_mem.sinc`
- Local macros: `/home/fsanches/compartilhado/kn5000-roms-disasm/tmp94c241.inc`
- Local macros: `/home/fsanches/compartilhado/custom-kn5000-roms/anotherworld/src/includes/local_macros.inc`
