// step2_ssa_dataflow.mlir
module {
  // 复杂表达式：计算 (a + b) * (c - d) / e
  func.func @complex_expression() -> i32 {
    // 定义输入常量
    %a = arith.constant 10 : i32
    %b = arith.constant 20 : i32
    %c = arith.constant 50 : i32
    %d = arith.constant 30 : i32
    %e = arith.constant 4 : i32
    
    // 第一层：并行计算（无依赖关系）
    %sum_ab = arith.addi %a, %b : i32      // %sum_ab = 30
    %diff_cd = arith.subi %c, %d : i32     // %diff_cd = 20
    
    // 第二层：依赖第一层的结果
    %product = arith.muli %sum_ab, %diff_cd : i32  // %product = 600
    
    // 第三层：依赖第二层的结果
    %result = arith.divsi %product, %e : i32       // %result = 150
    
    return %result : i32
  }
  
  // 演示数据流依赖分析
  func.func @dependency_demo() -> (i32, i32, i32) {
    %x = arith.constant 5 : i32
    %y = arith.constant 3 : i32
    
    // 这两个操作可以并行执行（无依赖）
    %result1 = arith.addi %x, %y : i32     // 5 + 3 = 8
    %result2 = arith.muli %x, %y : i32     // 5 * 3 = 15
    
    // 这个操作依赖于前两个结果（串行）
    %result3 = arith.addi %result1, %result2 : i32  // 8 + 15 = 23
    
    return %result1, %result2, %result3 : i32, i32, i32
  }
  
  // 演示SSA约束：每个变量只能赋值一次
  func.func @ssa_constraint_demo() -> i32 {
    %x = arith.constant 10 : i32    // %x 第一次赋值
    %y = arith.addi %x, %x : i32    // 不能写成 %x = arith.addi %x, %x
    %z = arith.muli %y, %x : i32    // 使用之前定义的 %x 和 %y
    return %z : i32
  }
}