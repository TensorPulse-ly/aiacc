module {
  func.func @integer_ranges() -> (i8, i16, i32, i64) {
    %c127_i8 = arith.constant 127 : i8
    %c32767_i16 = arith.constant 32767 : i16
    %c2147483647_i32 = arith.constant 2147483647 : i32
    %c1000000000000_i64 = arith.constant 1000000000000 : i64
    return %c127_i8, %c32767_i16, %c2147483647_i32, %c1000000000000_i64 : i8, i16, i32, i64
  }
  func.func @float_precision() -> (f32, f64) {
    %cst = arith.constant 3.14159274 : f32
    %cst_0 = arith.constant 3.1415926535897931 : f64
    return %cst, %cst_0 : f32, f64
  }
  func.func @type_safety() -> (i32, f32) {
    %c10_i32 = arith.constant 10 : i32
    %c20_i32 = arith.constant 20 : i32
    %0 = arith.addi %c10_i32, %c20_i32 : i32
    %cst = arith.constant 3.140000e+00 : f32
    %cst_0 = arith.constant 2.710000e+00 : f32
    %1 = arith.addf %cst, %cst_0 : f32
    return %0, %1 : i32, f32
  }
  func.func @overflow_example() -> (i8, i8) {
    %c127_i8 = arith.constant 127 : i8
    %c1_i8 = arith.constant 1 : i8
    %0 = arith.addi %c127_i8, %c1_i8 : i8
    %c-128_i8 = arith.constant -128 : i8
    %1 = arith.subi %c-128_i8, %c1_i8 : i8
    return %0, %1 : i8, i8
  }
}

