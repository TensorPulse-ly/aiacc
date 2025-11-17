module {
  func.func @mixed_operations(%arg0: i32, %arg1: i32) -> i32 {
    %c10 = arith.constant 10 : i32
    %sum = arith.addi %arg0, %arg1 : i32
    %cond = arith.cmpi slt, %sum, %c10 : i32
    
    scf.if %cond {
      %result = arith.muli %sum, %c10 : i32
    } else {
      %result = arith.subi %sum, %c10 : i32
    }
    
    return %sum : i32
  }
}
