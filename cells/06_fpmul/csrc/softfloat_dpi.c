// SoftFloat DPI-C 接口文件，用于 FPMUL 模块验证

#include <stdio.h>
#include <stdint.h>
#include "softfloat.h"


// FP16 乘法函数
uint16_t dpi_f16_mul(uint16_t a, uint16_t b) {
    float16_t f16_a_val, f16_b_val, result;
    float32_t f32_a_val, f32_b_val, f32_res;

    f16_a_val.v = a;
    f16_b_val.v = b;

    f32_a_val = f16_to_f32(f16_a_val);
    f32_b_val = f16_to_f32(f16_b_val);

    f32_res = f32_mul(f32_a_val, f32_b_val);

    // 返回结果
    result = f32_to_f16(f32_res);
    return result.v;
}

// FP32 乘法函数  
uint32_t dpi_f32_mul(uint32_t a, uint32_t b) {
    // 清除异常标志
    softfloat_exceptionFlags = 0;
    
    // 转换为 SoftFloat 格式
    float32_t f32_a, f32_b, result;
    float64_t f64_a, f64_b, f64_res;
    f32_a.v = a;
    f32_b.v = b;

    f64_a = f32_to_f64(f32_a);
    f64_b = f32_to_f64(f32_b);
    // 执行乘法
    f64_res = f64_mul(f64_a, f64_b);
    result = f64_to_f32(f64_res);
    return result.v;
}

// 设置异常标志
void dpi_softfloat_raiseFlags(uint32_t flags) {
    softfloat_exceptionFlags |= (uint_fast8_t)flags;
}


// 获取当前异常标志
uint32_t dpi_get_exception_flags() {
    return (uint32_t)softfloat_exceptionFlags;
}

// 清除异常标志
void dpi_clear_exception_flags() {
    softfloat_exceptionFlags = 0;
}

// 设置舍入模式
void dpi_set_rounding_mode(uint32_t mode) {
    softfloat_roundingMode = (uint_fast8_t)mode;
}

// 获取舍入模式
uint32_t dpi_get_rounding_mode() {
    return (uint32_t)softfloat_roundingMode;
}
