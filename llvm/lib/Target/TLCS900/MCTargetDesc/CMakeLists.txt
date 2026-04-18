include_directories( ${CMAKE_CURRENT_BINARY_DIR}/..
                     ${CMAKE_CURRENT_SOURCE_DIR}/.. )

add_llvm_component_library(LLVMTLCS900Desc
  TLCS900MCTargetDesc.cpp

  LINK_COMPONENTS
  MC
  Support
  TLCS900Info

  ADD_TO_COMPONENT
  TLCS900
)
