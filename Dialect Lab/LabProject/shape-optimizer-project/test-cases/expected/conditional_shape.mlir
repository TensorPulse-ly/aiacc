// Test Case 3: 条件形状选择 - 优化结果
// 常量条件分支应该被简化
module {
  func.func @select_shape(%use_large: i1) -> tensor<?xf32> {
    // 这个函数保持不变，因为参数是动态的
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

  // 常量true条件优化：选择large分支
  func.func @test_with_true_constant() -> tensor<1000xf32> {
    // 优化：直接使用large_size = 1000，函数调用被内联
    %result = tensor.empty() : tensor<1000xf32>
    return %result : tensor<1000xf32>
  }
  
  // 常量false条件优化：选择small分支
  func.func @test_with_false_constant() -> tensor<100xf32> {
    // 优化：直接使用small_size = 100，函数调用被内联
    %result = tensor.empty() : tensor<100xf32>
    return %result : tensor<100xf32>
  }
  
  // 直接条件分支优化
  func.func @direct_conditional() -> (tensor<50xf32>, tensor<100xf32>) {
    // true条件：选择第一个分支 (dim1 = 50)
    %tensor1 = tensor.empty() : tensor<50xf32>
    
    // false条件：选择第二个分支 (dim2 = 100)
    %tensor2 = tensor.empty() : tensor<100xf32>
    
    return %tensor1, %tensor2 : tensor<50xf32>, tensor<100xf32>
  }
}