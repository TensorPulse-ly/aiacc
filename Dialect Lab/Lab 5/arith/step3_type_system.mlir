// step3_type_system.mlir
module {
  // 演示不同整数类型的范围
  func.func @integer_ranges() -> (i8, i16, i32, i64) {
    // i8: -128 到 127
    %i8_max = arith.constant 127 : i8
    
    // i16: -32768 到 32767  
    %i16_max = arith.constant 32767 : i16
    
    // i32: -2^31 到 2^31-1
    %i32_max = arith.constant 2147483647 : i32
    
    // i64: -2^63 到 2^63-1
    %i64_big = arith.constant 1000000000000 : i64
    
    return %i8_max, %i16_max, %i32_max, %i64_big : i8, i16, i32, i64
  }
  
  // 演示浮点精度差异
  func.func @float_precision() -> (f32, f64) {
    // f32: 单精度，约7位有效数字
    %pi_f32 = arith.constant 3.141592653589793 : f32  // 会被截断
    
    // f64: 双精度，约15位有效数字
    %pi_f64 = arith.constant 3.141592653589793 : f64  // 保持完整精度
    
    return %pi_f32, %pi_f64 : f32, f64
  }
  
  // 演示类型安全：同类型才能运算
  func.func @type_safety() -> (i32, f32) {
    %a = arith.constant 10 : i32
    %b = arith.constant 20 : i32
    %int_result = arith.addi %a, %b : i32    // ✓ 正确：同为i32
    
    %fa = arith.constant 3.14 : f32
    %fb = arith.constant 2.71 : f32
    %float_result = arith.addf %fa, %fb : f32  // ✓ 正确：同为f32
    
    // ❌ 错误示例（会导致编译错误）：
    // %wrong = arith.addi %a, %fa : ???    // 类型不匹配！
    
    return %int_result, %float_result : i32, f32
  }
  
  // 演示溢出行为
  func.func @overflow_example() -> (i8, i8) {
    %max_i8 = arith.constant 127 : i8      // i8的最大值
    %one = arith.constant 1 : i8
    
    // 溢出：127 + 1 = -128 (在i8中)
    %overflow_result = arith.addi %max_i8, %one : i8
    
    %min_i8 = arith.constant -128 : i8     // i8的最小值
    %underflow_result = arith.subi %min_i8, %one : i8  // -128 - 1 = 127
    
    return %overflow_result, %underflow_result : i8, i8
  }
}