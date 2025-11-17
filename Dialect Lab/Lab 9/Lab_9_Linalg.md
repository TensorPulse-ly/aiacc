# Lab 9: MLIR linalg Dialect

## 实验概述

### 实验目标
通过本实验，学生将掌握 MLIR linalg Dialect 的核心操作，包括：
- 张量的创建与填充
- 矩阵乘法运算
- 张量变换操作（转置）
- linalg.generic 的高级用法

### 实验环境要求
- MLIR 编译器环境（LLVM 15.0.7 或兼容版本）
- 支持 linalg、tensor、arith、builtin 等 Dialect

### 预备知识
- 了解 MLIR 基本概念和 SSA 形式
- 熟悉 builtin、arith、tensor Dialect 基础操作
- 掌握线性代数基本概念（矩阵乘法、转置等）

---

## 实验内容

### 阶段1：基础张量填充与操作

**学习目标**：掌握 `linalg.fill` 和 `linalg.init_tensor` 的使用

#### 任务 1.1：基础矩阵填充
创建一个函数 `@fill_matrix`，实现以下功能：
- 创建一个 2×3 的空张量
- 使用常量 5.0 填充整个张量
- 返回填充后的张量

**关键操作**：
- `linalg.init_tensor` - 创建指定形状的空张量
- `arith.constant` - 定义常量
- `linalg.fill` - 用常量填充张量

#### 任务 1.2：向量填充
创建函数 `@fill_vector`，填充一个 4 维向量，填充值为 1.0

#### 任务 1.3：三维张量填充
创建函数 `@fill_3d_tensor`，填充一个 2×2×2 的三维张量，填充值为 -1.0

**思考问题**：
1. `linalg.init_tensor` 和 `tensor.empty` 有什么区别？
- 版本差异：`linalg.init_tensor` 是 LLVM 15.x 及更早版本中使用的操作，而 `tensor.empty` 是 LLVM 16.x 及更新版本中的替代操作
- 功能一致性：两者功能基本相同，都用于创建指定形状的未初始化张量
- 所属 Dialect：`linalg.init_tensor` 属于 linalg Dialect，而 `tensor.empty` 属于 tensor Dialect，后者更符合操作的语义归属

2. 为什么需要先创建空张量再填充，而不是直接创建填充好的张量？
- MLIR 设计哲学：MLIR 采用了明确的操作分离原则，每个操作都有单一、明确的职责
- 优化空间：编译器可以对创建和填充操作分别进行优化，比如内存布局优化、填充模式识别等
- 可组合性：这种设计支持更灵活的操作组合，可以根据需要选择不同的填充策略
- 类型系统一致性：`linalg.fill` 的 `outs` 参数设计要求输入一个已存在的张量，这保证了类型系统的一致性
---

### 阶段2：矩阵乘法运算

**学习目标**：掌握 `linalg.matmul` 进行各种形状的矩阵乘法

#### 任务 2.1：基础矩阵乘法
实现函数 `@basic_matmul`，完成 (2×3) × (3×2) = (2×2) 的矩阵乘法：
- 矩阵 A (2×3)：所有元素为 2.0
- 矩阵 B (3×2)：所有元素为 3.0
- 计算 C = A × B

**预期结果**：每个元素应为 2.0 × 3.0 × 3 = 18.0

#### 任务 2.2：矩阵乘向量
实现函数 `@vector_matmul`，完成 (3×4) × (4×1) = (3×1) 的运算：
- 矩阵 A (3×4)：所有元素为 1.0
- 向量 B (4×1)：所有元素为 0.5
- 计算结果向量

**预期结果**：每个元素应为 1.0 × 0.5 × 4 = 2.0

#### 任务 2.3：方阵乘法
实现函数 `@square_matmul`，完成 (2×2) × (2×2) = (2×2) 的方阵乘法：
- 矩阵 A：所有元素为 4.0
- 矩阵 B：所有元素为 2.0

**预期结果**：每个元素应为 4.0 × 2.0 × 2 = 16.0

**思考问题**：
1. 矩阵乘法的维度规则是什么？

- 基本规则：对于矩阵乘法 C = A × B，矩阵 A 的列数必须等于矩阵 B 的行数
- 维度计算：如果 A 是 m×k 矩阵，B 是 k×n 矩阵，则结果 C 是 m×n 矩阵
- 数学表达：C[i,j] = Σ(k=0 to K-1) A[i,k] × B[k,j]
- MLIR 中的体现：`linalg.matmul` 会在编译时检查维度兼容性

2. `linalg.matmul` 的 `ins` 和 `outs` 参数分别代表什么？

- ins (inputs)：
    - 表示操作的输入参数
    - 对于 linalg.matmul，包含两个矩阵：左乘数和右乘数
    - 这些是只读的，不会被操作修改

- outs (outputs)：
    - 表示操作的输出张量
    - 必须是预先分配好的张量，通常用 0 初始化
    - linalg.matmul 会将计算结果累加到这个张量中
    - 支持原地更新（in-place update）的优化

---

### 阶段3：张量变换操作

**学习目标**：掌握 `linalg.generic` 进行复杂的张量操作

#### 任务 3.1：基本矩阵转置
实现函数 `@basic_transpose`，将 (2×3) 矩阵转置为 (3×2)：
- 使用 `linalg.generic` 和 `affine_map`
- 理解索引映射的概念

**关键概念**：
- `indexing_maps`：定义输入输出的索引映射关系
- `affine_map<(i, j) -> (j, i)>`：转置映射
- `iterator_types`：指定迭代器类型

#### 任务 3.2：方阵转置
实现函数 `@square_transpose`，对 (3×3) 方阵进行转置

#### 任务 3.3：三维张量转置
实现函数 `@tensor_3d_transpose`，将 (2×3×4) 张量转置为 (4×3×2)：
- 维度重排：[0,1,2] → [2,1,0]
- 使用三维索引映射

#### 任务 3.4：组合操作
实现函数 `@fill_then_transpose`，先填充后转置：
- 创建 (2×4) 矩阵并填充为 6.0
- 转置为 (4×2) 矩阵

**思考问题**：
1. `linalg.generic` 相比专用操作（如 `linalg.matmul`）有什么优势？

- 通用性：linalg.generic 可以表达任意的张量操作，而专用操作只能处理特定模式
- 灵活性：支持自定义的索引映射和迭代模式，可以实现复杂的数据重排和计算
- 统一性：所有 linalg 操作都可以用 linalg.generic 表示，提供了统一的优化和分析框架
- 可扩展性：当需要新的操作模式时，不需要添加新的专用操作，直接用 linalg.generic 即可
- 优化潜力：编译器可以对 linalg.generic 进行更深入的分析和优化

2. 如何理解 `affine_map` 中的索引映射？

- 基本概念：affine_map 定义了迭代空间到张量索引空间的映射关系
- 语法格式：affine_map<(迭代变量) -> (张量索引)>
- 转置例子：affine_map<(i, j) -> (j, i)> 表示将迭代器 (i,j) 映射到张量的 (j,i) 位置

3. 三维张量转置时，索引映射应该如何设计？
- 对于三维张量转置 (2×3×4) → (4×3×2)，需要将维度 [0,1,2] 重排为 [2,1,0]：

---

## 实验步骤

### 步骤 1：环境准备
1. 确保 MLIR 编译环境已正确安装
2. 创建工作目录并准备测试文件

### 步骤 2：代码编写
1. 根据任务要求，逐个实现各阶段的函数
2. 注意 LLVM 15.x 版本的兼容性（使用 `linalg.init_tensor` 而非 `tensor.empty`）
3. 确保每个函数的类型签名正确

### 步骤 3：编译测试
使用以下命令编译和测试代码：
```bash
# 语法检查
mlir-opt --verify-diagnostics your_file.mlir

# 优化测试
mlir-opt --linalg-fold-unit-extent-dims your_file.mlir

# 转换测试  
mlir-opt --convert-linalg-to-llvm your_file.mlir
```

### 步骤 4：结果验证
1. 验证每个函数能正确编译
2. 检查张量形状和类型是否符合预期
3. 理解每个操作的数学含义

---

## 参考代码
### 阶段1：基础张量填充与操作

```mlir
module {
  // 函数1：创建并填充一个2x3的张量，填充值为5.0
  func.func @fill_matrix() -> tensor<2x3xf32> {
    // 定义填充常量
    %fill_value = arith.constant 5.0 : f32
    
    // 创建空张量 (LLVM 15.x 版本使用 linalg.init_tensor)
    %empty = linalg.init_tensor [2, 3] : tensor<2x3xf32>
    
    // 使用linalg.fill填充张量
    %filled = linalg.fill ins(%fill_value : f32) outs(%empty : tensor<2x3xf32>) -> tensor<2x3xf32>
    
    return %filled : tensor<2x3xf32>
  }

  // 函数2：填充不同大小的张量
  func.func @fill_vector() -> tensor<4xf32> {
    %fill_value = arith.constant 1.0 : f32
    %empty = linalg.init_tensor [4] : tensor<4xf32>
    %filled = linalg.fill ins(%fill_value : f32) outs(%empty : tensor<4xf32>) -> tensor<4xf32>
    
    return %filled : tensor<4xf32>
  }

  // 函数3：填充3D张量
  func.func @fill_3d_tensor() -> tensor<2x2x2xf32> {
    %fill_value = arith.constant -1.0 : f32
    %empty = linalg.init_tensor [2, 2, 2] : tensor<2x2x2xf32>
    %filled = linalg.fill ins(%fill_value : f32) outs(%empty : tensor<2x2x2xf32>) -> tensor<2x2x2xf32>
    
    return %filled : tensor<2x2x2xf32>
  }
}
```

### 阶段2：矩阵乘法运算

```mlir
module {
  // 函数1：基本矩阵乘法 (2x3) * (3x2) = (2x2)
  func.func @basic_matmul() -> tensor<2x2xf32> {
    // 创建第一个矩阵A (2x3)，填充为2.0
    %fill_a = arith.constant 2.0 : f32
    %empty_a = linalg.init_tensor [2, 3] : tensor<2x3xf32>
    %matrix_a = linalg.fill ins(%fill_a : f32) outs(%empty_a : tensor<2x3xf32>) -> tensor<2x3xf32>
    
    // 创建第二个矩阵B (3x2)，填充为3.0
    %fill_b = arith.constant 3.0 : f32
    %empty_b = linalg.init_tensor [3, 2] : tensor<3x2xf32>
    %matrix_b = linalg.fill ins(%fill_b : f32) outs(%empty_b : tensor<3x2xf32>) -> tensor<3x2xf32>
    
    // 创建输出矩阵C (2x2)，初始化为0.0
    %fill_c = arith.constant 0.0 : f32
    %empty_c = linalg.init_tensor [2, 2] : tensor<2x2xf32>
    %matrix_c = linalg.fill ins(%fill_c : f32) outs(%empty_c : tensor<2x2xf32>) -> tensor<2x2xf32>
    
    // 执行矩阵乘法：C = A * B
    %result = linalg.matmul ins(%matrix_a, %matrix_b : tensor<2x3xf32>, tensor<3x2xf32>) 
                           outs(%matrix_c : tensor<2x2xf32>) -> tensor<2x2xf32>
    
    return %result : tensor<2x2xf32>
  }

  // 函数2：不同尺寸的矩阵乘法 (3x4) * (4x1) = (3x1)
  func.func @vector_matmul() -> tensor<3x1xf32> {
    // 矩阵A (3x4)
    %fill_a = arith.constant 1.0 : f32
    %empty_a = linalg.init_tensor [3, 4] : tensor<3x4xf32>
    %matrix_a = linalg.fill ins(%fill_a : f32) outs(%empty_a : tensor<3x4xf32>) -> tensor<3x4xf32>
    
    // 向量B (4x1)
    %fill_b = arith.constant 0.5 : f32
    %empty_b = linalg.init_tensor [4, 1] : tensor<4x1xf32>
    %vector_b = linalg.fill ins(%fill_b : f32) outs(%empty_b : tensor<4x1xf32>) -> tensor<4x1xf32>
    
    // 输出向量C (3x1)
    %fill_c = arith.constant 0.0 : f32
    %empty_c = linalg.init_tensor [3, 1] : tensor<3x1xf32>
    %vector_c = linalg.fill ins(%fill_c : f32) outs(%empty_c : tensor<3x1xf32>) -> tensor<3x1xf32>
    
    // 矩阵乘向量
    %result = linalg.matmul ins(%matrix_a, %vector_b : tensor<3x4xf32>, tensor<4x1xf32>) 
                           outs(%vector_c : tensor<3x1xf32>) -> tensor<3x1xf32>
    
    return %result : tensor<3x1xf32>
  }

  // 函数3：方阵乘法 (2x2) * (2x2) = (2x2)
  func.func @square_matmul() -> tensor<2x2xf32> {
    // 第一个方阵，填充为4.0
    %fill_a = arith.constant 4.0 : f32
    %empty_a = linalg.init_tensor [2, 2] : tensor<2x2xf32>
    %matrix_a = linalg.fill ins(%fill_a : f32) outs(%empty_a : tensor<2x2xf32>) -> tensor<2x2xf32>
    
    // 第二个方阵，填充为2.0
    %fill_b = arith.constant 2.0 : f32
    %empty_b = linalg.init_tensor [2, 2] : tensor<2x2xf32>
    %matrix_b = linalg.fill ins(%fill_b : f32) outs(%empty_b : tensor<2x2xf32>) -> tensor<2x2xf32>
    
    // 输出方阵，初始化为0.0
    %fill_c = arith.constant 0.0 : f32
    %empty_c = linalg.init_tensor [2, 2] : tensor<2x2xf32>
    %matrix_c = linalg.fill ins(%fill_c : f32) outs(%empty_c : tensor<2x2xf32>) -> tensor<2x2xf32>
    
    // 方阵乘法
    %result = linalg.matmul ins(%matrix_a, %matrix_b : tensor<2x2xf32>, tensor<2x2xf32>) 
                           outs(%matrix_c : tensor<2x2xf32>) -> tensor<2x2xf32>
    
    return %result : tensor<2x2xf32>
  }
}
```

### 阶段3：张量变换操作

```mlir
// 阶段3：张量变换操作
// 目标：学习使用linalg.generic进行张量转置 (LLVM 15.0.7兼容版本)

module {
  // 函数1：基本矩阵转置 (2x3) -> (3x2)
  func.func @basic_transpose() -> tensor<3x2xf32> {
    // 创建输入矩阵 (2x3)，填充为7.0
    %fill_input = arith.constant 7.0 : f32
    %empty_input = linalg.init_tensor [2, 3] : tensor<2x3xf32>
    %input_matrix = linalg.fill ins(%fill_input : f32) outs(%empty_input : tensor<2x3xf32>) -> tensor<2x3xf32>
    
    // 创建输出矩阵 (3x2)，初始化为0.0
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [3, 2] : tensor<3x2xf32>
    %output_matrix = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<3x2xf32>) -> tensor<3x2xf32>
    
    // 使用linalg.generic实现转置操作：将(2x3)转置为(3x2)
    // 关键：输入映射 (i,j) -> (i,j)，输出映射 (i,j) -> (j,i) 实现转置
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j) -> (j, i)>,  // 输入：从(3x2)空间映射到(2x3)输入
        affine_map<(i, j) -> (i, j)>   // 输出：标准映射到(3x2)输出
      ],
      iterator_types = ["parallel", "parallel"]
    } ins(%input_matrix : tensor<2x3xf32>) outs(%output_matrix : tensor<3x2xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<3x2xf32>
    
    return %result : tensor<3x2xf32>
  }

  // 函数2：方阵转置 (3x3) -> (3x3)
  func.func @square_transpose() -> tensor<3x3xf32> {
    // 创建方阵，填充为8.0
    %fill_input = arith.constant 8.0 : f32
    %empty_input = linalg.init_tensor [3, 3] : tensor<3x3xf32>
    %input_matrix = linalg.fill ins(%fill_input : f32) outs(%empty_input : tensor<3x3xf32>) -> tensor<3x3xf32>
    
    // 输出方阵
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [3, 3] : tensor<3x3xf32>
    %output_matrix = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<3x3xf32>) -> tensor<3x3xf32>
    
    // 方阵转置
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j) -> (j, i)>,  // 输入转置映射
        affine_map<(i, j) -> (i, j)>   // 输出标准映射
      ],
      iterator_types = ["parallel", "parallel"]
    } ins(%input_matrix : tensor<3x3xf32>) outs(%output_matrix : tensor<3x3xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<3x3xf32>
    
    return %result : tensor<3x3xf32>
  }

  // 函数3：3D张量转置 (2x3x4) -> (4x3x2)
  func.func @tensor_3d_transpose() -> tensor<4x3x2xf32> {
    // 创建3D张量 (2x3x4)
    %fill_input = arith.constant 9.0 : f32
    %empty_input = linalg.init_tensor [2, 3, 4] : tensor<2x3x4xf32>
    %input_tensor = linalg.fill ins(%fill_input : f32) outs(%empty_input : tensor<2x3x4xf32>) -> tensor<2x3x4xf32>
    
    // 创建输出3D张量 (4x3x2)
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [4, 3, 2] : tensor<4x3x2xf32>
    %output_tensor = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<4x3x2xf32>) -> tensor<4x3x2xf32>
    
    // 3D张量转置：将维度顺序从[0,1,2]变为[2,1,0]
    // 输入映射：(i,j,k) -> (k,j,i) 实现维度重排
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j, k) -> (k, j, i)>,  // 输入：第0维->第2维，第1维不变，第2维->第0维
        affine_map<(i, j, k) -> (i, j, k)>   // 输出：标准映射
      ],
      iterator_types = ["parallel", "parallel", "parallel"]
    } ins(%input_tensor : tensor<2x3x4xf32>) outs(%output_tensor : tensor<4x3x2xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<4x3x2xf32>
    
    return %result : tensor<4x3x2xf32>
  }

  // 函数4：组合操作 - 先填充再转置
  func.func @fill_then_transpose() -> tensor<4x2xf32> {
    // 步骤1：创建并填充原始矩阵
    %fill_value = arith.constant 6.0 : f32
    %empty = linalg.init_tensor [2, 4] : tensor<2x4xf32>
    %filled = linalg.fill ins(%fill_value : f32) outs(%empty : tensor<2x4xf32>) -> tensor<2x4xf32>
    
    // 步骤2：创建转置输出矩阵
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [4, 2] : tensor<4x2xf32>
    %output = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<4x2xf32>) -> tensor<4x2xf32>
    
    // 步骤3：执行转置
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j) -> (j, i)>,  // 输入转置映射
        affine_map<(i, j) -> (i, j)>   // 输出标准映射
      ],
      iterator_types = ["parallel", "parallel"]
    } ins(%filled : tensor<2x4xf32>) outs(%output : tensor<4x2xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<4x2xf32>
    
    return %result : tensor<4x2xf32>
  }
}
```