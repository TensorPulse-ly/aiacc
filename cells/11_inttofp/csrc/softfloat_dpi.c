#include <stdint.h>
#include "softfloat.h"

/*------------------ 全局配置 ------------------*/
void set_softfloat_rounding_mode(uint32_t mode) {
    softfloat_roundingMode = mode;
}
void clear_softfloat_flags(void) {
    softfloat_exceptionFlags = 0;
}
uint32_t get_softfloat_flags(void) {
    return softfloat_exceptionFlags;
}

/*------------------ 整数 → 浮点位模式 ------------------*/
uint32_t int32_to_fp32(int32_t val, int is_signed) {
    float32_t res;
    if (is_signed)
        res = i32_to_f32(val);
    else
        res = ui32_to_f32((uint32_t)val);
    return res.v;
}

uint32_t uint32_to_fp32(uint32_t val) {
    return ui32_to_f32(val).v;
}

uint16_t int16_to_fp16(int16_t val, int is_signed) {
    float16_t res;
    if (is_signed)
        res = i32_to_f16((int32_t)val);
    else
        res = ui32_to_f16((uint32_t)(uint16_t)val);
    return res.v;
}

uint16_t uint16_to_fp16(uint16_t val) {
    return ui32_to_f16(val).v;
}

/*------------------ 位模式 → 十进制 ------------------*/
double fp32_to_real(uint32_t a) {
    float32_t f = { .v = a };
    float64_t f64 = f32_to_f64(f);
    union { uint64_t i; double d; } u = { .i = f64.v };
    return u.d;
}

double fp16_to_real(uint16_t a) {
    float16_t f16 = { .v = a };
    float32_t f32 = f16_to_f32(f16);
    return fp32_to_real(f32.v);
}
