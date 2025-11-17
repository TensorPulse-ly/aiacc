// verify_step2.cpp - 验证第二步：SSA和数据流
#include <iostream>

int main() {
    std::cout << "=== Step 2: SSA和数据流验证 ===" << std::endl;
    
    // 对应 complex_expression 函数
    std::cout << "\n--- complex_expression 函数验证 ---" << std::endl;
    std::cout << "计算表达式: (a + b) * (c - d) / e" << std::endl;
    
    // 定义输入常量
    int a = 10, b = 20, c = 50, d = 30, e = 4;
    std::cout << "输入值: a=" << a << ", b=" << b << ", c=" << c << ", d=" << d << ", e=" << e << std::endl;
    
    // 第一层：并行计算（无依赖关系）
    int sum_ab = a + b;      // 对应 %sum_ab = arith.addi %a, %b
    int diff_cd = c - d;     // 对应 %diff_cd = arith.subi %c, %d
    
    std::cout << "\n第一层计算（可并行）：" << std::endl;
    std::cout << "  sum_ab = a + b = " << sum_ab << " (期望: 30)" << std::endl;
    std::cout << "  diff_cd = c - d = " << diff_cd << " (期望: 20)" << std::endl;
    
    // 第二层：依赖第一层的结果
    int product = sum_ab * diff_cd;  // 对应 %product = arith.muli %sum_ab, %diff_cd
    
    std::cout << "\n第二层计算（依赖第一层）：" << std::endl;
    std::cout << "  product = sum_ab * diff_cd = " << product << " (期望: 600)" << std::endl;
    
    // 第三层：依赖第二层的结果
    int result = product / e;        // 对应 %result = arith.divsi %product, %e
    
    std::cout << "\n第三层计算（依赖第二层）：" << std::endl;
    std::cout << "  result = product / e = " << result << " (期望: 150)" << std::endl;
    
    // 对应 dependency_demo 函数
    std::cout << "\n--- dependency_demo 函数验证 ---" << std::endl;
    
    int x = 5, y = 3;
    std::cout << "输入值: x=" << x << ", y=" << y << std::endl;
    
    // 这两个操作可以并行执行（无依赖）
    int result1 = x + y;     // 对应 arith.addi
    int result2 = x * y;     // 对应 arith.muli
    
    std::cout << "\n并行计算（无依赖）：" << std::endl;
    std::cout << "  result1 = x + y = " << result1 << " (期望: 8)" << std::endl;
    std::cout << "  result2 = x * y = " << result2 << " (期望: 15)" << std::endl;
    
    // 这个操作依赖于前两个结果（串行）
    int result3 = result1 + result2;  // 对应 arith.addi %result1, %result2
    
    std::cout << "\n串行计算（有依赖）：" << std::endl;
    std::cout << "  result3 = result1 + result2 = " << result3 << " (期望: 23)" << std::endl;
    
    // 对应 ssa_constraint_demo 函数
    std::cout << "\n--- ssa_constraint_demo 函数验证 ---" << std::endl;
    std::cout << "演示SSA约束：每个变量只能赋值一次" << std::endl;
    
    int x_val = 10;          // 对应 %x = arith.constant 10
    int y_val = x_val + x_val;  // 对应 %y = arith.addi %x, %x  (注意不能重新赋值给x)
    int z_val = y_val * x_val;  // 对应 %z = arith.muli %y, %x
    
    std::cout << "  x_val = " << x_val << std::endl;
    std::cout << "  y_val = x_val + x_val = " << y_val << " (期望: 20)" << std::endl;
    std::cout << "  z_val = y_val * x_val = " << z_val << " (期望: 200)" << std::endl;
    
    std::cout << "\n=== 数据流分析总结 ===" << std::endl;
    std::cout << "1. 第一层的 sum_ab 和 diff_cd 可以并行计算" << std::endl;
    std::cout << "2. 第二层的 product 必须等待第一层完成" << std::endl;
    std::cout << "3. 第三层的 result 必须等待第二层完成" << std::endl;
    std::cout << "4. SSA约束确保每个变量只赋值一次，避免数据竞争" << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    
    return 0;
}