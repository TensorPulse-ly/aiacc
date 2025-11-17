// ========================================
// Part 1: 基础张量操作 - 答案
// ========================================

module {
  // 练习 1.1.1: 创建1D张量并插入元素
  func.func @exercise_1_1_1() -> tensor<6xf32> {
    %c0 = arith.constant 0 : index
    %c2 = arith.constant 2 : index
    %c4 = arith.constant 4 : index
    %val1 = arith.constant 3.0 : f32
    %val2 = arith.constant 5.0 : f32
    %val3 = arith.constant 7.0 : f32
    
    // 使用 linalg.init_tensor 替代 tensor.empty
    %empty = linalg.init_tensor [6] : tensor<6xf32>
    %t1 = tensor.insert %val1 into %empty[%c0] : tensor<6xf32>
    %t2 = tensor.insert %val2 into %t1[%c2] : tensor<6xf32>
    %t3 = tensor.insert %val3 into %t2[%c4] : tensor<6xf32>
    
    return %t3 : tensor<6xf32>
  }

  // 练习 1.1.2: 从张量中提取元素
  func.func @exercise_1_1_2(%input: tensor<5x3xf32>) -> f32 {
    %c2 = arith.constant 2 : index
    %c1 = arith.constant 1 : index
    
    %val = tensor.extract %input[%c2, %c1] : tensor<5x3xf32>
    
    return %val : f32
  }
}