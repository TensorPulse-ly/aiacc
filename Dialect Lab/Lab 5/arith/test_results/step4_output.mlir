module {
  func.func @integer_comparisons() -> (i1, i1, i1, i1, i1, i1) {
    %c10_i32 = arith.constant 10 : i32
    %c20_i32 = arith.constant 20 : i32
    %0 = arith.cmpi eq, %c10_i32, %c20_i32 : i32
    %1 = arith.cmpi ne, %c10_i32, %c20_i32 : i32
    %2 = arith.cmpi slt, %c10_i32, %c20_i32 : i32
    %3 = arith.cmpi sle, %c10_i32, %c20_i32 : i32
    %4 = arith.cmpi sgt, %c10_i32, %c20_i32 : i32
    %5 = arith.cmpi sge, %c10_i32, %c20_i32 : i32
    return %0, %1, %2, %3, %4, %5 : i1, i1, i1, i1, i1, i1
  }
  func.func @float_comparisons() -> (i1, i1, i1, i1) {
    %cst = arith.constant 3.140000e+00 : f32
    %cst_0 = arith.constant 2.710000e+00 : f32
    %0 = arith.cmpf oeq, %cst, %cst_0 : f32
    %1 = arith.cmpf olt, %cst, %cst_0 : f32
    %2 = arith.cmpf ogt, %cst, %cst_0 : f32
    %3 = arith.cmpf une, %cst, %cst_0 : f32
    return %0, %1, %2, %3 : i1, i1, i1, i1
  }
  func.func @max_function() -> i32 {
    %c42_i32 = arith.constant 42 : i32
    %c24_i32 = arith.constant 24 : i32
    %0 = arith.cmpi sgt, %c42_i32, %c24_i32 : i32
    %1 = scf.if %0 -> (i32) {
      scf.yield %c42_i32 : i32
    } else {
      scf.yield %c24_i32 : i32
    }
    return %1 : i32
  }
  func.func @abs_function() -> i32 {
    %c-15_i32 = arith.constant -15 : i32
    %c0_i32 = arith.constant 0 : i32
    %0 = arith.cmpi slt, %c-15_i32, %c0_i32 : i32
    %1 = scf.if %0 -> (i32) {
      %2 = arith.subi %c0_i32, %c-15_i32 : i32
      scf.yield %2 : i32
    } else {
      scf.yield %c-15_i32 : i32
    }
    return %1 : i32
  }
  func.func @sign_function() -> i32 {
    %c25_i32 = arith.constant 25 : i32
    %c0_i32 = arith.constant 0 : i32
    %c1_i32 = arith.constant 1 : i32
    %c-1_i32 = arith.constant -1 : i32
    %0 = arith.cmpi sgt, %c25_i32, %c0_i32 : i32
    %1 = scf.if %0 -> (i32) {
      scf.yield %c1_i32 : i32
    } else {
      %2 = arith.cmpi eq, %c25_i32, %c0_i32 : i32
      %3 = scf.if %2 -> (i32) {
        scf.yield %c0_i32 : i32
      } else {
        scf.yield %c-1_i32 : i32
      }
      scf.yield %3 : i32
    }
    return %1 : i32
  }
}

