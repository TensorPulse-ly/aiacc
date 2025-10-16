#include <iostream>

// 使用 extern "C" 来告诉 C++ 编译器，这个函数是用 C 语言的规则来链接的，
// 以防止 C++ 的名称修饰（name mangling）问题。
// 函数签名必须与 MLIR 中的函数完全匹配。
extern "C" {
    int if_else_example(int a, int b);
}

int main() {
    // 测试用例 1: 5 < 10, 应该返回 5 + 10 = 15
    int result1 = if_else_example(5, 10);
    std::cout << "if_else_example(5, 10) -> " << result1 << std::endl;
    std::cout << "Expected: 15" << std::endl;
    std::cout << "--------------------" << std::endl;


    // 测试用例 2: 20 > 10, 应该返回 20 - 10 = 10
    int result2 = if_else_example(20, 10);
    std::cout << "if_else_example(20, 10) -> " << result2 << std::endl;
    std::cout << "Expected: 10" << std::endl;

    return 0;
}