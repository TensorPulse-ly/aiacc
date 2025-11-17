// 阶段3：张量变换操作
// 目标：学习使用linalg.generic进行张量转置 (LLVM 15.0.7兼容版本)

module {
  // 函数1：基本矩阵转置 (2x3) -> (3x2)
  func.func @basic_transpose() -> tensor<3x2xf32> {
    // 创建输入矩阵 (2x3)，填充为7.0
    %fill_input = arith.constant 7.0 : f32
    %empty_input = linalg.init_tensor [2, 3] : tensor<2x3xf32>
    %input_matrix = linalg.fill ins(%fill_input : f32) outs(%empty_input : tensor<2x3xf32>) -> tensor<2x3xf32>
    
    // 创建输出矩阵 (3x2)，初始化为0.0
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [3, 2] : tensor<3x2xf32>
    %output_matrix = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<3x2xf32>) -> tensor<3x2xf32>
    
    // 使用linalg.generic实现转置操作：将(2x3)转置为(3x2)
    // 关键：输入映射 (i,j) -> (i,j)，输出映射 (i,j) -> (j,i) 实现转置
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j) -> (j, i)>,  // 输入：从(3x2)空间映射到(2x3)输入
        affine_map<(i, j) -> (i, j)>   // 输出：标准映射到(3x2)输出
      ],
      iterator_types = ["parallel", "parallel"]
    } ins(%input_matrix : tensor<2x3xf32>) outs(%output_matrix : tensor<3x2xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<3x2xf32>
    
    return %result : tensor<3x2xf32>
  }

  // 函数2：方阵转置 (3x3) -> (3x3)
  func.func @square_transpose() -> tensor<3x3xf32> {
    // 创建方阵，填充为8.0
    %fill_input = arith.constant 8.0 : f32
    %empty_input = linalg.init_tensor [3, 3] : tensor<3x3xf32>
    %input_matrix = linalg.fill ins(%fill_input : f32) outs(%empty_input : tensor<3x3xf32>) -> tensor<3x3xf32>
    
    // 输出方阵
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [3, 3] : tensor<3x3xf32>
    %output_matrix = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<3x3xf32>) -> tensor<3x3xf32>
    
    // 方阵转置
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j) -> (j, i)>,  // 输入转置映射
        affine_map<(i, j) -> (i, j)>   // 输出标准映射
      ],
      iterator_types = ["parallel", "parallel"]
    } ins(%input_matrix : tensor<3x3xf32>) outs(%output_matrix : tensor<3x3xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<3x3xf32>
    
    return %result : tensor<3x3xf32>
  }

  // 函数3：3D张量转置 (2x3x4) -> (4x3x2)
  func.func @tensor_3d_transpose() -> tensor<4x3x2xf32> {
    // 创建3D张量 (2x3x4)
    %fill_input = arith.constant 9.0 : f32
    %empty_input = linalg.init_tensor [2, 3, 4] : tensor<2x3x4xf32>
    %input_tensor = linalg.fill ins(%fill_input : f32) outs(%empty_input : tensor<2x3x4xf32>) -> tensor<2x3x4xf32>
    
    // 创建输出3D张量 (4x3x2)
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [4, 3, 2] : tensor<4x3x2xf32>
    %output_tensor = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<4x3x2xf32>) -> tensor<4x3x2xf32>
    
    // 3D张量转置：将维度顺序从[0,1,2]变为[2,1,0]
    // 输入映射：(i,j,k) -> (k,j,i) 实现维度重排
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j, k) -> (k, j, i)>,  // 输入：第0维->第2维，第1维不变，第2维->第0维
        affine_map<(i, j, k) -> (i, j, k)>   // 输出：标准映射
      ],
      iterator_types = ["parallel", "parallel", "parallel"]
    } ins(%input_tensor : tensor<2x3x4xf32>) outs(%output_tensor : tensor<4x3x2xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<4x3x2xf32>
    
    return %result : tensor<4x3x2xf32>
  }

  // 函数4：组合操作 - 先填充再转置
  func.func @fill_then_transpose() -> tensor<4x2xf32> {
    // 步骤1：创建并填充原始矩阵
    %fill_value = arith.constant 6.0 : f32
    %empty = linalg.init_tensor [2, 4] : tensor<2x4xf32>
    %filled = linalg.fill ins(%fill_value : f32) outs(%empty : tensor<2x4xf32>) -> tensor<2x4xf32>
    
    // 步骤2：创建转置输出矩阵
    %fill_output = arith.constant 0.0 : f32
    %empty_output = linalg.init_tensor [4, 2] : tensor<4x2xf32>
    %output = linalg.fill ins(%fill_output : f32) outs(%empty_output : tensor<4x2xf32>) -> tensor<4x2xf32>
    
    // 步骤3：执行转置
    %result = linalg.generic {
      indexing_maps = [
        affine_map<(i, j) -> (j, i)>,  // 输入转置映射
        affine_map<(i, j) -> (i, j)>   // 输出标准映射
      ],
      iterator_types = ["parallel", "parallel"]
    } ins(%filled : tensor<2x4xf32>) outs(%output : tensor<4x2xf32>) {
    ^bb0(%in: f32, %out: f32):
      linalg.yield %in : f32
    } -> tensor<4x2xf32>
    
    return %result : tensor<4x2xf32>
  }
}