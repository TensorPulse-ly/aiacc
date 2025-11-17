# 快速开始指南

## 🚀 第一次运行

### 1. 设置环境变量
```bash
# 设置MLIR路径（根据你的安装调整）
export MLIR_DIR=/usr/local/lib/cmake/mlir
export LLVM_DIR=/usr/local/lib/cmake/llvm
```

### 2. 构建项目
```bash
cd framework
mkdir build && cd build
cmake ..
make -j4
```

如果成功，你会看到：
```
[100%] Built target shape-opt
```

### 3. 测试基础功能
```bash
# 回到测试目录
cd ../../test-cases

# 运行测试（初始状态会失败，这是正常的）
./run-tests.sh
```

你应该看到类似输出：
```
Testing: conv_shape
✗ FAILED: conv_shape - Output doesn't match expected
Testing: dynamic_shape  
✗ FAILED: dynamic_shape - Output doesn't match expected
...
```

这是正常的！因为Pass还没有实现优化逻辑。

## 📝 开始实现

### 1. 查看当前状态
```bash
# 查看未优化的输出
../framework/build/shape-opt --shape-optimizer input/conv_shape.mlir
```

你会看到：
```
ShapeOptimizerPass: 请实现优化逻辑！
输入模块包含 XX 个操作
// 然后是原始的未优化MLIR代码
```

### 2. 编辑实现文件
打开 `framework/ShapeOptimizerPass.h`，找到 `runOnOperation()` 方法：

```cpp
void runOnOperation() override {
    ModuleOp module = getOperation();
    
    // 删除这个占位实现：
    llvm::outs() << "ShapeOptimizerPass: 请实现优化逻辑！\n";
    
    // 在这里开始你的实现...
}
```

### 3. 实现第一个优化：算术折叠

从简单的开始，试试这个：

```cpp
void runOnOperation() override {
    ModuleOp module = getOperation();
    
    // 收集常量
    DenseMap<Value, Attribute> constantValues;
    collectConstants(module, constantValues);
    
    // 简单的加法折叠
    SmallVector<Operation*, 4> toErase;
    
    module.walk([&](arith::AddIOp addOp) {
        Value lhs = addOp.getLhs();
        Value rhs = addOp.getRhs();
        
        auto lhsConst = getConstantIntValue(lhs, constantValues);
        auto rhsConst = getConstantIntValue(rhs, constantValues);
        
        if (lhsConst && rhsConst) {
            OpBuilder builder(addOp);
            int64_t result = *lhsConst + *rhsConst;
            auto newConst = createIntConstant(builder, addOp.getLoc(), result, addOp.getType());
            
            addOp.getResult().replaceAllUsesWith(newConst.getResult());
            toErase.push_back(addOp);
        }
    });
    
    for (Operation *op : toErase) {
        op->erase();
    }
}
```

### 4. 重新编译和测试
```bash
cd framework/build
make
cd ../../test-cases
../framework/build/shape-opt --shape-optimizer input/conv_shape.mlir
```

现在你应该看到一些算术运算被优化了！

## 📊 进度追踪

### Level 1: 基础算术折叠
- [ ] 实现 `arith.addi` 折叠
- [ ] 实现 `arith.subi` 折叠  
- [ ] 实现 `arith.muli` 折叠
- [ ] 实现 `arith.divsi` 折叠
- [ ] 通过 `conv_shape.mlir` 测试

### Level 2: 形状推导
- [ ] 实现 `tensor.empty` 静态化
- [ ] 处理多维张量
- [ ] 通过 `dynamic_shape.mlir` 测试

### Level 3: 控制流优化
- [ ] 实现 `scf.if` 常量条件优化
- [ ] 处理函数调用内联
- [ ] 通过 `conditional_shape.mlir` 测试

### Level 4: 完成项目
- [ ] 通过所有测试
- [ ] 代码清理和优化
- [ ] 编写项目总结

## 🐛 调试技巧

### 1. 查看详细错误
```bash
./run-tests.sh --verbose
```

### 2. 单步调试
```bash
# 只运行一个测试
../framework/build/shape-opt --shape-optimizer input/conv_shape.mlir > debug_output.mlir

# 比较差异
diff debug_output.mlir expected/conv_shape.mlir
```

### 3. 验证MLIR语法
```bash
mlir-opt --verify-diagnostics debug_output.mlir
```

### 4. 添加调试输出
在你的Pass中添加：
```cpp
llvm::outs() << "处理操作: " << *op << "\n";
```

## ❓ 常见问题

**Q: 编译失败，找不到MLIR？**  
A: 检查环境变量，确保MLIR_DIR指向正确路径。

**Q: 测试输出为空？**  
A: 检查Pass是否被正确调用，确保有 `--shape-optimizer` 参数。

**Q: 优化没有效果？**  
A: 在 `runOnOperation()` 开头添加调试输出，确认代码被执行。

## 📚 学习资源

- 查看 `input/` 目录下的测试用例，理解优化目标
- 参考 `expected/` 目录下的期望输出
- 阅读课程Lab代码，了解类似的实现模式

祝你实现顺利！🎯