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

// 直接将FP16输入转换为FP32后再做乘法
uint32_t fp16_inputs_mul_to_fp32_softfloat(uint16_t a, uint16_t b) {
    float16_t f16_a_val, f16_b_val;
    float32_t f32_a_val, f32_b_val, f32_res;

    f16_a_val.v = a;
    f16_b_val.v = b;

    f32_a_val = f16_to_f32(f16_a_val);
    f32_b_val = f16_to_f32(f16_b_val);

    f32_res = f32_mul(f32_a_val, f32_b_val);

    return f32_res.v;
}