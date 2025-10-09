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

// 对5个FP32数进行加法运算 - 用于5输入加法器验证
uint32_t fp32_add_5_softfloat(uint32_t input0, uint32_t input1,
                              uint32_t input2, uint32_t input3,
                              uint32_t input4)
{
    
    //softfloat_exceptionFlags = 0;

    float32_t f32_inputs[5];
    float32_t f32_result;
    float64_t f64_result;

    f32_inputs[0].v = input0;
    f32_inputs[1].v = input1;
    f32_inputs[2].v = input2;
    f32_inputs[3].v = input3;
    f32_inputs[4].v = input4;

    // 将第一个FP32转换为FP64开始计算
    f64_result = f32_to_f64(f32_inputs[0]);

    // 2. 顺序累加
    f64_result = f64_add(f64_result, f32_to_f64(f32_inputs[1]));
    f64_result = f64_add(f64_result, f32_to_f64(f32_inputs[2]));
    f64_result = f64_add(f64_result, f32_to_f64(f32_inputs[3]));
    f64_result = f64_add(f64_result, f32_to_f64(f32_inputs[4]));

    // 将64位结果转换回32位
    f32_result = f64_to_f32(f64_result);
    return f32_result.v;
}

