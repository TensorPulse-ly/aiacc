# Lab 10: MLIR 优化 Pass 实验

## 实验目标

通过本实验，你将学会：
1. 使用 MLIR 的 `RewritePattern` 系统实现声明式优化
2. 创建自定义的优化 Pass 并集成到 MLIR 工具链中
3. 编译和运行自定义的 MLIR 优化工具
4. 验证代数恒等式优化的效果（`x + 0 = x`）

## 前置条件

- 已构建的 MLIR 开发环境
- 基础的 C++ 和 CMake 知识
- 理解 MLIR 的基本概念：Dialect、Operation、Pass

## 实验背景

在 MLIR 中，优化通常通过 Pattern Rewriting 系统实现。相比手动遍历 IR 节点，`RewritePattern` 提供了更声明式、更易维护的方法。本实验将实现一个简单但实用的优化：消除与零相加的冗余运算。

---

## 第一部分：环境搭建

### 步骤 1：创建项目结构

创建实验目录 `mlir-optimization-lab`，并建立以下文件结构：

```
mlir-optimization-lab/
├── CMakeLists.txt         # 构建配置
├── my-opt.cpp            # 主程序入口
├── MyPass.h              # Pass 声明
├── MyPass.cpp            # Pass 实现
├── MyPatterns.h          # Pattern 声明
├── MyPatterns.cpp        # Pattern 实现
└── test.mlir             # 测试用例
```

### 步骤 2：创建测试用例

在 `test.mlir` 中创建一个包含冗余加零操作的函数：

```mlir
module {
  func.func @test_add_zero(%arg0: i32) -> i32 {
    // TODO
  }
}
```

**思考题 1：** 观察这个 IR，你认为哪些操作是冗余的？优化后的结果应该是什么样的？

<details>
<summary>答案</summary>

冗余操作是 `arith.addi %arg0, %c0`，因为任何数加零等于它本身。优化后应该直接返回 `%arg0`，常量 `%c0` 也会变成死代码被后续清理。

</details>

---

## 第二部分：实现 RewritePattern

### 步骤 3：设计 Pattern 头文件

在 `MyPatterns.h` 中，你需要：

1. 包含必要的 MLIR 头文件
2. 声明一个继承自 `OpRewritePattern<arith::AddIOp>` 的结构体
3. 重写 `matchAndRewrite` 方法

**编程任务 1：** 完成 `MyPatterns.h` 的框架代码。

<details>
<summary>参考框架</summary>

```cpp
#ifndef MY_PATTERNS_H
#define MY_PATTERNS_H

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

struct RemoveAddZeroPattern : public mlir::OpRewritePattern<mlir::arith::AddIOp> {
  using OpRewritePattern<mlir::arith::AddIOp>::OpRewritePattern;

  mlir::LogicalResult matchAndRewrite(mlir::arith::AddIOp op,
                                mlir::PatternRewriter &rewriter) const override;
};

#endif
```

</details>

### 步骤 4：实现 Pattern 逻辑

在 `MyPatterns.cpp` 中实现优化逻辑。你需要：

1. 获取加法操作的两个操作数
2. 检查是否有操作数为零常量
3. 如果找到零常量，用非零操作数替换整个加法操作

**编程任务 2：** 实现 `matchAndRewrite` 方法。

**提示：**
- 使用 `op.getLhs()` 和 `op.getRhs()` 获取操作数
- 使用 `getDefiningOp<arith::ConstantOp>()` 检查是否为常量
- 使用 `rewriter.replaceOp(op, replacement)` 进行替换
- 返回 `success()` 或 `failure()` 表示匹配结果

<details>
<summary>实现参考</summary>

```cpp
mlir::LogicalResult RemoveAddZeroPattern::matchAndRewrite(
    mlir::arith::AddIOp op, mlir::PatternRewriter &rewriter) const {
  
  mlir::Value lhs = op.getLhs();
  mlir::Value rhs = op.getRhs();

  // 检查是否为零常量的辅助函数
  auto isZeroConst = [](mlir::Value val) -> bool {
    if (auto cst = val.getDefiningOp<mlir::arith::ConstantOp>()) {
      if (auto attr = mlir::dyn_cast<mlir::IntegerAttr>(cst.getValue()))
        return attr.getValue().isZero();
    }
    return false;
  };

  // 如果右操作数是 0，替换为左操作数
  if (isZeroConst(rhs)) {
    rewriter.replaceOp(op, lhs);
    return mlir::success();
  }

  // 如果左操作数是 0，替换为右操作数  
  if (isZeroConst(lhs)) {
    rewriter.replaceOp(op, rhs);
    return mlir::success();
  }

  return mlir::failure();
}
```

</details>

**思考题 2：** 为什么需要检查左右两个操作数？加法的交换律在这里如何体现？

<details>
<summary>答案</summary>

因为加法满足交换律，`0 + x` 和 `x + 0` 都等于 `x`。我们需要检查两种情况，确保无论零常量在哪个位置都能被优化。

</details>

---

## 第三部分：创建优化 Pass

### 步骤 5：定义 Pass 接口

在 `MyPass.h` 中声明 Pass 的创建和注册函数：

```cpp
#ifndef MY_PASS_H
#define MY_PASS_H

#include <memory>

namespace mlir {
class Pass;

std::unique_ptr<Pass> createRemoveMyAddZeroPass();
void registerRemoveMyAddZeroPass();
}

#endif
```

### 步骤 6：实现 Pass 类

在 `MyPass.cpp` 中，你需要：

1. 创建一个继承自 `PassWrapper` 的 Pass 类
2. 在 `runOnOperation` 中收集 Pattern 并应用
3. 实现 Pass 的注册逻辑

**编程任务 3：** 完成 Pass 的实现。

**关键点：**
- 继承 `PassWrapper<YourPass, OperationPass<func::FuncOp>>`
- 创建 `RewritePatternSet` 并添加你的 Pattern
- 使用 `applyPatternsGreedily` 应用优化

<details>
<summary>实现框架</summary>

```cpp
namespace {
struct RemoveMyAddZeroPass
    : public PassWrapper<RemoveMyAddZeroPass, OperationPass<func::FuncOp>> {

  StringRef getArgument() const final { return "remove-my-add-zero"; }
  StringRef getDescription() const final { return "Remove redundant add-zero operations"; }

  void runOnOperation() override {
    func::FuncOp func = getOperation();
    MLIRContext *ctx = &getContext();

    // 创建 Pattern 集合
    RewritePatternSet patterns(ctx);
    patterns.add<RemoveAddZeroPattern>(ctx);

    // 应用 Pattern
    if (failed(applyPatternsGreedily(func, std::move(patterns))))
      signalPassFailure();
  }
};
}
```

</details>

**思考题 3：** 为什么选择 `OperationPass<func::FuncOp>` 而不是 `ModulePass`？

<details>
<summary>答案</summary>

因为我们的优化在函数级别进行，`OperationPass<func::FuncOp>` 可以并行处理不同函数，提高性能。`ModulePass` 适用于需要跨函数分析的优化。

</details>

---

## 第四部分：构建主程序

### 步骤 7：实现工具入口

在 `my-opt.cpp` 中创建类似 `mlir-opt` 的工具：

**编程任务 4：** 实现主函数，注册必要的方言和你的 Pass。

**要点：**
- 注册 `arith` 和 `func` 方言
- 调用你的 Pass 注册函数
- 使用 `MlirOptMain` 作为主循环

<details>
<summary>完整实现</summary>

```cpp
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "MyPass.h"

int main(int argc, char **argv) {
    mlir::DialectRegistry registry;
    registry.insert<mlir::arith::ArithDialect, mlir::func::FuncDialect>();

    mlir::registerRemoveMyAddZeroPass();

    return mlir::asMainReturnCode(
        mlir::MlirOptMain(argc, argv, "My Optimization Tool\n", registry));
}
```

</details>

---

## 第五部分：编译和测试

### 步骤 8：配置构建系统

创建 `CMakeLists.txt` 来链接必要的 MLIR 库：

**编程任务 5：** 完成 CMake 配置，确保链接所有必需的库。

**关键库：**
- `MLIROptLib`, `MLIRMlirOptMain` (工具框架)
- `MLIRPass`, `MLIRTransforms` (Pass 系统)
- `MLIRArithDialect`, `MLIRFuncDialect` (方言)

### 步骤 9：编译和运行

```bash
mkdir build && cd build
cmake -DMLIR_DIR=/path/to/llvm-build/lib/cmake/mlir ..
make
```

运行优化：
```bash
./my-opt ../test.mlir --remove-my-add-zero
```

**验证任务：** 比较优化前后的 IR，确认加零操作被消除。

**思考题 4：** 如果看到常量 `%c0` 仍然存在，这正常吗？如何完全清理？

<details>
<summary>答案</summary>

这是正常的。我们的 Pass 只负责消除加零操作，未使用的常量会在后续的死代码消除（DCE）Pass 中被清理。可以添加 `--canonicalize` 或 `--symbol-dce` 来完全清理。

</details>

---

## 第六部分：扩展挑战

### 挑战任务：实现乘一优化

实现另一个代数恒等式：`x * 1 = x`

1. 在 `MyPatterns.h` 中添加 `RemoveMulOnePattern`
2. 创建处理 `arith.muli` 的逻辑
3. 在 Pass 中注册新 Pattern
4. 创建测试用例验证效果

**提示：** 复用加零优化的结构，改变匹配的操作类型和常量值。

---

## 实验总结

通过本实验，你学会了：
- MLIR Pattern Rewriting 的核心概念
- 如何实现声明式的优化逻辑
- Pass 系统的基本使用方法
- MLIR 工具链的构建和集成

**反思问题：**
1. Pattern 方法相比手动 IR 遍历有什么优势？
2. 如何扩展这个框架来处理更复杂的优化？
3. 在实际项目中，如何组织和管理多个 Pattern？

---

## Reference Code

### 完整项目结构
```
mlir-optimization-lab/
├── CMakeLists.txt
├── my-opt.cpp
├── MyPass.h
├── MyPass.cpp
├── MyPatterns.h
├── MyPatterns.cpp
└── test.mlir
```

### CMakeLists.txt
```cmake
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

target_link_libraries(my-opt PRIVATE
  MLIROptLib
  MLIRMlirOptMain
  MLIRTransformUtils
  MLIRPass
  MLIRRewrite
  MLIRTransforms
  MLIRFuncDialect  
  MLIRArithDialect
  MLIRIR
  MLIRDialect
  MLIRSupport
  MLIRAnalysis
  MLIRParser
  LLVMCore
  LLVMSupport
  LLVMDemangle
)

if(APPLE)
  target_link_options(my-opt PRIVATE -Wl,-undefined,dynamic_lookup)
endif()
```

### my-opt.cpp
```cpp
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "MyPass.h"

int main(int argc, char **argv) {
    mlir::DialectRegistry registry;
    registry.insert<mlir::arith::ArithDialect, 
                    mlir::func::FuncDialect>();

    mlir::registerRemoveMyAddZeroPass();

    return mlir::asMainReturnCode(
        mlir::MlirOptMain(argc, argv, "My Pass Tool\n", registry));
}
```

### MyPass.h
```cpp
#ifndef MY_PASS_H
#define MY_PASS_H

#include <memory>

namespace mlir {
class Pass;

std::unique_ptr<Pass> createRemoveMyAddZeroPass();
void registerRemoveMyAddZeroPass();
}

#endif
```

### MyPass.cpp
```cpp
#include "MyPass.h"
#include "MyPatterns.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace {
struct RemoveMyAddZeroPass
    : public PassWrapper<RemoveMyAddZeroPass, OperationPass<func::FuncOp>> {

    virtual ~RemoveMyAddZeroPass() = default;

    StringRef getArgument() const final { return "remove-my-add-zero"; }
    StringRef getDescription() const final { return "Fold arith.addi with zero"; }

    void runOnOperation() override {
        func::FuncOp func = getOperation();
        MLIRContext *ctx = &getContext();

        RewritePatternSet patterns(ctx);
        patterns.add<RemoveAddZeroPattern>(ctx);

        if (failed(applyPatternsGreedily(func, std::move(patterns))))
            signalPassFailure();
    }
};
}

std::unique_ptr<Pass> mlir::createRemoveMyAddZeroPass() {
    return std::make_unique<RemoveMyAddZeroPass>();
}

void mlir::registerRemoveMyAddZeroPass() {
    PassRegistration<RemoveMyAddZeroPass>();
}
```

### MyPatterns.h
```cpp
#ifndef MY_PATTERNS_H
#define MY_PATTERNS_H

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/PatternMatch.h"

struct RemoveAddZeroPattern : public mlir::OpRewritePattern<mlir::arith::AddIOp> {
  using OpRewritePattern<mlir::arith::AddIOp>::OpRewritePattern;

  mlir::LogicalResult matchAndRewrite(mlir::arith::AddIOp op,
                                mlir::PatternRewriter &rewriter) const override {
    mlir::Value lhs = op.getLhs();
    mlir::Value rhs = op.getRhs();

    auto isZeroConst = [](mlir::Value val) -> bool {
      if (auto cst = val.getDefiningOp<mlir::arith::ConstantOp>()) {
        if (auto attr = mlir::dyn_cast<mlir::IntegerAttr>(cst.getValue()))
          return attr.getValue().isZero();
      }
      return false;
    };

    if (isZeroConst(rhs)) {
      rewriter.replaceOp(op, lhs);
      return mlir::success();
    }

    if (isZeroConst(lhs)) {
      rewriter.replaceOp(op, rhs);
      return mlir::success();
    }

    return mlir::failure();
  }
};

#endif
```

### MyPatterns.cpp
```cpp
#include "MyPatterns.h"
```

### test.mlir
```mlir
module {
  func.func @test_add_zero(%arg0: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %sum = arith.addi %arg0, %c0 : i32
    return %sum : i32
  }
}
```

### 编译和运行流程
```bash
# 1. 创建构建目录
mkdir build && cd build

# 2. 配置 CMake（替换实际的 MLIR 路径）
cmake -DMLIR_DIR=/path/to/llvm-build/lib/cmake/mlir ..

# 3. 编译
make

# 4. 运行优化（从 build 目录）
./my-opt ../test.mlir --remove-my-add-zero

# 5. 期望输出：加零操作被消除
# module {
#   func.func @test_add_zero(%arg0: i32) -> i32 {
#     %c0 = arith.constant 0 : i32
#     return %arg0 : i32
#   }
# }
```