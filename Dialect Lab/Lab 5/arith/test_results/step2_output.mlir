module {
  func.func @complex_expression() -> i32 {
    %c10_i32 = arith.constant 10 : i32
    %c20_i32 = arith.constant 20 : i32
    %c50_i32 = arith.constant 50 : i32
    %c30_i32 = arith.constant 30 : i32
    %c4_i32 = arith.constant 4 : i32
    %0 = arith.addi %c10_i32, %c20_i32 : i32
    %1 = arith.subi %c50_i32, %c30_i32 : i32
    %2 = arith.muli %0, %1 : i32
    %3 = arith.divsi %2, %c4_i32 : i32
    return %3 : i32
  }
  func.func @dependency_demo() -> (i32, i32, i32) {
    %c5_i32 = arith.constant 5 : i32
    %c3_i32 = arith.constant 3 : i32
    %0 = arith.addi %c5_i32, %c3_i32 : i32
    %1 = arith.muli %c5_i32, %c3_i32 : i32
    %2 = arith.addi %0, %1 : i32
    return %0, %1, %2 : i32, i32, i32
  }
  func.func @ssa_constraint_demo() -> i32 {
    %c10_i32 = arith.constant 10 : i32
    %0 = arith.addi %c10_i32, %c10_i32 : i32
    %1 = arith.muli %0, %c10_i32 : i32
    return %1 : i32
  }
}

