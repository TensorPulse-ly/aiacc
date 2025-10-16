// Test Case 4: 矩阵操作链
// 测试linalg dialect和综合优化
module {
  func.func @matrix_operations() -> tensor<?x?xf32> {
    %c2 = arith.constant 2 : index
    %c3 = arith.constant 3 : index
    %c4 = arith.constant 4 : index
    %zero = arith.constant 0.0 : f32
    
    // 创建矩阵
    %mat1 = tensor.empty(%c2, %c3) : tensor<?x?xf32>
    %mat2 = tensor.empty(%c3, %c4) : tensor<?x?xf32>
    %output = tensor.empty(%c2, %c4) : tensor<?x?xf32>
    
    // 填充输出矩阵为零
    %filled_output = linalg.fill ins(%zero : f32) outs(%output : tensor<?x?xf32>) -> tensor<?x?xf32>
    
    return %filled_output : tensor<?x?xf32>
  }
  
  // 矩阵尺寸计算
  func.func @compute_matrix_sizes() -> (index, index, index) {
    %rows = arith.constant 8 : index
    %cols = arith.constant 16 : index
    %batch = arith.constant 2 : index
    
    // 计算总大小
    %matrix_size = arith.muli %rows, %cols : index
    %total_size = arith.muli %matrix_size, %batch : index
    
    return %rows, %cols, %total_size : index, index, index
  }
  
  // 复杂的张量创建链
  func.func @tensor_creation_chain() -> tensor<?x?xf32> {
    // 基础维度
    %base_dim = arith.constant 4 : index
    %scale_factor = arith.constant 3 : index
    %padding = arith.constant 2 : index
    
    // 计算实际维度
    %scaled_dim = arith.muli %base_dim, %scale_factor : index  // 4 * 3 = 12
    %final_dim = arith.addi %scaled_dim, %padding : index      // 12 + 2 = 14
    
    // 创建正方形矩阵
    %matrix = tensor.empty(%final_dim, %final_dim) : tensor<?x?xf32>
    
    return %matrix : tensor<?x?xf32>
  }
  
  // 带有linalg操作的简单情况
  func.func @simple_linalg_ops() -> tensor<?xf32> {
    %size = arith.constant 10 : index
    %fill_value = arith.constant 1.0 : f32
    
    %tensor = tensor.empty(%size) : tensor<?xf32>
    %filled = linalg.fill ins(%fill_value : f32) outs(%tensor : tensor<?xf32>) -> tensor<?xf32>
    
    return %filled : tensor<?xf32>
  }
}