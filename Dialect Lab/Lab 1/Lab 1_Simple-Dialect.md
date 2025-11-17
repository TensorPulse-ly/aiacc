# Lab 1 Simple-Dialect: 基础上手 MLIR 自定义 Dialect

## 实验目标

通过本实验，你将学会：
- 理解 MLIR Dialect 的基本概念和架构
- 掌握创建自定义 Dialect 的完整流程
- 学会定义自定义操作（Operations）并理解其组成部分
- 了解 MLIR 的编译和测试流程
- 熟悉 MLIR 的基本工具链使用

## 前置条件

- 已安装 LLVM/MLIR 工具链（版本 15 或更高）
- 能够成功运行 `mlir-opt` 命令
- 基本的 C++ 编程知识
- 熟悉命令行操作

## 实验内容

### 第一步：验证基础环境

在开始编写自定义 Dialect 之前，我们需要确认 MLIR 环境是否正确安装和配置。

**任务说明：**
1. 创建一个简单的 MLIR 文件
2. 使用 `mlir-opt` 验证语法
3. 尝试转换为 LLVM IR

**操作步骤：**
```bash
# 创建一个测试用的 MLIR 文件
cat > hello.mlir << 'EOF'
module {
  func.func @main() -> i32 {
    %0 = arith.constant 42 : i32
    return %0 : i32
  }
}
EOF

# 验证语法是否正确
mlir-opt hello.mlir

# 尝试转换为 LLVM IR
mlir-opt --convert-func-to-llvm --convert-arith-to-llvm --reconcile-unrealized-casts hello.mlir | mlir-translate --mlir-to-llvmir
```

**期望结果：**
- 如果环境配置正确，你应该能看到 LLVM IR 输出
- 如果出现错误，请检查 LLVM/MLIR 的安装路径

### 第二步：理解我们要实现的目标

**任务说明：**
我们将创建一个名为 `simple` 的 Dialect，它包含一个简单的 `hello` 操作。

**目标效果：**
```mlir
module {
  simple.hello
}
```

**关键概念理解：**
- `simple` 是我们 Dialect 的名称空间
- `hello` 是我们定义的操作名
- 这个操作不接受任何输入，也不产生任何输出
- 它的唯一作用是在编译时被识别为有效的 MLIR 操作

### 第三步：创建项目结构

**任务说明：**
建立一个清晰的项目目录结构，为后续开发做准备。

**操作步骤：**
```bash
# 创建主工作目录
mkdir simple-dialect && cd simple-dialect

# 创建我们的目标测试文件
cat > simple.mlir << 'EOF'
module {
  simple.hello
}
EOF
```

### 第四步：理解 Dialect 的组成部分

**任务说明：**
在开始编码前，我们需要理解一个 MLIR Dialect 包含哪些核心组件。

**Dialect 的基本组成：**
1. **Dialect 类**：管理整个 Dialect 的注册和初始化
2. **Operation 类**：定义具体的操作行为
3. **解析器和打印器**：处理文本形式的 IR 读写
4. **验证器**：确保操作的语义正确性

**我们的设计决策：**
- Dialect 名称：`simple`
- 操作名称：`hello`
- 操作特性：零输入、零输出、无副作用

### 第五步：设计头文件结构

**任务说明：**
设计 `SimpleDialect.h` 头文件，定义我们的 Dialect 和 Operation 类。

**设计要点：**
1. 继承正确的 MLIR 基类
2. 正确定义操作的特征（Traits）
3. 声明必要的静态方法
4. 包含适当的头文件

**关键概念：**
- `mlir::Dialect`：所有 Dialect 的基类
- `mlir::Op`：所有操作的基类
- `OpTrait::ZeroOperands`：表示操作不接受输入
- `OpTrait::ZeroResults`：表示操作不产生输出

### 第六步：实现 Dialect 类

**任务说明：**
创建 `SimpleDialect.cpp` 实现文件，实现 Dialect 的具体功能。

**实现要点：**
1. 正确初始化 Dialect
2. 注册我们的操作
3. 设置正确的命名空间

**关键方法理解：**
- 构造函数：初始化 Dialect 并设置其属性
- `initialize()`：注册 Dialect 包含的所有操作
- `addOperations<>()`：将操作类添加到 Dialect 中

### 第七步：创建测试工具

**任务说明：**
创建一个简单的测试工具 `simple-opt.cpp`，用于加载和测试我们的 Dialect。

**工具功能：**
1. 注册我们的 Dialect
2. 提供命令行接口
3. 集成 MLIR 的标准优化框架

**为什么需要这个工具：**
- `mlir-opt` 默认不包含我们的自定义 Dialect
- 我们需要一个能够识别 `simple` Dialect 的工具
- 这个工具可以扩展支持更多自定义功能

### 第八步：编译项目

**任务说明：**
使用适当的编译器选项编译我们的项目。

**编译要点：**
1. 正确链接 MLIR 库
2. 设置正确的包含路径
3. 使用合适的 C++ 标准

**注意事项：**
- LLVM 路径可能因系统而异
- 某些系统可能需要额外的库依赖
- 编译错误通常指向路径或依赖问题

### 第九步：测试和验证

**任务说明：**
运行我们创建的工具，验证 Dialect 是否正常工作。

**测试内容：**
1. 基本功能测试：能否解析我们的 MLIR 文件
2. 错误处理测试：错误语法是否能被正确识别
3. 诊断功能测试：验证器是否正常工作

**期望结果：**
- 正确的 MLIR 文件应该被成功解析
- 错误的语法应该产生有意义的错误信息

---

## Reference Code (参考代码)

### SimpleDialect.h
```cpp
#ifndef SIMPLE_DIALECT_H
#define SIMPLE_DIALECT_H

// 包含 MLIR 核心头文件
#include "mlir/IR/Dialect.h"          // Dialect 基类
#include "mlir/IR/OpDefinition.h"     // Operation 定义相关
#include "mlir/IR/OpImplementation.h" // Operation 实现相关

namespace simple {

/**
 * SimpleDialect 类
 * 继承自 mlir::Dialect，管理整个 simple dialect 的生命周期
 */
class SimpleDialect : public mlir::Dialect {
public:
  // 构造函数：接受 MLIR 上下文作为参数
  explicit SimpleDialect(mlir::MLIRContext *ctx);
  
  // 静态方法：返回 dialect 的命名空间字符串
  // 这个字符串会成为所有操作的前缀（如 "simple.hello"）
  static llvm::StringRef getDialectNamespace() { return "simple"; }
  
  // 初始化方法：注册 dialect 包含的所有操作、类型等
  void initialize();
};

/**
 * HelloOp 类
 * 定义 "simple.hello" 操作
 * 
 * 模板参数说明：
 * - HelloOp: 操作类本身（CRTP 模式）
 * - mlir::OpTrait::ZeroOperands: 表示此操作不接受任何输入操作数
 * - mlir::OpTrait::ZeroResults: 表示此操作不产生任何结果
 */
class HelloOp : public mlir::Op<HelloOp, 
                                mlir::OpTrait::ZeroOperands, 
                                mlir::OpTrait::ZeroResults> {
public:
  // 使用基类的构造函数
  using Op::Op;
  
  // 静态方法：返回操作的完整名称
  // 格式为 "namespace.operation"
  static llvm::StringRef getOperationName() { 
    return "simple.hello"; 
  }
  
  // 构建方法：用于程序化创建此操作的实例
  // 由于我们的操作不需要任何参数，所以实现为空
  static void build(mlir::OpBuilder &, mlir::OperationState &state) {}
  
  // 返回此操作支持的属性名称列表
  // 我们的简单操作不需要任何属性
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  // 打印方法：定义操作如何在 MLIR 文本中显示
  // 我们只打印一个空格，保持简洁
  void print(mlir::OpAsmPrinter &p) {
    p << " ";
  }
  
  // 解析方法：定义如何从 MLIR 文本解析此操作
  // 我们的操作格式很简单，不需要解析任何额外内容
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    return mlir::success();
  }
};

} // namespace simple

#endif
```

### SimpleDialect.cpp
```cpp
#include "SimpleDialect.h"
#include "mlir/IR/Builders.h"  // 用于构建 MLIR 结构

using namespace mlir;

namespace simple {

/**
 * SimpleDialect 构造函数
 * 
 * 参数：
 * - ctx: MLIR 上下文，管理所有 MLIR 相关的内存和状态
 * 
 * 基类构造函数参数：
 * - getDialectNamespace(): 返回 "simple" 字符串
 * - ctx: 传递上下文
 * - TypeID::get<SimpleDialect>(): 为这个 dialect 创建唯一标识符
 */
SimpleDialect::SimpleDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<SimpleDialect>()) {
  // 调用初始化方法注册所有操作
  initialize();
}

/**
 * 初始化方法
 * 向 dialect 注册所有包含的操作
 * 
 * addOperations<>() 是一个模板方法，可以一次注册多个操作类型
 * 目前我们只有一个 HelloOp 操作
 */
void SimpleDialect::initialize() {
  addOperations<HelloOp>();
}

} // namespace simple
```

### simple-opt.cpp
```cpp
#include "SimpleDialect.h"                           // 我们的自定义 dialect
#include "mlir/IR/MLIRContext.h"                    // MLIR 上下文
#include "mlir/Tools/mlir-opt/MlirOptMain.h"        // mlir-opt 主函数

/**
 * 主函数：创建一个类似 mlir-opt 的工具，但包含我们的自定义 dialect
 * 
 * 工作流程：
 * 1. 创建 dialect 注册表
 * 2. 注册我们的 SimpleDialect
 * 3. 调用 MLIR 的标准主函数处理命令行参数和文件
 */
int main(int argc, char **argv) {
  // 创建 dialect 注册表
  // 这个注册表告诉 MLIR 系统有哪些 dialect 可用
  mlir::DialectRegistry registry;
  
  // 将我们的 SimpleDialect 注册到系统中
  // 注册后，MLIR 就能识别 "simple.*" 格式的操作
  registry.insert<simple::SimpleDialect>();
  
  // 调用 MLIR 提供的标准主函数
  // 这个函数会：
  // - 解析命令行参数
  // - 读取输入文件
  // - 应用指定的优化 pass
  // - 输出结果
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Simple dialect test\n", registry));
}
```

### 编译脚本 (compile.sh)
```bash
#!/bin/bash

# 设置 LLVM 安装路径
# 请根据你的系统调整这个路径
export LLVM_DIR=/usr/local/Cellar/llvm@15/15.0.7

# 检查 LLVM 目录是否存在
if [ ! -d "$LLVM_DIR" ]; then
    echo "错误：LLVM 目录不存在：$LLVM_DIR"
    echo "请修改 LLVM_DIR 变量指向正确的 LLVM 安装目录"
    exit 1
fi

echo "使用 LLVM 目录：$LLVM_DIR"

# 编译命令
# -std=c++17: 使用 C++17 标准
# -I: 添加头文件搜索路径
# -L: 添加库文件搜索路径
clang++ -std=c++17 \
  -I$LLVM_DIR/include \
  -L$LLVM_DIR/lib \
  $(ls $LLVM_DIR/lib/libMLIR*.a | grep -E "(OptLib|Parser|IR|Support)" | tr '\n' ' ') \
  -lLLVMSupport -lLLVMCore -lLLVMDemangle \
  -lncurses -lz -lpthread \
  SimpleDialect.cpp simple-opt.cpp -o simple-opt

# 检查编译是否成功
if [ $? -eq 0 ]; then
    echo "编译成功！生成了 simple-opt 可执行文件"
else
    echo "编译失败，请检查错误信息"
fi
```

### 测试脚本 (test.sh)
```bash
#!/bin/bash

echo "=== 测试自定义 Dialect ==="

# 测试 1：基本功能测试
echo "测试 1：基本功能"
echo "输入文件内容："
cat simple.mlir
echo ""
echo "解析结果："
./simple-opt simple.mlir
echo ""

# 测试 2：验证诊断功能
echo "测试 2：验证诊断"
./simple-opt --verify-diagnostics simple.mlir
if [ $? -eq 0 ]; then
    echo "✓ 诊断测试通过"
else
    echo "✗ 诊断测试失败"
fi
echo ""

# 测试 3：错误处理测试
echo "测试 3：错误处理"
echo "module { simple.hello extra_stuff }" > wrong.mlir
echo "错误输入："
cat wrong.mlir
echo ""
echo "错误处理结果："
./simple-opt wrong.mlir
echo ""

# 清理临时文件
rm -f wrong.mlir

echo "=== 测试完成 ==="
```

---