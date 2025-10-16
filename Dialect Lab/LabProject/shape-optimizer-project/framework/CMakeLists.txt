# CMakeLists.txt for Shape Optimizer Project - 学生版本
# ML形状计算优化器的构建配置

cmake_minimum_required(VERSION 3.15)
project(ShapeOptimizer)

# 设置C++标准
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 查找MLIR和LLVM
find_package(MLIR REQUIRED CONFIG)
find_package(LLVM REQUIRED CONFIG)

# 添加MLIR和LLVM的包含目录
include_directories(${MLIR_INCLUDE_DIRS})
include_directories(${LLVM_INCLUDE_DIRS})

# 添加MLIR和LLVM的定义
add_definitions(${MLIR_DEFINITIONS})
add_definitions(${LLVM_DEFINITIONS})

# 设置MLIR的TableGen路径（如果需要）
set(MLIR_TABLEGEN_EXE mlir-tblgen)

# 创建可执行文件
# 注意：当你完成ShapeOptimizerPass.cpp的实现后，取消下一行的注释
add_executable(shape-opt
    main.cpp
    ShapeOptimizerPass.cpp  # 取消注释当你实现了这个文件
)

# 如果你还没有实现ShapeOptimizerPass.cpp，可以先注释掉上面的代码，使用下面的：
# add_executable(shape-opt
#     main.cpp
# )

# 链接必要的MLIR库
target_link_libraries(shape-opt PRIVATE
    # MLIR核心库
    MLIROptLib
    MLIRMlirOptMain
    
    # Pass基础设施
    MLIRPass
    MLIRTransforms
    MLIRTransformUtils
    
    # 我们使用的Dialects
    MLIRFuncDialect
    MLIRArithDialect
    MLIRTensorDialect
    MLIRSCFDialect
    MLIRLinalgDialect
    
    # IR和解析
    MLIRIR
    MLIRParser
    MLIRSupport
    
    # LLVM核心库
    LLVMCore
    LLVMSupport
    LLVMDemangle
)

# 如果是macOS，添加特殊的链接选项
if(APPLE)
    target_link_options(shape-opt PRIVATE -Wl,-undefined,dynamic_lookup)
endif()

# 编译选项
target_compile_options(shape-opt PRIVATE
    $<$<CXX_COMPILER_ID:GNU>:-Wall -Wextra>
    $<$<CXX_COMPILER_ID:Clang>:-Wall -Wextra>
    $<$<CXX_COMPILER_ID:MSVC>:/W4>
)

# 调试信息
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_definitions(shape-opt PRIVATE DEBUG=1)
endif()

# 安装目标（可选）
install(TARGETS shape-opt
    RUNTIME DESTINATION bin
)

# 打印配置信息
message(STATUS "MLIR Include Dirs: ${MLIR_INCLUDE_DIRS}")
message(STATUS "LLVM Include Dirs: ${LLVM_INCLUDE_DIRS}")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")

# 学生指导信息
message(STATUS "")
message(STATUS "========================================")
message(STATUS "Shape Optimizer Project - 学生版本")
message(STATUS "========================================")
message(STATUS "")
message(STATUS "构建项目:")
message(STATUS "  mkdir build && cd build")
message(STATUS "  cmake ..")
message(STATUS "  make")
message(STATUS "")
message(STATUS "运行测试:")
message(STATUS "  cd ../test-cases")
message(STATUS "  ./run-tests.sh")
message(STATUS "")
message(STATUS "开始实现:")
message(STATUS "  1. 编辑 ShapeOptimizerPass.h")
message(STATUS "  2. 实现 runOnOperation() 方法")
message(STATUS "  3. 运行测试验证实现")
message(STATUS "")
message(STATUS "注意: 确保 ShapeOptimizerPass.cpp 被包含在构建中")
message(STATUS "========================================")