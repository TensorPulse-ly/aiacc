// verify_step1.cpp - 验证第一步：基础arith操作
#include <iostream>
#include <iomanip>

int main() {
    std::cout << "=== Step 1: 基础arith操作验证 ===" << std::endl;
    std::cout << std::fixed << std::setprecision(2);
    
    // 对应 basic_arithmetic 函数
    std::cout << "\n--- basic_arithmetic 函数验证 ---" << std::endl;
    
    // 1. 整数常量定义和运算
    int a = 10, b = 3;
    int sum = a + b;        // 对应 arith.addi
    int diff = a - b;       // 对应 arith.subi
    int prod = a * b;       // 对应 arith.muli
    int quot = a / b;       // 对应 arith.divsi
    
    std::cout << "整数运算：" << std::endl;
    std::cout << "  a = " << a << ", b = " << b << std::endl;
    std::cout << "  sum (a + b) = " << sum << " (期望: 13)" << std::endl;
    std::cout << "  diff (a - b) = " << diff << " (期望: 7)" << std::endl;
    std::cout << "  prod (a * b) = " << prod << " (期望: 30)" << std::endl;
    std::cout << "  quot (a / b) = " << quot << " (期望: 3)" << std::endl;
    
    // 2. 浮点数常量和运算
    float fa = 10.5f, fb = 3.2f;
    float fsum = fa + fb;   // 对应 arith.addf
    
    std::cout << "\n浮点运算：" << std::endl;
    std::cout << "  fa = " << fa << ", fb = " << fb << std::endl;
    std::cout << "  fsum (fa + fb) = " << fsum << " (期望: 13.70)" << std::endl;
    
    // 3. 简单比较
    bool cmp = sum > diff;  // 对应 arith.cmpi sgt
    std::cout << "\n比较运算：" << std::endl;
    std::cout << "  cmp (sum > diff) = " << (cmp ? "true" : "false") << " (期望: true)" << std::endl;
    
    // 对应 constant_types 函数
    std::cout << "\n--- constant_types 函数验证 ---" << std::endl;
    
    int8_t small_int = 42;              // i8
    int32_t normal_int = 1000;          // i32
    int64_t big_int = 1000000;          // i64
    float float_val = 3.14f;            // f32
    double double_val = 2.718281828;    // f64
    
    std::cout << "不同类型常量：" << std::endl;
    std::cout << "  small_int (i8) = " << (int)small_int << std::endl;
    std::cout << "  normal_int (i32) = " << normal_int << std::endl;
    std::cout << "  big_int (i64) = " << big_int << std::endl;
    std::cout << "  float_val (f32) = " << float_val << std::endl;
    std::cout << "  double_val (f64) = " << double_val << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    std::cout << "如果所有结果都符合期望，说明你对Step 1的理解是正确的！" << std::endl;
    
    return 0;
}