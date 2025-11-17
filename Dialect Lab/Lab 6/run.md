## for
1.  **降级到 LLVM**:

    ```sh
    mlir-opt --pass-pipeline='builtin.module(convert-scf-to-cf, convert-arith-to-llvm, convert-cf-to-llvm, convert-func-to-llvm, reconcile-unrealized-casts)' for_test.mlir > for_test_llvm.mlir
    ```

2.  **翻译为 LLVM IR**:

    ```sh
    mlir-translate --mlir-to-llvmir for_test_llvm.mlir > for_test.ll
    ```

3.  **编译 LLVM IR**:

    ```sh
    clang++ -c for_test.ll -o for_test.o
    ```

4.  **编译 C++ 代码**:

    ```sh
    clang++ -c for_main.cpp -o for_main.o
    ```

5.  **链接生成可执行文件**:

    ```sh
    clang++ for_main.o for_test.o -o for_executable
    ```

6.  **运行验证**:

    ```sh
    ./for_executable
    ```



## if

1.  **Lower MLIR all the way to the LLVM Dialect (The corrected step)**:

    ```sh
    mlir-opt --pass-pipeline='builtin.module(convert-scf-to-cf, convert-arith-to-llvm, convert-cf-to-llvm, convert-func-to-llvm)' test.mlir > test_llvm.mlir
    ```

2.  **Translate MLIR (LLVM Dialect) to LLVM IR**:

    ```sh
    mlir-translate --mlir-to-llvmir test_llvm.mlir > test.ll
    ```

3.  **Compile LLVM IR to an object file**:

    ```sh
    clang++ -c test.ll -o test.o
    ```

4.  **Compile the C++ driver**:

    ```sh
    clang++ -c main.cpp -o main.o
    ```

5.  **Link and create the executable**:

    ```sh
    clang++ main.o test.o -o main_executable
    ```

6.  **Run and verify\!**

    ```sh
    ./main_executable
    ```