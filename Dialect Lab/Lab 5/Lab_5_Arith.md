# Lab 5: MLIR arith Dialect

## 实验目标

通过本实验，你将：
- 掌握 MLIR arith Dialect 的核心操作：常量定义、基础运算、比较操作
- 深入理解 MLIR 类型系统：整数与浮点数的区别和使用场景
- 熟练运用 SSA 形式：理解值的单次赋值和数据流传递
- 学会构建条件逻辑：结合 scf 实现复杂的分支结构
- 验证执行结果：通过 C++ 程序验证 MLIR 逻辑的正确性

## 前置知识

- 已完成 Lab 1 和 Lab 2，熟悉 MLIR 基本概念
- 理解 SSA (Static Single Assignment) 形式
- 具备基本的 C++ 编程知识
- 了解基本的数据类型和运算概念

## 实验环境要求

- LLVM/MLIR 工具链（版本 15 或更高）
- C++ 编译器（g++ 或 clang++）
- 能够运行 `mlir-opt` 命令

---

## Step 1: 基础 arith 操作

### 任务描述
学习 arith Dialect 的核心操作，包括常量定义和基础四则运算。

### 学习要点
1. **常量定义**：使用 `arith.constant` 定义编译时常量
2. **整数运算**：`arith.addi`, `arith.subi`, `arith.muli`, `arith.divsi`
3. **浮点运算**：`arith.addf`, `arith.subf`, `arith.mulf`, `arith.divf`
4. **基础比较**：`arith.cmpi`, `arith.cmpf`

### 实验任务
1. 创建 `step1_basic_arith.mlir` 文件
2. 实现 `basic_arithmetic` 函数，计算两个整数的四则运算
3. 实现 `constant_types` 函数，展示不同数据类型的常量定义
4. 使用 `mlir-opt` 验证语法正确性
5. 编译运行对应的 C++ 验证程序

### 思考题
1. **Q1**: `arith.addi` 和 `arith.addf` 的区别是什么？
   **A1**: `arith.addi` 用于整数加法，`arith.addf` 用于浮点数加法。MLIR 严格区分整数和浮点数操作。

2. **Q2**: 为什么 MLIR 中的类型标注如此重要？
   **A2**: MLIR 具有严格的类型安全，所有操作的输入输出类型必须明确指定，这有助于编译器进行优化和错误检测。

3. **Q3**: 在 MLIR 中，常量 `42 : i32` 和 `42 : i64` 有什么区别？
   **A3**: 前者是 32 位整数，后者是 64 位整数。它们占用不同的内存空间，数值范围也不同。

---

## Step 2: SSA 形式和数据流

### 任务描述
通过构建复杂的数学表达式，理解 SSA 约束和数据依赖关系。

### 学习要点
1. **SSA 约束**：每个变量只能赋值一次
2. **数据依赖**：操作之间的先后关系
3. **并行性**：无依赖操作可以并行执行
4. **复杂表达式**：如何分解复杂计算

### 实验任务
1. 创建 `step2_ssa_dataflow.mlir` 文件
2. 实现复杂表达式 `(a + b) * (c - d) / e` 的计算
3. 分析哪些操作可以并行执行
4. 演示 SSA 变量命名规则
5. 绘制数据流依赖图

### 思考题
1. **Q1**: 在表达式 `(a + b) * (c - d) / e` 中，哪些操作可以并行执行？
   **A1**: `(a + b)` 和 `(c - d)` 可以并行执行，因为它们之间没有数据依赖关系。

2. **Q2**: 为什么不能写 `%x = arith.addi %x, %x : i32`？
   **A2**: 这违反了 SSA 形式的基本约束：每个变量只能被赋值一次。应该使用新的变量名，如 `%y = arith.addi %x, %x : i32`。

3. **Q3**: SSA 形式对编译器优化有什么好处？
   **A3**: SSA 形式简化了数据流分析，消除了变量别名问题，使编译器更容易进行优化，如常量传播、死代码消除等。

---

## Step 3: 类型系统

### 任务描述
深入理解 MLIR 的类型系统，学习不同数据类型的特性和限制。

### 学习要点
1. **整数类型**：`i8`, `i16`, `i32`, `i64` 的范围和特性
2. **浮点类型**：`f32`, `f64` 的精度差异
3. **类型安全**：相同类型才能进行运算
4. **溢出行为**：超出类型范围时的表现

### 实验任务
1. 创建 `step3_type_system.mlir` 文件
2. 演示不同整数类型的数值范围
3. 比较单精度和双精度浮点数的精度差异
4. 展示类型安全检查
5. 观察整数溢出和下溢现象

### 思考题
1. **Q1**: `i8` 类型能表示的数值范围是多少？
   **A1**: `i8` 可以表示 -128 到 127 的整数（8 位有符号整数）。

2. **Q2**: 为什么 `127 + 1` 在 `i8` 类型中等于 `-128`？
   **A2**: 这是整数溢出现象。`i8` 使用补码表示，当超过最大值时会回绕到最小值。

3. **Q3**: `f32` 和 `f64` 在精度上有什么区别？
   **A3**: `f32` 是单精度浮点数，约有 7 位有效数字；`f64` 是双精度浮点数，约有 15 位有效数字。

---

## Step 4: 比较操作和条件逻辑

### 任务描述
掌握所有比较操作的谓词，并结合 scf.if 实现条件分支逻辑。

### 学习要点
1. **整数比较谓词**：`eq`, `ne`, `slt`, `sle`, `sgt`, `sge`
2. **浮点比较谓词**：有序 vs 无序比较
3. **条件分支**：`scf.if` 的使用方法
4. **实用函数**：实现 max, min, abs, sign 等函数

### 实验任务
1. 创建 `step4_comparison_operations.mlir` 文件
2. 演示所有整数和浮点比较操作
3. 实现最大值函数
4. 实现绝对值函数
5. 实现符号函数（返回 -1, 0, 1）

### 思考题
1. **Q1**: `arith.cmpf olt` 和 `arith.cmpf ult` 的区别是什么？
   **A1**: `olt` 是有序小于比较，如果操作数包含 NaN 则返回 false；`ult` 是无序小于比较，如果操作数包含 NaN 则返回 true。

2. **Q2**: 为什么浮点比较需要区分有序和无序？
   **A2**: 因为浮点数有特殊值 NaN（Not a Number），有序比较会将 NaN 视为"不可比较"，无序比较会将包含 NaN 的比较视为 true。

3. **Q3**: `scf.if` 语句中的 `scf.yield` 有什么作用？
   **A3**: `scf.yield` 用于从 if 分支中返回值，类似于函数的 return 语句，但用于结构化控制流中。

---

## 综合练习

### 任务：实现一个完整的数学函数库

基于前面四个步骤学到的知识，实现以下函数：

1. **三元运算符**：`condition ? value1 : value2`
2. **范围检查函数**：将值限制在 `[min, max]` 范围内
3. **安全除法函数**：避免除零错误
4. **浮点数相等比较**：考虑精度误差的安全比较

### 验证方法

1. **语法验证**：使用 `mlir-opt` 检查语法
2. **逻辑验证**：运行对应的 C++ 程序验证结果
3. **错误测试**：故意制造错误，观察错误信息

---

## 学习总结

### 掌握的核心概念
- arith Dialect 的基本操作和语法
- MLIR 的严格类型系统
- SSA 形式的约束和优势
- 数据流分析和并行性
- 条件逻辑的实现方法

### 常见错误及避免方法
- **类型不匹配**：确保操作数类型一致
- **SSA 违规**：不要重复定义同一个变量
- **语法错误**：注意冒号、括号、类型标注的位置

### 扩展学习建议
- 尝试实现更复杂的数学算法
- 研究编译器优化对 arith 操作的影响
- 学习其他 MLIR Dialect（tensor, linalg, memref）

---

## Reference Code

### step1_basic_arith.mlir
```mlir
// step1_basic_arith.mlir
module {
  // 演示基础的四则运算
  func.func @basic_arithmetic() -> (i32, f32) {
    // 1. 整数常量定义
    %a = arith.constant 10 : i32
    %b = arith.constant 3 : i32
    
    // 2. 整数基础运算
    %sum = arith.addi %a, %b : i32        // 10 + 3 = 13
    %diff = arith.subi %a, %b : i32       // 10 - 3 = 7
    %prod = arith.muli %a, %b : i32       // 10 * 3 = 30
    %quot = arith.divsi %a, %b : i32      // 10 / 3 = 3
    
    // 3. 浮点数常量和运算
    %fa = arith.constant 10.5 : f32
    %fb = arith.constant 3.2 : f32
    %fsum = arith.addf %fa, %fb : f32     // 10.5 + 3.2 = 13.7
    
    // 4. 简单比较
    %cmp = arith.cmpi sgt, %sum, %diff : i32  // 13 > 7 = true
    
    return %sum, %fsum : i32, f32
  }
  
  // 演示常量的不同类型
  func.func @constant_types() -> (i8, i32, i64, f32, f64) {
    %small_int = arith.constant 42 : i8
    %normal_int = arith.constant 1000 : i32
    %big_int = arith.constant 1000000 : i64
    %float_val = arith.constant 3.14 : f32
    %double_val = arith.constant 2.718281828 : f64
    
    return %small_int, %normal_int, %big_int, %float_val, %double_val : i8, i32, i64, f32, f64
  }
}
```

### step2_ssa_dataflow.mlir
```mlir
// step2_ssa_dataflow.mlir
module {
  // 复杂表达式：计算 (a + b) * (c - d) / e
  func.func @complex_expression() -> i32 {
    // 定义输入常量
    %a = arith.constant 10 : i32
    %b = arith.constant 20 : i32
    %c = arith.constant 50 : i32
    %d = arith.constant 30 : i32
    %e = arith.constant 4 : i32
    
    // 第一层：并行计算（无依赖关系）
    %sum_ab = arith.addi %a, %b : i32      // %sum_ab = 30
    %diff_cd = arith.subi %c, %d : i32     // %diff_cd = 20
    
    // 第二层：依赖第一层的结果
    %product = arith.muli %sum_ab, %diff_cd : i32  // %product = 600
    
    // 第三层：依赖第二层的结果
    %result = arith.divsi %product, %e : i32       // %result = 150
    
    return %result : i32
  }
  
  // 演示数据流依赖分析
  func.func @dependency_demo() -> (i32, i32, i32) {
    %x = arith.constant 5 : i32
    %y = arith.constant 3 : i32
    
    // 这两个操作可以并行执行（无依赖）
    %result1 = arith.addi %x, %y : i32     // 5 + 3 = 8
    %result2 = arith.muli %x, %y : i32     // 5 * 3 = 15
    
    // 这个操作依赖于前两个结果（串行）
    %result3 = arith.addi %result1, %result2 : i32  // 8 + 15 = 23
    
    return %result1, %result2, %result3 : i32, i32, i32
  }
  
  // 演示SSA约束：每个变量只能赋值一次
  func.func @ssa_constraint_demo() -> i32 {
    %x = arith.constant 10 : i32    // %x 第一次赋值
    %y = arith.addi %x, %x : i32    // 不能写成 %x = arith.addi %x, %x
    %z = arith.muli %y, %x : i32    // 使用之前定义的 %x 和 %y
    return %z : i32
  }
}
```

### step3_type_system.mlir
```mlir
// step3_type_system.mlir
module {
  // 演示不同整数类型的范围
  func.func @integer_ranges() -> (i8, i16, i32, i64) {
    // i8: -128 到 127
    %i8_max = arith.constant 127 : i8
    
    // i16: -32768 到 32767  
    %i16_max = arith.constant 32767 : i16
    
    // i32: -2^31 到 2^31-1
    %i32_max = arith.constant 2147483647 : i32
    
    // i64: -2^63 到 2^63-1
    %i64_big = arith.constant 1000000000000 : i64
    
    return %i8_max, %i16_max, %i32_max, %i64_big : i8, i16, i32, i64
  }
  
  // 演示浮点精度差异
  func.func @float_precision() -> (f32, f64) {
    // f32: 单精度，约7位有效数字
    %pi_f32 = arith.constant 3.141592653589793 : f32  // 会被截断
    
    // f64: 双精度，约15位有效数字
    %pi_f64 = arith.constant 3.141592653589793 : f64  // 保持完整精度
    
    return %pi_f32, %pi_f64 : f32, f64
  }
  
  // 演示类型安全：同类型才能运算
  func.func @type_safety() -> (i32, f32) {
    %a = arith.constant 10 : i32
    %b = arith.constant 20 : i32
    %int_result = arith.addi %a, %b : i32    // ✓ 正确：同为i32
    
    %fa = arith.constant 3.14 : f32
    %fb = arith.constant 2.71 : f32
    %float_result = arith.addf %fa, %fb : f32  // ✓ 正确：同为f32
    
    // ❌ 错误示例（会导致编译错误）：
    // %wrong = arith.addi %a, %fa : ???    // 类型不匹配！
    
    return %int_result, %float_result : i32, f32
  }
  
  // 演示溢出行为
  func.func @overflow_example() -> (i8, i8) {
    %max_i8 = arith.constant 127 : i8      // i8的最大值
    %one = arith.constant 1 : i8
    
    // 溢出：127 + 1 = -128 (在i8中)
    %overflow_result = arith.addi %max_i8, %one : i8
    
    %min_i8 = arith.constant -128 : i8     // i8的最小值
    %underflow_result = arith.subi %min_i8, %one : i8  // -128 - 1 = 127
    
    return %overflow_result, %underflow_result : i8, i8
  }
}
```

### step4_comparison_operations.mlir
```mlir
// step4_comparison_operations.mlir
module {
  // 演示所有整数比较操作
  func.func @integer_comparisons() -> (i1, i1, i1, i1, i1, i1) {
    %a = arith.constant 10 : i32
    %b = arith.constant 20 : i32
    
    // 相等性比较
    %eq = arith.cmpi eq, %a, %b : i32    // equal: 10 == 20 = false
    %ne = arith.cmpi ne, %a, %b : i32    // not equal: 10 != 20 = true
    
    // 有符号比较
    %slt = arith.cmpi slt, %a, %b : i32  // signed less than: 10 < 20 = true
    %sle = arith.cmpi sle, %a, %b : i32  // signed less equal: 10 <= 20 = true
    %sgt = arith.cmpi sgt, %a, %b : i32  // signed greater than: 10 > 20 = false
    %sge = arith.cmpi sge, %a, %b : i32  // signed greater equal: 10 >= 20 = false
    
    return %eq, %ne, %slt, %sle, %sgt, %sge : i1, i1, i1, i1, i1, i1
  }
  
  // 演示浮点比较（重点是有序vs无序）
  func.func @float_comparisons() -> (i1, i1, i1, i1) {
    %a = arith.constant 3.14 : f32
    %b = arith.constant 2.71 : f32
    
    // 有序比较（如果有NaN，结果为false）
    %oeq = arith.cmpf oeq, %a, %b : f32  // ordered equal: 3.14 == 2.71 = false
    %olt = arith.cmpf olt, %a, %b : f32  // ordered less than: 3.14 < 2.71 = false
    %ogt = arith.cmpf ogt, %a, %b : f32  // ordered greater than: 3.14 > 2.71 = true
    
    // 无序比较（如果有NaN，结果为true）
    %une = arith.cmpf une, %a, %b : f32  // unordered not equal: 3.14 != 2.71 = true
    
    return %oeq, %olt, %ogt, %une : i1, i1, i1, i1
  }
  
  // 实现实用的比较函数：最大值
  func.func @max_function() -> i32 {
    %a = arith.constant 42 : i32
    %b = arith.constant 24 : i32
    
    %cmp = arith.cmpi sgt, %a, %b : i32  // 42 > 24 = true
    %max = scf.if %cmp -> (i32) {
      scf.yield %a : i32  // 返回42
    } else {
      scf.yield %b : i32  // 不会执行
    }
    
    return %max : i32  // 返回42
  }
  
  // 实现绝对值函数
  func.func @abs_function() -> i32 {
    %x = arith.constant -15 : i32
    %zero = arith.constant 0 : i32
    
    %is_negative = arith.cmpi slt, %x, %zero : i32  // -15 < 0 = true
    %abs_result = scf.if %is_negative -> (i32) {
      %neg_x = arith.subi %zero, %x : i32  // 0 - (-15) = 15
      scf.yield %neg_x : i32
    } else {
      scf.yield %x : i32  // 不会执行
    }
    
    return %abs_result : i32  // 返回15
  }
  
  // 演示条件嵌套：符号函数
  func.func @sign_function() -> i32 {
    %x = arith.constant 25 : i32
    %zero = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %neg_one = arith.constant -1 : i32
    
    %is_positive = arith.cmpi sgt, %x, %zero : i32  // 25 > 0 = true
    %result = scf.if %is_positive -> (i32) {
      scf.yield %one : i32  // 返回1
    } else {
      %is_zero = arith.cmpi eq, %x, %zero : i32
      %inner_result = scf.if %is_zero -> (i32) {
        scf.yield %zero : i32  // 返回0
      } else {
        scf.yield %neg_one : i32  // 返回-1
      }
      scf.yield %inner_result : i32
    }
    
    return %result : i32  // 返回1
  }
}
```

### C++ 验证程序

#### verify_step1.cpp
```cpp
// verify_step1.cpp - 验证第一步：基础arith操作
#include <iostream>
#include <iomanip>

int main() {
    std::cout << "=== Step 1: 基础arith操作验证 ===" << std::endl;
    std::cout << std::fixed << std::setprecision(2);
    
    // 对应 basic_arithmetic 函数
    std::cout << "\n--- basic_arithmetic 函数验证 ---" << std::endl;
    
    // 1. 整数常量定义和运算
    int a = 10, b = 3;
    int sum = a + b;        // 对应 arith.addi
    int diff = a - b;       // 对应 arith.subi
    int prod = a * b;       // 对应 arith.muli
    int quot = a / b;       // 对应 arith.divsi
    
    std::cout << "整数运算：" << std::endl;
    std::cout << "  a = " << a << ", b = " << b << std::endl;
    std::cout << "  sum (a + b) = " << sum << " (期望: 13)" << std::endl;
    std::cout << "  diff (a - b) = " << diff << " (期望: 7)" << std::endl;
    std::cout << "  prod (a * b) = " << prod << " (期望: 30)" << std::endl;
    std::cout << "  quot (a / b) = " << quot << " (期望: 3)" << std::endl;
    
    // 2. 浮点数常量和运算
    float fa = 10.5f, fb = 3.2f;
    float fsum = fa + fb;   // 对应 arith.addf
    
    std::cout << "\n浮点运算：" << std::endl;
    std::cout << "  fa = " << fa << ", fb = " << fb << std::endl;
    std::cout << "  fsum (fa + fb) = " << fsum << " (期望: 13.70)" << std::endl;
    
    // 3. 简单比较
    bool cmp = sum > diff;  // 对应 arith.cmpi sgt
    std::cout << "\n比较运算：" << std::endl;
    std::cout << "  cmp (sum > diff) = " << (cmp ? "true" : "false") << " (期望: true)" << std::endl;
    
    // 对应 constant_types 函数
    std::cout << "\n--- constant_types 函数验证 ---" << std::endl;
    
    int8_t small_int = 42;              // i8
    int32_t normal_int = 1000;          // i32
    int64_t big_int = 1000000;          // i64
    float float_val = 3.14f;            // f32
    double double_val = 2.718281828;    // f64
    
    std::cout << "不同类型常量：" << std::endl;
    std::cout << "  small_int (i8) = " << (int)small_int << std::endl;
    std::cout << "  normal_int (i32) = " << normal_int << std::endl;
    std::cout << "  big_int (i64) = " << big_int << std::endl;
    std::cout << "  float_val (f32) = " << float_val << std::endl;
    std::cout << "  double_val (f64) = " << double_val << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    std::cout << "如果所有结果都符合期望，说明你对Step 1的理解是正确的！" << std::endl;
    
    return 0;
}
```

#### verify_step2.cpp
```cpp
// verify_step2.cpp - 验证第二步：SSA和数据流
#include <iostream>

int main() {
    std::cout << "=== Step 2: SSA和数据流验证 ===" << std::endl;
    
    // 对应 complex_expression 函数
    std::cout << "\n--- complex_expression 函数验证 ---" << std::endl;
    std::cout << "计算表达式: (a + b) * (c - d) / e" << std::endl;
    
    // 定义输入常量
    int a = 10, b = 20, c = 50, d = 30, e = 4;
    std::cout << "输入值: a=" << a << ", b=" << b << ", c=" << c << ", d=" << d << ", e=" << e << std::endl;
    
    // 第一层：并行计算（无依赖关系）
    int sum_ab = a + b;      // 对应 %sum_ab = arith.addi %a, %b
    int diff_cd = c - d;     // 对应 %diff_cd = arith.subi %c, %d
    
    std::cout << "\n第一层计算（可并行）：" << std::endl;
    std::cout << "  sum_ab = a + b = " << sum_ab << " (期望: 30)" << std::endl;
    std::cout << "  diff_cd = c - d = " << diff_cd << " (期望: 20)" << std::endl;
    
    // 第二层：依赖第一层的结果
    int product = sum_ab * diff_cd;  // 对应 %product = arith.muli %sum_ab, %diff_cd
    
    std::cout << "\n第二层计算（依赖第一层）：" << std::endl;
    std::cout << "  product = sum_ab * diff_cd = " << product << " (期望: 600)" << std::endl;
    
    // 第三层：依赖第二层的结果
    int result = product / e;        // 对应 %result = arith.divsi %product, %e
    
    std::cout << "\n第三层计算（依赖第二层）：" << std::endl;
    std::cout << "  result = product / e = " << result << " (期望: 150)" << std::endl;
    
    // 对应 dependency_demo 函数
    std::cout << "\n--- dependency_demo 函数验证 ---" << std::endl;
    
    int x = 5, y = 3;
    std::cout << "输入值: x=" << x << ", y=" << y << std::endl;
    
    // 这两个操作可以并行执行（无依赖）
    int result1 = x + y;     // 对应 arith.addi
    int result2 = x * y;     // 对应 arith.muli
    
    std::cout << "\n并行计算（无依赖）：" << std::endl;
    std::cout << "  result1 = x + y = " << result1 << " (期望: 8)" << std::endl;
    std::cout << "  result2 = x * y = " << result2 << " (期望: 15)" << std::endl;
    
    // 这个操作依赖于前两个结果（串行）
    int result3 = result1 + result2;  // 对应 arith.addi %result1, %result2
    
    std::cout << "\n串行计算（有依赖）：" << std::endl;
    std::cout << "  result3 = result1 + result2 = " << result3 << " (期望: 23)" << std::endl;
    
    // 对应 ssa_constraint_demo 函数
    std::cout << "\n--- ssa_constraint_demo 函数验证 ---" << std::endl;
    std::cout << "演示SSA约束：每个变量只能赋值一次" << std::endl;
    
    int x_val = 10;          // 对应 %x = arith.constant 10
    int y_val = x_val + x_val;  // 对应 %y = arith.addi %x, %x  (注意不能重新赋值给x)
    int z_val = y_val * x_val;  // 对应 %z = arith.muli %y, %x
    
    std::cout << "  x_val = " << x_val << std::endl;
    std::cout << "  y_val = x_val + x_val = " << y_val << " (期望: 20)" << std::endl;
    std::cout << "  z_val = y_val * x_val = " << z_val << " (期望: 200)" << std::endl;
    
    std::cout << "\n=== 数据流分析总结 ===" << std::endl;
    std::cout << "1. 第一层的 sum_ab 和 diff_cd 可以并行计算" << std::endl;
    std::cout << "2. 第二层的 product 必须等待第一层完成" << std::endl;
    std::cout << "3. 第三层的 result 必须等待第二层完成" << std::endl;
    std::cout << "4. SSA约束确保每个变量只赋值一次，避免数据竞争" << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    
    return 0;
}
```

#### verify_step3.cpp
```cpp
// verify_step3.cpp - 验证第三步：类型系统
#include <iostream>
#include <iomanip>
#include <limits>

int main() {
    std::cout << "=== Step 3: 类型系统验证 ===" << std::endl;
    
    // 对应 integer_ranges 函数
    std::cout << "\n--- integer_ranges 函数验证 ---" << std::endl;
    std::cout << "演示不同整数类型的范围：" << std::endl;
    
    // i8: -128 到 127
    int8_t i8_max = 127;    // 对应 arith.constant 127 : i8
    std::cout << "  i8_max = " << (int)i8_max << " (i8范围: -128 到 127)" << std::endl;
    
    // i16: -32768 到 32767
    int16_t i16_max = 32767;  // 对应 arith.constant 32767 : i16
    std::cout << "  i16_max = " << i16_max << " (i16范围: -32768 到 32767)" << std::endl;
    
    // i32: -2^31 到 2^31-1
    int32_t i32_max = 2147483647;  // 对应 arith.constant 2147483647 : i32
    std::cout << "  i32_max = " << i32_max << " (i32范围: -2^31 到 2^31-1)" << std::endl;
    
    // i64: -2^63 到 2^63-1
    int64_t i64_big = 1000000000000LL;  // 对应 arith.constant 1000000000000 : i64
    std::cout << "  i64_big = " << i64_big << " (i64范围: -2^63 到 2^63-1)" << std::endl;
    
    // 对应 float_precision 函数
    std::cout << "\n--- float_precision 函数验证 ---" << std::endl;
    std::cout << "演示浮点精度差异：" << std::endl;
    std::cout << std::fixed << std::setprecision(15);
    
    // f32: 单精度，约7位有效数字
    float pi_f32 = 3.141592653589793f;   // 对应 arith.constant ... : f32（会被截断）
    
    // f64: 双精度，约15位有效数字
    double pi_f64 = 3.141592653589793;   // 对应 arith.constant ... : f64（保持完整精度）
    
    std::cout << "  pi_f32 (单精度) = " << pi_f32 << std::endl;
    std::cout << "  pi_f64 (双精度) = " << pi_f64 << std::endl;
    std::cout << "  注意：f32精度较低，小数位被截断" << std::endl;
    
    // 对应 type_safety 函数
    std::cout << "\n--- type_safety 函数验证 ---" << std::endl;
    std::cout << "演示类型安全：同类型才能运算" << std::endl;
    
    int32_t a = 10, b = 20;
    int32_t int_result = a + b;          // 对应 arith.addi %a, %b : i32 ✓
    
    float fa = 3.14f, fb = 2.71f;
    float float_result = fa + fb;        // 对应 arith.addf %fa, %fb : f32 ✓
    
    std::cout << std::fixed << std::setprecision(2);
    std::cout << "  int_result (i32 + i32) = " << int_result << " ✓ 正确" << std::endl;
    std::cout << "  float_result (f32 + f32) = " << float_result << " ✓ 正确" << std::endl;
    std::cout << "  注意：不能将 i32 和 f32 直接相加，会产生编译错误" << std::endl;
    
    // 对应 overflow_example 函数
    std::cout << "\n--- overflow_example 函数验证 ---" << std::endl;
    std::cout << "演示溢出行为：" << std::endl;
    
    int8_t max_i8 = 127;                 // i8的最大值
    int8_t one = 1;
    
    // 溢出：127 + 1 = -128 (在i8中)
    int8_t overflow_result = max_i8 + one;  // 对应 arith.addi %max_i8, %one : i8
    
    int8_t min_i8 = -128;                // i8的最小值
    int8_t underflow_result = min_i8 - one; // 对应 arith.subi %min_i8, %one : i8
    
    std::cout << "  max_i8 = " << (int)max_i8 << " (i8最大值)" << std::endl;
    std::cout << "  overflow_result = max_i8 + 1 = " << (int)overflow_result 
              << " (期望: -128，发生溢出)" << std::endl;
    
    std::cout << "  min_i8 = " << (int)min_i8 << " (i8最小值)" << std::endl;
    std::cout << "  underflow_result = min_i8 - 1 = " << (int)underflow_result 
              << " (期望: 127，发生下溢)" << std::endl;
    
    std::cout << "\n=== 类型系统总结 ===" << std::endl;
    std::cout << "1. 整数类型有固定的位宽和范围：i8 < i16 < i32 < i64" << std::endl;
    std::cout << "2. 浮点类型有不同的精度：f32(单精度) < f64(双精度)" << std::endl;
    std::cout << "3. 相同类型才能进行运算，MLIR具有严格的类型安全" << std::endl;
    std::cout << "4. 超出类型范围会发生溢出，需要注意数值范围" << std::endl;
    
    std::cout << "\n=== 类型范围参考 ===" << std::endl;
    std::cout << "i8:  " << (int)std::numeric_limits<int8_t>::min() 
              << " 到 " << (int)std::numeric_limits<int8_t>::max() << std::endl;
    std::cout << "i16: " << std::numeric_limits<int16_t>::min() 
              << " 到 " << std::numeric_limits<int16_t>::max() << std::endl;
    std::cout << "i32: " << std::numeric_limits<int32_t>::min() 
              << " 到 " << std::numeric_limits<int32_t>::max() << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    
    return 0;
}
```

#### verify_step4.cpp
```cpp
// verify_step4.cpp - 验证第四步：比较操作和条件逻辑
#include <iostream>
#include <cmath>

int main() {
    std::cout << "=== Step 4: 比较操作和条件逻辑验证 ===" << std::endl;
    
    // 对应 integer_comparisons 函数
    std::cout << "\n--- integer_comparisons 函数验证 ---" << std::endl;
    
    int a = 10, b = 20;
    std::cout << "输入值: a=" << a << ", b=" << b << std::endl;
    
    // 相等性比较
    bool eq = (a == b);      // 对应 arith.cmpi eq
    bool ne = (a != b);      // 对应 arith.cmpi ne
    
    // 有符号比较
    bool slt = (a < b);      // 对应 arith.cmpi slt
    bool sle = (a <= b);     // 对应 arith.cmpi sle
    bool sgt = (a > b);      // 对应 arith.cmpi sgt
    bool sge = (a >= b);     // 对应 arith.cmpi sge
    
    std::cout << "\n整数比较结果：" << std::endl;
    std::cout << "  eq (a == b): " << (eq ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  ne (a != b): " << (ne ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  slt (a < b): " << (slt ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  sle (a <= b): " << (sle ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  sgt (a > b): " << (sgt ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  sge (a >= b): " << (sge ? "true" : "false") << " (期望: false)" << std::endl;
    
    // 对应 float_comparisons 函数
    std::cout << "\n--- float_comparisons 函数验证 ---" << std::endl;
    
    float fa = 3.14f, fb = 2.71f;
    std::cout << "输入值: fa=" << fa << ", fb=" << fb << std::endl;
    
    // 有序比较（如果有NaN，结果为false）
    bool oeq = (fa == fb);   // 对应 arith.cmpf oeq
    bool olt = (fa < fb);    // 对应 arith.cmpf olt
    bool ogt = (fa > fb);    // 对应 arith.cmpf ogt
    
    // 无序比较（如果有NaN，结果为true）
    bool une = (fa != fb);   // 对应 arith.cmpf une
    
    std::cout << "\n浮点比较结果：" << std::endl;
    std::cout << "  oeq (fa == fb): " << (oeq ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  olt (fa < fb): " << (olt ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  ogt (fa > fb): " << (ogt ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  une (fa != fb): " << (une ? "true" : "false") << " (期望: true)" << std::endl;
    
    // 对应 max_function 函数
    std::cout << "\n--- max_function 函数验证 ---" << std::endl;
    
    int val_a = 42, val_b = 24;
    std::cout << "输入值: val_a=" << val_a << ", val_b=" << val_b << std::endl;
    
    bool cmp = (val_a > val_b);  // 对应 arith.cmpi sgt
    int max_val = cmp ? val_a : val_b;  // 对应 scf.if
    
    std::cout << "比较结果: val_a > val_b = " << (cmp ? "true" : "false") << std::endl;
    std::cout << "最大值: " << max_val << " (期望: 42)" << std::endl;
    
    // 对应 abs_function 函数
    std::cout << "\n--- abs_function 函数验证 ---" << std::endl;
    
    int x = -15;
    int zero = 0;
    std::cout << "输入值: x=" << x << std::endl;
    
    bool is_negative = (x < zero);  // 对应 arith.cmpi slt
    int abs_result = is_negative ? (zero - x) : x;  // 对应 scf.if 和 arith.subi
    
    std::cout << "是否为负数: " << (is_negative ? "true" : "false") << std::endl;
    std::cout << "绝对值: " << abs_result << " (期望: 15)" << std::endl;
    
    // 对应 sign_function 函数
    std::cout << "\n--- sign_function 函数验证 ---" << std::endl;
    
    int y = 25;
    int zero_val = 0, one = 1, neg_one = -1;
    std::cout << "输入值: y=" << y << std::endl;
    
    bool is_positive = (y > zero_val);  // 对应 arith.cmpi sgt
    int result;
    
    if (is_positive) {
        result = one;  // 返回1
    } else {
        bool is_zero = (y == zero_val);  // 对应 arith.cmpi eq
        if (is_zero) {
            result = zero_val;  // 返回0
        } else {
            result = neg_one;   // 返回-1
        }
    }
    
    std::cout << "是否为正数: " << (is_positive ? "true" : "false") << std::endl;
    std::cout << "符号函数结果: " << result << " (期望: 1)" << std::endl;
    
    // 演示NaN处理（浮点比较的特殊情况）
    std::cout << "\n--- NaN处理演示 ---" << std::endl;
    
    float nan_val = std::numeric_limits<float>::quiet_NaN();
    float normal_val = 1.0f;
    
    // 有序比较：如果有NaN，结果为false
    bool ordered_eq = (nan_val == normal_val);    // false
    bool ordered_lt = (nan_val < normal_val);     // false
    
    // 无序比较：如果有NaN，结果为true
    bool unordered_ne = (nan_val != normal_val);  // true
    
    std::cout << "NaN与正常值比较：" << std::endl;
    std::cout << "  有序相等 (NaN == 1.0): " << (ordered_eq ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  有序小于 (NaN < 1.0): " << (ordered_lt ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  无序不等 (NaN != 1.0): " << (unordered_ne ? "true" : "false") << " (期望: true)" << std::endl;
    
    std::cout << "\n=== 比较操作总结 ===" << std::endl;
    std::cout << "1. 整数比较谓词：eq(==), ne(!=), slt(<), sle(<=), sgt(>), sge(>=)" << std::endl;
    std::cout << "2. 浮点比较分为有序和无序，处理NaN的方式不同" << std::endl;
    std::cout << "3. 比较结果是i1类型(布尔值)，可用于条件分支" << std::endl;
    std::cout << "4. 结合scf.if可以实现复杂的条件逻辑" << std::endl;
    
    std::cout << "\n=== 条件逻辑模式 ===" << std::endl;
    std::cout << "• max函数：比较两值，返回较大者" << std::endl;
    std::cout << "• abs函数：判断正负，返回绝对值" << std::endl;
    std::cout << "• sign函数：嵌套条件，返回符号(-1,0,1)" << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    
    return 0;
}
```