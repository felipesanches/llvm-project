add_llvm_component_library(LLVMTLCS900Desc
  TLCS900MCAsmInfo.cpp
  TLCS900MCTargetDesc.cpp
  TLCS900InstPrinter.cpp

  LINK_COMPONENTS
  MC
  TLCS900Info
  Support
  TargetParser

  ADD_TO_COMPONENT
  TLCS900
)

add_dependencies(LLVMTLCS900Desc TLCS900CommonTableGen)
