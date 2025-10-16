module {
  func.func @basic_arithmetic() -> (i32, f32) {
    %c10_i32 = arith.constant 10 : i32
    %c3_i32 = arith.constant 3 : i32
    %0 = arith.addi %c10_i32, %c3_i32 : i32
    %1 = arith.subi %c10_i32, %c3_i32 : i32
    %2 = arith.muli %c10_i32, %c3_i32 : i32
    %3 = arith.divsi %c10_i32, %c3_i32 : i32
    %cst = arith.constant 1.050000e+01 : f32
    %cst_0 = arith.constant 3.200000e+00 : f32
    %4 = arith.addf %cst, %cst_0 : f32
    %5 = arith.cmpi sgt, %0, %1 : i32
    return %0, %4 : i32, f32
  }
  func.func @constant_types() -> (i8, i32, i64, f32, f64) {
    %c42_i8 = arith.constant 42 : i8
    %c1000_i32 = arith.constant 1000 : i32
    %c1000000_i64 = arith.constant 1000000 : i64
    %cst = arith.constant 3.140000e+00 : f32
    %cst_0 = arith.constant 2.7182818279999998 : f64
    return %c42_i8, %c1000_i32, %c1000000_i64, %cst, %cst_0 : i8, i32, i64, f32, f64
  }
}

