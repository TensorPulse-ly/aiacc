# Lab 6: MLIR `scf` Dialect 结构化控制流实验

## 实验目标

完成本实验后，你应能够：
1. **理解** `scf` Dialect 的核心作用，即在 MLIR 中表达结构化的控制流（循环和分支）
2. **掌握** `scf.for` 的基本语法，并用它实现一个求和循环
3. **掌握** `scf.if` 的基本语法，并用它实现条件分支逻辑
4. **学会** 如何将 `scf` 与 `arith` Dialect 结合，实现有意义的计算和逻辑判断
5. **理解** `scf.yield` 的用法，从控制流块中返回值
6. **掌握** MLIR 中类型转换（`i32` 与 `index` 类型间的转换）

## 前置条件

在开始本实验前，你应已掌握：
- MLIR 的基本语法和结构（SSA 变量、Op、Type）
- `builtin` Dialect 的核心概念（`module`, `func.func`）
- `arith` Dialect 的基本操作：`arith.constant`、`arith.addi`、`arith.subi`、`arith.cmpi`
- 基本的命令行编译和运行技能

## 理论背景

### `scf` Dialect 简介

`scf`（Structured Control Flow）Dialect 是 MLIR 的结构化控制流方言，提供了高级的控制流操作：

| 操作 | 功能 | 基本语法 |
|------|------|----------|
| `scf.for` | 计数循环 | `scf.for %i = %start to %end step %step { ... }` |
| `scf.if` | 条件分支 | `scf.if %condition { ... } else { ... }` |
| `scf.yield` | 返回值 | `scf.yield %value : type` |

### 关键概念

1. **循环变量类型**：`scf.for` 中的循环变量必须是 `index` 类型
2. **iter_args**：循环迭代参数，用于在循环过程中传递和更新值
3. **条件返回值**：`scf.if` 可以返回值，需要在 `then` 和 `else` 块中都使用 `scf.yield`
4. **类型转换**：经常需要在 `i32` 和 `index` 类型之间转换

## 任务一：实现求和循环 (`scf.for`)

### 目标
使用 `scf.for` 实现一个求和函数，计算从 1 到 n 的所有整数的和（即实现数学公式：1 + 2 + 3 + ... + n）。

### 分析需求
你需要实现一个函数 `@sum_loop_example`，它：
- 接受一个 `i32` 类型的参数 `%n`
- 返回一个 `i32` 类型的结果
- 计算从 1 到 n 的累加和

### 设计思路

**步骤1：理解类型约束**
- 思考：为什么 `scf.for` 的循环变量必须是 `index` 类型？
- 你需要哪些类型转换操作？

**步骤2：设计循环结构**
- 循环应该从哪里开始？到哪里结束？
- 如何在循环中维护累加和？
- 什么是 `iter_args`？它如何工作？

**步骤3：编写代码框架**
尝试填写以下框架：

```mlir
module {
  func.func @sum_loop_example(%n: i32) -> i32 {
    // 1. 类型转换：将 %n 从 i32 转换为 index 类型
    %n_idx = arith._____ %n : i32 to _____
    
    // 2. 定义所需常量
    %c0_i32 = arith.constant __ : i32      // 初始和值是多少？
    %c1_idx = arith.constant __ : index    // 循环步长和起始值是多少？
    
    // 3. 计算循环上界（提示：从1到n+1，不包含上界）
    %n_plus_1_idx = arith._____ %n_idx, %c1_idx : index
    
    // 4. 编写 for 循环
    %final_sum = scf.for %i = _____ to _____ step _____
        iter_args(______ = ______) -> (i32) {
        
        // 5. 循环体：进行累加计算
        // 提示：需要将 %i 转换回 i32 类型
        
        scf.yield _____ : i32
    }
    
    return %final_sum : i32
  }
}
```

### 思考题
1. 为什么需要计算 `%n_plus_1_idx` 作为循环上界？
2. `iter_args` 中的初始值应该是什么？
3. 循环体内部需要进行哪些计算？

## 任务二：实现条件分支 (`scf.if`)

### 目标
使用 `scf.if` 实现一个条件函数：
- 如果 `a < b`，返回 `a + b`
- 否则返回 `a - b`

### 分析需求
你需要实现一个函数 `@if_else_example`，它：
- 接受两个 `i32` 类型的参数 `%a` 和 `%b`
- 根据比较结果执行不同的计算
- 返回一个 `i32` 类型的结果

### 设计思路

**步骤1：创建比较条件**
- 使用什么操作来比较两个整数？
- 比较操作的结果是什么类型？

**步骤2：设计分支结构**
- `scf.if` 如何返回值？
- 两个分支中都需要什么操作？

**步骤3：编写代码框架**
尝试填写以下框架：

```mlir
module {
  func.func @if_else_example(%a: i32, %b: i32) -> i32 {
    // 1. 创建比较条件：a < b
    %condition = arith._____ _____, %a, %b : i32
    
    // 2. 使用 scf.if 执行条件分支
    %result = scf.if %condition -> (_____) {
      // then 分支：计算 a + b
      %sum = arith._____ %a, %b : i32
      scf._____ %sum : i32
    } else {
      // else 分支：计算 a - b  
      %diff = arith._____ %a, %b : i32
      scf._____ %diff : i32
    }
    
    return %result : i32
  }
}
```

### 思考题
1. `arith.cmpi` 的 `slt` 参数表示什么意思？
2. 为什么 `scf.if` 需要指定 `-> (i32)`？
3. 如果忘记写 `scf.yield` 会发生什么？

## 实验步骤

### 步骤一：环境准备

```bash
# 创建实验目录
mkdir lab6-scf && cd lab6-scf

# 创建所需文件
touch sum_loop.mlir
touch if_else.mlir
```

### 步骤二：实现并测试求和循环

1. **编写** `sum_loop.mlir`，按照任务一的指导完成代码
2. **验证语法**：
   ```bash
   mlir-opt sum_loop.mlir
   ```
3. **编译和测试**：
   ```bash
   # 转换为 LLVM IR
   mlir-opt --convert-scf-to-cf --convert-arith-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts sum_loop.mlir | mlir-translate --mlir-to-llvmir > sum_loop.ll
   
   # 编译测试程序（测试程序见参考代码）
   clang++ -O0 sum_loop.ll test_sum_loop.cpp -o test_sum_loop
   
   # 运行测试
   ./test_sum_loop
   ```

### 步骤三：实现并测试条件分支

1. **编写** `if_else.mlir`，按照任务二的指导完成代码
2. **验证语法**：
   ```bash
   mlir-opt if_else.mlir
   ```
3. **编译和测试**：
   ```bash
   # 转换为 LLVM IR
   mlir-opt --convert-scf-to-cf --convert-arith-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts if_else.mlir | mlir-translate --mlir-to-llvmir > if_else.ll
   
   # 编译测试程序
   clang++ -O0 if_else.ll test_if_else.cpp -o test_if_else
   
   # 运行测试
   ./test_if_else
   ```

## 测试验证

### 求和循环测试

**期望结果**：
```
Testing sum_loop_example(10)
Result: 55
Expected: 55
Test PASSED!
```

**验证公式**：1 + 2 + ... + n = n(n+1)/2
- 对于 n=10：10×11/2 = 55

### 条件分支测试

**期望结果**：
```
if_else_example(5, 10) -> 15
Expected: 15
--------------------
if_else_example(20, 10) -> 10
Expected: 10
```

**验证逻辑**：
- 测试1：5 < 10 为真，返回 5 + 10 = 15
- 测试2：20 < 10 为假，返回 20 - 10 = 10

## 调试提示

### 常见编译错误

1. **类型不匹配错误**
   ```
   error: 'scf.for' op expects loop variable to be an index
   ```
   **解决**：检查循环变量是否为 `index` 类型

2. **操作数类型错误**
   ```
   error: operand type mismatch
   ```
   **解决**：检查是否需要类型转换

3. **缺少 yield 错误**
   ```
   error: expected 'scf.yield' at the end of the region
   ```
   **解决**：在分支或循环块末尾添加 `scf.yield`

### 调试方法

1. **逐步验证**：先写基本结构，再逐步添加细节
2. **类型检查**：确保每个操作的输入输出类型匹配
3. **语法验证**：频繁使用 `mlir-opt` 检查语法

## 常见问题

### Q1：为什么 `scf.for` 要求循环变量是 `index` 类型？
**A**：`index` 类型是 MLIR 专门为索引和循环设计的类型，可以适应不同目标平台的指针宽度。

### Q2：`iter_args` 的作用是什么？
**A**：`iter_args` 用于在循环迭代间传递状态。每次迭代开始时接收上次的值，结束时通过 `scf.yield` 传递给下次迭代。

### Q3：`scf.if` 什么时候需要返回值？
**A**：当你需要根据条件选择不同的值时。如果只是执行不同的副作用操作，可以不返回值。

### Q4：类型转换操作有哪些？
**A**：主要有 `arith.index_cast`（`i32` ↔ `index`）、`arith.extsi`（符号扩展）、`arith.trunci`（截断）等。

## 参考代码
# Lab 6: 参考代码

## 1. sum_loop.mlir - 求和循环实现
module {
  func.func @sum_loop_example(%n: i32) -> i32 {
    // ---- Type Conversion Section ----
    // Cast the input %n from i32 to index type for loop control.
    %n_idx = arith.index_cast %n : i32 to index
    
    // ---- Loop Constants (now using 'index' type) ----
    %c0_i32 = arith.constant 0 : i32 // For initializing the sum (i32)
    %c1_idx = arith.constant 1 : index // For loop step and bounds (index)
    
    // Calculate upper bound using index types
    %n_plus_1_idx = arith.addi %n_idx, %c1_idx : index
    
    // ---- The Loop (now correctly using 'index' types) ----
    // The loop variable %i is now of type 'index'.
    // The initial sum %sum_iter is correctly initialized from an i32 constant.
    %final_sum = scf.for %i = %c1_idx to %n_plus_1_idx step %c1_idx
        iter_args(%sum_iter = %c0_i32) -> (i32) {
      
      // ---- Calculation inside loop ----
      // Cast the loop variable %i from index back to i32 for the addition.
      %i_i32 = arith.index_cast %i : index to i32
      %next_sum = arith.addi %sum_iter, %i_i32 : i32
      scf.yield %next_sum : i32
    }
    
    return %final_sum : i32
  }
}

## 2. test_sum_loop.cpp - 求和循环测试
#include <iostream>

// 声明将在 MLIR 中定义的 C 函数
extern "C" {
    int sum_loop_example(int n);
}

int main() {
    // 测试用例：计算 1 到 10 的和
    int n = 10;
    int expected_sum = 55; // 1+2+...+10 = 55
    
    int result = sum_loop_example(n);
    
    std::cout << "Testing sum_loop_example(" << n << ")" << std::endl;
    std::cout << "Result: " << result << std::endl;
    std::cout << "Expected: " << expected_sum << std::endl;
    
    if (result == expected_sum) {
        std::cout << "Test PASSED!" << std::endl;
    } else {
        std::cout << "Test FAILED!" << std::endl;
    }
    
    return 0;
}

## 3. if_else.mlir - 条件分支实现
module {
  // 函数定义：接收两个 i32，返回一个 i32。
  // 如果 a < b, 返回 a + b
  // 否则, 返回 a - b
  func.func @if_else_example(%a: i32, %b: i32) -> i32 {
    // 1. 使用 `arith.cmpi` 创建条件。
    %condition = arith.cmpi slt, %a, %b : i32
    
    // 2. 使用 `scf.if` 执行条件分支并返回结果。
    %result = scf.if %condition -> (i32) {
      %sum = arith.addi %a, %b : i32
      scf.yield %sum : i32
    } else {
      %diff = arith.subi %a, %b : i32
      scf.yield %diff : i32
    }
    
    // 3. 返回由 `scf.if` 操作产生的结果。
    return %result : i32
  }
}

## 4. test_if_else.cpp - 条件分支测试
#include <iostream>

// 使用 extern "C" 来告诉 C++ 编译器，这个函数是用 C 语言的规则来链接的，
// 以防止 C++ 的名称修饰（name mangling）问题。
// 函数签名必须与 MLIR 中的函数完全匹配。
extern "C" {
    int if_else_example(int a, int b);
}

int main() {
    // 测试用例 1: 5 < 10, 应该返回 5 + 10 = 15
    int result1 = if_else_example(5, 10);
    std::cout << "if_else_example(5, 10) -> " << result1 << std::endl;
    std::cout << "Expected: 15" << std::endl;
    std::cout << "--------------------" << std::endl;
    
    // 测试用例 2: 20 > 10, 应该返回 20 - 10 = 10
    int result2 = if_else_example(20, 10);
    std::cout << "if_else_example(20, 10) -> " << result2 << std::endl;
    std::cout << "Expected: 10" << std::endl;
    
    return 0;
}

## 5. 编译脚本 compile.sh
#!/bin/bash

echo "=== Lab 6: SCF Dialect 编译脚本 ==="

# 编译求和循环
echo "编译求和循环..."
mlir-opt --convert-scf-to-cf --convert-arith-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts sum_loop.mlir | mlir-translate --mlir-to-llvmir > sum_loop.ll

if [ ! -f sum_loop.ll ]; then
    echo "✗ 求和循环 MLIR->LLVM 转换失败"
    exit 1
fi

clang++ -O0 sum_loop.ll test_sum_loop.cpp -o test_sum_loop

if [ $? -eq 0 ]; then
    echo "✓ 求和循环编译成功"
else
    echo "✗ 求和循环编译失败"
    exit 1
fi

# 编译条件分支
echo "编译条件分支..."
mlir-opt --convert-scf-to-cf --convert-arith-to-llvm --convert-func-to-llvm --reconcile-unrealized-casts if_else.mlir | mlir-translate --mlir-to-llvmir > if_else.ll

if [ ! -f if_else.ll ]; then
    echo "✗ 条件分支 MLIR->LLVM 转换失败"
    exit 1
fi

clang++ -O0 if_else.ll test_if_else.cpp -o test_if_else

if [ $? -eq 0 ]; then
    echo "✓ 条件分支编译成功"
else
    echo "✗ 条件分支编译失败"
    exit 1
fi

echo "=== 编译完成！==="

## 6. 测试脚本 test.sh
#!/bin/bash

echo "=== Lab 6: SCF Dialect 测试脚本 ==="

# 测试求和循环
echo "测试求和循环："
if [ -f test_sum_loop ]; then
    ./test_sum_loop
else
    echo "错误：test_sum_loop 可执行文件不存在，请先运行编译脚本"
fi
echo ""

# 测试条件分支
echo "测试条件分支："
if [ -f test_if_else ]; then
    ./test_if_else
else
    echo "错误：test_if_else 可执行文件不存在，请先运行编译脚本"
fi
echo ""

echo "=== 所有测试完成！==="