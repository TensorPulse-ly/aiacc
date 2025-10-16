module {
  llvm.func @if_else_example(%arg0: i32, %arg1: i32) -> i32 {
    %0 = llvm.icmp "slt" %arg0, %arg1 : i32
    llvm.cond_br %0, ^bb1, ^bb2
  ^bb1:  // pred: ^bb0
    %1 = llvm.add %arg0, %arg1 : i32
    llvm.br ^bb3(%1 : i32)
  ^bb2:  // pred: ^bb0
    %2 = llvm.sub %arg0, %arg1 : i32
    llvm.br ^bb3(%2 : i32)
  ^bb3(%3: i32):  // 2 preds: ^bb1, ^bb2
    llvm.br ^bb4
  ^bb4:  // pred: ^bb3
    llvm.return %3 : i32
  }
}

