module {
  func.func @test_add_zero(%arg0: i32) -> i32 {
    %c0 = arith.constant 0 : i32
    %sum = arith.addi %arg0, %c0 : i32
    return %sum : i32
  }
}