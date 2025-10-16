# Lab 7: Memory-Dialect - MLIR 内存管理 Dialect 开发

## 实验目标

通过本实验，你将：
- 深入理解 MLIR 的内存管理机制和 memref 类型系统
- 学会创建处理多维数组的自定义操作
- 掌握操作数、结果和索引的处理方法
- 实现内存操作的类型验证和安全检查
- 编写 Pass 将自定义操作转换为标准 memref 操作
- 理解 MLIR 中内存抽象的层次结构

## 前置条件

- 已成功完成 Lab 1 和 Lab 2
- 理解 MLIR 的基本概念（Dialect、Operation、Type、Pass）
- 熟悉 C++ 编程和模板机制
- 了解多维数组和内存布局的基本概念
- 掌握 memref 类型的基本用法

## 实验背景

### 为什么需要内存管理 Dialect？

在 MLIR 中，内存管理是一个核心概念。虽然 MLIR 提供了标准的 `memref` dialect，但在某些场景下，我们需要：

1. **更高层次的抽象**：隐藏底层内存分配细节
2. **特定领域的语义**：为特定应用提供专门的内存操作
3. **简化的接口**：提供更直观的矩阵操作语法
4. **优化机会**：在高层次进行内存访问优化

### 我们要实现什么？

本实验将创建一个 `memory` dialect，提供简洁的矩阵内存操作：

```mlir
// 目标语法
%matrix = memory.create_matrix 3, 4 : memref<3x4xf32>
memory.set %matrix[%i, %j] = %value : memref<3x4xf32>
%val = memory.get %matrix[%i, %j] : memref<3x4xf32>
memory.print %matrix : memref<3x4xf32>
```

## 实验任务

### 任务 1：环境验证和理论学习

**1.1 验证 MLIR 环境**

首先验证你的 MLIR 环境能够处理 memref 操作：

```bash
# 创建测试文件
cat > memref_test.mlir << 'EOF'
func.func @test_memref() {
  %matrix = memref.alloc() : memref<2x3xf32>
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %val = arith.constant 1.5 : f32
  
  memref.store %val, %matrix[%c0, %c1] : memref<2x3xf32>
  %loaded = memref.load %matrix[%c0, %c1] : memref<2x3xf32>
  
  memref.dealloc %matrix : memref<2x3xf32>
  return
}
EOF

# 验证语法
mlir-opt memref_test.mlir
```

**思考题：**
- 观察上述代码，memref 操作的基本模式是什么？
- `memref<2x3xf32>` 类型表示什么含义？
- 为什么需要 `index` 类型来做数组索引？

**答案：**
- **memref 操作的基本模式**：遵循"分配-使用-释放"的模式。先用 `alloc` 分配内存，然后用 `load/store` 进行读写访问，最后用 `dealloc` 释放内存。这是显式内存管理的典型模式。
- **`memref<2x3xf32>` 类型含义**：表示一个 2 行 3 列的二维数组，元素类型为 32 位浮点数。`memref` 是 MLIR 中表示内存引用的类型，包含形状信息、元素类型和可选的内存空间/布局信息。
- **`index` 类型的必要性**：`index` 是 MLIR 的目标无关整数类型，专门用于数组索引和内存地址计算。它可以根据目标平台自动选择合适的位宽（32位或64位），确保索引操作的正确性和效率。

**1.2 理解 memref 类型系统**

研究以下不同的 memref 类型声明：

```mlir
memref<4x4xf32>           // 固定形状
memref<?x?xf32>           // 动态形状  
memref<2x3xf32, 1>        // 指定内存空间
```

**实验任务：**
- 查阅 MLIR 文档，理解动态形状 memref 的用途
- 思考：什么时候使用固定形状，什么时候使用动态形状？

**答案：**
- **动态形状 memref 的用途**：当数组的维度在编译时无法确定时使用，比如处理不同大小的输入数据、函数参数中的数组等。动态形状提供了更大的灵活性，但可能影响某些编译时优化。
- **使用场景选择**：
  - **固定形状**：当数组大小在编译时已知且不变时使用，如固定大小的卷积核、预定义的查找表等。优点是可以进行更多编译时优化。
  - **动态形状**：当数组大小在运行时确定时使用，如用户输入的矩阵、batch size 不固定的神经网络层等。提供更大灵活性但可能牺牲部分性能。

### 任务 2：设计自定义操作接口

**2.1 操作设计分析**

在开始编码前，我们需要仔细设计每个操作的接口。分析以下设计决策：

| 操作 | 输入 | 输出 | 设计考虑 |
|------|------|------|----------|
| `create_matrix` | 两个 index 值（行、列） | memref<?x?xf32> | 为什么用动态形状？ |
| `set` | memref + 两个 index + f32 值 | 无 | 为什么没有返回值？ |
| `get` | memref + 两个 index | f32 值 | 类型如何保证一致？ |
| `print` | memref | 无 | 如何处理调试操作？ |

**思考题：**
- 为什么 `create_matrix` 返回动态形状的 memref 而不是固定形状？
- `set` 操作属于什么类型的操作特征（Trait）？
- 如何确保 `get` 和 `set` 操作的类型安全？

**答案：**
- **使用动态形状的原因**：因为矩阵的行数和列数是通过运行时的 `index` 值参数传入的，在编译时无法确定具体数值。如果使用固定形状，就无法支持运行时动态指定矩阵大小的功能。动态形状 `memref<?x?xf32>` 可以在运行时根据参数确定实际形状。
- **`set` 操作的特征**：属于 `ZeroResults` 特征，因为它是一个副作用操作（side-effect operation），只修改内存状态而不返回值。它还可能具有 `MemWrite` 等内存效果特征。
- **类型安全保证**：
  - 在解析阶段，确保 memref 的元素类型与 get/set 的值类型一致（都是 f32）
  - 索引必须是 `index` 类型
  - 在验证阶段检查 memref 的维度与索引数量匹配
  - 可以添加运行时边界检查防止越界访问

**2.2 语法设计验证**

设计并验证每个操作的文本语法：

```mlir
// 你认为以下语法合理吗？为什么？
%mat = memory.create_matrix %rows, %cols : memref<?x?xf32>
memory.set %mat[%i, %j] = %val : memref<?x?xf32>  
%result = memory.get %mat[%i, %j] : memref<?x?xf32>
```

**实验任务：**
- 分析每个操作的解析难度
- 思考如何处理索引的方括号语法
- 考虑类型推断的可能性

**答案：**
- **解析难度分析**：
  - `create_matrix`：相对简单，标准的操作数-类型格式
  - `set`：最复杂，需要解析方括号、等号等特殊符号
  - `get`：中等复杂度，需要解析方括号语法
- **方括号语法处理**：
  - 使用 `parser.parseLSquare()` 和 `parser.parseRSquare()` 解析 `[` 和 `]`
  - 在方括号内使用 `parser.parseComma()` 分割多个索引
  - 需要仔细处理操作数的解析顺序
- **类型推断可能性**：
  - `get` 操作的返回类型可以从 memref 的元素类型推断
  - `set` 操作可以推断出值参数应该与 memref 元素类型匹配
  - 但为了清晰性和错误检查，显式类型标注仍然有价值

### 任务 3：实现 Dialect 框架

**3.1 创建项目结构**

```bash
mkdir memory-dialect && cd memory-dialect
# 创建必要的源文件（你需要哪些文件？）
```

**3.2 实现 MemoryDialect 类**

创建 `MemoryDialect.h`，思考以下问题：
- 需要包含哪些 MLIR 头文件？
- Dialect 类需要实现哪些方法？
- 如何正确设置命名空间？

**提示：**
- 查看 Lab 1 和 Lab 2 中的 Dialect 实现模式
- 注意 MLIR 版本差异可能导致的头文件路径变化
- 确保正确继承 `mlir::Dialect` 基类

**答案：**
- **必需的头文件**：
  ```cpp
  #include "mlir/IR/Dialect.h"          // Dialect 基类
  #include "mlir/IR/OpDefinition.h"     // Op 定义相关
  #include "mlir/IR/OpImplementation.h" // 解析和打印
  #include "mlir/IR/Builders.h"         // IR 构建器
  #include "mlir/IR/BuiltinTypes.h"     // 内置类型如 MemRefType
  ```
- **Dialect 类必需方法**：
  - 构造函数：初始化 Dialect 并设置 TypeID
  - `getDialectNamespace()`：返回命名空间字符串
  - `initialize()`：注册包含的操作、类型等
- **命名空间设置**：使用 `namespace memory` 包装所有自定义类，在 `getDialectNamespace()` 中返回 `"memory"`

**3.3 验证编译环境**

在实现具体操作前，先创建一个最小的 Dialect：

```cpp
// 只注册 Dialect，不包含任何操作
class MemoryDialect : public mlir::Dialect {
  // 最小实现
};
```

**实验任务：**
- 创建简单的测试程序验证 Dialect 可以注册
- 解决可能的编译和链接问题
- 确认 MLIR 库的正确链接

### 任务 4：实现矩阵创建操作

**4.1 分析 CreateMatrixOp 的需求**

这个操作需要：
- 接受两个 `index` 类型的操作数（行数、列数）
- 返回一个动态形状的 `memref<?x?xf32>`
- 支持文本格式的解析和打印

**思考题：**
- 选择什么操作特征（Traits）？
- 如何在 `build` 方法中创建正确的 memref 类型？
- 解析时如何处理操作数的类型解析？

**答案：**
- **操作特征选择**：`mlir::OpTrait::OneResult` - 表示操作产生一个结果。不需要其他特征，因为操作数数量是固定的（2个）。
- **创建 memref 类型**：
  ```cpp
  auto f32Type = builder.getF32Type();
  auto memrefType = mlir::MemRefType::get({-1, -1}, f32Type);
  ```
  其中 `{-1, -1}` 表示两个动态维度。
- **操作数类型解析**：
  ```cpp
  auto indexType = parser.getBuilder().getIndexType();
  if (parser.resolveOperands({rows, cols}, indexType, result.operands))
    return mlir::failure();
  ```
  确保两个操作数都被解析为 `index` 类型。

**4.2 实现步骤指导**

1. **定义操作类结构**
   ```cpp
   class CreateMatrixOp : public mlir::Op<CreateMatrixOp, /* 什么特征？ */> {
     // 需要实现哪些静态方法？
   };
   ```

2. **实现 build 方法**
   - 如何创建动态形状的 MemRefType？
   - `state.addOperands()` 和 `state.addTypes()` 的使用

3. **实现 parse 方法**
   - 解析操作数和类型的顺序
   - 如何使用 `parser.resolveOperands()`？

4. **实现 print 方法**
   - 输出格式的设计
   - 如何获取操作数和结果类型？

**验证方法：**
创建简单的测试用例验证操作可以被解析：
```mlir
%c2 = arith.constant 2 : index
%c3 = arith.constant 3 : index  
%mat = memory.create_matrix %c2, %c3 : memref<?x?xf32>
```

### 任务 5：实现内存访问操作

**5.1 实现 SetElementOp**

这是最复杂的操作之一，需要处理：
- 方括号索引语法的解析
- 多个不同类型的操作数
- 无返回值的操作特征

**关键挑战：**
- 如何解析 `%matrix[%i, %j] = %value` 语法？
- 操作数的顺序如何安排？
- 如何确保索引和值的类型正确？

**实现提示：**
1. 操作数顺序建议：`[memref, index1, index2, value]`
2. 解析时需要处理：`[`, `,`, `]`, `=` 等特殊符号
3. 使用 `ZeroResults` 特征

**答案：**
- **解析复杂语法的方法**：
  ```cpp
  // 按顺序解析每个符号
  if (parser.parseOperand(memref) ||          // %matrix
      parser.parseLSquare() ||                // [
      parser.parseOperand(i) ||               // %i
      parser.parseComma() ||                  // ,
      parser.parseOperand(j) ||               // %j
      parser.parseRSquare() ||                // ]
      parser.parseEqual() ||                  // =
      parser.parseOperand(value) ||           // %value
      parser.parseColon() ||                  // :
      parser.parseType(memrefType))           // type
    return mlir::failure();
  ```
- **操作数顺序**：`[memref, i, j, value]` 是合理的，因为这样在构建器中可以清晰地分组处理。
- **类型安全保证**：为每类操作数指定正确的类型，在 `resolveOperands` 时进行检查。

**5.2 实现 GetElementOp** 

相对简单，但需要注意：
- 返回值类型如何确定？
- 与 SetElementOp 的语法一致性

**5.3 实现 PrintMatrixOp**

最简单的操作，用于调试：
- 只接受一个 memref 操作数
- 无返回值
- 在转换 Pass 中可以删除或转换为其他形式

### 任务 6：测试和调试

**6.1 创建综合测试**

创建 `test-memory.mlir` 文件，包含：

```mlir
module {
  func.func @matrix_demo() {
    // 测试矩阵创建
    // 测试元素设置
    // 测试元素读取
    // 测试打印功能
  }
}
```

**6.2 编译和运行测试**

解决可能遇到的问题：
- 链接错误：需要哪些 MLIR 库？
- 命名空间错误：检查 dialect 名称
- 解析错误：验证语法实现

**常见问题排查：**
- 如果编译失败，检查头文件路径和库链接
- 如果解析失败，检查 `parse` 方法的实现
- 如果运行时错误，检查操作特征的正确性

### 任务 7：实现转换 Pass

**7.1 理解转换目标**

我们需要将自定义操作转换为标准 memref 操作：
- `memory.create_matrix` → `memref.alloc`
- `memory.set` → `memref.store`
- `memory.get` → `memref.load`
- `memory.print` → 删除（或转换为调试输出）

**7.2 实现转换 Pass**

创建 `MemoryPass.cpp`，思考：
- Pass 的基本结构是什么？
- 如何遍历和收集需要转换的操作？
- 转换顺序是否重要？

**关键步骤：**
1. 收集所有需要转换的操作
2. 逐个创建等价的标准操作
3. 替换所有使用关系
4. 删除原操作

**答案：**
- **Pass 基本结构**：继承 `PassWrapper<ClassName, OperationPass<ModuleOp>>`，实现 `runOnOperation()` 方法。
- **遍历和收集**：使用 `getOperation().walk()` 遍历 IR 树，用 `dyn_cast` 识别目标操作类型。
- **转换顺序**：通常先收集所有操作，再批量转换，避免在遍历过程中修改 IR 导致迭代器失效。依赖关系上，应该先处理数据生产者（create_matrix），再处理消费者（get/set）。

**7.3 测试转换效果**

使用命令行测试转换：
```bash
# 转换前
./memory-opt test-memory.mlir

# 转换后  
./memory-opt --convert-memory-to-memref test-memory.mlir
```

对比转换前后的 IR，验证语义等价性。

### 任务 8：优化和扩展

**8.1 添加错误处理**

思考并实现：
- 索引越界检查
- 类型不匹配检查
- 空指针检查

**8.2 性能优化**

考虑：
- 是否可以进行常量折叠？
- 能否优化连续的内存访问？
- 如何处理内存对齐？

**8.3 功能扩展**

可选的扩展功能：
- 支持不同的元素类型（不仅仅是 f32）
- 添加矩阵运算操作（加法、乘法等）
- 支持子矩阵操作

## 实验验收

### 基本要求（70分）

- [ ] 成功创建并注册 MemoryDialect
- [ ] 实现所有四个基本操作的解析和打印
- [ ] 通过基本的语法测试
- [ ] 实现基本的转换 Pass

### 进阶要求（85分）

- [ ] 添加适当的错误处理和验证
- [ ] 实现完整的测试套件
- [ ] 转换 Pass 能正确处理所有操作
- [ ] 代码结构清晰，注释完整

### 高级要求（100分）

- [ ] 实现类型推断或泛型支持
- [ ] 添加性能优化功能
- [ ] 扩展功能（如子矩阵操作）
- [ ] 完善的文档和使用示例

## 学习总结

完成实验后，思考以下问题：

1. **设计决策**：为什么选择动态形状的 memref？有什么优缺点？
2. **抽象层次**：我们的 memory dialect 与标准 memref 相比，提供了什么价值？
3. **类型安全**：MLIR 的类型系统如何帮助我们避免内存安全问题？
4. **优化机会**：在 dialect 层面可以进行哪些优化？
5. **实际应用**：这种内存抽象在什么场景下最有用？

**学习总结答案：**

1. **动态形状的优缺点**：
   - **优点**：灵活性高，支持运行时确定大小；接口统一，不需要为每种大小定义不同操作
   - **缺点**：运行时开销更大；某些编译时优化无法进行；类型检查相对宽松

2. **抽象价值**：
   - 提供了更直观的矩阵操作语法，隐藏了底层内存管理细节
   - 为特定领域提供了专门的语义，便于后续优化
   - 在高层进行错误检查和类型验证更容易

3. **类型安全**：
   - 静态类型检查防止类型不匹配
   - index 类型确保索引操作的正确性
   - memref 类型包含维度信息，可以进行边界检查

4. **优化机会**：
   - 矩阵访问模式分析和优化
   - 内存布局优化
   - 批量操作合并
   - 常量传播和折叠

5. **实际应用场景**：
   - 科学计算库的高层接口
   - 领域特定语言的后端
   - 深度学习框架的中间表示
   - 需要内存访问优化的高性能计算应用

## 参考资源

- [MLIR Language Reference](https://mlir.llvm.org/docs/LangRef/)
- [MLIR Dialect Developer Documentation](https://mlir.llvm.org/docs/Tutorials/DefiningAttributesAndTypes/)
- [MemRef Dialect Documentation](https://mlir.llvm.org/docs/Dialects/MemRef/)

---

## 参考代码

### MemoryDialect.h

```cpp
#ifndef MEMORY_DIALECT_H
#define MEMORY_DIALECT_H

#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"

namespace memory {

/**
 * MemoryDialect 类
 * 管理内存相关的操作
 */
class MemoryDialect : public mlir::Dialect {
public:
  explicit MemoryDialect(mlir::MLIRContext *ctx);
  static llvm::StringRef getDialectNamespace() { return "memory"; }
  void initialize();
};

/**
 * CreateMatrixOp - 创建矩阵操作
 * 语法：%matrix = memory.create_matrix rows, cols : memref<RxCxf32>
 */
class CreateMatrixOp : public mlir::Op<CreateMatrixOp, mlir::OpTrait::OneResult> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.create_matrix"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value rows, mlir::Value cols) {
    auto f32Type = builder.getF32Type();
    auto memrefType = mlir::MemRefType::get({-1, -1}, f32Type);
    
    state.addOperands({rows, cols});
    state.addTypes(memrefType);
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    auto results = this->getOperation()->getResults();
    p << " " << operands[0] << ", " << operands[1] 
      << " : " << results[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand rows, cols;
    mlir::Type resultType;
    
    if (parser.parseOperand(rows) ||
        parser.parseComma() ||
        parser.parseOperand(cols) ||
        parser.parseColon() ||
        parser.parseType(resultType))
      return mlir::failure();
    
    auto indexType = parser.getBuilder().getIndexType();
    if (parser.resolveOperands({rows, cols}, indexType, result.operands))
      return mlir::failure();
    
    result.addTypes(resultType);
    return mlir::success();
  }
};

/**
 * SetElementOp - 设置矩阵元素操作
 * 语法：memory.set %matrix[%i, %j] = %value : memref<RxCxf32>
 */
class SetElementOp : public mlir::Op<SetElementOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.set"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value memref, mlir::ValueRange indices, mlir::Value value) {
    state.addOperands({memref});
    state.addOperands(indices);
    state.addOperands({value});
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    p << " " << operands[0] << "["
      << operands[1] << ", " << operands[2] << "] = " 
      << operands[3] << " : " << operands[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand memref, i, j, value;
    mlir::Type memrefType;
    
    if (parser.parseOperand(memref) ||
        parser.parseLSquare() ||
        parser.parseOperand(i) ||
        parser.parseComma() ||
        parser.parseOperand(j) ||
        parser.parseRSquare() ||
        parser.parseEqual() ||
        parser.parseOperand(value) ||
        parser.parseColon() ||
        parser.parseType(memrefType))
      return mlir::failure();
    
    auto indexType = parser.getBuilder().getIndexType();
    auto f32Type = parser.getBuilder().getF32Type();
    
    if (parser.resolveOperand(memref, memrefType, result.operands) ||
        parser.resolveOperands({i, j}, indexType, result.operands) ||
        parser.resolveOperand(value, f32Type, result.operands))
      return mlir::failure();
    
    return mlir::success();
  }
};

/**
 * GetElementOp - 获取矩阵元素操作
 * 语法：%value = memory.get %matrix[%i, %j] : memref<RxCxf32>
 */
class GetElementOp : public mlir::Op<GetElementOp, mlir::OpTrait::OneResult> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.get"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value memref, mlir::ValueRange indices) {
    state.addOperands({memref});
    state.addOperands(indices);
    state.addTypes(builder.getF32Type());
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    auto operands = this->getOperation()->getOperands();
    p << " " << operands[0] << "["
      << operands[1] << ", " << operands[2] << "] : " 
      << operands[0].getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand memref, i, j;
    mlir::Type memrefType;
    
    if (parser.parseOperand(memref) ||
        parser.parseLSquare() ||
        parser.parseOperand(i) ||
        parser.parseComma() ||
        parser.parseOperand(j) ||
        parser.parseRSquare() ||
        parser.parseColon() ||
        parser.parseType(memrefType))
      return mlir::failure();
    
    auto indexType = parser.getBuilder().getIndexType();
    
    if (parser.resolveOperand(memref, memrefType, result.operands) ||
        parser.resolveOperands({i, j}, indexType, result.operands))
      return mlir::failure();
    
    result.addTypes(parser.getBuilder().getF32Type());
    return mlir::success();
  }
};

/**
 * PrintMatrixOp - 打印矩阵操作
 * 语法：memory.print %matrix : memref<RxCxf32>
 */
class PrintMatrixOp : public mlir::Op<PrintMatrixOp, mlir::OpTrait::ZeroResults> {
public:
  using Op::Op;
  static llvm::StringRef getOperationName() { return "memory.print"; }
  
  static void build(mlir::OpBuilder &builder, mlir::OperationState &state,
                    mlir::Value memref) {
    state.addOperands({memref});
  }
  
  static llvm::ArrayRef<llvm::StringRef> getAttributeNames() {
    return {};
  }
  
  void print(mlir::OpAsmPrinter &p) {
    p << " " << this->getOperation()->getOperand(0) 
      << " : " << this->getOperation()->getOperand(0).getType();
  }
  
  static mlir::ParseResult parse(mlir::OpAsmParser &parser, 
                                mlir::OperationState &result) {
    mlir::OpAsmParser::UnresolvedOperand memref;
    mlir::Type memrefType;
    
    if (parser.parseOperand(memref) ||
        parser.parseColon() ||
        parser.parseType(memrefType))
      return mlir::failure();
    
    if (parser.resolveOperand(memref, memrefType, result.operands))
      return mlir::failure();
    
    return mlir::success();
  }
};

} // namespace memory

#endif
```

### MemoryDialect.cpp

```cpp
#include "MemoryDialect.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace memory {

MemoryDialect::MemoryDialect(MLIRContext *ctx)
    : Dialect(getDialectNamespace(), ctx, TypeID::get<MemoryDialect>()) {
  initialize();
}

void MemoryDialect::initialize() {
  addOperations<CreateMatrixOp, SetElementOp, GetElementOp, PrintMatrixOp>();
}

} // namespace memory
```

### MemoryPass.h

```cpp
#ifndef MEMORY_PASS_H
#define MEMORY_PASS_H

#include "mlir/Pass/Pass.h"

namespace memory {

std::unique_ptr<mlir::Pass> createMemoryToMemRefPass();

} // namespace memory

#endif
```

### MemoryPass.cpp

```cpp
#include "MemoryPass.h"
#include "MemoryDialect.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Arithmetic/IR/Arithmetic.h"

using namespace mlir;

namespace memory {

namespace {

struct MemoryToMemRefPass : public PassWrapper<MemoryToMemRefPass, OperationPass<ModuleOp>> {
  
  StringRef getArgument() const final {
    return "convert-memory-to-memref";
  }
  
  StringRef getDescription() const final {
    return "Convert memory dialect operations to standard memref operations";
  }
  
  void runOnOperation() override {
    SmallVector<CreateMatrixOp, 4> createOps;
    SmallVector<SetElementOp, 4> setOps;  
    SmallVector<GetElementOp, 4> getOps;
    SmallVector<PrintMatrixOp, 4> printOps;
    
    getOperation().walk([&](Operation *op) {
      if (auto createOp = dyn_cast<CreateMatrixOp>(op))
        createOps.push_back(createOp);
      else if (auto setOp = dyn_cast<SetElementOp>(op))
        setOps.push_back(setOp);
      else if (auto getOp = dyn_cast<GetElementOp>(op))
        getOps.push_back(getOp);
      else if (auto printOp = dyn_cast<PrintMatrixOp>(op))
        printOps.push_back(printOp);
    });
    
    // 转换 CreateMatrixOp -> memref.alloc
    for (auto op : createOps) {
      OpBuilder builder(op);
      
      auto resultType = op->getResult(0).getType().cast<MemRefType>();
      auto operands = op->getOperands();
      
      auto allocOp = builder.create<memref::AllocOp>(
          op.getLoc(), resultType, operands);
      
      op->getResult(0).replaceAllUsesWith(allocOp.getResult());
      op->erase();
      
      llvm::outs() << "Converted memory.create_matrix to memref.alloc\n";
    }
    
    // 转换 SetElementOp -> memref.store
    for (auto op : setOps) {
      OpBuilder builder(op);
      auto operands = op->getOperands();
      
      Value memref = operands[0];
      Value i = operands[1]; 
      Value j = operands[2];
      Value value = operands[3];
      
      builder.create<memref::StoreOp>(
          op.getLoc(), value, memref, ValueRange{i, j});
      
      op->erase();
      llvm::outs() << "Converted memory.set to memref.store\n";
    }
    
    // 转换 GetElementOp -> memref.load
    for (auto op : getOps) {
      OpBuilder builder(op);
      auto operands = op->getOperands();
      
      Value memref = operands[0];
      Value i = operands[1];
      Value j = operands[2];
      
      auto loadOp = builder.create<memref::LoadOp>(
          op.getLoc(), memref, ValueRange{i, j});
      
      op->getResult(0).replaceAllUsesWith(loadOp.getResult());
      op->erase();
      
      llvm::outs() << "Converted memory.get to memref.load\n";
    }
    
    // 删除 PrintMatrixOp
    for (auto op : printOps) {
      llvm::outs() << "Removed memory.print (debug operation)\n";
      op->erase();
    }
  }
};

} // namespace

std::unique_ptr<Pass> createMemoryToMemRefPass() {
  return std::make_unique<MemoryToMemRefPass>();
}

} // namespace memory
```

### memory-opt.cpp

```cpp
#include "MemoryDialect.h"
#include "MemoryPass.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arithmetic/IR/Arithmetic.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Pass/PassRegistry.h"

int main(int argc, char **argv) {
  mlir::DialectRegistry registry;
  
  // 标准 Dialect
  registry.insert<mlir::func::FuncDialect>();
  registry.insert<mlir::arith::ArithmeticDialect>();
  registry.insert<mlir::memref::MemRefDialect>();
  
  // 自定义 Dialect
  registry.insert<memory::MemoryDialect>();
  
  // 注册自定义 Pass
  mlir::registerPass([]() -> std::unique_ptr<mlir::Pass> {
    return memory::createMemoryToMemRefPass();
  });
  
  return mlir::asMainReturnCode(
      mlir::MlirOptMain(argc, argv, "Memory dialect test tool\n", registry));
}
```

### 测试文件 (test-memory.mlir)

```mlir
// Memory Dialect 功能测试
module {
  func.func @matrix_demo() {
    // 创建一个2x3的矩阵
    %c2 = arith.constant 2 : index
    %c3 = arith.constant 3 : index
    %matrix = memory.create_matrix %c2, %c3 : memref<?x?xf32>
    
    // 定义索引和值
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %val1 = arith.constant 1.5 : f32
    %val2 = arith.constant 2.5 : f32
    %val3 = arith.constant 3.5 : f32
    
    // 设置矩阵元素
    memory.set %matrix[%c0, %c0] = %val1 : memref<?x?xf32>
    memory.set %matrix[%c0, %c1] = %val2 : memref<?x?xf32>
    memory.set %matrix[%c1, %c0] = %val3 : memref<?x?xf32>
    
    // 读取矩阵元素
    %read1 = memory.get %matrix[%c0, %c0] : memref<?x?xf32>
    %read2 = memory.get %matrix[%c0, %c1] : memref<?x?xf32>
    %read3 = memory.get %matrix[%c1, %c0] : memref<?x?xf32>
    
    // 打印矩阵（调试用）
    memory.print %matrix : memref<?x?xf32>
    
    return
  }
  
  func.func @matrix_computation() -> f32 {
    // 演示矩阵计算场景
    %c2 = arith.constant 2 : index
    %mat = memory.create_matrix %c2, %c2 : memref<?x?xf32>
    
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %v1 = arith.constant 10.0 : f32
    %v2 = arith.constant 20.0 : f32
    
    // 设置对角线元素
    memory.set %mat[%c0, %c0] = %v1 : memref<?x?xf32>
    memory.set %mat[%c1, %c1] = %v2 : memref<?x?xf32>
    
    // 读取并计算
    %a = memory.get %mat[%c0, %c0] : memref<?x?xf32>
    %b = memory.get %mat[%c1, %c1] : memref<?x?xf32>
    %sum = arith.addf %a, %b : f32
    
    return %sum : f32
  }
}
```

### 编译脚本 (compile-memory.sh)

```bash
#!/bin/bash

export LLVM_DIR=/usr/local/Cellar/llvm@15/15.0.7

echo "编译 memory-opt 工具..."

# 获取所有 MLIR 库
ALL_MLIR_LIBS=$(find "$LLVM_DIR/lib" -name "libMLIR*.a" | tr '\n' ' ')

clang++ -std=c++17 \
  -I"$LLVM_DIR/include" \
  -L"$LLVM_DIR/lib" \
  -o memory-opt \
  MemoryDialect.cpp MemoryPass.cpp memory-opt.cpp \
  $ALL_MLIR_LIBS \
  -lLLVMCore \
  -lLLVMSupport \
  -lLLVMDemangle \
  -lncurses -lz -lpthread

if [ $? -eq 0 ]; then
    echo "✓ 编译成功！"
    echo "测试程序："
    ./memory-opt --help | head -3
else
    echo "✗ 编译失败"
fi
```