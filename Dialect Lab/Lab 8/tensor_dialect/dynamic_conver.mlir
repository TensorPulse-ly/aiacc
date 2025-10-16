// ========================================
// Part 4: 动态张量与类型转换
// ========================================

module {
  // 练习 4.1.1 兼容版: 创建和操作动态张量
  func.func @exercise_4_1_1(%d0: index, %d1: index, %d2: index) -> tensor<?x?x?xf32> {
    %c0 = arith.constant 0 : index
    %val = arith.constant 42.0 : f32
    
    // 使用 linalg.init_tensor 替代 tensor.empty，传入动态维度
    %dynamic = linalg.init_tensor [%d0, %d1, %d2] : tensor<?x?x?xf32>
    %result = tensor.insert %val into %dynamic[%c0, %c0, %c0] : tensor<?x?x?xf32>
    
    return %result : tensor<?x?x?xf32>
  }

  // 练习 4.2.1 兼容版: 静态到动态转换
  func.func @exercise_4_2_1() -> tensor<3x4x5xf32> {
    // 使用 linalg.init_tensor 替代 tensor.empty
    %static = linalg.init_tensor [3, 4, 5] : tensor<3x4x5xf32>
    %dynamic = tensor.cast %static : tensor<3x4x5xf32> to tensor<?x?x?xf32>
    %back_to_static = tensor.cast %dynamic : tensor<?x?x?xf32> to tensor<3x4x5xf32>
    
    return %back_to_static : tensor<3x4x5xf32>
  }

  // 练习 4.2.2: 处理动态张量的切片
  func.func @exercise_4_2_2(%input: tensor<?x?xf32>) -> tensor<2x2xf32> {
    %slice = tensor.extract_slice %input[0, 0] [2, 2] [1, 1] :
      tensor<?x?xf32> to tensor<2x2xf32>
    
    return %slice : tensor<2x2xf32>
  }
}