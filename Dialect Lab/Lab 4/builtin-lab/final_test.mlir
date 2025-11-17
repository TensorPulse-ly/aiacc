module {
  // 展示builtin提供的基础结构
  func.func @demo(%input1: i32, %input2: f32) -> (i32, f32, i1) {
    // builtin类型的使用
    %const_int = arith.constant 100 : i32
    %const_float = arith.constant 3.14 : f32
    
    // 在builtin框架内使用其他dialect
    %sum_int = arith.addi %input1, %const_int : i32
    %sum_float = arith.addf %input2, %const_float : f32
    %comparison = arith.cmpi sgt, %sum_int, %const_int : i32
    
    // builtin的return操作
    return %sum_int, %sum_float, %comparison : i32, f32, i1
  }
}
