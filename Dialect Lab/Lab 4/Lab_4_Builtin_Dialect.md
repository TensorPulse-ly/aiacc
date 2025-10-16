# Lab 4 Builtin-Dialect: 掌握MLIR的"地基"

## 实验目标

通过本实验，你将学会：
- 深入理解builtin Dialect作为MLIR"地基"的核心作用
- 掌握`builtin.module`和`func.func`操作的使用方法
- 熟练运用builtin提供的基本标量类型和函数类型
- 学会构建完整的MLIR程序结构
- 理解builtin Dialect与其他Dialect的依赖关系
- 掌握用C++程序化构建MLIR结构的方法

## 前置条件

- 已成功完成Lab 1和Lab 2
- 理解MLIR的基本概念和SSA变量
- 熟悉`mlir-opt`等基本工具的使用
- 具备基本的C++编程知识

## 实验背景

builtin Dialect是MLIR的"地基"，就像盖房子时需要的砖头和水泥。它不是通过TableGen动态定义的，而是MLIR核心代码直接"硬编码"的基础设施。几乎所有的MLIR代码都离不开它，因为它定义了：

- 程序的顶层结构（`module`）
- 函数定义机制（`func.func`）  
- 基本数据类型（`i32`, `f32`等）
- 与其他Dialect协作的框架

## 实验内容

### 第一步：环境检查和设置

**任务说明：**
验证MLIR环境配置，为后续实验做准备。

**操作步骤：**
```bash
# 创建工作目录
mkdir builtin-lab && cd builtin-lab

# 检查MLIR环境
echo "LLVM_DIR: $LLVM_DIR"
mlir-opt --help | head -5
```

**验证要点：**
- LLVM_DIR环境变量已设置
- mlir-opt工具可正常运行
- 能够访问MLIR头文件和库

### 第二步：理解builtin.module的特殊性

**任务说明：**
通过对比实验，理解`module`作为顶层容器的必要性和唯一性。

**操作步骤：**
1. 创建`basic.mlir`，包含最简单的module结构
2. 创建`nested_module_test.mlir`，测试module嵌套（应该失败）
3. 创建`no_module_test.mlir`，测试缺少module的情况（应该失败）

**测试命令：**
```bash
mlir-opt basic.mlir --verify-diagnostics
mlir-opt nested_module_test.mlir  # 应该失败
mlir-opt no_module_test.mlir      # 应该失败
```

**思考问题：**

1. **为什么module不能嵌套？**
   
   **答案：** module在MLIR中被设计为顶层编译单元，类似于文件或编译模块的概念。允许嵌套会带来复杂的命名空间和符号解析问题，违背了MLIR"简单而强大"的设计理念。每个module代表一个独立的编译单元，有自己的符号表和优化边界。

2. **为什么所有MLIR代码都必须在module内？**
   
   **答案：** module提供了必要的上下文环境，包括符号管理、内存管理和编译单元边界。没有module，MLIR无法正确管理函数的可见性、进行符号解析，也无法为优化Pass提供明确的作用域。module是MLIR工具链（如mlir-opt）处理IR的基本单位。

3. **module与其他编程语言中的"文件"概念有什么相似之处？**
   
   **答案：** 
   - **作用域边界**：就像C++的源文件定义了编译单元边界，module定义了MLIR的编译单元
   - **符号管理**：类似于文件级别的全局变量和函数声明，module管理内部的符号表
   - **独立性**：就像文件可以独立编译，module可以独立优化和处理
   - **链接单位**：多个文件可以链接成程序，多个module可以组合成更大的系统

### 第三步：探索func.func的功能

**任务说明：**
学习函数定义的各种形式，理解SSA变量和类型系统。

**操作步骤：**
1. 创建`functions.mlir`，包含不同类型的函数定义
2. 测试无参数函数、单参数函数、多参数多返回值函数
3. 验证函数签名的正确性

**测试命令：**
```bash
mlir-opt functions.mlir --verify-diagnostics
```

**分析要点：**
- 函数名用`@`前缀
- 参数用`%arg0`、`%arg1`等SSA变量表示
- 返回类型必须与return语句匹配
- 支持多参数和多返回值

### 第四步：掌握builtin类型系统

**任务说明：**
实践builtin提供的基本标量类型，理解类型在MLIR中的作用。

**操作步骤：**
1. 创建`types.mlir`，测试各种基本类型
2. 包含整数类型（i1, i32, i64）和浮点类型（f32, f64）
3. 测试函数类型的表示方法

**测试命令：**
```bash
mlir-opt types.mlir --verify-diagnostics
```

**关键理解：**
- builtin提供基础类型，其他Dialect复用这些类型
- 函数类型用`(input_types) -> return_types`表示
- 类型信息在整个IR中保持一致性

### 第五步：构建完整的MLIR程序

**任务说明：**
结合builtin和其他Dialect，构建一个完整的加法函数。

**操作步骤：**
1. 创建`complete_program.mlir`，实现加法功能
2. 观察builtin如何与arith Dialect协作
3. 分析程序的层次结构

**测试命令：**
```bash
mlir-opt complete_program.mlir --verify-diagnostics
```

**结构分析：**
- `module { ... }`：builtin.module作为容器
- `func.func @add(...)`：builtin提供函数框架
- `%arg0: f32`：builtin提供类型系统
- `arith.addf`：在builtin框架内使用其他Dialect

### 第六步：理解Dialect协作关系

**任务说明：**
创建复杂示例，展示builtin如何为其他Dialect提供基础设施。

**操作步骤：**
1. 创建`dialect_integration.mlir`，混合使用多个Dialect
2. 观察所有操作都在builtin提供的framework内执行
3. 理解"builtin提供骨架，其他Dialect提供血肉"

**测试命令：**
```bash
mlir-opt dialect_integration.mlir --verify-diagnostics
```

**重点观察：**
- 所有操作都在`module`和`func.func`框架内
- `i32`等类型被多个Dialect共享
- builtin作为"地基"的支撑作用

### 第七步：探索类型转换机制

**任务说明：**
了解`builtin.unrealized_conversion_cast`的特殊用途。

**操作步骤：**
1. 创建`conversion_test.mlir`，使用类型转换操作
2. 理解这是"幕后魔法"，主要用于Pass开发
3. 认识到这是高级特性，初学者可以先了解概念

**测试命令：**
```bash
mlir-opt conversion_test.mlir --verify-diagnostics
```

### 第八步：程序化构建MLIR结构

**任务说明：**
学会用C++代码动态创建builtin结构，深入理解其工作机制。

**操作步骤：**
1. 创建`builtin-builder.cpp`，程序化构建MLIR模块
2. 理解OpBuilder、MLIRContext等核心类
3. 学会创建模块、函数、操作的完整流程

**编译命令：**
```bash
# 检查环境（如果LLVM_DIR未设置，需要先设置）
echo "LLVM_DIR: $LLVM_DIR"

# 编译程序
clang++ -std=c++17 \
  -I$LLVM_DIR/include \
  -L$LLVM_DIR/lib \
  $(ls $LLVM_DIR/lib/libMLIR*.a | grep -E "(IR|Func|Arith|Support)" | tr '\n' ' ') \
  -lLLVMSupport -lLLVMCore -lLLVMDemangle \
  -lncurses -lz -lpthread \
  builtin-builder.cpp -o builtin-builder
```

**运行测试：**
```bash
./builtin-builder
./builtin-builder > generated.mlir
mlir-opt generated.mlir --verify-diagnostics
```

### 第九步：综合验证和分析

**任务说明：**
创建最终测试，验证对builtin Dialect的全面理解。

**操作步骤：**
1. 创建`final_test.mlir`，展示所有学到的概念
2. 运行完整的测试序列
3. 分析builtin在整个MLIR生态中的地位

**测试命令：**
```bash
mlir-opt final_test.mlir --verify-diagnostics
```

### 第十步：实验总结

**任务说明：**
总结builtin Dialect的核心特性和设计哲学。

**总结要点：**
1. **builtin的特殊地位**：硬编码的"地基"，而非TableGen定义
2. **module的作用**：顶层容器，不可嵌套，必不可少
3. **func.func的功能**：函数定义框架，支持复杂签名
4. **类型系统**：基础标量类型，被所有Dialect共享
5. **协作机制**：为其他Dialect提供基础设施框架
6. **程序化构建**：通过C++ API动态创建IR结构

**深入思考：**

1. **为什么MLIR选择将builtin硬编码而不是用TableGen？**
   
   **答案：** builtin是所有其他Dialect的基础，需要在MLIR系统启动时就存在。如果用TableGen定义，会产生循环依赖问题——TableGen本身需要基础类型和操作才能工作。硬编码确保了系统的bootstrapping能够顺利进行，也保证了核心功能的稳定性和性能。

2. **builtin Dialect的设计如何体现了MLIR的可扩展性？**
   
   **答案：** builtin提供了最小但完备的基础设施集合，包括基本类型、函数框架和模块结构，但不包含任何特定领域的操作。这种设计让其他Dialect可以在稳定的基础上自由扩展，而不会相互冲突。所有Dialect都"平等"地使用builtin提供的服务，体现了MLIR的模块化和可组合性。

3. **程序化IR构建在实际应用中有什么价值？**
   
   **答案：** 
   - **编译器前端开发**：可以将高级语言（如Python、Julia）直接转换为MLIR
   - **代码生成**：在运行时动态生成优化的计算代码
   - **DSL实现**：为特定领域语言提供后端支持
   - **自动优化**：基于Profile信息动态生成优化版本
   - **调试和测试**：程序化生成测试用例和基准程序

## 预期学习成果

完成本实验后，你应该能够：

1. **深刻理解builtin Dialect的核心作用**：认识到它是MLIR的基础设施
2. **熟练使用module和func.func**：掌握MLIR程序的基本结构
3. **理解类型系统设计**：明白builtin如何为整个生态提供类型基础
4. **掌握Dialect协作机制**：理解builtin如何支撑其他Dialect
5. **具备程序化构建能力**：能用C++动态创建复杂的MLIR结构
6. **培养系统性思维**：理解MLIR架构的分层设计理念

## 常见问题解答

**Q: 编译时出现头文件未找到错误？**
A: 检查LLVM_DIR设置，确保指向正确的LLVM安装目录，包含include/mlir子目录。

**Q: 链接时出现符号未定义错误？**
A: 确保链接了必要的MLIR库，特别是IR、Support、Func等核心库。

**Q: 为什么某些测试故意失败？**
A: 这些测试用于验证MLIR的错误检测机制，比如module嵌套检查。

**Q: 程序化构建的意义是什么？**
A: 它让你理解MLIR的内部工作机制，为开发编译器前端或优化Pass打基础。

---

## Reference Code (参考代码)

### basic.mlir
```mlir
module {
  func.func @simple() {
    return
  }
}
```

### nested_module_test.mlir
```mlir
module {
  module {
    func.func @inner() {
      return
    }
  }
}
```

### no_module_test.mlir
```mlir
func.func @orphan() {
  return
}
```

### functions.mlir
```mlir
module {
  // 无参数，无返回值
  func.func @no_params() {
    return
  }
  
  // 单参数，单返回值
  func.func @single_param(%arg0: i32) -> i32 {
    return %arg0 : i32
  }
  
  // 多参数，多返回值
  func.func @multi_params(%arg0: f32, %arg1: f32) -> (f32, f32) {
    return %arg0, %arg1 : f32, f32
  }
  
  // 复杂类型参数
  func.func @complex_types(%arg0: i64, %arg1: f64) -> f64 {
    return %arg1 : f64
  }
}
```

### types.mlir
```mlir
module {
  // 测试各种整数类型
  func.func @integer_types() -> (i1, i32, i64) {
    %bool = arith.constant true : i1
    %int32 = arith.constant 42 : i32
    %int64 = arith.constant 1000 : i64
    return %bool, %int32, %int64 : i1, i32, i64
  }
  
  // 测试各种浮点类型
  func.func @float_types() -> (f32, f64) {
    %float32 = arith.constant 3.14 : f32
    %float64 = arith.constant 2.718 : f64
    return %float32, %float64 : f32, f64
  }
  
  // 测试函数类型的表示
  func.func @function_types(%arg0: (i32, i32) -> i32) -> (i32, i32) -> i32 {
    return %arg0 : (i32, i32) -> i32
  }
}
```

### complete_program.mlir
```mlir
module {
  func.func @add(%arg0: f32, %arg1: f32) -> f32 {
    %sum = arith.addf %arg0, %arg1 : f32
    return %sum : f32
  }
}
```

### dialect_integration.mlir
```mlir
module {
  func.func @mixed_operations(%arg0: i32, %arg1: i32) -> i32 {
    %c10 = arith.constant 10 : i32
    %sum = arith.addi %arg0, %arg1 : i32
    %cond = arith.cmpi slt, %sum, %c10 : i32
    
    scf.if %cond {
      %result = arith.muli %sum, %c10 : i32
    } else {
      %result = arith.subi %sum, %c10 : i32
    }
    
    return %sum : i32
  }
}
```

### conversion_test.mlir
```mlir
module {
  func.func @type_conversion(%arg0: i32) -> f32 {
    %converted = builtin.unrealized_conversion_cast %arg0 : i32 to f32
    return %converted : f32
  }
}
```

### final_test.mlir
```mlir
module {
  // 展示builtin提供的基础结构
  func.func @demo(%input1: i32, %input2: f32) -> (i32, f32, i1) {
    // builtin类型的使用
    %const_int = arith.constant 100 : i32
    %const_float = arith.constant 3.14 : f32
    
    // 在builtin框架内使用其他dialect
    %sum_int = arith.addi %input1, %const_int : i32
    %sum_float = arith.addf %input2, %const_float : f32
    %comparison = arith.cmpi sgt, %sum_int, %const_int : i32
    
    // builtin的return操作
    return %sum_int, %sum_float, %comparison : i32, f32, i1
  }
}
```

### builtin-builder.cpp
```cpp
#include "mlir/IR/Builders.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arithmetic/IR/Arithmetic.h"  // LLVM 15中是Arithmetic
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

int main() {
    // 创建MLIR上下文
    MLIRContext context;
    context.getOrLoadDialect<func::FuncDialect>();
    context.getOrLoadDialect<arith::ArithmeticDialect>();
    
    // 创建模块
    OpBuilder builder(&context);
    auto module = ModuleOp::create(builder.getUnknownLoc());
    
    // 在模块内创建函数
    builder.setInsertionPointToEnd(module.getBody());
    
    // 定义函数类型：(f32, f32) -> f32
    auto funcType = builder.getFunctionType({builder.getF32Type(), builder.getF32Type()}, 
                                           builder.getF32Type());
    
    // 创建函数
    auto func = builder.create<func::FuncOp>(builder.getUnknownLoc(), "add", funcType);
    
    // 创建函数体
    Block* entryBlock = func.addEntryBlock();
    builder.setInsertionPointToStart(entryBlock);
    
    // 获取参数
    auto arg0 = entryBlock->getArgument(0);
    auto arg1 = entryBlock->getArgument(1);
    
    // 创建加法操作
    auto sum = builder.create<arith::AddFOp>(builder.getUnknownLoc(), arg0, arg1);
    
    // 创建返回操作
    builder.create<func::ReturnOp>(builder.getUnknownLoc(), sum.getResult());
    
    // 打印生成的IR
    module.print(llvm::outs());
    
    return 0;
}
```