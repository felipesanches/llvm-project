include_directories( ${CMAKE_CURRENT_BINARY_DIR}/..\
                     ${CMAKE_CURRENT_SOURCE_DIR}/.. )

add_llvm_component_library(LLVMTLCS900Info
  TLCS900TargetInfo.cpp

  LINK_COMPONENTS
  MC
  Support

  ADD_TO_COMPONENT
  TLCS900
)

add_dependencies(LLVMTLCS900Info TLCS900CommonTableGen)
