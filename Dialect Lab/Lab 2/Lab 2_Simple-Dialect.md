# Lab 2 Simple-Dialect: MLIR 自定义 Dialect 进阶

## 实验目标

在 Lab 1 的基础上，进一步掌握 MLIR Dialect 的高级特性：
- 理解操作的不同类型：属性、操作数、结果
- 学会创建带参数的操作（属性和操作数）
- 掌握实现数学运算操作的方法
- 学习编写 Pass 进行 Dialect 间的转换
- 理解 MLIR 的类型系统和操作特征（Traits）

## 前置条件

- 已成功完成 Lab 1
- 理解 MLIR 的基本概念（Dialect、Operation、Type）
- 具备基本的 MLIR 环境和编译知识
- 熟悉 C++ 模板和继承机制

## 实验内容

### 第一步：理解操作的复杂性

**任务说明：**
在 Lab 1 中，我们创建了一个简单的 `hello` 操作，它既不接受输入也不产生输出。在实际应用中，大多数操作都需要处理数据，这就涉及到操作的三个核心组件。

**MLIR 操作的三个核心组件：**
1. **属性（Attributes）**：编译时已知的静态数据（如常量、配置参数）
2. **操作数（Operands）**：运行时的输入值（如变量、表达式结果）
3. **结果（Results）**：操作产生的输出值

**我们将要实现的操作类型：**
- `simple.hello`：无参数操作（Lab 1 已完成）
- `simple.print`：带属性的操作（字符串消息）
- `simple.add`：带操作数和结果的数学运算

### 第二步：设计操作接口

**任务说明：**
在开始编码前，我们需要设计每个操作的接口，明确它们的输入、输出和行为。

**操作设计规格：**

1. **HelloOp (`simple.hello`)**
   - 输入：无
   - 输出：无
   - 用途：测试基本功能

2. **PrintOp (`simple.print`)**
   - 输入：字符串属性 `message`
   - 输出：无
   - 语法：`simple.print "Hello World"`
   - 用途：在编译时显示消息

3. **AddOp (`simple.add`)**
   - 输入：两个相同类型的操作数
   - 输出：与输入相同类型的结果
   - 语法：`%result = simple.add %lhs, %rhs : i32`
   - 用途：执行加法运算

**关键设计考虑：**
- 类型安全：确保操作数和结果类型一致
- 可解析性：设计清晰的文本语法
- 可扩展性：为将来添加更多操作留出空间

### 第三步：理解操作特征（Traits）

**任务说明：**
MLIR 使用特征（Traits）系统来描述操作的通用行为，这有助于编译器进行优化和验证。

**常用的操作特征：**
- `ZeroOperands`：操作不接受任何操作数
- `ZeroResults`：操作不产生任何结果
- `SameOperandsAndResultType`：所有操作数和结果具有相同类型
- `OneResult`：操作产生一个结果

**我们的操作特征选择：**
- `HelloOp`：`ZeroOperands + ZeroResults`
- `PrintOp`：`ZeroResults`（只有属性，无操作数）
- `AddOp`：`SameOperandsAndResultType`（输入输出类型相同）

**为什么特征很重要：**
- 编译器可以基于特征进行优化
- 减少样板代码的编写
- 提供自动的验证逻辑

### 第四步：实现带属性的操作

**任务说明：**
学习如何创建包含属性的操作。属性是编译时已知的静态数据。

**PrintOp 的关键实现要点：**
1. **构建方法**：如何在代码中创建操作实例
2. **属性管理**：如何声明和访问属性
3. **解析方法**：如何从文本解析属性
4. **打印方法**：如何将属性输出为文本

**属性的工作机制：**
- 属性存储在操作的元数据中
- 可以在编译时被优化器访问和修改
- 不参与数据流，只提供配置信息

### 第五步：实现数学运算操作

**任务说明：**
学习如何创建处理运行时数据的操作，包括操作数和结果的管理。

**AddOp 的关键实现要点：**
1. **类型系统**：确保操作数类型一致性
2. **数据流**：处理输入和输出的连接
3. **解析复杂性**：处理类型标注和操作数解析
4. **验证逻辑**：确保操作语义正确

**操作数和结果的区别：**
- 操作数是操作的输入，来自其他操作的结果
- 结果是操作的输出，可以被其他操作使用
- 类型信息必须在操作数和结果之间保持一致

### 第六步：测试扩展的 Dialect

**任务说明：**
创建综合测试用例，验证所有新操作的功能。

**测试策略：**
1. **语法测试**：确保操作能被正确解析
2. **类型测试**：验证类型系统工作正常
3. **集成测试**：在完整的模块中测试操作

**预期测试文件内容：**
```mlir
module {
  simple.hello                           // 基本操作
  simple.print "Hello World"             // 属性操作
  simple.print "Testing features!"       // 多个属性操作
  
  func.func @test() -> i32 {              // 函数上下文
    %0 = arith.constant 10 : i32          // 创建常量
    %1 = arith.constant 20 : i32
    %2 = simple.add %0, %1 : i32          // 数学运算
    return %2 : i32
  }
}
```

### 第七步：理解 Pass 系统

**任务说明：**
学习 MLIR 的 Pass 系统，了解如何在不同 Dialect 之间转换操作。

**Pass 的核心概念：**
- **转换 Pass**：将一种表示转换为另一种表示
- **优化 Pass**：改进代码性能或质量
- **分析 Pass**：收集程序信息但不修改代码

**我们的转换目标：**
- 将 `simple.add` 转换为标准的 `arith.addi`
- 保持其他操作不变
- 验证转换的正确性

**Pass 的工作原理：**
1. 遍历 IR 树，查找目标操作
2. 创建等价的替代操作
3. 更新所有使用关系
4. 删除原始操作

### 第八步：设计转换 Pass

**任务说明：**
设计一个将我们的自定义操作转换为标准操作的 Pass。

**Pass 设计要点：**
1. **模式匹配**：识别需要转换的操作
2. **操作创建**：构建替代操作
3. **数据流更新**：正确连接输入输出关系
4. **清理工作**：删除旧操作，避免内存泄漏

**转换的安全性考虑：**
- 确保类型兼容性
- 保持程序语义不变
- 处理边界情况和错误

### 第九步：实现 Pass 注册

**任务说明：**
学习如何将自定义 Pass 集成到 MLIR 的 Pass 管理系统中。

**Pass 注册的步骤：**
1. 创建 Pass 类
2. 实现转换逻辑
3. 注册到 Pass 管理器
4. 提供命令行接口

**Pass 管理系统的优势：**
- 自动处理依赖关系
- 提供统一的命令行接口
- 支持 Pass 流水线组合

### 第十步：综合测试和验证

**任务说明：**
全面测试扩展的 Dialect 和 Pass 系统。

**测试内容：**
1. **基本功能测试**：所有操作都能正确解析和执行
2. **Pass 转换测试**：转换前后的 IR 语义一致
3. **错误处理测试**：非法输入能被正确检测和报告
4. **性能测试**：Pass 执行效率满足要求

**验证方法：**
- 对比转换前后的 IR
- 使用 `mlir-opt` 的验证功能
- 编写自动化测试脚本

---

## 参考代码

### SimpleDialect.h
```cpp
#ifndef SIMPLE_DIALECT_H
#define SIMPLE_DIALECT_H

// MLIR 核心头文件
#include "mlir/IR/Dialect.h"          // Dialect 基类
#include "mlir/IR/OpDefinition.h"     // Operation 定义
#include "mlir/IR/OpImplementation.h" // Operation 实现
#include "mlir/IR/Builders.h"         // IR 构建器
#include "mlir/IR/Operation.h"        // Operation 基础设施

namespace simple {

/**
 * SimpleDialect 类 - 扩展
 * 管理多个不同类型的操作
 */
class SimpleDialect : public mlir::Dialect {
public:
  explicit SimpleDialect(mlir::MLIRContext *ctx);
  static llvm::StringRef getDialectNamespace() { return "simple"; }
  void initialize();
};

/**
 * HelloOp - 基础操作（Lab 1 中的操作）
 * 特征：ZeroOperands + ZeroResults
 * 语法：simple.hello
 */
class HelloOp : public mlir::Op<HelloOp, 
                                mlir::OpTrait::ZeroOperands, 
                                mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.hello"; }
  static void build(mlir::OpBuilder &, mlir::OperationState &state) {}
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    p << " ";
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    return mlir::success();
  }
};

/**
 * PrintOp - 带属性的操作
 * 特征：ZeroResults（只有属性，无操作数）
 * 语法：simple.print "message"
 * 
 * 这个操作演示了如何处理编译时属性
 */
class PrintOp : public mlir::Op<PrintOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.print"; }
  
  /**
   * 构建方法 - 用于程序化创建操作实例
   * 
   * @param builder: IR 构建器，用于创建 MLIR 结构
   * @param state: 操作状态，收集操作的所有信息
   * @param message: 要打印的消息字符串
   */
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state, 
                    llvm::StringRef message) {
    // 将字符串转换为 MLIR 属性并添加到操作中
    state.addAttribute("message", builder.getStringAttr(message));
  }
  
  /**
   * 声明此操作支持的属性名称
   * 返回静态数组，包含所有可能的属性名
   */
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    static llvm::StringRef attrNames[] = {"message"};
    return llvm::ArrayRef<llvm::StringRef>(attrNames);
  }
  
  /**
   * 打印方法 - 定义操作的文本表示
   * 格式：simple.print "message"
   */
  void print(mlir::OpAsmPrinter &p) {
    // 获取 message 属性并以引号包围的形式打印
    p << " \"" << (*this)->getAttr("message") << "\"";
  }
  
  /**
   * 解析方法 - 从文本解析操作
   * 需要解析引号包围的字符串
   */
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    std::string message;
    // 解析字符串字面量
    if (parser.parseString(&message))
      return mlir::failure();
    
    // 将解析的字符串添加为属性
    result.addAttribute("message", parser.getBuilder().getStringAttr(message));
    return mlir::success();
  }
};

/**
 * AddOp - 数学运算操作
 * 特征：SameOperandsAndResultType（输入输出类型相同）
 * 语法：%result = simple.add %lhs, %rhs : type
 * 
 * 这个操作演示了如何处理运行时数据流
 */
class AddOp : public mlir::Op<AddOp, mlir::OpTrait::SameOperandsAndResultType> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "simple.add"; }
  
  /**
   * 构建方法 - 创建加法操作
   * 
   * @param builder: IR 构建器
   * @param state: 操作状态
   * @param lhs: 左操作数
   * @param rhs: 右操作数
   */
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value lhs, mlir::Value rhs) {
    // 添加两个操作数
    state.addOperands({lhs, rhs});
    // 结果类型与左操作数相同
    state.addTypes(lhs.getType());
  }
  
  /**
   * 此操作不需要属性
   */
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  /**
   * 打印方法 - 格式：%result = simple.add %lhs, %rhs : type
   */
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    auto results = this->getOperation()->getResults();
    p << " " << operands[0] << ", " << operands[1] 
      << " : " << results[0].getType();
  }
  
  /**
   * 解析方法 - 解析复杂的操作数和类型信息
   * 需要处理：操作数引用、类型标注、操作数解析
   */
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand lhs, rhs;
    mlir::Type type;
    
    // 按顺序解析：%lhs, %rhs : type
    if (parser.parseOperand(lhs) ||          // 解析第一个操作数
        parser.parseComma() ||               // 解析逗号
        parser.parseOperand(rhs) ||          // 解析第二个操作数
        parser.parseColon() ||               // 解析冒号
        parser.parseType(type))              // 解析类型
      return mlir::failure();
      
    // 将未解析的操作数转换为实际的 Value 对象
    if (parser.resolveOperands({lhs, rhs}, type, result.operands))
      return mlir::failure();
      
    // 添加结果类型
    result.addTypes(type);
    return mlir::success();
  }
};

} // namespace simple

#endif
```

### SimpleDialect.cpp
```cpp
#include "SimpleDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace simple {

/**
 * SimpleDialect 构造函数
 * 初始化包含多个操作的 Dialect
 */
SimpleDialect::SimpleDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<SimpleDialect>()) {
  initialize();
}

/**
 * 注册所有操作到 Dialect 中
 * 现在包含三个不同类型的操作
 */
void SimpleDialect::initialize() {
  addOperations<HelloOp, PrintOp, AddOp>();
}

} // namespace simple
```

### SimplePass.h
```cpp
#ifndef SIMPLE_PASS_H
#define SIMPLE_PASS_H

#include "mlir/Pass/Pass.h"

namespace simple {

/**
 * 创建 Simple 到 Arith 的转换 Pass
 * 将 simple.add 转换为 arith.addi
 * 
 * @return 转换 Pass 的智能指针
 */
std::unique_ptr<mlir::Pass> createSimpleToArithPass();

} // namespace simple

#endif
```

### SimplePass.cpp
```cpp
#include "SimplePass.h"
#include "SimpleDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Dialect/Arith/IR/Arith.h"

using namespace mlir;

namespace simple {

namespace {

/**
 * SimpleToArithPass - 将 Simple Dialect 操作转换为 Arith Dialect
 * 
 * 这个 Pass 演示了基本的操作转换模式：
 * 1. 查找目标操作
 * 2. 创建等价操作
 * 3. 替换使用关系
 * 4. 清理原操作
 */
struct SimpleToArithPass : public PassWrapper<SimpleToArithPass, OperationPass<ModuleOp>> {
  
  /**
   * 返回 Pass 的命令行参数名
   * 用户可以通过 --convert-simple-to-arith 调用此 Pass
   */
  StringRef getArgument() const final {
    return "convert-simple-to-arith";
  }
  
  /**
   * 返回 Pass 的描述信息
   * 在帮助信息中显示
   */
  StringRef getDescription() const final {
    return "Convert simple dialect operations to arith dialect";
  }
  
  /**
   * Pass 的主要执行逻辑
   * 在整个模块上运行，查找并转换所有 simple.add 操作
   */
  void runOnOperation() override {
    // 第一步：收集所有需要转换的操作
    // 我们不能在遍历过程中直接修改 IR，因为这会影响迭代器
    SmallVector<AddOp, 4> addOps;
    
    // 使用 walk 方法遍历整个模块，查找 AddOp
    getOperation().walk([&](AddOp op) {
      addOps.push_back(op);
    });
    
    // 第二步：逐个转换收集到的操作
    for (auto op : addOps) {
      // 创建 IR 构建器，在原操作位置插入新操作
      OpBuilder builder(op);
      auto operands = op->getOperands();
      auto resultType = op->getResult(0).getType();
      
      // 方法一：使用 OperationState 手动构建操作
      // 这种方法提供了最大的控制权
      OperationState state(op.getLoc(), "arith.addi");
      state.addOperands({operands[0], operands[1]});
      state.addTypes(resultType);
      
      Operation *newOp = builder.create(state);
      
      // 方法二：使用类型化的操作构建器（注释掉的替代方案）
      // auto newOp = builder.create<mlir::arith::AddIOp>(
      //     op.getLoc(), operands[0], operands[1]);
      
      // 第三步：替换所有对原操作结果的使用
      // 这会自动更新所有引用这个结果的地方
      op->getResult(0).replaceAllUsesWith(newOp->getResult(0));
      
      // 第四步：删除原操作
      // 现在原操作不再被使用，可以安全删除
      op->erase();
      
      // 输出转换信息（可选，用于调试）
      llvm::outs() << "Converted simple.add to arith.addi\n";
    }
  }
};

} // namespace

/**
 * Pass 创建函数
 * 供外部调用以创建 Pass 实例
 */
std::unique_ptr<Pass> createSimpleToArithPass() {
  return std::make_unique<SimpleToArithPass>();
}

} // namespace simple
```

### simple-opt.cpp
```cpp
#include "SimpleDialect.h"
#include "SimplePass.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"      // func dialect
#include "mlir/Dialect/Arith/IR/Arith.h"       // arith dialect
#include "mlir/Pass/PassRegistry.h"            // Pass 注册

/**
 * simple-opt 主函数
 * 
 * 功能：
 * 1. 注册必要的 Dialect
 * 2. 注册自定义 Pass
 * 3. 提供 mlir-opt 兼容的命令行接口
 */
int main(int argc, char **argv) {
  // 创建 Dialect 注册表
  mlir::DialectRegistry registry;
  
  // 注册标准 Dialect
  registry.insert<mlir::func::FuncDialect>();   // 函数 dialect
  registry.insert<mlir::arith::ArithDialect>(); // 算术 dialect
  
  // 注册我们的自定义 Dialect
  registry.insert<simple::SimpleDialect>();
  
  // 注册我们的自定义 Pass
  // 使用 lambda 函数创建 Pass 实例
  mlir::registerPass([]() -> std::unique_ptr<mlir::Pass> {
    return simple::createSimpleToArithPass();
  });
  
  // 调用 MLIR 的标准主函数
  // 这会处理命令行参数、文件 I/O 和 Pass 执行
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Simple dialect test with passes\n", registry));
}
```

### 编译脚本 (compile-extended.sh)
```bash
#!/bin/bash

# 设置 LLVM 安装路径
export LLVM_DIR=/usr/local/Cellar/llvm@15/15.0.7

# 检查目录存在性
if [ ! -d "$LLVM_DIR" ]; then
    echo "错误：LLVM 目录不存在：$LLVM_DIR"
    echo "请修改 LLVM_DIR 变量"
    exit 1
fi

echo "编译扩展版 simple-opt..."

# 编译命令 - 包含 Pass 支持
# 需要链接更多的 MLIR 库来支持 Pass 系统
clang++ -std=c++17 \
  -I$LLVM_DIR/include \
  -L$LLVM_DIR/lib \
  $(ls $LLVM_DIR/lib/libMLIR*.a | grep -E "(OptLib|Parser|IR|Support|Pass|Transforms|Arith)" | tr '\n' ' ') \
  -lLLVMSupport -lLLVMCore -lLLVMDemangle \
  -lncurses -lz -lpthread \
  SimpleDialect.cpp SimplePass.cpp simple-opt.cpp -o simple-opt

if [ $? -eq 0 ]; then
    echo "✓ 编译成功！"
    echo "可执行文件：simple-opt"
else
    echo "✗ 编译失败"
    exit 1
fi
```

### 测试文件 (test-extended.mlir)
```mlir
// 扩展功能测试文件
// 包含所有三种类型的操作

module {
  // 基础操作 - 无参数
  simple.hello
  
  // 属性操作 - 编译时字符串
  simple.print "Hello World"
  simple.print "Testing extended features!"
  simple.print "Attributes work correctly"
  
  // 函数定义，包含数学运算操作
  func.func @test_math() -> i32 {
    // 创建常量操作数
    %0 = arith.constant 10 : i32
    %1 = arith.constant 20 : i32
    
    // 使用我们的自定义加法操作
    %2 = simple.add %0, %1 : i32
    
    return %2 : i32
  }
}
```

### 综合测试脚本 (test-extended.sh)
```bash
#!/bin/bash

echo "=== Lab 2 扩展功能测试 ==="

# 测试 1：基本解析功能
echo "测试 1：基本解析功能"
echo "输入文件："
cat test-extended.mlir
echo ""
echo "解析结果："
./simple-opt test-extended.mlir
echo ""

# 测试 2：验证诊断
echo "测试 2：验证诊断"
./simple-opt --verify-diagnostics test-extended.mlir
if [ $? -eq 0 ]; then
    echo "✓ 验证通过"
else
    echo "✗ 验证失败"
fi
echo ""

# 测试 3：Pass 转换
echo "测试 3：Pass 转换"
echo "转换前的 IR："
./simple-opt test-extended.mlir | grep -A 5 -B 5 "simple.add"
echo ""
echo "转换后的 IR："
./simple-opt --convert-simple-to-arith test-extended.mlir | grep -A 5 -B 5 "arith.addi"
echo ""

# 测试 4：查看可用 Pass
echo "测试 4：可用的 Pass"
./simple-opt --help | grep convert-simple
echo ""

# 测试 5：错误处理
echo "测试 5：错误处理"
echo "func.func @error() { simple.add %unknown : i32 }" > error.mlir
echo "错误输入测试："
./simple-opt error.mlir 2>&1 || echo "✓ 正确检测到错误"
rm -f error.mlir
echo ""

echo "=== 测试完成 ==="
```

---