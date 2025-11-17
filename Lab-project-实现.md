# Lab-project实现

## 1.优化前后对比

### 1.1conditional_shape.mlir

​	优化前代码包含四个函数，其中@select_shape函数实现了基于布尔条件的张量大小选择逻辑，使用scf.if操作在两个预定义的常量大小（100和1000）之间进行选择。@test_with_true_constant和@test_with_false_constant函数通过func.call调用@select_shape，传入编译时常量作为条件，但由于跨函数调用的复杂性，这些调用无法在当前优化阶段被简化。 

```mlir
// Test Case 3: 条件形状选择
// 测试scf dialect的常量条件优化
module {
  func.func @select_shape(%use_large: i1) -> tensor<?xf32> {
    %small_size = arith.constant 100 : index
    %large_size = arith.constant 1000 : index
    
    %selected_size = scf.if %use_large -> index {
      scf.yield %large_size : index
    } else {
      scf.yield %small_size : index  
    }
    
    %tensor = tensor.empty(%selected_size) : tensor<?xf32>
    return %tensor : tensor<?xf32>
  }

  // 常量条件测试 - 应该被优化
  func.func @test_with_true_constant() -> tensor<?xf32> {
    %true = arith.constant 1 : i1
    %result = func.call @select_shape(%true) : (i1) -> tensor<?xf32>
    return %result : tensor<?xf32>
  }
  
  // 另一个常量条件测试
  func.func @test_with_false_constant() -> tensor<?xf32> {
    %false = arith.constant 0 : i1
    %result = func.call @select_shape(%false) : (i1) -> tensor<?xf32>
    return %result : tensor<?xf32>
  }
  
  // 直接的常量条件分支
  func.func @direct_conditional() -> (tensor<?xf32>, tensor<?xf32>) {
    %true_cond = arith.constant 1 : i1
    %false_cond = arith.constant 0 : i1
    
    %dim1 = arith.constant 50 : index
    %dim2 = arith.constant 100 : index
    
    %tensor1 = scf.if %true_cond -> tensor<?xf32> {
      %t = tensor.empty(%dim1) : tensor<?xf32>
      scf.yield %t : tensor<?xf32>
    } else {
      %t = tensor.empty(%dim2) : tensor<?xf32>
      scf.yield %t : tensor<?xf32>
    }
    
    %tensor2 = scf.if %false_cond -> tensor<?xf32> {
      %t = tensor.empty(%dim1) : tensor<?xf32>
      scf.yield %t : tensor<?xf32>
    } else {
      %t = tensor.empty(%dim2) : tensor<?xf32>
      scf.yield %t : tensor<?xf32>
    }
    
    return %tensor1, %tensor2 : tensor<?xf32>, tensor<?xf32>
  }
}
```

​	优化后经过控制流简化和常量折叠优化后，代码实现了分支消除和类型推导。@direct_conditional函数发生了显著的变化：编译器识别出%true_cond和%false_cond都是编译时常量，直接确定了执行路径，完全消除了scf.if条件分支结构。原本的动态分支选择被替换为直接的张量创建操作，tensor.empty(%dim1)和tensor.empty(%dim2)被优化为创建静态形状张量tensor<50xf32>和tensor<100xf32>。函数签名也从返回(tensor<?xf32>, tensor<?xf32>)更新为(tensor<50xf32>, tensor<100xf32>)，准确反映了实际的返回类型。 

```mlir
module {
  func.func @select_shape(%arg0: i1) -> tensor<?xf32> {
    %c100 = arith.constant 100 : index
    %c1000 = arith.constant 1000 : index
    %0 = scf.if %arg0 -> (index) {
      scf.yield %c1000 : index
    } else {
      scf.yield %c100 : index
    }
    %1 = tensor.empty(%0) : tensor<?xf32>
    return %1 : tensor<?xf32>
  }
  func.func @test_with_true_constant() -> tensor<1000xf32> {
    %0 = tensor.empty() : tensor<1000xf32>
    return %0 : tensor<1000xf32>
  }
  func.func @test_with_false_constant() -> tensor<100xf32> {
    %0 = tensor.empty() : tensor<100xf32>
    return %0 : tensor<100xf32>
  }
  func.func @direct_conditional() -> (tensor<50xf32>, tensor<100xf32>) {
    %0 = tensor.empty() : tensor<50xf32>
    %1 = tensor.empty() : tensor<100xf32>
    return %0, %1 : tensor<50xf32>, tensor<100xf32>
  }
}
```

### 1.2conv_shape.mlir

​	优化前 @conv_output_shape函数按照公式(input + 2*padding - kernel) / stride + 1进行逐步计算。 @simple_arithmetic函数提供了一个简化的算术折叠测试案例，通过加法和乘法的组合展示基本的常量计算链。 

```
// Test Case 1: 卷积层输出形状计算
// 测试算术常量折叠功能
module {
  func.func @conv_output_shape() -> (index, index) {
    // 输入参数：224x224 图像，3x3卷积核，步长2，填充1
    %input_h = arith.constant 224 : index
    %input_w = arith.constant 224 : index
    %kernel_size = arith.constant 3 : index
    %stride = arith.constant 2 : index
    %padding = arith.constant 1 : index
    %c1 = arith.constant 1 : index
    %c2 = arith.constant 2 : index
    
    // 卷积输出公式: (input + 2*padding - kernel) / stride + 1
    // 高度计算
    %pad_double = arith.muli %padding, %c2 : index
    %input_padded_h = arith.addi %input_h, %pad_double : index
    %temp_h = arith.subi %input_padded_h, %kernel_size : index
    %output_h_raw = arith.divsi %temp_h, %stride : index
    %final_h = arith.addi %output_h_raw, %c1 : index
    
    // 宽度计算（相同逻辑）
    %input_padded_w = arith.addi %input_w, %pad_double : index
    %temp_w = arith.subi %input_padded_w, %kernel_size : index
    %output_w_raw = arith.divsi %temp_w, %stride : index
    %final_w = arith.addi %output_w_raw, %c1 : index
    
    return %final_h, %final_w : index, index
  }
  
  // 额外测试：简单的算术折叠
  func.func @simple_arithmetic() -> index {
    %a = arith.constant 10 : index
    %b = arith.constant 5 : index
    %c = arith.constant 2 : index
    
    %sum = arith.addi %a, %b : index      // 10 + 5 = 15
    %product = arith.muli %sum, %c : index // 15 * 2 = 30
    
    return %product : index
  }
}
```

​	优化后，可以看到用于获取最终值的中间量已经被消除，直接返回了最终结果。

```
module {
  func.func @conv_output_shape() -> (index, index) {
    %c112 = arith.constant 112 : index
    %c112_0 = arith.constant 112 : index
    return %c112, %c112_0 : index, index
  }
  func.func @simple_arithmetic() -> index {
    %c30 = arith.constant 30 : index
    return %c30 : index
  }
}
```

### 1.3dynamic_shape.mlir

​	优化前代码包含三个函数，每个都包含大量的编译时常量定义和基于这些常量的算术计算。@create_tensors函数通过常量%dim1和%dim2创建多维张量，并计算总元素数量，所有张量都使用动态形状声明。@nested_computation函数模拟了批处理场景下的3D张量创建，涉及batch、height、width三个维度的常量定义。@computed_shape函数实现了更复杂的形状计算链，通过乘法和加法操作计算最终的张量大小（16*3+4=52）。 

```mlir
// Test Case 2: 动态形状推导
// 测试tensor dialect的静态形状转换
module {
  func.func @create_tensors() -> (tensor<?x?xf32>, tensor<?xf32>) {
    %dim1 = arith.constant 10 : index
    %dim2 = arith.constant 20 : index
    
    // 计算总元素数
    %total = arith.muli %dim1, %dim2 : index
    
    // 创建动态形状的张量
    %tensor2d = tensor.empty(%dim1, %dim2) : tensor<?x?xf32>
    %tensor1d = tensor.empty(%total) : tensor<?xf32>
    
    return %tensor2d, %tensor1d : tensor<?x?xf32>, tensor<?xf32>
  }
  
  // 嵌套计算测试
  func.func @nested_computation() -> tensor<?x?x?xf32> {
    %batch = arith.constant 4 : index
    %height = arith.constant 32 : index
    %width = arith.constant 32 : index
    
    // 多维张量创建
    %tensor3d = tensor.empty(%batch, %height, %width) : tensor<?x?x?xf32>
    
    return %tensor3d : tensor<?x?x?xf32>
  }
  
  // 带算术运算的形状计算
  func.func @computed_shape() -> tensor<?xf32> {
    %base = arith.constant 16 : index
    %multiplier = arith.constant 3 : index
    %offset = arith.constant 4 : index
    
    // 计算：16 * 3 + 4 = 52
    %temp = arith.muli %base, %multiplier : index
    %final_size = arith.addi %temp, %offset : index
    
    %tensor = tensor.empty(%final_size) : tensor<?xf32>
    return %tensor : tensor<?xf32>
  }
}
```

​	优化后所有函数的返回类型都从动态形状更新为精确的静态形状：@create_tensors从(tensor<?x?xf32>, tensor<?xf32>)变为(tensor<10x20xf32>, tensor<200xf32>)，@nested_computation从tensor<?x?x?xf32>变为tensor<4x32x32xf32>，@computed_shape从tensor<?xf32>变为tensor<52xf32>。编译器成功执行了常量折叠，将算术计算链替换为预计算的结果，如将%base*%multiplier+%offset的计算直接替换为常量52。 

```mlir
module {
  func.func @create_tensors() -> (tensor<10x20xf32>, tensor<200xf32>) {
    %0 = tensor.empty() : tensor<10x20xf32>
    %1 = tensor.empty() : tensor<200xf32>
    return %0, %1 : tensor<10x20xf32>, tensor<200xf32>
  }
  func.func @nested_computation() -> tensor<4x32x32xf32> {
    %0 = tensor.empty() : tensor<4x32x32xf32>
    return %0 : tensor<4x32x32xf32>
  }
  func.func @computed_shape() -> tensor<52xf32> {
    %0 = tensor.empty() : tensor<52xf32>
    return %0 : tensor<52xf32>
  }
}
```

### 1.4matrix_chain.mlir

​	优化前包含了大量的编译时可确定但未优化的计算。代码中存在多个函数，每个函数都定义了多个常量变量（如%c2、%c3、%c4等），并通过这些常量进行算术运算来计算张量的维度。所有的张量都使用动态形状声明（tensor<?x?xf32>、tensor<?xf32>），需要在运行时传递维度参数给tensor.empty操作。 

```mlir
// Test Case 4: 矩阵操作链
// 测试linalg dialect和综合优化
module {
  func.func @matrix_operations() -> tensor<?x?xf32> {
    %c2 = arith.constant 2 : index
    %c3 = arith.constant 3 : index
    %c4 = arith.constant 4 : index
    %zero = arith.constant 0.0 : f32
    
    // 创建矩阵
    %mat1 = tensor.empty(%c2, %c3) : tensor<?x?xf32>        //2x3x
    %mat2 = tensor.empty(%c3, %c4) : tensor<?x?xf32>        //3x4x
    %output = tensor.empty(%c2, %c4) : tensor<?x?xf32>      //2x4x
    
    // 填充输出矩阵为零
    %filled_output = linalg.fill ins(%zero : f32) outs(%output : tensor<?x?xf32>) -> tensor<?x?xf32>
    
    return %filled_output : tensor<?x?xf32>     //2x4x
  }
  
  // 矩阵尺寸计算
  func.func @compute_matrix_sizes() -> (index, index, index) {
    %rows = arith.constant 8 : index
    %cols = arith.constant 16 : index
    %batch = arith.constant 2 : index
    
    // 计算总大小
    %matrix_size = arith.muli %rows, %cols : index  //128
    %total_size = arith.muli %matrix_size, %batch : index   //256
    
    return %rows, %cols, %total_size : index, index, index      //8 16 256
  }
  
  // 复杂的张量创建链
  func.func @tensor_creation_chain() -> tensor<?x?xf32> {
    // 基础维度
    %base_dim = arith.constant 4 : index
    %scale_factor = arith.constant 3 : index
    %padding = arith.constant 2 : index
    
    // 计算实际维度
    %scaled_dim = arith.muli %base_dim, %scale_factor : index  // 4 * 3 = 12
    %final_dim = arith.addi %scaled_dim, %padding : index      // 12 + 2 = 14
    
    // 创建正方形矩阵
    %matrix = tensor.empty(%final_dim, %final_dim) : tensor<?x?xf32>
    
    return %matrix : tensor<?x?xf32>    //14x14x
  }
  
  // 带有linalg操作的简单情况
  func.func @simple_linalg_ops() -> tensor<?xf32> {
    %size = arith.constant 10 : index
    %fill_value = arith.constant 1.0 : f32
    
    %tensor = tensor.empty(%size) : tensor<?xf32>       //10x
    %filled = linalg.fill ins(%fill_value : f32) outs(%tensor : tensor<?xf32>) -> tensor<?xf32>
    
    return %filled : tensor<?xf32>      //10x
  }
}
```

​	优化后所有动态形状张量都被转换为静态形状（tensor<2x4xf32>、tensor<14x14xf32>、tensor<10xf32>），完全消除了运行时的形状计算开销。常量折叠优化将原本的算术计算链替换为直接的常量值。 

```
module {
  func.func @matrix_operations() -> tensor<2x4xf32> {
    %cst = arith.constant 0.000000e+00 : f32
    %0 = tensor.empty() : tensor<2x3xf32>
    %1 = tensor.empty() : tensor<3x4xf32>
    %2 = tensor.empty() : tensor<2x4xf32>
    %3 = linalg.fill ins(%cst : f32) outs(%2 : tensor<2x4xf32>) -> tensor<2x4xf32>
    return %3 : tensor<2x4xf32>
  }
  func.func @compute_matrix_sizes() -> (index, index, index) {
    %c8 = arith.constant 8 : index
    %c16 = arith.constant 16 : index
    %c256 = arith.constant 256 : index
    return %c8, %c16, %c256 : index, index, index
  }
  func.func @tensor_creation_chain() -> tensor<14x14xf32> {
    %0 = tensor.empty() : tensor<14x14xf32>
    return %0 : tensor<14x14xf32>
  }
  func.func @simple_linalg_ops() -> tensor<10xf32> {
    %cst = arith.constant 1.000000e+00 : f32
    %0 = tensor.empty() : tensor<10xf32>
    %1 = linalg.fill ins(%cst : f32) outs(%0 : tensor<10xf32>) -> tensor<10xf32>
    return %1 : tensor<10xf32>
  }
}
```



## 2.主要优化函数说明

### **2.1折叠算术运算**

​	这里只说明加法折叠，减法、乘法、除法的逻辑与加法基本一致

```cpp
    bool foldArithmeticOperations(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<Operation*, 8> toErase; // 初始预分配8个元素的空间，大多数情况下足够使用
        bool changed = false;   // 标记是否发生了任何优化，用于通知调用者重新开始优化轮次
        
        // 处理加法
        module->walk([&](arith::AddIOp addOp) {
            auto lhsConst = getConstantIntValue(addOp.getLhs(), constantMap);   // 尝试获取左操作数的常量值
            auto rhsConst = getConstantIntValue(addOp.getRhs(), constantMap);   // 尝试获取右操作数的常量值
            
            if (lhsConst && rhsConst) {  // 检查两个操作数是否都是常量
                int64_t result = *lhsConst + *rhsConst; // 编译时计算加法结果
                OpBuilder builder(addOp);   // 创建IR构建器，位置设在当前加法操作处，新创建的常量将插入到这个位置
                auto newConst = createIntConstant(builder, addOp.getLoc(), result, addOp.getType());    // 创建新的常量操作来替换加法运算，使用原操作的位置信息、计算结果和类型
                addOp.getResult().replaceAllUsesWith(newConst.getResult());     //将原加法操作的所有使用替换为新常量，这会更新IR中所有引用原加法结果的地方
                toErase.push_back(addOp);   // 标记原加法操作待删除（不能立即删除，因为还在遍历中）
                changed = true; // 标记发生了优化
            }
        });
```

###  2.2Linalg操作类型不匹配问题 

​	 在MLIR优化过程中，linalg操作类型不匹配通常发生在以下场景： 

​		 形状推导优化后的类型不同步 

```mlir
// 优化前：动态形状
%tensor = tensor.empty(%dim1, %dim2) : tensor<?x?xf32>
%filled = linalg.fill ins(%value : f32) outs(%tensor : tensor<?x?xf32>) -> tensor<?x?xf32>

// 形状推导优化后：输入变成静态形状，但linalg.fill声明还是动态形状
%tensor = tensor.empty() : tensor<10x20xf32>  // ← 输入已经是静态形状
%filled = linalg.fill ins(%value : f32) outs(%tensor : tensor<10x20xf32>) -> tensor<?x?xf32>
//                                                                               ^^^^^^^^^^^^^^^^
//                                                                              声明的输出类型还是动态的
```

​		 常量折叠导致的类型变化 

```
// 优化前
%c10 = arith.constant 10 : index
%c20 = arith.constant 20 : index  
%tensor = tensor.empty(%c10, %c20) : tensor<?x?xf32>
%filled = linalg.fill ins(%zero : f32) outs(%tensor : tensor<?x?xf32>) -> tensor<?x?xf32>

// 常量折叠后：tensor.empty的类型变了，但linalg.fill的返回类型声明没更新
%tensor = tensor.empty() : tensor<10x20xf32>
%filled = linalg.fill ins(%zero : f32) outs(%tensor : tensor<10x20xf32>) -> tensor<?x?xf32>
//        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
//        输入是 tensor<10x20xf32>，但声明返回 tensor<?x?xf32>
```

​	在Lab-project中matrix_chain.mlir文件中，@matrix_operations和@simple_linglg_ops这两个函数就会遇到这个问题。

```mlir
func.func @matrix_operations() -> tensor<?x?xf32> {  // ← 函数签名还是动态
    %c2 = arith.constant 2 : index
    %c3 = arith.constant 3 : index  
    %c4 = arith.constant 4 : index
    %zero = arith.constant 0.0 : f32
    
    // 经过常量折叠和形状推导后，tensor.empty被优化
    %output = tensor.empty() : tensor<2x4xf32>  // ← 输入已变成静态类型
    
    // 但linalg.fill的类型声明还没更新
    %filled_output = linalg.fill ins(%zero : f32) outs(%output : tensor<2x4xf32>) -> tensor<?x?xf32>
    //                                                                              ^^^^^^^^^^^^^^^^^
    //                                                                              问题：声明还是动态类型
    return %filled_output : tensor<?x?xf32>
}

func.func @simple_linalg_ops() -> tensor<?xf32> {  // ← 函数签名还是动态
    %size = arith.constant 10 : index
    %fill_value = arith.constant 1.0 : f32
    
    // 经过常量折叠后，tensor.empty被优化
    %tensor = tensor.empty() : tensor<10xf32>  // ← 输入已变成静态类型
    
    // 但linalg.fill的类型声明还没更新
    %filled = linalg.fill ins(%fill_value : f32) outs(%tensor : tensor<10xf32>) -> tensor<?xf32>
    //                                                                             ^^^^^^^^^^^^^^
    //                                                                             问题：声明还是动态类型
    return %filled : tensor<?xf32>
}
```

​	这种问题一般是Pass的执行顺序导致的。

​	**fixLinalgOperations函数**就是来修复这个问题的

```cpp
    bool fixLinalgOperations(ModuleOp module) {
        SmallVector<std::pair<Operation*, Operation*>, 4> replacements; //std::pair<Operation*, Operation*>：存储操作对，第一个是旧操作，第二个是新操作
        bool changed = false;   //记录是否发生了任何修复
        
        module->walk([&](linalg::FillOp fillOp) {
            // 获取输入张量和输出类型
            Value inputTensor = fillOp.getOutputs()[0]; //fillOp.getOutputs()[0]：获取fill操作的第一个输出参数（要填充的张量）
            Type actualInputType = inputTensor.getType();   //获取输入的类型
            Type declaredOutputType = fillOp.getResult(0).getType();    //获取输出的类型
            
            // 如果输入类型和声明的输出类型不匹配，需要修复
            if (actualInputType != declaredOutputType) {
                OpBuilder builder(fillOp);
                
                // 获取填充值
                Value fillValue = fillOp.getInputs()[0];
                
                // 创建新的linalg.fill操作，输出类型与输入类型匹配
                auto newFillOp = builder.create<linalg::FillOp>(
                    fillOp.getLoc(),
                    TypeRange{actualInputType}, // 明确指定输出类型
                    fillValue,
                    inputTensor
                );
                
                replacements.push_back({fillOp, newFillOp});    //将旧操作和新操作的配对添加到替换列表
                changed = true;
            }
        });
        
        // 执行替换
        for (auto& pair : replacements) {   //遍历所有需要替换的操作对
            Operation* oldOp = pair.first;
            Operation* newOp = pair.second;
            
            // 替换所有使用
            for (unsigned i = 0; i < oldOp->getNumResults(); ++i) {
                oldOp->getResult(i).replaceAllUsesWith(newOp->getResult(i));    //将旧操作第i个结果的所有使用替换为新操作的对应结果
            }
            
            // 删除旧操作
            oldOp->erase();
        }
        
        return changed;
    }
```

### 2.3静态形状推导

```cpp
    bool propagateStaticShapes(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<tensor::EmptyOp, 4> toReplace;  //存储需要替换的tensor.empty操作
        SmallVector<linalg::FillOp, 4> linalgToFix;     //存储需要替换的tensor.empty操作
        bool changed = false;
        
        module->walk([&](tensor::EmptyOp emptyOp) {
            // 检查所有动态维度是否都是常量
            SmallVector<int64_t, 4> staticSizes;
            bool allStatic = true;
            
            for (Value dynamicSize : emptyOp.getDynamicSizes()) {   //遍历tensor.empty的所有动态维度参数，getDynamicSizes()：返回动态维度的Value列表
                auto constValue = getConstantIntValue(dynamicSize, constantMap);    //尝试从常量映射中获取维度的整数值
                if (constValue) {
                    staticSizes.push_back(*constValue);     //如果是常量，添加到staticSizes
                } else {
                    allStatic = false;      //如果不是常量，标记为非全静态并退出循环
                    break;
                }
            }
            
            if (allStatic && !emptyOp.getDynamicSizes().empty()) {      //只有当所有动态维度都是常量且确实存在动态维度时才优化
                // 创建静态形状的张量类型
                auto currentType = llvm::cast<RankedTensorType>(emptyOp.getType());     //获取当前张量的类型并安全转换为RankedTensorType
                auto shape = currentType.getShape().vec();      //获取形状的可修改副本
                
                // 替换动态维度（-1）为静态值
                int dynamicIdx = 0;
                for (size_t i = 0; i < shape.size(); ++i) {     //遍历形状的每一个维度
                    if (shape[i] == ShapedType::kDynamic) {     //ShapedType::kDynamic：MLIR中表示动态维度的常量（-1）
                        shape[i] = staticSizes[dynamicIdx++];   //用实际常量值替换动态维度标记
                    }
                }
                
                // 创建新的静态张量类型，使用静态形状但保持相同元素类型
                auto newType = RankedTensorType::get(shape, currentType.getElementType());
                
                // 创建新的empty操作（不需要动态尺寸）
                OpBuilder builder(emptyOp);
                auto newEmptyOp = builder.create<tensor::EmptyOp>(
                    emptyOp.getLoc(), newType, ValueRange{}
                );
                
                //替换所有使用，标记待删除，设置变化标志
                emptyOp.getResult().replaceAllUsesWith(newEmptyOp.getResult());
                toReplace.push_back(emptyOp);
                changed = true;
                
                // 检查并收集需要修复的linalg.fill操作
                for (auto user : newEmptyOp.getResult().getUsers()) {
                    if (auto fillOp = dyn_cast<linalg::FillOp>(user)) {
                        linalgToFix.push_back(fillOp);
                    }
                }
            }
        });
        
        // 删除旧的tensor.empty操作
        for (auto op : toReplace) {
            op->erase();
        }
        
        // 修复受影响的linalg操作
        for (auto fillOp : linalgToFix) {
            Value inputTensor = fillOp.getOutputs()[0];
            Type actualInputType = inputTensor.getType();
            Type declaredOutputType = fillOp.getResult(0).getType();
            
            if (actualInputType != declaredOutputType) {
                OpBuilder builder(fillOp);
                Value fillValue = fillOp.getInputs()[0];
                
                // 创建新的linalg.fill，输出类型与输入类型匹配
                auto newFillOp = builder.create<linalg::FillOp>(
                    fillOp.getLoc(),
                    fillValue,
                    inputTensor
                );
                
                fillOp.getResult(0).replaceAllUsesWith(newFillOp.getResult(0));
                fillOp->erase();
                changed = true;
            }
        }
        
        return changed;
    }
```

### 2.4简化控制流

```cpp
    bool simplifyControlFlow(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<scf::IfOp, 4> toReplace;        //存储需要替换的if操作
        bool changed = false;
        
        module->walk([&](scf::IfOp ifOp) {      //遍历所有scf.if操作
            auto conditionValue = getConstantBoolValue(ifOp.getCondition(), constantMap);       //尝试获取条件的常量布尔值
            
            if (conditionValue) {   //如果条件是常量
                OpBuilder builder(ifOp);
                
                // 根据条件值选择then或else分支     解引用optional获取布尔值
                Region *selectedRegion = *conditionValue ? &ifOp.getThenRegion() : &ifOp.getElseRegion();
                
                // 将选中分支的操作移动到if操作之前
                Block *selectedBlock = &selectedRegion->front();
                Operation *insertPoint = ifOp;  //设置插入点为if操作位置
                
                // 收集分支中的操作（除了yield）
                SmallVector<Operation*, 4> opsToMove;
                for (Operation &op : selectedBlock->getOperations()) {
                    if (!isa<scf::YieldOp>(op)) {
                        opsToMove.push_back(&op);
                    }
                }
                
                // 将收集的操作移动到if之前
                for (Operation *op : opsToMove) {
                    op->moveBefore(insertPoint);
                }
                
                // 处理返回值
                if (ifOp.getNumResults() > 0) { //如果if操作有返回值
                    auto yieldOp = cast<scf::YieldOp>(selectedBlock->getTerminator());      //获取分支的终结操作（yield）
                    for (unsigned i = 0; i < ifOp.getNumResults(); ++i) {       //将if的结果替换为yield的操作数
                        ifOp.getResult(i).replaceAllUsesWith(yieldOp.getOperand(i));
                    }
                }
                
                toReplace.push_back(ifOp);
                changed = true;
            }
        });
        
        // 删除已优化的if操作
        for (auto ifOp : toReplace) {
            ifOp->erase();
        }
        
        return changed;
    }
```

### **2.5死代码移除**

​	死代码指的是程序中永远不会被执行或者其结果永远不会被使用的代码。进行死代码移除可以优化性能、优化内存使用、优化编译等。

​	例如

```mlir
func.func @unreachable_code() -> index {
    %result = arith.constant 42 : index
    return %result : index
    
    // 以下代码永远不会执行（死代码），因为上面已经return了，所以下面的代码永远不会执行
    %dead = arith.constant 100 : index    // ← 死代码
    %more_dead = arith.addi %dead, %dead : index // ← 死代码
}
```

```mlir
func.func @unused_result() -> index {
    %unused = arith.constant 100 : index     // ← 死代码：结果未使用
    %used = arith.constant 42 : index        // ← 活代码：结果被使用
    return %used : index
}
```

```mlir
func.func @dead_branch() -> index {
    %false_cond = arith.constant 0 : i1
    
    %result = scf.if %false_cond -> index {
        // 这个分支永远不会执行（死代码）
        %dead = arith.constant 100 : index    // ← 死代码
        scf.yield %dead : index
    } else {
        %live = arith.constant 42 : index     // ← 活代码
        scf.yield %live : index  
    }
    return %result : index
}
```

​	在Lab-project中，conv_shape.mlir中就有许多“死代码”， 在这个例子中，这些代码被称为"死代码"是因为它们在优化过程中会被消除，而不是因为它们永远不会被执行。 由于所有输入都是常量，所有基于这些常量的计算都可以在编译时完成。优化过程如下 

​	识别常量：

```mlir
// 所有输入都是编译时常量
%input_h = arith.constant 224 : index           // 编译时常量
%input_w = arith.constant 224 : index           // 编译时常量  
%kernel_size = arith.constant 3 : index         // 编译时常量
%stride = arith.constant 2 : index              // 编译时常量
%padding = arith.constant 1 : index             // 编译时常量
%c1 = arith.constant 1 : index                  // 编译时常量
%c2 = arith.constant 2 : index                  // 编译时常量
```

​	 编译器执行常量折叠时： 

```mlir
// 步骤1：%padding * %c2
%pad_double = arith.muli %padding, %c2 : index  
// 编译器计算：1 * 2 = 2，替换为：
%pad_double = arith.constant 2 : index

// 步骤2：%input_h + %pad_double  
%input_padded_h = arith.addi %input_h, %pad_double : index
// 编译器计算：224 + 2 = 226，替换为：
%input_padded_h = arith.constant 226 : index

// 步骤3：继续折叠...
%temp_h = arith.subi %input_padded_h, %kernel_size : index
// 编译器计算：226 - 3 = 223，替换为：
%temp_h = arith.constant 223 : index

// 步骤4：
%output_h_raw = arith.divsi %temp_h, %stride : index  
// 编译器计算：223 / 2 = 111，替换为：
%output_h_raw = arith.constant 111 : index

// 步骤5：
%final_h = arith.addi %output_h_raw, %c1 : index
// 编译器计算：111 + 1 = 112，替换为：
%final_h = arith.constant 112 : index
```

​	 经过常量折叠后： 

```
func.func @conv_output_shape() -> (index, index) {
    // 这些常量定义现在没有用户了
    %input_h = arith.constant 224 : index           // ← 现在是死代码
    %input_w = arith.constant 224 : index           // ← 现在是死代码
    %kernel_size = arith.constant 3 : index         // ← 现在是死代码
    %stride = arith.constant 2 : index              // ← 现在是死代码
    %padding = arith.constant 1 : index             // ← 现在是死代码
    %c1 = arith.constant 1 : index                  // ← 现在是死代码
    %c2 = arith.constant 2 : index                  // ← 现在是死代码
    
    // 这些中间计算已经被替换为常量
    // 原始的算术操作现在是死代码
    %final_h = arith.constant 112 : index           // 直接是结果
    %final_w = arith.constant 112 : index           // 直接是结果
    
    return %final_h, %final_w : index, index
}
```

​	最终 ，死代码消除pass移除所有未使用的操作： 

```
  func.func @conv_output_shape() -> (index, index) {
    %c112 = arith.constant 112 : index
    %c112_0 = arith.constant 112 : index
    return %c112, %c112_0 : index, index
  }
```

​	死代码消除的函数如下

```cpp
    bool removeDeadCode(ModuleOp module) {
        SmallVector<Operation*, 16> toErase;    //预分配16个元素空间的删除列表
        bool changed = false;
        
        // 多次迭代，直到没有更多死代码
        bool foundDeadCode = true;
        while (foundDeadCode) {
            foundDeadCode = false;      //重置标志和清空删除列表
            toErase.clear();
            
            module->walk([&](Operation *op) {
                // 跳过没有结果的操作（无结果的操作通常有副作用，不删除）
                if (op->getNumResults() == 0) {
                    return;
                }
                
                // 跳过函数和模块级操作，重要的结构性操作
                if (isa<func::FuncOp, ModuleOp>(op)) {
                    return;
                }
                
                // 检查所有结果是否都未被使用
                bool allUnused = true;
                for (Value result : op->getResults()) {     //遍历所有结果
                    if (!result.getUses().empty()) {    //如果使用者非空，设置allUnused为false，跳出循环
                        allUnused = false;
                        break;
                    }
                }
                
                // 只删除确实未使用的常量操作
                if (allUnused && isa<arith::ConstantOp>(op)) {
                    toErase.push_back(op);
                    foundDeadCode = true;
                    changed = true;
                }
            });
            
            // 删除这一轮找到的死代码
            for (Operation *op : toErase) {
                op->erase();
            }
        }
        
        return changed;
    }
```

### **2.6更新函数签名**

​	为什么需要更新函数签名？

​	 在MLIR优化过程中，函数体内的操作可能会发生类型变化，但函数的声明（签名）没有自动更新，这会导致： 

 1. 类型不一致：函数声明说返回`i32`，但实际返回了`i64` 

 2.  验证失败：MLIR的类型检查器会报错 

 3.  后续优化受阻：类型不匹配阻止进一步优化 

    比如

    ```
    // 优化前：函数签名声明返回i32
    func.func @example() -> i32 {
        %0 = arith.constant 42 : i32
        return %0 : i32
    }
    
    // 经过某种优化后：常量被提升为i64，但函数签名未更新
    func.func @example() -> i32 {    // ← 签名还是i32，但实际返回i64
        %0 = arith.constant 42 : i64  // ← 类型变成了i64
        return %0 : i64               // ← 返回i64
    }
    // 这种不一致会导致验证错误！
    ```

    ​	再例如在dynamic_shape.mlir中的create_tensors函数中，优化前函数返回是 (tensor<?x?xf32>, tensor<?xf32>) ，但是经过优化后实际返回是 (tensor<10x20xf32>, tensor<200xf32>) ，这就出现了不一致，如果不更新的话优化mlir文件时就会报错。

    ​	更新函数签名函数

    ```cpp
      /**
         * 更新函数签名以匹配优化后的类型
         */
        bool updateFunctionSignatures(ModuleOp module) {
            bool changed = false;
            
            module->walk([&](func::FuncOp funcOp) {     //遍历模块中的所有函数操作
                // 收集返回操作中的实际类型
                SmallVector<Type, 4> newResultTypes;
                bool needsUpdate = false;
                
                funcOp->walk([&](func::ReturnOp returnOp) {     //在当前函数内查找所有return操作
                    newResultTypes.clear();     //清空之前的类型记录
                    for (Value operand : returnOp.getOperands()) {      //遍历return操作的所有操作数
                        newResultTypes.push_back(operand.getType());    //获取每个返回值的实际类型
                    }
                    
                    // 检查是否与函数签名匹配
                    auto currentResultTypes = funcOp.getFunctionType().getResults();    //获取函数签名中声明的返回类型，用于与实际类型比较
                    if (newResultTypes.size() != currentResultTypes.size()) {
                        return;     //如果实际返回值数量与声明不符，直接返回
                    }
                    
                    for (size_t i = 0; i < newResultTypes.size(); ++i) {    //比较每个位置的实际类型与声明类型
                        if (newResultTypes[i] != currentResultTypes[i]) {
                            needsUpdate = true;     //一旦发现不匹配就设置needsUpdate = true并退出循环
                            break;
                        }
                    }
                });
                
                //执行签名更新
                if (needsUpdate && !newResultTypes.empty()) {   //如果needsUpdate为true且新的类型不为空
                    // 创建新的函数类型
                    auto newFuncType = FunctionType::get(
                        funcOp.getContext(),
                        funcOp.getFunctionType().getInputs(),   //保持原有的输入参数类型不变
                        newResultTypes      //使用新的返回类型
                    );
                    
                    // 更新函数类型
                    funcOp.setFunctionType(newFuncType);
                    changed = true;
                }
            });
            
            return changed;
        }
    ```

### 2.7内联函数inlineSimpleFunctions**

 	函数内联（Function Inlining）是编译器优化技术，将函数调用替换为函数体的直接代码。 

​	 基本示例：

```
func.func @add(%a: index, %b: index) -> index {
  %result = arith.addi %a, %b : index
  return %result : index
}

func.func @main() -> index {
  %c10 = arith.constant 10 : index
  %c20 = arith.constant 20 : index
  %sum = func.call @add(%c10, %c20) : (index, index) -> index  // 函数调用
  return %sum : index
}

//上面是mlir原代码，下面是内联后的代码

func.func @add(%a: index, %b: index) -> index {
  %result = arith.addi %a, %b : index
  return %result : index
}

func.func @main() -> index {
  %c10 = arith.constant 10 : index
  %c20 = arith.constant 20 : index
  // 原本是func.call @add，调用add函数，这里直接插入函数体，无需调用
  %result = arith.addi %c10, %c20 : index
  %sum = %result
  return %sum : index
}
```

​	内联的作用可以减少调用开销，更重要的是可以暴露更多优化机会。

​	比如

```
func.func @helper(%x: index) -> index {
  %c2 = arith.constant 2 : index
  %doubled = arith.muli %x, %c2 : index
  return %doubled : index
}

func.func @main() -> index {
  %c10 = arith.constant 10 : index
  %result = func.call @helper(%c10) : (index) -> index
  return %result : index
}		//%x和%c10的关联被函数调用隔离，而内联后

func.func @main() -> index {
  %c10 = arith.constant 10 : index
  %c2 = arith.constant 2 : index
  %doubled = arith.muli %c10, %c2 : index  // 现在可以看到都是常量！
  %result = %doubled
  return %result : index
}
```

​	而在Lab-project中，conditional_shape.mlir文件的优化就需要函数内联。在这个文件中，@test_with_true_constant调用@select_shape，编译器无法知道%use_large参数的值 ，scf.if无法被优化，形状推导无法进行。

```
func.func @select_shape(%use_large: i1) -> tensor<?xf32> {
  %small_size = arith.constant 100 : index
  %large_size = arith.constant 1000 : index
  %selected_size = scf.if %use_large -> index {
    scf.yield %large_size : index
  } else {
    scf.yield %small_size : index  
  }
  %tensor = tensor.empty(%selected_size) : tensor<?xf32>
  return %tensor : tensor<?xf32>
}

// 这里是内联的关键目标！
func.func @test_with_true_constant() -> tensor<?xf32> {
  %true = arith.constant 1 : i1
  %result = func.call @select_shape(%true) : (i1) -> tensor<?xf32>
  return %result : tensor<?xf32>
}

//这里内联后变成
func.func @test_with_true_constant() -> tensor<?xf32> {
     %true = arith.constant 1 : i1
     // 内联后的代码：
     %small_size = arith.constant 100 : index
     %large_size = arith.constant 1000 : index
     %selected_size = scf.if %true -> index {  // 现在条件是常量！
       scf.yield %large_size : index
     } else {
       scf.yield %small_size : index  
     }
     %tensor = tensor.empty(%selected_size) : tensor<?xf32>
     return %tensor : tensor<?xf32>
   }
```

### 2.8主要函数runOnOperation

​	这个函数主要是Pass的主要执行入口点，函数如下，加入了一些日志方便调试优化信息。

```cpp
    void runOnOperation() override {    //Pass的主要执行入口点
        ModuleOp module = getOperation();   //获取当前要处理的模块操作
        
        llvm::outs() << "ShapeOptimizerPass: 开始优化...\n";    //输出调试信息
        
        // 主优化循环 - 迭代直到收敛
        bool globalChanged = true;      //标记是否有任何优化发生
        int iteration = 0;      //记录迭代轮数
        
        while (globalChanged && iteration < 10) { // 防止无限循环   当有优化发生且未超过最大迭代次数时继续  限制10轮防止无限循环
            globalChanged = false;  //设置为false，下面如果有优化函数调用，在具体函数实现里设置为true
            iteration++;    //增加迭代计数器
            
            llvm::outs() << "  第 " << iteration << " 轮优化:\n";   //输出当前轮次信息
            
            // Phase 1: 收集常量
            DenseMap<Value, Attribute> constantMap;     //创建从MLIR Value到常量属性的映射
            collectConstants(module, constantMap);      //调用辅助方法收集所有常量
            llvm::outs() << "    收集到 " << constantMap.size() << " 个常量\n";     //输出收集到的常量数量
            
            //函数内联（提前执行，让常量能传播）
            bool inlineChanged = inlineSimpleFunctions(module, constantMap);
            if (inlineChanged) {
                llvm::outs() << "    函数内联: 有优化\n";
                globalChanged = true;
                continue; // 重新开始，因为内联可能创建新的优化机会
            }
            
            // Phase 2: 算术折叠
            bool arithChanged = foldArithmeticOperations(module, constantMap);
            if (arithChanged) {
                llvm::outs() << "    算术折叠: 有优化\n";
                globalChanged = true;
                continue; // 重新开始，因为常量可能发生变化
            }
            
            // Phase 3: 静态形状推导
            bool shapeChanged = propagateStaticShapes(module, constantMap);
            if (shapeChanged) {
                llvm::outs() << "    形状推导: 有优化\n";
                globalChanged = true;
            }
            
            // Phase 4: 控制流简化
            bool controlFlowChanged = simplifyControlFlow(module, constantMap);
            if (controlFlowChanged) {
                llvm::outs() << "    控制流简化: 有优化\n";
                globalChanged = true;
            }
            
            // Phase 6: 更新函数签名
            bool signatureChanged = updateFunctionSignatures(module);
            if (signatureChanged) {
                llvm::outs() << "    函数签名更新: 有优化\n";
                globalChanged = true;
            }
            
            // Phase 7: 死代码消除（在函数签名更新之后）
            bool deadCodeChanged = removeDeadCode(module);
            if (deadCodeChanged) {
                llvm::outs() << "    死代码消除: 有优化\n";
                globalChanged = true;
            }
        }
        
        llvm::outs() << "ShapeOptimizerPass: 优化完成，共 " << iteration << " 轮\n";
    }
```

## 3.完整代码

### 	3.1ShapeOptimizerPass.h

```cpp
/**
 * ShapeOptimizerPass.h
 * 
 * 实现ML形状计算优化Pass，包括：
 * 1. 算术常量折叠（arith.addi, arith.muli等）
 * 2. 张量形状推导（tensor.empty）
 * 3. 控制流优化（scf.if）
 * 4. 函数内联优化
 */

#ifndef SHAPE_OPTIMIZER_PASS_H
#define SHAPE_OPTIMIZER_PASS_H

#include "mlir/Pass/Pass.h"     //包含MLIR Pass框架的基础类，提供Pass的基本结构
#include "mlir/IR/BuiltinOps.h"     //包含MLIR内置操作，如ModuleOp等
#include "mlir/IR/MLIRContext.h"       //包含MLIR上下文管理，用于创建和管理MLIR对象
#include "mlir/IR/PatternMatch.h"       //包含模式匹配框架，用于查找和替换IR模式
#include "mlir/IR/Builders.h"       //包含IR构建器，用于创建新的MLIR操作

// Dialect headers
#include "mlir/Dialect/Func/IR/FuncOps.h"       //包含函数dialect的操作定义（func.func, func.call, func.return等）
#include "mlir/Dialect/Arith/IR/Arith.h"    //包含算术dialect的操作（arith.constant, arith.addi, arith.muli等）
#include "mlir/Dialect/Tensor/IR/Tensor.h"  //包含张量dialect的操作（tensor.empty等）
#include "mlir/Dialect/SCF/IR/SCF.h"    //包含结构化控制流dialect（scf.if, scf.yield等）
#include "mlir/Dialect/Linalg/IR/Linalg.h"  //包含线性代数dialect（linalg.fill等）

// Utilities
#include "llvm/ADT/DenseMap.h"      //LLVM的高效哈希映射容器，用于存储Value到Attribute的映射
#include "llvm/ADT/SmallVector.h"       //LLVM的小向量容器，对小数据集优化的动态数组
#include <optional>     //C++17的可选值类型，用于表示可能不存在的值

namespace mlir {

class ShapeComputeOptimizerPass : public PassWrapper<ShapeComputeOptimizerPass, OperationPass<ModuleOp>> {
public:
    // Required for LLVM 20.x
    MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ShapeComputeOptimizerPass)
    
    StringRef getArgument() const final {   //final关键字表示子类不能重写此方法
        return "shape-optimizer";   //定义Pass的命令行参数名称，用户可以通过--shape-optimizer来调用这个Pass
    }
    
    StringRef getDescription() const final {    //定义Pass的描述信息，在帮助信息中显示
        return "Optimize ML shape computations by folding constants and deriving static shapes"; 
    }

    void runOnOperation() override {    //Pass的主要执行入口点
        ModuleOp module = getOperation();   //获取当前要处理的模块操作
        
        llvm::outs() << "ShapeOptimizerPass: 开始优化...\n";    //输出调试信息
        
        // 主优化循环 - 迭代直到收敛
        bool globalChanged = true;      //标记是否有任何优化发生
        int iteration = 0;      //记录迭代轮数
        
        while (globalChanged && iteration < 10) { // 防止无限循环   当有优化发生且未超过最大迭代次数时继续  限制10轮防止无限循环
            globalChanged = false;  //设置为false，下面如果有优化函数调用，在具体函数实现里设置为true
            iteration++;    //增加迭代计数器
            
            llvm::outs() << "  第 " << iteration << " 轮优化:\n";   //输出当前轮次信息
            
            // Phase 1: 收集常量
            DenseMap<Value, Attribute> constantMap;     //创建从MLIR Value到常量属性的映射
            collectConstants(module, constantMap);      //调用辅助方法收集所有常量
            llvm::outs() << "    收集到 " << constantMap.size() << " 个常量\n";     //输出收集到的常量数量
            
            //函数内联（提前执行，让常量能传播）
            bool inlineChanged = inlineSimpleFunctions(module, constantMap);
            if (inlineChanged) {
                llvm::outs() << "    函数内联: 有优化\n";
                globalChanged = true;
                continue; // 重新开始，因为内联可能创建新的优化机会
            }
            
            // Phase 2: 算术折叠
            bool arithChanged = foldArithmeticOperations(module, constantMap);
            if (arithChanged) {
                llvm::outs() << "    算术折叠: 有优化\n";
                globalChanged = true;
                continue; // 重新开始，因为常量可能发生变化
            }
            
            // Phase 3: 静态形状推导
            bool shapeChanged = propagateStaticShapes(module, constantMap);
            if (shapeChanged) {
                llvm::outs() << "    形状推导: 有优化\n";
                globalChanged = true;
            }
            
            // Phase 4: 控制流简化
            bool controlFlowChanged = simplifyControlFlow(module, constantMap);
            if (controlFlowChanged) {
                llvm::outs() << "    控制流简化: 有优化\n";
                globalChanged = true;
            }
            
            // Phase 6: 更新函数签名
            bool signatureChanged = updateFunctionSignatures(module);
            if (signatureChanged) {
                llvm::outs() << "    函数签名更新: 有优化\n";
                globalChanged = true;
            }
            
            // Phase 7: 死代码消除（在函数签名更新之后）
            bool deadCodeChanged = removeDeadCode(module);
            if (deadCodeChanged) {
                llvm::outs() << "    死代码消除: 有优化\n";
                globalChanged = true;
            }
        }
        
        llvm::outs() << "ShapeOptimizerPass: 优化完成，共 " << iteration << " 轮\n";
    }

private:
    /**
     * 收集模块中的所有常量
     */
    void collectConstants(ModuleOp module, DenseMap<Value, Attribute> &constantMap) {
        module->walk([&](arith::ConstantOp constOp) {   //lambda函数，捕获constantMap的引用，walk方法传入参数为ConstantOp
            constantMap[constOp.getResult()] = constOp.getValue();  //constOp.getResult()：获取常量操作的结果Value  constOp.getValue()：获取常量的Attribute值   constantMap[key] = value：在映射中建立关联
        });
    }
    
    /**
     * 折叠算术运算
     * 返回：是否有任何更改
     */
    bool foldArithmeticOperations(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<Operation*, 8> toErase; // 初始预分配8个元素的空间，大多数情况下足够使用
        bool changed = false;   // 标记是否发生了任何优化，用于通知调用者重新开始优化轮次
        
        // 处理加法
        module->walk([&](arith::AddIOp addOp) {
            auto lhsConst = getConstantIntValue(addOp.getLhs(), constantMap);   // 尝试获取左操作数的常量值
            auto rhsConst = getConstantIntValue(addOp.getRhs(), constantMap);   // 尝试获取右操作数的常量值
            
            if (lhsConst && rhsConst) {  // 检查两个操作数是否都是常量
                int64_t result = *lhsConst + *rhsConst; // 编译时计算加法结果
                OpBuilder builder(addOp);   // 创建IR构建器，位置设在当前加法操作处，新创建的常量将插入到这个位置
                auto newConst = createIntConstant(builder, addOp.getLoc(), result, addOp.getType());    // 创建新的常量操作来替换加法运算，使用原操作的位置信息、计算结果和类型
                addOp.getResult().replaceAllUsesWith(newConst.getResult());     //将原加法操作的所有使用替换为新常量，这会更新IR中所有引用原加法结果的地方
                toErase.push_back(addOp);   // 标记原加法操作待删除（不能立即删除，因为还在遍历中）
                changed = true; // 标记发生了优化
            }
        });
        
        // 处理乘法
        module->walk([&](arith::MulIOp mulOp) {
            auto lhsConst = getConstantIntValue(mulOp.getLhs(), constantMap);
            auto rhsConst = getConstantIntValue(mulOp.getRhs(), constantMap);
            
            if (lhsConst && rhsConst) {
                int64_t result = *lhsConst * *rhsConst;
                OpBuilder builder(mulOp);
                auto newConst = createIntConstant(builder, mulOp.getLoc(), result, mulOp.getType());
                mulOp.getResult().replaceAllUsesWith(newConst.getResult());
                toErase.push_back(mulOp);
                changed = true;
            }
        });
        
        // 处理减法
        module->walk([&](arith::SubIOp subOp) {
            auto lhsConst = getConstantIntValue(subOp.getLhs(), constantMap);
            auto rhsConst = getConstantIntValue(subOp.getRhs(), constantMap);
            
            if (lhsConst && rhsConst) {
                int64_t result = *lhsConst - *rhsConst;
                OpBuilder builder(subOp);
                auto newConst = createIntConstant(builder, subOp.getLoc(), result, subOp.getType());
                subOp.getResult().replaceAllUsesWith(newConst.getResult());
                toErase.push_back(subOp);
                changed = true;
            }
        });
        
        // 处理除法
        module->walk([&](arith::DivSIOp divOp) {
            auto lhsConst = getConstantIntValue(divOp.getLhs(), constantMap);
            auto rhsConst = getConstantIntValue(divOp.getRhs(), constantMap);
            
            if (lhsConst && rhsConst && *rhsConst != 0) {
                int64_t result = *lhsConst / *rhsConst;
                OpBuilder builder(divOp);
                auto newConst = createIntConstant(builder, divOp.getLoc(), result, divOp.getType());
                divOp.getResult().replaceAllUsesWith(newConst.getResult());
                toErase.push_back(divOp);
                changed = true;
            }
        });
        
        // 删除已优化的操作
        for (Operation *op : toErase) {
            op->erase();
        }
        
        return changed;  // 返回是否发生了优化，如果返回true，调用者通常会重新开始优化轮次以处理新产生的常量
    }
    
    /**
     * 修复linalg操作的类型不匹配问题
     */
    bool fixLinalgOperations(ModuleOp module) {
        SmallVector<std::pair<Operation*, Operation*>, 4> replacements; //std::pair<Operation*, Operation*>：存储操作对，第一个是旧操作，第二个是新操作
        bool changed = false;   //记录是否发生了任何修复
        
        module->walk([&](linalg::FillOp fillOp) {
            // 获取输入张量和输出类型
            Value inputTensor = fillOp.getOutputs()[0]; //fillOp.getOutputs()[0]：获取fill操作的第一个输出参数（要填充的张量）
            Type actualInputType = inputTensor.getType();   //获取输入的类型
            Type declaredOutputType = fillOp.getResult(0).getType();    //获取输出的类型
            
            // 如果输入类型和声明的输出类型不匹配，需要修复
            if (actualInputType != declaredOutputType) {
                OpBuilder builder(fillOp);
                
                // 获取填充值
                Value fillValue = fillOp.getInputs()[0];
                
                // 创建新的linalg.fill操作，输出类型与输入类型匹配
                auto newFillOp = builder.create<linalg::FillOp>(
                    fillOp.getLoc(),
                    TypeRange{actualInputType}, // 明确指定输出类型
                    fillValue,
                    inputTensor
                );
                
                replacements.push_back({fillOp, newFillOp});    //将旧操作和新操作的配对添加到替换列表
                changed = true;
            }
        });
        
        // 执行替换
        for (auto& pair : replacements) {   //遍历所有需要替换的操作对
            Operation* oldOp = pair.first;
            Operation* newOp = pair.second;
            
            // 替换所有使用
            for (unsigned i = 0; i < oldOp->getNumResults(); ++i) {
                oldOp->getResult(i).replaceAllUsesWith(newOp->getResult(i));    //将旧操作第i个结果的所有使用替换为新操作的对应结果
            }
            
            // 删除旧操作
            oldOp->erase();
        }
        
        return changed;
    }
    
    /**
     * 推导静态张量形状
     */
    bool propagateStaticShapes(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<tensor::EmptyOp, 4> toReplace;  //存储需要替换的tensor.empty操作
        SmallVector<linalg::FillOp, 4> linalgToFix;     //存储需要替换的tensor.empty操作
        bool changed = false;
        
        module->walk([&](tensor::EmptyOp emptyOp) {
            // 检查所有动态维度是否都是常量
            SmallVector<int64_t, 4> staticSizes;
            bool allStatic = true;
            
            for (Value dynamicSize : emptyOp.getDynamicSizes()) {   //遍历tensor.empty的所有动态维度参数，getDynamicSizes()：返回动态维度的Value列表
                auto constValue = getConstantIntValue(dynamicSize, constantMap);    //尝试从常量映射中获取维度的整数值
                if (constValue) {
                    staticSizes.push_back(*constValue);     //如果是常量，添加到staticSizes
                } else {
                    allStatic = false;      //如果不是常量，标记为非全静态并退出循环
                    break;
                }
            }
            
            if (allStatic && !emptyOp.getDynamicSizes().empty()) {      //只有当所有动态维度都是常量且确实存在动态维度时才优化
                // 创建静态形状的张量类型
                auto currentType = llvm::cast<RankedTensorType>(emptyOp.getType());     //获取当前张量的类型并安全转换为RankedTensorType
                auto shape = currentType.getShape().vec();      //获取形状的可修改副本
                
                // 替换动态维度（-1）为静态值
                int dynamicIdx = 0;
                for (size_t i = 0; i < shape.size(); ++i) {     //遍历形状的每一个维度
                    if (shape[i] == ShapedType::kDynamic) {     //ShapedType::kDynamic：MLIR中表示动态维度的常量（-1）
                        shape[i] = staticSizes[dynamicIdx++];   //用实际常量值替换动态维度标记
                    }
                }
                
                // 创建新的静态张量类型，使用静态形状但保持相同元素类型
                auto newType = RankedTensorType::get(shape, currentType.getElementType());
                
                // 创建新的empty操作（不需要动态尺寸）
                OpBuilder builder(emptyOp);
                auto newEmptyOp = builder.create<tensor::EmptyOp>(
                    emptyOp.getLoc(), newType, ValueRange{}
                );
                
                //替换所有使用，标记待删除，设置变化标志
                emptyOp.getResult().replaceAllUsesWith(newEmptyOp.getResult());
                toReplace.push_back(emptyOp);
                changed = true;
                
                // 检查并收集需要修复的linalg.fill操作
                for (auto user : newEmptyOp.getResult().getUsers()) {
                    if (auto fillOp = dyn_cast<linalg::FillOp>(user)) {
                        linalgToFix.push_back(fillOp);
                    }
                }
            }
        });
        
        // 删除旧的tensor.empty操作
        for (auto op : toReplace) {
            op->erase();
        }
        
        // 修复受影响的linalg操作
        for (auto fillOp : linalgToFix) {
            Value inputTensor = fillOp.getOutputs()[0];
            Type actualInputType = inputTensor.getType();
            Type declaredOutputType = fillOp.getResult(0).getType();
            
            if (actualInputType != declaredOutputType) {
                OpBuilder builder(fillOp);
                Value fillValue = fillOp.getInputs()[0];
                
                // 创建新的linalg.fill，输出类型与输入类型匹配
                auto newFillOp = builder.create<linalg::FillOp>(
                    fillOp.getLoc(),
                    fillValue,
                    inputTensor
                );
                
                fillOp.getResult(0).replaceAllUsesWith(newFillOp.getResult(0));
                fillOp->erase();
                changed = true;
            }
        }
        
        return changed;
    }
    
    /**
     * 简化控制流
     */
    bool simplifyControlFlow(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<scf::IfOp, 4> toReplace;        //存储需要替换的if操作
        bool changed = false;
        
        module->walk([&](scf::IfOp ifOp) {      //遍历所有scf.if操作
            auto conditionValue = getConstantBoolValue(ifOp.getCondition(), constantMap);       //尝试获取条件的常量布尔值
            
            if (conditionValue) {   //如果条件是常量
                OpBuilder builder(ifOp);
                
                // 根据条件值选择then或else分支     解引用optional获取布尔值
                Region *selectedRegion = *conditionValue ? &ifOp.getThenRegion() : &ifOp.getElseRegion();
                
                // 将选中分支的操作移动到if操作之前
                Block *selectedBlock = &selectedRegion->front();
                Operation *insertPoint = ifOp;  //设置插入点为if操作位置
                
                // 收集分支中的操作（除了yield）
                SmallVector<Operation*, 4> opsToMove;
                for (Operation &op : selectedBlock->getOperations()) {
                    if (!isa<scf::YieldOp>(op)) {
                        opsToMove.push_back(&op);
                    }
                }
                
                // 将收集的操作移动到if之前
                for (Operation *op : opsToMove) {
                    op->moveBefore(insertPoint);
                }
                
                // 处理返回值
                if (ifOp.getNumResults() > 0) { //如果if操作有返回值
                    auto yieldOp = cast<scf::YieldOp>(selectedBlock->getTerminator());      //获取分支的终结操作（yield）
                    for (unsigned i = 0; i < ifOp.getNumResults(); ++i) {       //将if的结果替换为yield的操作数
                        ifOp.getResult(i).replaceAllUsesWith(yieldOp.getOperand(i));
                    }
                }
                
                toReplace.push_back(ifOp);
                changed = true;
            }
        });
        
        // 删除已优化的if操作
        for (auto ifOp : toReplace) {
            ifOp->erase();
        }
        
        return changed;
    }
    
    /**
     * 移除死代码（未使用的常量和操作）
     */
    bool removeDeadCode(ModuleOp module) {
        SmallVector<Operation*, 16> toErase;    //预分配16个元素空间的删除列表
        bool changed = false;
        
        // 多次迭代，直到没有更多死代码
        bool foundDeadCode = true;
        while (foundDeadCode) {
            foundDeadCode = false;      //重置标志和清空删除列表
            toErase.clear();
            
            module->walk([&](Operation *op) {
                // 跳过没有结果的操作（无结果的操作通常有副作用，不删除）
                if (op->getNumResults() == 0) {
                    return;
                }
                
                // 跳过函数和模块级操作，重要的结构性操作
                if (isa<func::FuncOp, ModuleOp>(op)) {
                    return;
                }
                
                // 检查所有结果是否都未被使用
                bool allUnused = true;
                for (Value result : op->getResults()) {     //遍历所有结果
                    if (!result.getUses().empty()) {    //如果使用者非空，设置allUnused为false，跳出循环
                        allUnused = false;
                        break;
                    }
                }
                
                // 只删除确实未使用的常量操作
                if (allUnused && isa<arith::ConstantOp>(op)) {
                    toErase.push_back(op);
                    foundDeadCode = true;
                    changed = true;
                }
            });
            
            // 删除这一轮找到的死代码
            for (Operation *op : toErase) {
                op->erase();
            }
        }
        
        return changed;
    }

    /**
     * 更新函数签名以匹配优化后的类型
     */
    bool updateFunctionSignatures(ModuleOp module) {
        bool changed = false;
        
        module->walk([&](func::FuncOp funcOp) {     //遍历模块中的所有函数操作
            // 收集返回操作中的实际类型
            SmallVector<Type, 4> newResultTypes;
            bool needsUpdate = false;
            
            funcOp->walk([&](func::ReturnOp returnOp) {     //在当前函数内查找所有return操作
                newResultTypes.clear();     //清空之前的类型记录
                for (Value operand : returnOp.getOperands()) {      //遍历return操作的所有操作数
                    newResultTypes.push_back(operand.getType());    //获取每个返回值的实际类型
                }
                
                // 检查是否与函数签名匹配
                auto currentResultTypes = funcOp.getFunctionType().getResults();    //获取函数签名中声明的返回类型，用于与实际类型比较
                if (newResultTypes.size() != currentResultTypes.size()) {
                    return;     //如果实际返回值数量与声明不符，直接返回
                }
                
                for (size_t i = 0; i < newResultTypes.size(); ++i) {    //比较每个位置的实际类型与声明类型
                    if (newResultTypes[i] != currentResultTypes[i]) {
                        needsUpdate = true;     //一旦发现不匹配就设置needsUpdate = true并退出循环
                        break;
                    }
                }
            });
            
            //执行签名更新
            if (needsUpdate && !newResultTypes.empty()) {   //如果needsUpdate为true且新的类型不为空
                // 创建新的函数类型
                auto newFuncType = FunctionType::get(
                    funcOp.getContext(),
                    funcOp.getFunctionType().getInputs(),   //保持原有的输入参数类型不变
                    newResultTypes      //使用新的返回类型
                );
                
                // 更新函数类型
                funcOp.setFunctionType(newFuncType);
                changed = true;
            }
        });
        
        return changed;
    }
    
    /**
     * 内联简单函数
     */
    bool inlineSimpleFunctions(ModuleOp module, const DenseMap<Value, Attribute> &constantMap) {
        SmallVector<func::CallOp, 4> toReplace;     //收集需要删除的函数调用操作（内联成功后原调用要删除）
        bool changed = false;   //标记是否发生了内联，用于返回给调用者
        
        // 收集所有函数
        DenseMap<StringRef, func::FuncOp> functions;
        module->walk([&](func::FuncOp funcOp) { //walk只对func::FuncOp类型的操作执行lambda
            functions[funcOp.getName()] = funcOp;   //funcOp.getName()：获取函数名，如"compute"、"helper"
        }); //建立从函数名到函数定义的快速查找映射
        
        module->walk([&](func::CallOp callOp) {     //遍历模块中的所有函数调用操作
            auto funcIt = functions.find(callOp.getCallee());   //callOp.getCallee()：获取被调用函数的名称  例如：对于func.call @helper(%arg)，返回"helper"
            if (funcIt != functions.end()) {
                func::FuncOp targetFunc = funcIt->second;   //targetFunc：存储被调用的函数定义  funcIt->second：获取键值对中的值部分（函数操作）
                
                // 检查是否可以内联
                if (shouldInlineFunction(targetFunc, callOp, constantMap)) {
                    if (inlineFunction(callOp, targetFunc)) {
                        toReplace.push_back(callOp);
                        changed = true;
                    }
                }
            }
        });
        
        // 删除已内联的调用
        for (auto callOp : toReplace) {
            callOp->erase();
        }
        
        return changed;
    }
    
    /**
     * 判断是否应该内联函数。返回bool值
     */
    bool shouldInlineFunction(func::FuncOp targetFunc, func::CallOp callOp, 
                             const DenseMap<Value, Attribute> &constantMap) {
        // 检查是否所有参数都是常量
        for (Value arg : callOp.getOperands()) {       //callOp.getOperands()：获取函数调用的所有实参   Value arg：遍历每个实际参数
            if (constantMap.find(arg) == constantMap.end()) {      //如果没找到说明有非常量参数，直接返回false
                return false;
            }
        }
        
        // 检查函数大小 - 放宽限制
        int opCount = 0;    //操作计数器初始化
        targetFunc->walk([&](Operation *) { opCount++; });  //遍历目标函数的所有操作
        
        // 如果所有参数都是常量，可以内联更大的函数
        return opCount < 50;
    }
    
    /**
     * 执行函数内联
     */
    bool inlineFunction(func::CallOp callOp, func::FuncOp targetFunc) {
        OpBuilder builder(callOp);
        
        // 获取目标函数的函数体（第一个基本块）
        // MLIR函数总是从入口基本块开始执行
        Block *funcBody = &targetFunc.getBody().front();
        
        // 创建IR映射表，用于将被调用函数的值映射到调用者的值
        //这是内联的核心：建立新旧值之间的对应关系
        IRMapping mapping;
        
        // 映射参数，将被调用函数的形参映射到调用时传入的实参
        for (unsigned i = 0; i < callOp.getNumOperands(); ++i) {
            mapping.map(funcBody->getArgument(i), callOp.getOperand(i));
        }
        
        // 克隆操作，设置插入点为当前函数调用位置，新操作将插入到这里
        Operation *insertPoint = callOp;
        SmallVector<Value, 4> returnValues;// 用于收集函数返回值，稍后用于替换调用结果
        
        for (Operation &op : funcBody->getOperations()) { // 遍历被调用函数体中的所有操作
            if (auto returnOp = dyn_cast<func::ReturnOp>(op)) {// 检查当前操作是否为返回操作
                // 不克隆return操作本身，而是收集其返回值
                for (Value operand : returnOp.getOperands()) {  // 通过映射表获取返回值在调用者上下文中的对应值
                    Value mappedOperand = mapping.lookupOrDefault(operand);//lookupOrDefault: 如果映射存在则返回映射值，否则返回原值
                    returnValues.push_back(mappedOperand);
                }
            } else {
                // 克隆其他操作
                Operation *clonedOp = builder.clone(op, mapping);
                clonedOp->moveBefore(insertPoint);
            }
        }
        
        // 替换调用的结果
        // 确保有足够的返回值（防止越界访问）
        for (unsigned i = 0; i < callOp.getNumResults(); ++i) {
            // 将函数调用的第i个结果的所有使用替换为对应的返回值
            // 这样原来使用函数调用结果的地方现在直接使用内联后的值
            if (i < returnValues.size()) {
                callOp.getResult(i).replaceAllUsesWith(returnValues[i]);
            }
        }
        
        return true;
    }
    
    // 辅助方法
    
    /**
     * 从常量映射中获取整数值
     */
    std::optional<int64_t> getConstantIntValue(Value value, const DenseMap<Value, Attribute> &constantMap) {
        auto it = constantMap.find(value);
        if (it == constantMap.end()) 
            return std::nullopt;
        
        if (auto intAttr = llvm::dyn_cast<IntegerAttr>(it->second)) {
            return intAttr.getValue().getSExtValue();
        }
        return std::nullopt;
    }
    
    /**
     * 从常量映射中获取布尔值
     */
    std::optional<bool> getConstantBoolValue(Value value, const DenseMap<Value, Attribute> &constantMap) {
        auto it = constantMap.find(value);
        if (it == constantMap.end()) 
            return std::nullopt;
        
        if (auto boolAttr = llvm::dyn_cast<BoolAttr>(it->second)) {
            return boolAttr.getValue();
        }
        
        if (auto intAttr = llvm::dyn_cast<IntegerAttr>(it->second)) {
            if (intAttr.getType().isInteger(1)) {
                return intAttr.getValue().getBoolValue();
            }
        }
        
        return std::nullopt;
    }
    
    /**
     * 创建整数常量
     */
    arith::ConstantOp createIntConstant(OpBuilder &builder, Location loc, int64_t value, Type type) {
        auto attr = IntegerAttr::get(type, value);
        return builder.create<arith::ConstantOp>(loc, attr);
    }
};

} // namespace mlir

#endif // SHAPE_OPTIMIZER_PASS_H
```

### 3.2ShapeOptimizePass.cpp

```cpp
/**
 * ShapeOptimizerPass.cpp
 * 
 * 在LLVM 20.x中，Pass实现可以完全在头文件中完成。
 * 这个文件主要是为了确保链接正确，并提供一些额外的辅助功能。
 */

#include "ShapeOptimizerPass.h"

// 目前所有实现都在头文件中，这里主要用于链接
```

### 3.3main.cpp

```cpp
/**
 * main.cpp
 */
#include "mlir/IR/MLIRContext.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"
#include "mlir/Pass/PassRegistry.h"

// 注册所有必要的Dialects
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"

// 我们的Pass
#include "ShapeOptimizerPass.h"

using namespace mlir;

int main(int argc, char **argv) {
    // 注册所有需要的dialects
    DialectRegistry registry;
    registry.insert<func::FuncDialect>();
    registry.insert<arith::ArithDialect>();
    registry.insert<tensor::TensorDialect>();
    registry.insert<scf::SCFDialect>();
    registry.insert<linalg::LinalgDialect>();
    
    // 注册我们的Pass
    PassRegistration<ShapeComputeOptimizerPass>();
    
    return asMainReturnCode(
        MlirOptMain(argc, argv, "Shape Optimizer - ML形状计算优化器\n", registry));
}
```

