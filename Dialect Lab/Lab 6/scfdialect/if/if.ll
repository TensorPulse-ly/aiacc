; ModuleID = 'LLVMDialectModule'
source_filename = "LLVMDialectModule"

define i32 @if_else_example(i32 %0, i32 %1) {
  %3 = icmp slt i32 %0, %1
  br i1 %3, label %4, label %6

4:                                                ; preds = %2
  %5 = add i32 %0, %1
  br label %8

6:                                                ; preds = %2
  %7 = sub i32 %0, %1
  br label %8

8:                                                ; preds = %4, %6
  %9 = phi i32 [ %7, %6 ], [ %5, %4 ]
  br label %10

10:                                               ; preds = %8
  ret i32 %9
}

!llvm.module.flags = !{!0}

!0 = !{i32 2, !"Debug Info Version", i32 3}
