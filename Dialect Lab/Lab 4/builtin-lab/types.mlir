module {
  // 测试各种整数类型
  func.func @integer_types() -> (i1, i32, i64) {
    %bool = arith.constant true : i1
    %int32 = arith.constant 42 : i32
    %int64 = arith.constant 1000 : i64
    return %bool, %int32, %int64 : i1, i32, i64
  }
  
  // 测试各种浮点类型
  func.func @float_types() -> (f32, f64) {
    %float32 = arith.constant 3.14 : f32
    %float64 = arith.constant 2.718 : f64
    return %float32, %float64 : f32, f64
  }
  
  // 测试函数类型的表示
  func.func @function_types(%arg0: (i32, i32) -> i32) -> (i32, i32) -> i32 {
    return %arg0 : (i32, i32) -> i32
  }
}
