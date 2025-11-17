cmake_minimum_required(VERSION 3.15)
project(MyOpt)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(MLIR REQUIRED CONFIG)

add_executable(my-opt
  my-opt.cpp
  MyPass.cpp
  MyPatterns.cpp
)

target_include_directories(my-opt PRIVATE
  ${MLIR_INCLUDE_DIRS}
  ${LLVM_INCLUDE_DIRS}
)

# 精确指定包含所需符号的库，按依赖顺序
target_link_libraries(my-opt PRIVATE
  # 核心库，包含基类定义
  MLIROptLib
  MLIRMlirOptMain
  
  # Pass 和 Pattern 相关
  MLIRTransformUtils
  MLIRPass
  MLIRRewrite
  MLIRTransforms
  
  # 方言
  MLIRFuncDialect  
  MLIRArithDialect
  
  # 核心 IR
  MLIRIR
  MLIRDialect
  MLIRSupport
  MLIRAnalysis
  MLIRParser
  
  # LLVM 核心
  LLVMCore
  LLVMSupport
  LLVMDemangle
)

# macOS 特殊处理
if(APPLE)
  target_link_options(my-opt PRIVATE -Wl,-undefined,dynamic_lookup)
endif()