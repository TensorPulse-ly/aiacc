# Lab 8: MLIR Tensor Dialect

## Lab概述
**实验目标**: 掌握MLIR中tensor Dialect的核心操作，理解张量的创建、操作、切片和形状变换

## 学习目标

完成本实验后，你将能够：
1. 理解tensor Dialect的基本概念和不可变性特点
2. 熟练使用tensor的创建、插入、提取操作
3. 掌握张量的切片和子集操作
4. 理解并应用张量的形状变换操作
5. 处理动态形状张量和类型转换
6. 为学习更高级的linalg Dialect打下基础


## 🚀 实验准备

### 环境检查
```bash
# 检查MLIR工具是否安装
mlir-opt --version
make help
```
---

## Part 1: 基础张量操作

### 📚 理论背景

**Tensor的不可变性**: 
在MLIR中，tensor是不可变的数据结构。这意味着：
- 每次"修改"操作都会创建一个新的tensor
- 原始tensor保持不变
- 这种设计有利于编译器优化和并行计算

### 🎯 实验任务

打开 `basic_tensor_op.mlir` 文件，完成以下练习：

#### 练习 1.1: 创建和填充1D张量
**任务**: 创建一个长度为5的张量，在位置0, 2, 4分别放入值1.0, 3.5, 7.2

**提示**:
- 使用 `tensor.empty()` 创建空张量
- 使用 `tensor.insert` 插入元素
- 记住每次插入都会返回新张量

```mlir
func.func @exercise_1_1() -> tensor<5xf32> {
  // TODO: 你的代码
}
```

**思考问题 1.1**: 如果你连续调用两次 `tensor.insert` 到同一个位置，最终结果是什么？
**答案**: 最终结果是第二次插入的值，因为每次插入都创建新张量，后面的操作会覆盖前面的结果。

#### 练习 1.2: 从2D张量提取元素
**任务**: 从一个3x4的张量中提取位置[1,2]的元素

```mlir
func.func @exercise_1_2(%input: tensor<3x4xf32>) -> f32 {
  // TODO: 你的代码
}
```

#### 练习 1.3: 理解张量不可变性
**任务**: 创建一个张量，插入两个不同的值，观察中间结果

```mlir
func.func @exercise_1_3() -> (tensor<3xf32>, tensor<3xf32>) {
  // TODO: 创建原始张量
  // TODO: 插入第一个值，保存中间结果
  // TODO: 插入第二个值，保存最终结果  
  // TODO: 返回中间结果和最终结果
}
```

**思考问题 1.2**: 上述函数返回的两个张量有什么区别？
**答案**: 第一个张量只包含第一次插入的值，第二个张量包含两个插入的值。这说明tensor操作不会修改原始数据，而是创建新的张量。

---

## Part 2: 切片和子集操作 (25分钟)

### 📚 理论背景

**张量切片**: 
- `tensor.extract_slice`: 从张量中提取子区域
- 语法: `[起始位置] [大小] [步长]`
- 类似NumPy的切片操作，但语法不同

**张量子集插入**:
- `tensor.insert_slice`: 将一个张量插入到另一个张量的指定位置
- 用于构建更大的张量或替换部分数据

### 🎯 实验任务

打开 `slicing_subsetting.mlir` 文件，完成以下练习：

#### 练习 2.1: 1D张量切片
**任务**: 从长度为8的张量中提取从位置2开始、长度为3的子序列

```mlir
func.func @exercise_2_1(%input: tensor<8xf32>) -> tensor<3xf32> {
  // TODO: 使用 tensor.extract_slice
  // 格式: tensor.extract_slice %input[起始] [长度] [步长]
}
```

#### 练习 2.2: 2D张量切片
**任务**: 从5x6的张量中提取一个2x3的子矩阵，起始位置为[1,2]

```mlir
func.func @exercise_2_2(%input: tensor<5x6xf32>) -> tensor<2x3xf32> {
  // TODO: 对于2D张量，需要指定两个维度的参数
}
```

**思考问题 2.1**: 如果起始位置超出张量边界会发生什么？
**答案**: 编译器会报错或运行时报错，因为MLIR会进行边界检查。这是一种安全机制。

#### 练习 2.3: 插入子张量
**任务**: 创建一个4x4的空张量，将一个2x2的子张量插入到位置[1,1]

```mlir
func.func @exercise_2_3(%sub: tensor<2x2xf32>) -> tensor<4x4xf32> {
  // TODO: 创建目标张量
  // TODO: 使用 tensor.insert_slice 插入子张量
}
```

#### 练习 2.4: 复合切片操作
**任务**: 从一个6x8张量中先提取中间4x6区域，再从中提取2x3区域

```mlir
func.func @exercise_2_4(%input: tensor<6x8xf32>) -> tensor<2x3xf32> {
  // TODO: 两步切片操作
  // 第一步: 提取4x6中间区域
  // 第二步: 从4x6中提取2x3区域
}
```

---

## Part 3: 形状变换 (25分钟)

### 📚 理论背景

**形状变换操作**:
- `tensor.reshape`: 改变张量形状（总元素数不变）
- `tensor.expand_shape`: 增加维度（通常是大小为1的维度）
- `tensor.collapse_shape`: 减少维度（合并相邻维度）
- `tensor.dim`: 获取张量的维度大小

**重要规则**:
- reshape时总元素数必须相同 
- expand/collapse主要用于处理大小为1的维度
- 维度映射必须正确指定

### 🎯 实验任务

打开 `shape_transform.mlir` 文件，完成以下练习：

#### 练习 3.1: 基础reshape
**任务**: 将2x3x4的3D张量重塑为6x4的2D张量

```mlir
func.func @exercise_3_1(%input: tensor<2x3x4xf32>) -> tensor<6x4xf32> {
  // TODO: 使用 tensor.reshape
  // 注意: 2*3*4 = 6*4 = 24，元素总数相同
}
```

**思考问题 3.1**: 为什么reshape要求元素总数相同？
**答案**: 因为reshape只是改变数据的组织方式，不创建或删除数据。如果总数不同，就无法一一对应地重新排列元素。

#### 练习 3.2: 张量展平
**任务**: 将任意形状的3D张量展平为1D张量

```mlir
func.func @exercise_3_2(%input: tensor<2x5x3xf32>) -> tensor<30xf32> {
  // TODO: 展平为1D，总元素数 = 2*5*3 = 30
}
```

#### 练习 3.3: 扩展维度
**任务**: 将2x5的张量扩展为2x1x5x1的4D张量

```mlir
func.func @exercise_3_3(%input: tensor<2x5xf32>) -> tensor<2x1x5x1xf32> {
  // TODO: 使用 tensor.expand_shape
  // 需要指定维度映射: [[0], [1, 2], [3, 4]]
  // 意思是: 原维度0->新维度0, 原维度1->新维度1,2
}
```

**思考问题 3.2**: expand_shape中的维度映射 `[[0], [1, 2]]` 是什么意思？
**答案**: 这表示原张量的第0维对应新张量的第0维，原张量的第1维被扩展为新张量的第1维和第2维。通常新增的维度大小为1。

#### 练习 3.4: 折叠维度
**任务**: 将3x1x4x1x2张量折叠为3x4x2张量（去除大小为1的维度）

```mlir
func.func @exercise_3_4(%input: tensor<3x1x4x1x2xf32>) -> tensor<3x4x2xf32> {
  // TODO: 使用 tensor.collapse_shape
  // 映射: [[0, 1], [2, 3], [4]] - 合并相邻维度
}
```

#### 练习 3.5: 动态维度计算
**任务**: 计算任意2D张量的总元素数

```mlir
func.func @exercise_3_5(%input: tensor<?x?xf32>) -> index {
  // TODO: 使用 tensor.dim 获取各维度大小
  // TODO: 使用 arith.muli 计算乘积
}
```

---

## Part 4: 动态张量和类型转换 (20分钟)

### 📚 理论背景

**静态 vs 动态形状**:
- 静态形状: 编译时确定，如 `tensor<4x6xf32>`
- 动态形状: 运行时确定，如 `tensor<?x?xf32>`
- 动态形状更灵活，但性能可能稍差

**类型转换**:
- `tensor.cast`: 在兼容类型间转换
- 可以从静态转动态，或在已知维度时从动态转静态
- 不兼容的转换会编译失败

### 🎯 实验任务

打开 `dynamic_conver.mlir` 文件，完成以下练习：

#### 练习 4.1: 创建动态张量
**任务**: 根据给定的维度参数创建动态3D张量，并在[0,0,0]位置插入值100.0

```mlir
func.func @exercise_4_1(%d0: index, %d1: index, %d2: index) -> tensor<?x?x?xf32> {
  // TODO: 使用 tensor.empty(%d0, %d1, %d2)
  // TODO: 插入值到指定位置
}
```

#### 练习 4.2: 静态到动态转换
**任务**: 将静态形状张量转换为动态形状，再转换回静态形状

```mlir
func.func @exercise_4_2() -> tensor<3x4xf32> {
  // TODO: 创建静态张量 tensor<3x4xf32>
  // TODO: 转换为动态形状 tensor<?x?xf32>  
  // TODO: 转换回静态形状 tensor<3x4xf32>
}
```

**思考问题 4.1**: 为什么可以从静态形状转换为动态形状？
**答案**: 因为静态形状包含了所有维度信息，转换为动态形状只是放宽了编译时的约束，运行时信息仍然完整。

#### 练习 4.3: 动态张量切片
**任务**: 从动态形状2D张量中提取固定大小的左上角3x3区域

```mlir
func.func @exercise_4_3(%input: tensor<?x?xf32>) -> tensor<3x3xf32> {
  // TODO: 即使输入是动态的，输出可以是静态的
  // TODO: 从[0,0]开始提取3x3区域
}
```

#### 练习 4.4: 动态维度查询
**任务**: 检查动态张量的维度，如果第一维大于10则提取前10个元素，否则提取全部

```mlir
func.func @exercise_4_4(%input: tensor<?xf32>) -> tensor<?xf32> {
  // TODO: 使用 tensor.dim 获取第一维大小
  // TODO: 使用 arith.cmpi 比较大小  
  // TODO: 使用 scf.if 条件选择
  // 注意: 这个练习结合了多个dialect的知识
}
```

**思考问题 4.2**: 什么情况下动态张量的类型转换会失败？
**答案**: 当尝试转换为不兼容的静态形状时会失败，比如动态张量实际是5x6，但试图转换为tensor<3x4xf32>。


---

## 📚 参考代码

### Part 1: 基础张量操作参考答案

```mlir
// basic_tensor_op.mlir - 参考答案

// 练习 1.1: 创建和填充1D张量
func.func @exercise_1_1() -> tensor<5xf32> {
  %c0 = arith.constant 0 : index
  %c2 = arith.constant 2 : index
  %c4 = arith.constant 4 : index
  %val1 = arith.constant 1.0 : f32
  %val2 = arith.constant 3.5 : f32
  %val3 = arith.constant 7.2 : f32
  
  %empty = tensor.empty() : tensor<5xf32>
  %t1 = tensor.insert %val1 into %empty[%c0] : tensor<5xf32>
  %t2 = tensor.insert %val2 into %t1[%c2] : tensor<5xf32>
  %t3 = tensor.insert %val3 into %t2[%c4] : tensor<5xf32>
  
  return %t3 : tensor<5xf32>
}

// 练习 1.2: 从2D张量提取元素
func.func @exercise_1_2(%input: tensor<3x4xf32>) -> f32 {
  %c1 = arith.constant 1 : index
  %c2 = arith.constant 2 : index
  
  %val = tensor.extract %input[%c1, %c2] : tensor<3x4xf32>
  
  return %val : f32
}

// 练习 1.3: 理解张量不可变性
func.func @exercise_1_3() -> (tensor<3xf32>, tensor<3xf32>) {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %val1 = arith.constant 10.0 : f32
  %val2 = arith.constant 20.0 : f32
  
  %empty = tensor.empty() : tensor<3xf32>
  %middle = tensor.insert %val1 into %empty[%c0] : tensor<3xf32>
  %final = tensor.insert %val2 into %middle[%c1] : tensor<3xf32>
  
  return %middle, %final : tensor<3xf32>, tensor<3xf32>
}
```

### Part 2: 切片和子集操作参考答案

```mlir
// slicing_subsetting.mlir - 参考答案

// 练习 2.1: 1D张量切片
func.func @exercise_2_1(%input: tensor<8xf32>) -> tensor<3xf32> {
  %slice = tensor.extract_slice %input[2] [3] [1] : 
    tensor<8xf32> to tensor<3xf32>
  
  return %slice : tensor<3xf32>
}

// 练习 2.2: 2D张量切片
func.func @exercise_2_2(%input: tensor<5x6xf32>) -> tensor<2x3xf32> {
  %slice = tensor.extract_slice %input[1, 2] [2, 3] [1, 1] :
    tensor<5x6xf32> to tensor<2x3xf32>
  
  return %slice : tensor<2x3xf32>
}

// 练习 2.3: 插入子张量
func.func @exercise_2_3(%sub: tensor<2x2xf32>) -> tensor<4x4xf32> {
  %empty = tensor.empty() : tensor<4x4xf32>
  
  %result = tensor.insert_slice %sub into %empty[1, 1] [2, 2] [1, 1] :
    tensor<2x2xf32> into tensor<4x4xf32>
  
  return %result : tensor<4x4xf32>
}

// 练习 2.4: 复合切片操作
func.func @exercise_2_4(%input: tensor<6x8xf32>) -> tensor<2x3xf32> {
  // 第一步: 从6x8中提取中间4x6区域 (从[1,1]开始)
  %middle = tensor.extract_slice %input[1, 1] [4, 6] [1, 1] :
    tensor<6x8xf32> to tensor<4x6xf32>
  
  // 第二步: 从4x6中提取2x3区域 (从[1,1]开始)
  %final = tensor.extract_slice %middle[1, 1] [2, 3] [1, 1] :
    tensor<4x6xf32> to tensor<2x3xf32>
  
  return %final : tensor<2x3xf32>
}
```

### Part 3: 形状变换参考答案

```mlir
// shape_transform.mlir - 参考答案

// 练习 3.1: 基础reshape
func.func @exercise_3_1(%input: tensor<2x3x4xf32>) -> tensor<6x4xf32> {
  %reshaped = tensor.reshape %input : (tensor<2x3x4xf32>) -> tensor<6x4xf32>
  
  return %reshaped : tensor<6x4xf32>
}

// 练习 3.2: 张量展平
func.func @exercise_3_2(%input: tensor<2x5x3xf32>) -> tensor<30xf32> {
  %flattened = tensor.reshape %input : (tensor<2x5x3xf32>) -> tensor<30xf32>
  
  return %flattened : tensor<30xf32>
}

// 练习 3.3: 扩展维度
func.func @exercise_3_3(%input: tensor<2x5xf32>) -> tensor<2x1x5x1xf32> {
  %expanded = tensor.expand_shape %input [[0], [1, 2], [3, 4]] :
    tensor<2x5xf32> into tensor<2x1x5x1xf32>
  
  return %expanded : tensor<2x1x5x1xf32>
}

// 练习 3.4: 折叠维度
func.func @exercise_3_4(%input: tensor<3x1x4x1x2xf32>) -> tensor<3x4x2xf32> {
  %collapsed = tensor.collapse_shape %input [[0, 1], [2, 3], [4]] :
    tensor<3x1x4x1x2xf32> into tensor<3x4x2xf32>
  
  return %collapsed : tensor<3x4x2xf32>
}

// 练习 3.5: 动态维度计算
func.func @exercise_3_5(%input: tensor<?x?xf32>) -> index {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  
  %dim0 = tensor.dim %input, %c0 : tensor<?x?xf32>
  %dim1 = tensor.dim %input, %c1 : tensor<?x?xf32>
  %total = arith.muli %dim0, %dim1 : index
  
  return %total : index
}
```

### Part 4: 动态张量和类型转换参考答案

```mlir
// dynamic_conver.mlir - 参考答案

// 练习 4.1: 创建动态张量
func.func @exercise_4_1(%d0: index, %d1: index, %d2: index) -> tensor<?x?x?xf32> {
  %c0 = arith.constant 0 : index
  %val = arith.constant 100.0 : f32
  
  %dynamic = tensor.empty(%d0, %d1, %d2) : tensor<?x?x?xf32>
  %result = tensor.insert %val into %dynamic[%c0, %c0, %c0] : tensor<?x?x?xf32>
  
  return %result : tensor<?x?x?xf32>
}

// 练习 4.2: 静态到动态转换
func.func @exercise_4_2() -> tensor<3x4xf32> {
  %static = tensor.empty() : tensor<3x4xf32>
  %dynamic = tensor.cast %static : tensor<3x4xf32> to tensor<?x?xf32>
  %back_to_static = tensor.cast %dynamic : tensor<?x?xf32> to tensor<3x4xf32>
  
  return %back_to_static : tensor<3x4xf32>
}

// 练习 4.3: 动态张量切片
func.func @exercise_4_3(%input: tensor<?x?xf32>) -> tensor<3x3xf32> {
  %slice = tensor.extract_slice %input[0, 0] [3, 3] [1, 1] :
    tensor<?x?xf32> to tensor<3x3xf32>
  
  return %slice : tensor<3x3xf32>
}

// 练习 4.4: 动态维度查询（复杂版本，结合scf dialect）
func.func @exercise_4_4(%input: tensor<?xf32>) -> tensor<?xf32> {
  %c0 = arith.constant 0 : index
  %c10 = arith.constant 10 : index
  
  %dim = tensor.dim %input, %c0 : tensor<?xf32>
  %cond = arith.cmpi sgt, %dim, %c10 : index
  
  %result = scf.if %cond -> tensor<?xf32> {
    // 如果维度大于10，提取前10个元素
    %slice = tensor.extract_slice %input[0] [10] [1] :
      tensor<?xf32> to tensor<10xf32>
    %casted = tensor.cast %slice : tensor<10xf32> to tensor<?xf32>
    scf.yield %casted : tensor<?xf32>
  } else {
    // 否则返回全部
    scf.yield %input : tensor<?xf32>
  }
  
  return %result : tensor<?xf32>
}
```

---