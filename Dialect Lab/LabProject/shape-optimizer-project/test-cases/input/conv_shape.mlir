// Test Case 1: 卷积层输出形状计算
// 测试算术常量折叠功能
module {
  func.func @conv_output_shape() -> (index, index) {
    // 输入参数：224x224 图像，3x3卷积核，步长2，填充1
    %input_h = arith.constant 224 : index
    %input_w = arith.constant 224 : index
    %kernel_size = arith.constant 3 : index
    %stride = arith.constant 2 : index
    %padding = arith.constant 1 : index
    %c1 = arith.constant 1 : index
    %c2 = arith.constant 2 : index
    
    // 卷积输出公式: (input + 2*padding - kernel) / stride + 1
    // 高度计算
    %pad_double = arith.muli %padding, %c2 : index
    %input_padded_h = arith.addi %input_h, %pad_double : index
    %temp_h = arith.subi %input_padded_h, %kernel_size : index
    %output_h_raw = arith.divsi %temp_h, %stride : index
    %final_h = arith.addi %output_h_raw, %c1 : index
    
    // 宽度计算（相同逻辑）
    %input_padded_w = arith.addi %input_w, %pad_double : index
    %temp_w = arith.subi %input_padded_w, %kernel_size : index
    %output_w_raw = arith.divsi %temp_w, %stride : index
    %final_w = arith.addi %output_w_raw, %c1 : index
    
    return %final_h, %final_w : index, index
  }
  
  // 额外测试：简单的算术折叠
  func.func @simple_arithmetic() -> index {
    %a = arith.constant 10 : index
    %b = arith.constant 5 : index
    %c = arith.constant 2 : index
    
    %sum = arith.addi %a, %b : index      // 10 + 5 = 15
    %product = arith.muli %sum, %c : index // 15 * 2 = 30
    
    return %product : index
  }
}