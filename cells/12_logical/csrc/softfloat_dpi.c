#include "softfloat.h"
#include <stdint.h>

// 使用与库相同的声明方式
extern THREAD_LOCAL uint_fast8_t softfloat_roundingMode;
extern THREAD_LOCAL uint_fast8_t softfloat_exceptionFlags;

// 设置舍入模式
void set_softfloat_rounding_mode(uint_fast8_t mode) {
    softfloat_roundingMode = mode;
}

// 清除异常标志
void clear_softfloat_flags() {
    softfloat_exceptionFlags = 0;
}

// 获取异常标志
uint_fast8_t get_softfloat_flags() {
    return softfloat_exceptionFlags;
}

// 浮点比较函数 (返回: 0=相等, 1=小于, 2=大于)
uint_fast8_t fp32_compare_softfloat(uint32_t a, uint32_t b) {
    float32_t f32_a = {.v = a}, f32_b = {.v = b};
    
    if (f32_eq(f32_a, f32_b)) return 0;      // 相等
    if (f32_lt(f32_a, f32_b)) return 1;      // 小于
    if (f32_le(f32_a, f32_b)) return 1;      // 小于或等于
    
    return 2;  // 大于
}

// 16位浮点比较
uint_fast8_t fp16_compare_softfloat(uint16_t a, uint16_t b) {
    float16_t f16_a = {.v = a}, f16_b = {.v = b};
    
    if (f16_eq(f16_a, f16_b)) return 0;      // 相等
    if (f16_lt(f16_a, f16_b)) return 1;      // 小于
    if (f16_le(f16_a, f16_b)) return 1;      // 小于或等于
    
    return 2;  // 大于
}