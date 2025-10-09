#include <stdio.h>
#include <stdint.h>
#include "softfloat.h"

// 设置SoftFloat的舍入模式
void set_softfloat_rounding_mode(uint32_t mode) {
    softfloat_roundingMode = mode;
}

// 清除SoftFloat的异常标志
void clear_softfloat_flags() {
    softfloat_exceptionFlags = 0;
}

// 获取SoftFloat的异常标志
uint32_t get_softfloat_flags() {
    return softfloat_exceptionFlags;
}

// 32位浮点数加法器
uint32_t fp32_add_softfloat(uint32_t a, uint32_t b) {
    float32_t f32_a, f32_b, f32_sum;
    
    // 加载输入值
    f32_a.v = a;
    f32_b.v = b;
    
    // 执行FP32加法
    f32_sum = f32_add(f32_a, f32_b);
    
    return f32_sum.v;
}

// 16位浮点数加法器
uint16_t fp16_add_softfloat(uint16_t a, uint16_t b) {
    float16_t f16_a, f16_b, f16_sum;
    
    // 加载输入值
    f16_a.v = a;
    f16_b.v = b;
    
    // 执行FP16加法
    f16_sum = f16_add(f16_a, f16_b);
    
    return f16_sum.v;
}

// 添加类型转换辅助函数
static double f32_to_real(float32_t f32) {
    union { uint32_t i; float f; } u = {.i = f32.v};
    return (double)u.f;
}

static double f16_to_real(float16_t f16) {
    float32_t f32 = f16_to_f32(f16);
    return f32_to_real(f32);
}

// 修正导出函数
double fp32_to_real(uint32_t a) {
    float32_t f32 = {.v = a};
    return f32_to_real(f32); // 直接转换为double
}

double fp16_to_real(uint16_t a) {
    float16_t f16 = {.v = a};
    return f16_to_real(f16); // 直接转换为double
}
