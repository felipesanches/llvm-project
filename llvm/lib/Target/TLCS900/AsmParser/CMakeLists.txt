add_llvm_component_library(LLVMTLCS900AsmParser
  TLCS900AsmParser.cpp

  LINK_COMPONENTS
  TLCS900Desc
  TLCS900Info
  CodeGenTypes
  MC
  MCParser
  Support

  ADD_TO_COMPONENT
  TLCS900
  )
