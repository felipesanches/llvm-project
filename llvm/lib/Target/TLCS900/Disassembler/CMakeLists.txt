add_llvm_component_library(LLVMTLCS900Disassembler
  TLCS900Disassembler.cpp

  LINK_COMPONENTS
  MCDisassembler
  MC
  TLCS900Desc
  TLCS900Info
  Support

  ADD_TO_COMPONENT
  TLCS900
  )
