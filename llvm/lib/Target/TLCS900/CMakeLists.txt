add_llvm_component_group(TLCS900)

add_llvm_target(TLCS900CodeGen
  TLCS900InitStub.cpp
  TLCS900TargetObjectFile.cpp

  DEPENDS
  intrinsics_gen

  LINK_COMPONENTS
  CodeGen
  Core
  MC
  Support
  Target

  ADD_TO_COMPONENT
  TLCS900
  )

add_subdirectory(TargetInfo)
add_subdirectory(MCTargetDesc)
