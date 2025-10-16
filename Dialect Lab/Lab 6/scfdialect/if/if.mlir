module {
  // 函数定义：接收两个 i32，返回一个 i32。
  // 如果 a < b, 返回 a + b
  // 否则, 返回 b - a
  func.func @if_else_example(%a: i32, %b: i32) -> i32 {
    // 1. 使用 `arith.cmpi` 创建条件。
    %condition = arith.cmpi slt, %a, %b : i32

    // 2. 使用 `scf.if` 执行条件分支并返回结果。
    %result = scf.if %condition -> (i32) {
      %sum = arith.addi %a, %b : i32
      scf.yield %sum : i32
    } else {
      %diff = arith.subi %a, %b : i32
      scf.yield %diff : i32
    }

    // 3. 返回由 `scf.if` 操作产生的结果。
    return %result : i32
  }
}