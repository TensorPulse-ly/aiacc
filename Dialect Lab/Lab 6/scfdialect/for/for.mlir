module {
  func.func @sum_loop_example(%n: i32) -> i32 {
    // ---- Type Conversion Section ----
    // Cast the input %n from i32 to index type for loop control.
    %n_idx = arith.index_cast %n : i32 to index

    // ---- Loop Constants (now using 'index' type) ----
    %c0_i32 = arith.constant 0 : i32 // For initializing the sum (i32)
    %c1_idx = arith.constant 1 : index // For loop step and bounds (index)

    // Calculate upper bound using index types
    %n_plus_1_idx = arith.addi %n_idx, %c1_idx : index

    // ---- The Loop (now correctly using 'index' types) ----
    // The loop variable %i is now of type 'index'.
    // The initial sum %sum_iter is correctly initialized from an i32 constant.
    %final_sum = scf.for %i = %c1_idx to %n_plus_1_idx step %c1_idx
        iter_args(%sum_iter = %c0_i32) -> (i32) {
      
      // ---- Calculation inside loop ----
      // Cast the loop variable %i from index back to i32 for the addition.
      %i_i32 = arith.index_cast %i : index to i32

      %next_sum = arith.addi %sum_iter, %i_i32 : i32

      scf.yield %next_sum : i32
    }

    return %final_sum : i32
  }
}