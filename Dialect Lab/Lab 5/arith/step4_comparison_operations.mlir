// step4_comparison_operations.mlir
module {
  // 演示所有整数比较操作
  func.func @integer_comparisons() -> (i1, i1, i1, i1, i1, i1) {
    %a = arith.constant 10 : i32
    %b = arith.constant 20 : i32
    
    // 相等性比较
    %eq = arith.cmpi eq, %a, %b : i32    // equal: 10 == 20 = false
    %ne = arith.cmpi ne, %a, %b : i32    // not equal: 10 != 20 = true
    
    // 有符号比较
    %slt = arith.cmpi slt, %a, %b : i32  // signed less than: 10 < 20 = true
    %sle = arith.cmpi sle, %a, %b : i32  // signed less equal: 10 <= 20 = true
    %sgt = arith.cmpi sgt, %a, %b : i32  // signed greater than: 10 > 20 = false
    %sge = arith.cmpi sge, %a, %b : i32  // signed greater equal: 10 >= 20 = false
    
    return %eq, %ne, %slt, %sle, %sgt, %sge : i1, i1, i1, i1, i1, i1
  }
  
  // 演示浮点比较（重点是有序vs无序）
  func.func @float_comparisons() -> (i1, i1, i1, i1) {
    %a = arith.constant 3.14 : f32
    %b = arith.constant 2.71 : f32
    
    // 有序比较（如果有NaN，结果为false）
    %oeq = arith.cmpf oeq, %a, %b : f32  // ordered equal: 3.14 == 2.71 = false
    %olt = arith.cmpf olt, %a, %b : f32  // ordered less than: 3.14 < 2.71 = false
    %ogt = arith.cmpf ogt, %a, %b : f32  // ordered greater than: 3.14 > 2.71 = true
    
    // 无序比较（如果有NaN，结果为true）
    %une = arith.cmpf une, %a, %b : f32  // unordered not equal: 3.14 != 2.71 = true
    
    return %oeq, %olt, %ogt, %une : i1, i1, i1, i1
  }
  
  // 实现实用的比较函数：最大值
  func.func @max_function() -> i32 {
    %a = arith.constant 42 : i32
    %b = arith.constant 24 : i32
    
    %cmp = arith.cmpi sgt, %a, %b : i32  // 42 > 24 = true
    %max = scf.if %cmp -> (i32) {
      scf.yield %a : i32  // 返回42
    } else {
      scf.yield %b : i32  // 不会执行
    }
    
    return %max : i32  // 返回42
  }
  
  // 实现绝对值函数
  func.func @abs_function() -> i32 {
    %x = arith.constant -15 : i32
    %zero = arith.constant 0 : i32
    
    %is_negative = arith.cmpi slt, %x, %zero : i32  // -15 < 0 = true
    %abs_result = scf.if %is_negative -> (i32) {
      %neg_x = arith.subi %zero, %x : i32  // 0 - (-15) = 15
      scf.yield %neg_x : i32
    } else {
      scf.yield %x : i32  // 不会执行
    }
    
    return %abs_result : i32  // 返回15
  }
  
  // 演示条件嵌套：符号函数
  func.func @sign_function() -> i32 {
    %x = arith.constant 25 : i32
    %zero = arith.constant 0 : i32
    %one = arith.constant 1 : i32
    %neg_one = arith.constant -1 : i32
    
    %is_positive = arith.cmpi sgt, %x, %zero : i32  // 25 > 0 = true
    %result = scf.if %is_positive -> (i32) {
      scf.yield %one : i32  // 返回1
    } else {
      %is_zero = arith.cmpi eq, %x, %zero : i32
      %inner_result = scf.if %is_zero -> (i32) {
        scf.yield %zero : i32  // 返回0
      } else {
        scf.yield %neg_one : i32  // 返回-1
      }
      scf.yield %inner_result : i32
    }
    
    return %result : i32  // 返回1
  }
}