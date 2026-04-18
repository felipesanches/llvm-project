include "llvm/Target/Target.td"

def TLCS900InstrInfo : InstrInfo;

def TLCS900 : Target {
  let InstructionSet = TLCS900InstrInfo;
}
