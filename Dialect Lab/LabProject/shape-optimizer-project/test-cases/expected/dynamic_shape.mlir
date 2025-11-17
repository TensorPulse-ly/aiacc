// Test Case 2: 动态形状推导 - 优化结果
// 动态形状应该转换为静态形状
module {
  func.func @create_tensors() -> (tensor<10x20xf32>, tensor<200xf32>) {
    // 优化结果：直接创建静态形状的张量
    // 10 * 20 = 200
    %tensor2d = tensor.empty() : tensor<10x20xf32>
    %tensor1d = tensor.empty() : tensor<200xf32>
    
    return %tensor2d, %tensor1d : tensor<10x20xf32>, tensor<200xf32>
  }
  
  // 嵌套计算优化结果
  func.func @nested_computation() -> tensor<4x32x32xf32> {
    // 直接使用静态形状
    %tensor3d = tensor.empty() : tensor<4x32x32xf32>
    
    return %tensor3d : tensor<4x32x32xf32>
  }
  
  // 计算形状优化结果
  func.func @computed_shape() -> tensor<52xf32> {
    // 优化结果：16 * 3 + 4 = 48 + 4 = 52
    %tensor = tensor.empty() : tensor<52xf32>
    return %tensor : tensor<52xf32>
  }
}