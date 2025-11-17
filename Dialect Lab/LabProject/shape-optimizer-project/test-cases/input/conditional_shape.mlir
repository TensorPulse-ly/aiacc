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
    %true = arith.constant true : i1
    %result = func.call @select_shape(%true) : (i1) -> tensor<?xf32>
    return %result : tensor<?xf32>
  }
  
  // 另一个常量条件测试
  func.func @test_with_false_constant() -> tensor<?xf32> {
    %false = arith.constant false : i1
    %result = func.call @select_shape(%false) : (i1) -> tensor<?xf32>
    return %result : tensor<?xf32>
  }
  
  // 直接的常量条件分支
  func.func @direct_conditional() -> (tensor<?xf32>, tensor<?xf32>) {
    %true_cond = arith.constant true : i1
    %false_cond = arith.constant false : i1
    
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