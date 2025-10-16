// verify_step4.cpp - 验证第四步：比较操作和条件逻辑
#include <iostream>
#include <cmath>

int main() {
    std::cout << "=== Step 4: 比较操作和条件逻辑验证 ===" << std::endl;
    
    // 对应 integer_comparisons 函数
    std::cout << "\n--- integer_comparisons 函数验证 ---" << std::endl;
    
    int a = 10, b = 20;
    std::cout << "输入值: a=" << a << ", b=" << b << std::endl;
    
    // 相等性比较
    bool eq = (a == b);      // 对应 arith.cmpi eq
    bool ne = (a != b);      // 对应 arith.cmpi ne
    
    // 有符号比较
    bool slt = (a < b);      // 对应 arith.cmpi slt
    bool sle = (a <= b);     // 对应 arith.cmpi sle
    bool sgt = (a > b);      // 对应 arith.cmpi sgt
    bool sge = (a >= b);     // 对应 arith.cmpi sge
    
    std::cout << "\n整数比较结果：" << std::endl;
    std::cout << "  eq (a == b): " << (eq ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  ne (a != b): " << (ne ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  slt (a < b): " << (slt ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  sle (a <= b): " << (sle ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  sgt (a > b): " << (sgt ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  sge (a >= b): " << (sge ? "true" : "false") << " (期望: false)" << std::endl;
    
    // 对应 float_comparisons 函数
    std::cout << "\n--- float_comparisons 函数验证 ---" << std::endl;
    
    float fa = 3.14f, fb = 2.71f;
    std::cout << "输入值: fa=" << fa << ", fb=" << fb << std::endl;
    
    // 有序比较（如果有NaN，结果为false）
    bool oeq = (fa == fb);   // 对应 arith.cmpf oeq
    bool olt = (fa < fb);    // 对应 arith.cmpf olt
    bool ogt = (fa > fb);    // 对应 arith.cmpf ogt
    
    // 无序比较（如果有NaN，结果为true）
    bool une = (fa != fb);   // 对应 arith.cmpf une
    
    std::cout << "\n浮点比较结果：" << std::endl;
    std::cout << "  oeq (fa == fb): " << (oeq ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  olt (fa < fb): " << (olt ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  ogt (fa > fb): " << (ogt ? "true" : "false") << " (期望: true)" << std::endl;
    std::cout << "  une (fa != fb): " << (une ? "true" : "false") << " (期望: true)" << std::endl;
    
    // 对应 max_function 函数
    std::cout << "\n--- max_function 函数验证 ---" << std::endl;
    
    int val_a = 42, val_b = 24;
    std::cout << "输入值: val_a=" << val_a << ", val_b=" << val_b << std::endl;
    
    bool cmp = (val_a > val_b);  // 对应 arith.cmpi sgt
    int max_val = cmp ? val_a : val_b;  // 对应 scf.if
    
    std::cout << "比较结果: val_a > val_b = " << (cmp ? "true" : "false") << std::endl;
    std::cout << "最大值: " << max_val << " (期望: 42)" << std::endl;
    
    // 对应 abs_function 函数
    std::cout << "\n--- abs_function 函数验证 ---" << std::endl;
    
    int x = -15;
    int zero = 0;
    std::cout << "输入值: x=" << x << std::endl;
    
    bool is_negative = (x < zero);  // 对应 arith.cmpi slt
    int abs_result = is_negative ? (zero - x) : x;  // 对应 scf.if 和 arith.subi
    
    std::cout << "是否为负数: " << (is_negative ? "true" : "false") << std::endl;
    std::cout << "绝对值: " << abs_result << " (期望: 15)" << std::endl;
    
    // 对应 sign_function 函数
    std::cout << "\n--- sign_function 函数验证 ---" << std::endl;
    
    int y = 25;
    int zero_val = 0, one = 1, neg_one = -1;
    std::cout << "输入值: y=" << y << std::endl;
    
    bool is_positive = (y > zero_val);  // 对应 arith.cmpi sgt
    int result;
    
    if (is_positive) {
        result = one;  // 返回1
    } else {
        bool is_zero = (y == zero_val);  // 对应 arith.cmpi eq
        if (is_zero) {
            result = zero_val;  // 返回0
        } else {
            result = neg_one;   // 返回-1
        }
    }
    
    std::cout << "是否为正数: " << (is_positive ? "true" : "false") << std::endl;
    std::cout << "符号函数结果: " << result << " (期望: 1)" << std::endl;
    
    // 演示NaN处理（浮点比较的特殊情况）
    std::cout << "\n--- NaN处理演示 ---" << std::endl;
    
    float nan_val = std::numeric_limits<float>::quiet_NaN();
    float normal_val = 1.0f;
    
    // 有序比较：如果有NaN，结果为false
    bool ordered_eq = (nan_val == normal_val);    // false
    bool ordered_lt = (nan_val < normal_val);     // false
    
    // 无序比较：如果有NaN，结果为true
    bool unordered_ne = (nan_val != normal_val);  // true
    
    std::cout << "NaN与正常值比较：" << std::endl;
    std::cout << "  有序相等 (NaN == 1.0): " << (ordered_eq ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  有序小于 (NaN < 1.0): " << (ordered_lt ? "true" : "false") << " (期望: false)" << std::endl;
    std::cout << "  无序不等 (NaN != 1.0): " << (unordered_ne ? "true" : "false") << " (期望: true)" << std::endl;
    
    std::cout << "\n=== 比较操作总结 ===" << std::endl;
    std::cout << "1. 整数比较谓词：eq(==), ne(!=), slt(<), sle(<=), sgt(>), sge(>=)" << std::endl;
    std::cout << "2. 浮点比较分为有序和无序，处理NaN的方式不同" << std::endl;
    std::cout << "3. 比较结果是i1类型(布尔值)，可用于条件分支" << std::endl;
    std::cout << "4. 结合scf.if可以实现复杂的条件逻辑" << std::endl;
    
    std::cout << "\n=== 条件逻辑模式 ===" << std::endl;
    std::cout << "• max函数：比较两值，返回较大者" << std::endl;
    std::cout << "• abs函数：判断正负，返回绝对值" << std::endl;
    std::cout << "• sign函数：嵌套条件，返回符号(-1,0,1)" << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    
    return 0;
}