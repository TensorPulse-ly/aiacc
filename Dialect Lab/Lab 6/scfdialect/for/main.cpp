#include <iostream>

// 声明将在 MLIR 中定义的 C 函数
extern "C" {
    int sum_loop_example(int n);
}

int main() {
    // 测试用例：计算 1 到 10 的和
    int n = 10;
    int expected_sum = 55; // 1+2+...+10 = 55

    int result = sum_loop_example(n);

    std::cout << "Testing sum_loop_example(" << n << ")" << std::endl;
    std::cout << "Result:   " << result << std::endl;
    std::cout << "Expected: " << expected_sum << std::endl;

    if (result == expected_sum) {
        std::cout << "Test PASSED!" << std::endl;
    } else {
        std::cout << "Test FAILED!" << std::endl;
    }

    return 0;
}