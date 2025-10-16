module {
  // 无参数，无返回值
  func.func @no_params() {
    return
  }
  
  // 单参数，单返回值
  func.func @single_param(%arg0: i32) -> i32 {
    return %arg0 : i32
  }
  
  // 多参数，多返回值
  func.func @multi_params(%arg0: f32, %arg1: f32) -> (f32, f32) {
    return %arg0, %arg1 : f32, f32
  }
  
  // 复杂类型参数
  func.func @complex_types(%arg0: i64, %arg1: f64) -> f64 {
    return %arg1 : f64
  }
}
