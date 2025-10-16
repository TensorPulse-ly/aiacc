// Memory Dialect 功能测试
// 演示矩阵内存操作的完整流程

module {
  func.func @matrix_demo() {
    // 创建一个2x3的矩阵
    %c2 = arith.constant 2 : index
    %c3 = arith.constant 3 : index
    %matrix = memory.create_matrix %c2, %c3 : memref<?x?xf32>
    
    // 定义索引和值
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %val1 = arith.constant 1.5 : f32
    %val2 = arith.constant 2.5 : f32
    %val3 = arith.constant 3.5 : f32
    
    // 设置矩阵元素
    memory.set %matrix[%c0, %c0] = %val1 : memref<?x?xf32>
    memory.set %matrix[%c0, %c1] = %val2 : memref<?x?xf32>
    memory.set %matrix[%c1, %c0] = %val3 : memref<?x?xf32>
    
    // 读取矩阵元素
    %read1 = memory.get %matrix[%c0, %c0] : memref<?x?xf32>
    %read2 = memory.get %matrix[%c0, %c1] : memref<?x?xf32>
    %read3 = memory.get %matrix[%c1, %c0] : memref<?x?xf32>
    
    // 打印矩阵（调试用）
    memory.print %matrix : memref<?x?xf32>
    
    return
  }
  
  func.func @matrix_computation() -> f32 {
    // 演示矩阵计算场景
    %c2 = arith.constant 2 : index
    %mat = memory.create_matrix %c2, %c2 : memref<?x?xf32>
    
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %v1 = arith.constant 10.0 : f32
    %v2 = arith.constant 20.0 : f32
    
    // 设置对角线元素
    memory.set %mat[%c0, %c0] = %v1 : memref<?x?xf32>
    memory.set %mat[%c1, %c1] = %v2 : memref<?x?xf32>
    
    // 读取并计算
    %a = memory.get %mat[%c0, %c0] : memref<?x?xf32>
    %b = memory.get %mat[%c1, %c1] : memref<?x?xf32>
    %sum = arith.addf %a, %b : f32
    
    return %sum : f32
  }
}