// 阶段2：矩阵乘法运算
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