// Test Case 1: 卷积层输出形状计算 - 优化结果
// 所有算术运算都应该被折叠为常量
module {
  func.func @conv_output_shape() -> (index, index) {
    // 优化结果：(224 + 2*1 - 3) / 2 + 1 = (224 + 2 - 3) / 2 + 1 = 223 / 2 + 1 = 111 + 1 = 112
    %final_h = arith.constant 112 : index
    %final_w = arith.constant 112 : index
    
    return %final_h, %final_w : index, index
  }
  
  // 简单算术折叠结果
  func.func @simple_arithmetic() -> index {
    // 优化结果：(10 + 5) * 2 = 15 * 2 = 30
    %product = arith.constant 30 : index
    
    return %product : index
  }
}