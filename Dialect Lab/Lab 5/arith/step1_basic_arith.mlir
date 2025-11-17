// step1_basic_arith.mlir
module {
  // 演示基础的四则运算
  func.func @basic_arithmetic() -> (i32, f32) {
    // 1. 整数常量定义
    %a = arith.constant 10 : i32
    %b = arith.constant 3 : i32
    
    // 2. 整数基础运算
    %sum = arith.addi %a, %b : i32        // 10 + 3 = 13
    %diff = arith.subi %a, %b : i32       // 10 - 3 = 7
    %prod = arith.muli %a, %b : i32       // 10 * 3 = 30
    %quot = arith.divsi %a, %b : i32      // 10 / 3 = 3
    
    // 3. 浮点数常量和运算
    %fa = arith.constant 10.5 : f32
    %fb = arith.constant 3.2 : f32
    %fsum = arith.addf %fa, %fb : f32     // 10.5 + 3.2 = 13.7
    
    // 4. 简单比较
    %cmp = arith.cmpi sgt, %sum, %diff : i32  // 13 > 7 = true
    
    return %sum, %fsum : i32, f32
  }
  
  // 演示常量的不同类型
  func.func @constant_types() -> (i8, i32, i64, f32, f64) {
    %small_int = arith.constant 42 : i8
    %normal_int = arith.constant 1000 : i32
    %big_int = arith.constant 1000000 : i64
    %float_val = arith.constant 3.14 : f32
    %double_val = arith.constant 2.718281828 : f64
    
    return %small_int, %normal_int, %big_int, %float_val, %double_val : i8, i32, i64, f32, f64
  }
}