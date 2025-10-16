# ML Shape Computation Optimizer

一个基于MLIR的机器学习形状计算优化器项目。通过实现编译器Pass来优化神经网络中的张量形状计算和算术运算。

## 项目概述

在机器学习编译器中，大量的计算涉及张量形状推导和算术运算。这些计算往往可以在编译时完成，从而减少运行时开销。本项目要求实现一个MLIR Pass来进行这类优化。

## 快速开始

### 1. 环境要求
- LLVM/MLIR 15.0 或更高版本
- CMake 3.15+
- C++17兼容的编译器

### 2. 构建项目
```bash
cd framework
mkdir build && cd build
cmake ..
make
```

### 3. 运行测试
```bash
cd ../test-cases
./run-tests.sh
```

## 项目结构

```
shape-optimizer-project/
├── test-cases/              # 测试用例
│   ├── input/               # 优化前的MLIR文件
│   │   ├── conv_shape.mlir     # 卷积形状计算
│   │   ├── dynamic_shape.mlir  # 动态形状推导
│   │   ├── conditional_shape.mlir # 条件形状选择
│   │   └── matrix_chain.mlir   # 矩阵操作链
│   ├── expected/            # 期望的优化结果
│   └── run-tests.sh         # 自动化测试脚本
├── framework/               # 框架代码
│   ├── main.cpp            # 工具主程序
│   ├── ShapeOptimizerPass.h # Pass头文件和骨架
│   └── CMakeLists.txt      # 构建配置
└── README.md               # 本文件
```

## 实现任务

### 必须实现的功能

1. **算术常量折叠** (arith dialect)
   - 加法：`arith.constant 2 + arith.constant 3 → arith.constant 5`
   - 减法、乘法、除法的类似优化

2. **张量形状推导** (tensor dialect)
   - `tensor.empty(%const1, %const2) → tensor.empty() : tensor<C1xC2xf32>`

3. **控制流简化** (scf dialect)
   - `scf.if %true → 直接使用then分支`
   - `scf.if %false → 直接使用else分支`

### 关键文件

- **`framework/ShapeOptimizerPass.h`**: 你需要完成的主要文件
- **`test-cases/run-tests.sh`**: 验证你的实现是否正确

### 测试用例说明

1. **conv_shape.mlir**: 测试卷积层输出尺寸的编译时计算
2. **dynamic_shape.mlir**: 测试动态张量形状转静态形状
3. **conditional_shape.mlir**: 测试常量条件分支的优化
4. **matrix_chain.mlir**: 测试矩阵操作的综合优化

## 开发指南

### 实现步骤

1. **阶段1**: 完成算术常量折叠，通过 `conv_shape.mlir` 测试
2. **阶段2**: 实现形状推导，通过 `dynamic_shape.mlir` 测试  
3. **阶段3**: 添加控制流优化，通过 `conditional_shape.mlir` 测试
4. **阶段4**: 综合测试，通过所有测试用例

### 核心算法提示

```cpp
void runOnOperation() override {
    // 1. 收集所有常量
    DenseMap<Value, Attribute> constantValues;
    module.walk([&](arith::ConstantOp op) {
        constantValues[op.getResult()] = op.getValue();
    });
    
    // 2. 折叠算术运算
    module.walk([&](arith::AddIOp op) {
        // 检查操作数是否都是常量，如果是则计算结果
    });
    
    // 3. 推导静态形状
    module.walk([&](tensor::EmptyOp op) {
        // 检查维度参数是否都是常量，如果是则创建静态形状
    });
    
    // 4. 简化控制流
    module.walk([&](scf::IfOp op) {
        // 检查条件是否为常量，如果是则选择对应分支
    });
}
```

### 调试技巧

1. **查看中间结果**:
   ```bash
   ./shape-opt --shape-optimizer input.mlir
   ```

2. **验证语法**:
   ```bash
   mlir-opt --verify-diagnostics output.mlir
   ```

3. **详细测试**:
   ```bash
   ./run-tests.sh --verbose
   ```

4. **单个测试**:
   ```bash
   ./shape-opt --shape-optimizer input/conv_shape.mlir > temp.mlir
   diff temp.mlir expected/conv_shape.mlir
   ```

## 常见问题

### Q: 编译时出现链接错误？
A: 检查MLIR库的路径，确保CMake能找到MLIR安装目录。

### Q: 测试失败但语法正确？
A: 仔细比较输出和期望结果，注意空白符和注释的差异。测试脚本会忽略这些差异。

### Q: 如何添加新的测试用例？
A: 在`test-cases/input/`添加输入文件，在`test-cases/expected/`添加期望输出，修改`run-tests.sh`。

### Q: Pass没有任何效果？
A: 检查Pass是否正确注册，运行时是否包含`--shape-optimizer`参数。

## 相关资源

- [MLIR Pass文档](https://mlir.llvm.org/docs/PassManagement/)
- [MLIR Dialect指南](https://mlir.llvm.org/docs/Dialects/)
- [常量折叠原理](https://en.wikipedia.org/wiki/Constant_folding)

## 贡献和反馈

如有问题或建议，请通过以下方式联系：
- 查看课程Lab实验代码
- 参考MLIR官方文档
- 运行`./shape-opt --help`查看工具选项

祝你实现愉快！🚀