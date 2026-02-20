add_llvm_component_group(TLCS900)

set(LLVM_TARGET_DEFINITIONS TLCS900.td)

tablegen(LLVM TLCS900GenRegisterInfo.inc -gen-register-info)
tablegen(LLVM TLCS900GenInstrInfo.inc -gen-instr-info)
tablegen(LLVM TLCS900GenAsmWriter.inc -gen-asm-writer)
tablegen(LLVM TLCS900GenAsmMatcher.inc -gen-asm-matcher)
tablegen(LLVM TLCS900GenDAGISel.inc -gen-dag-isel)
tablegen(LLVM TLCS900GenCallingConv.inc -gen-callingconv)
tablegen(LLVM TLCS900GenSubtargetInfo.inc -gen-subtarget)
tablegen(LLVM TLCS900GenMCPseudoLowering.inc -gen-pseudo-lowering)

add_public_tablegen_target(TLCS900CommonTableGen)

add_llvm_target(TLCS900CodeGen
  TLCS900AsmPrinter.cpp
  TLCS900BitManipOpt.cpp
  TLCS900BitTestOpt.cpp
  TLCS900BranchShortening.cpp
  TLCS900DJNZOpt.cpp
  TLCS900RedundantCmpElim.cpp
  TLCS900FrameLowering.cpp
  TLCS900InstrInfo.cpp
  TLCS900ISelLowering.cpp
  TLCS900SelectionDAGInfo.cpp
  TLCS900MachineFunction.cpp
  TLCS900RegisterInfo.cpp
  TLCS900Subtarget.cpp
  TLCS900TargetObjectFile.cpp
  TLCS900ISelDAGToDAG.cpp
  TLCS900TargetMachine.cpp

  DEPENDS
  intrinsics_gen

  LINK_COMPONENTS
  TLCS900Desc
  TLCS900Info
  AsmPrinter
  CodeGen
  CodeGenTypes
  Core
  MC
  SelectionDAG
  Support
  Target

  ADD_TO_COMPONENT
  TLCS900
  )

add_subdirectory(AsmParser)
add_subdirectory(Disassembler)
add_subdirectory(TargetInfo)
add_subdirectory(MCTargetDesc)
