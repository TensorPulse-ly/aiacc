// Test Case 4: 矩阵操作链 - 优化结果
// 所有动态形状应该转换为静态形状
module {
  func.func @matrix_operations() -> tensor<2x4xf32> {
    %zero = arith.constant 0.0 : f32
    
    // 优化：直接创建静态形状的矩阵
    %output = tensor.empty() : tensor<2x4xf32>
    
    // linalg.fill 保持不变（这是实际的计算操作）
    %filled_output = linalg.fill ins(%zero : f32) outs(%output : tensor<2x4xf32>) -> tensor<2x4xf32>
    
    return %filled_output : tensor<2x4xf32>
  }
  
  // 矩阵尺寸计算优化
  func.func @compute_matrix_sizes() -> (index, index, index) {
    %rows = arith.constant 8 : index
    %cols = arith.constant 16 : index
    // 优化：8 * 16 * 2 = 256
    %total_size = arith.constant 256 : index
    
    return %rows, %cols, %total_size : index, index, index
  }
  
  // 张量创建链优化
  func.func @tensor_creation_chain() -> tensor<14x14xf32> {
    // 优化：4 * 3 + 2 = 12 + 2 = 14
    // 直接创建静态形状的正方形矩阵
    %matrix = tensor.empty() : tensor<14x14xf32>
    
    return %matrix : tensor<14x14xf32>
  }
  
  // linalg操作优化
  func.func @simple_linalg_ops() -> tensor<10xf32> {
    %fill_value = arith.constant 1.0 : f32
    
    // 优化：直接创建静态形状
    %tensor = tensor.empty() : tensor<10xf32>
    %filled = linalg.fill ins(%fill_value : f32) outs(%tensor : tensor<10xf32>) -> tensor<10xf32>
    
    return %filled : tensor<10xf32>
  }
}