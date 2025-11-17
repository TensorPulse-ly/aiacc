// 阶段1：基础张量填充与操作
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