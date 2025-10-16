// ========================================
// Part 2: 张量切片与子集操作 - 答案
// ========================================

module {
  // 练习 2.1.1: 1D张量切片
  func.func @exercise_2_1_1(%input: tensor<10xf32>) -> tensor<4xf32> {
    %slice = tensor.extract_slice %input[3] [4] [1] : 
      tensor<10xf32> to tensor<4xf32>
    
    return %slice : tensor<4xf32>
  }

  // 练习 2.1.2: 2D张量切片
  func.func @exercise_2_1_2(%input: tensor<4x6xf32>) -> tensor<2x3xf32> {
    %slice = tensor.extract_slice %input[1, 2] [2, 3] [1, 1] :
      tensor<4x6xf32> to tensor<2x3xf32>
    
    return %slice : tensor<2x3xf32>
  }

  // 练习 2.2.1: 插入切片
  func.func @exercise_2_2_1(%sub_tensor: tensor<3x2xf32>) -> tensor<6x6xf32> {
    // 使用 linalg.init_tensor 替代 tensor.empty (兼容版本)
    %original = linalg.init_tensor [6, 6] : tensor<6x6xf32>
    
    %result = tensor.insert_slice %sub_tensor into %original[2, 3] [3, 2] [1, 1] :
      tensor<3x2xf32> into tensor<6x6xf32>
    
    return %result : tensor<6x6xf32>
  }
}