`include "../define/fp32_defines.vh"

module fp32_unpacker (
    input wire [`FP32_WIDTH-1:0] fp_in,       // FP32 输入

    output wire sign,                         // 符号位
    output wire [`FP32_EXP_WIDTH-1:0] exponent,    // 指数位 
    output wire [`FP32_MANT_WIDTH-1:0] mantissa,   // 尾数位
    output wire is_zero,                      // 输入是否为 0
    output wire is_inf,                       // 输入是否为无穷大
    output wire is_nan                       // 输入是否为 NaN
);

    // 直接分解
    assign sign = fp_in[`FP32_WIDTH-1];
    assign exponent = fp_in[`FP32_WIDTH-2 : `FP32_MANT_WIDTH];
    assign mantissa = fp_in[`FP32_MANT_WIDTH-1 : 0];

    // 特殊情况检测
    wire exp_all_zeros = (exponent == {`FP32_EXP_WIDTH{1'b0}});
    wire exp_all_ones = (exponent == {`FP32_EXP_WIDTH{1'b1}});
    wire mant_all_zeros = (mantissa == {`FP32_MANT_WIDTH{1'b0}});

    // 是否为零 (包括 +0 和 -0)
    assign is_zero = exp_all_zeros && mant_all_zeros;
    // 是否为无穷大 (指数全1，尾数全0)
    assign is_inf = exp_all_ones && mant_all_zeros;
    // 是否为 NaN (指数全1，尾数非0)
    assign is_nan = exp_all_ones && !mant_all_zeros;

endmodule
