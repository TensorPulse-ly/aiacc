// verify_step3.cpp - 验证第三步：类型系统
#include <iostream>
#include <iomanip>
#include <limits>

int main() {
    std::cout << "=== Step 3: 类型系统验证 ===" << std::endl;
    
    // 对应 integer_ranges 函数
    std::cout << "\n--- integer_ranges 函数验证 ---" << std::endl;
    std::cout << "演示不同整数类型的范围：" << std::endl;
    
    // i8: -128 到 127
    int8_t i8_max = 127;    // 对应 arith.constant 127 : i8
    std::cout << "  i8_max = " << (int)i8_max << " (i8范围: -128 到 127)" << std::endl;
    
    // i16: -32768 到 32767
    int16_t i16_max = 32767;  // 对应 arith.constant 32767 : i16
    std::cout << "  i16_max = " << i16_max << " (i16范围: -32768 到 32767)" << std::endl;
    
    // i32: -2^31 到 2^31-1
    int32_t i32_max = 2147483647;  // 对应 arith.constant 2147483647 : i32
    std::cout << "  i32_max = " << i32_max << " (i32范围: -2^31 到 2^31-1)" << std::endl;
    
    // i64: -2^63 到 2^63-1
    int64_t i64_big = 1000000000000LL;  // 对应 arith.constant 1000000000000 : i64
    std::cout << "  i64_big = " << i64_big << " (i64范围: -2^63 到 2^63-1)" << std::endl;
    
    // 对应 float_precision 函数
    std::cout << "\n--- float_precision 函数验证 ---" << std::endl;
    std::cout << "演示浮点精度差异：" << std::endl;
    std::cout << std::fixed << std::setprecision(15);
    
    // f32: 单精度，约7位有效数字
    float pi_f32 = 3.141592653589793f;   // 对应 arith.constant ... : f32（会被截断）
    
    // f64: 双精度，约15位有效数字
    double pi_f64 = 3.141592653589793;   // 对应 arith.constant ... : f64（保持完整精度）
    
    std::cout << "  pi_f32 (单精度) = " << pi_f32 << std::endl;
    std::cout << "  pi_f64 (双精度) = " << pi_f64 << std::endl;
    std::cout << "  注意：f32精度较低，小数位被截断" << std::endl;
    
    // 对应 type_safety 函数
    std::cout << "\n--- type_safety 函数验证 ---" << std::endl;
    std::cout << "演示类型安全：同类型才能运算" << std::endl;
    
    int32_t a = 10, b = 20;
    int32_t int_result = a + b;          // 对应 arith.addi %a, %b : i32 ✓
    
    float fa = 3.14f, fb = 2.71f;
    float float_result = fa + fb;        // 对应 arith.addf %fa, %fb : f32 ✓
    
    std::cout << std::fixed << std::setprecision(2);
    std::cout << "  int_result (i32 + i32) = " << int_result << " ✓ 正确" << std::endl;
    std::cout << "  float_result (f32 + f32) = " << float_result << " ✓ 正确" << std::endl;
    std::cout << "  注意：不能将 i32 和 f32 直接相加，会产生编译错误" << std::endl;
    
    // 对应 overflow_example 函数
    std::cout << "\n--- overflow_example 函数验证 ---" << std::endl;
    std::cout << "演示溢出行为：" << std::endl;
    
    int8_t max_i8 = 127;                 // i8的最大值
    int8_t one = 1;
    
    // 溢出：127 + 1 = -128 (在i8中)
    int8_t overflow_result = max_i8 + one;  // 对应 arith.addi %max_i8, %one : i8
    
    int8_t min_i8 = -128;                // i8的最小值
    int8_t underflow_result = min_i8 - one; // 对应 arith.subi %min_i8, %one : i8
    
    std::cout << "  max_i8 = " << (int)max_i8 << " (i8最大值)" << std::endl;
    std::cout << "  overflow_result = max_i8 + 1 = " << (int)overflow_result 
              << " (期望: -128，发生溢出)" << std::endl;
    
    std::cout << "  min_i8 = " << (int)min_i8 << " (i8最小值)" << std::endl;
    std::cout << "  underflow_result = min_i8 - 1 = " << (int)underflow_result 
              << " (期望: 127，发生下溢)" << std::endl;
    
    std::cout << "\n=== 类型系统总结 ===" << std::endl;
    std::cout << "1. 整数类型有固定的位宽和范围：i8 < i16 < i32 < i64" << std::endl;
    std::cout << "2. 浮点类型有不同的精度：f32(单精度) < f64(双精度)" << std::endl;
    std::cout << "3. 相同类型才能进行运算，MLIR具有严格的类型安全" << std::endl;
    std::cout << "4. 超出类型范围会发生溢出，需要注意数值范围" << std::endl;
    
    std::cout << "\n=== 类型范围参考 ===" << std::endl;
    std::cout << "i8:  " << (int)std::numeric_limits<int8_t>::min() 
              << " 到 " << (int)std::numeric_limits<int8_t>::max() << std::endl;
    std::cout << "i16: " << std::numeric_limits<int16_t>::min() 
              << " 到 " << std::numeric_limits<int16_t>::max() << std::endl;
    std::cout << "i32: " << std::numeric_limits<int32_t>::min() 
              << " 到 " << std::numeric_limits<int32_t>::max() << std::endl;
    
    std::cout << "\n=== 验证完成 ===" << std::endl;
    
    return 0;
}