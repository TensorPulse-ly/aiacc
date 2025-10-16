// ========================================
// Part 3: 张量形状变换 - 最兼容版本
// ========================================

module {
  // 练习 3.1.1 最兼容版: 基本reshape操作 (4x3x2 -> 6x4)
  func.func @exercise_3_1_1(%input: tensor<4x3x2xf32>) -> tensor<6x4xf32> {
    // 先展平到1D (总元素数 = 4*3*2 = 24)
    %flattened = tensor.collapse_shape %input [[0, 1, 2]] : 
      tensor<4x3x2xf32> into tensor<24xf32>
    
    // 再重塑为目标形状 6x4 (移除 output_shape 参数)
    %reshaped = tensor.expand_shape %flattened [[0, 1]] : 
      tensor<24xf32> into tensor<6x4xf32>
    
    return %reshaped : tensor<6x4xf32>
  }

  // 练习 3.1.2 最兼容版: 展平张量 (2x3x4 -> 24)
  func.func @exercise_3_1_2(%input: tensor<2x3x4xf32>) -> tensor<24xf32> {
    %flattened = tensor.collapse_shape %input [[0, 1, 2]] : 
      tensor<2x3x4xf32> into tensor<24xf32>
    
    return %flattened : tensor<24xf32>
  }

    // 练习 3.2.1: 扩展维度 (3x5 -> 3x1x5x1)
    func.func @exercise_3_2_1(%input: tensor<3x5xf32>) -> tensor<3x1x5x1xf32> {
    // 输入张量有2个维度，所以 reassociation 必须正好有2个分组。
    // 第一个分组 [0] 表示： 输入的第0维 映射到 输出的第0维。
    // 第二个分组 [1, 2, 3] 表示： 输入的第1维 展开成 输出的第1、2、3维。
    %expanded = tensor.expand_shape %input [[0], [1, 2, 3]] :
        tensor<3x5xf32> into tensor<3x1x5x1xf32>

    return %expanded : tensor<3x1x5x1xf32>
    }

  // 练习 3.2.2: 折叠维度 (2x1x3x1x4 -> 2x3x4)
  func.func @exercise_3_2_2(%input: tensor<2x1x3x1x4xf32>) -> tensor<2x3x4xf32> {
    %collapsed = tensor.collapse_shape %input [[0, 1], [2, 3], [4]] :
      tensor<2x1x3x1x4xf32> into tensor<2x3x4xf32>
    
    return %collapsed : tensor<2x3x4xf32>
  }

  // 练习 3.3.1: 获取维度大小并计算总元素数
  func.func @exercise_3_3_1(%input: tensor<?x?xf32>) -> index {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    
    %dim0 = tensor.dim %input, %c0 : tensor<?x?xf32>
    %dim1 = tensor.dim %input, %c1 : tensor<?x?xf32>
    %total = arith.muli %dim0, %dim1 : index
    
    return %total : index
  }
}