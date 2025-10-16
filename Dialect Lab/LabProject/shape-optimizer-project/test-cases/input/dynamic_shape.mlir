// Test Case 2: 动态形状推导
// 测试tensor dialect的静态形状转换
module {
  func.func @create_tensors() -> (tensor<?x?xf32>, tensor<?xf32>) {
    %dim1 = arith.constant 10 : index
    %dim2 = arith.constant 20 : index
    
    // 计算总元素数
    %total = arith.muli %dim1, %dim2 : index
    
    // 创建动态形状的张量
    %tensor2d = tensor.empty(%dim1, %dim2) : tensor<?x?xf32>
    %tensor1d = tensor.empty(%total) : tensor<?xf32>
    
    return %tensor2d, %tensor1d : tensor<?x?xf32>, tensor<?xf32>
  }
  
  // 嵌套计算测试
  func.func @nested_computation() -> tensor<?x?x?xf32> {
    %batch = arith.constant 4 : index
    %height = arith.constant 32 : index
    %width = arith.constant 32 : index
    
    // 多维张量创建
    %tensor3d = tensor.empty(%batch, %height, %width) : tensor<?x?x?xf32>
    
    return %tensor3d : tensor<?x?x?xf32>
  }
  
  // 带算术运算的形状计算
  func.func @computed_shape() -> tensor<?xf32> {
    %base = arith.constant 16 : index
    %multiplier = arith.constant 3 : index
    %offset = arith.constant 4 : index
    
    // 计算：16 * 3 + 4 = 52
    %temp = arith.muli %base, %multiplier : index
    %final_size = arith.addi %temp, %offset : index
    
    %tensor = tensor.empty(%final_size) : tensor<?xf32>
    return %tensor : tensor<?xf32>
  }
}