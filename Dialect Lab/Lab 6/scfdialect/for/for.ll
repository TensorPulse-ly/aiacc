; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"

define i32 @sum_loop_example(i32 %0) {
  %2 = sext i32 %0 to i64
  %3 = add i64 %2, 1
  br label %4

4:                                                ; preds = %8, %1
  %5 = phi i64 [ %11, %8 ], [ 1, %1 ]
  %6 = phi i32 [ %10, %8 ], [ 0, %1 ]
  %7 = icmp slt i64 %5, %3
  br i1 %7, label %8, label %12

8:                                                ; preds = %4
  %9 = trunc i64 %5 to i32
  %10 = add i32 %6, %9
  %11 = add i64 %5, 1
  br label %4

12:                                               ; preds = %4
  ret i32 %6
}

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
