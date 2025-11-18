`timescale 1ns / 1ps

module add32_comb (
    input  [31:0]  src0,
    input  [31:0]  src1,
    input          sign_s0,
    input          sign_s1,
    input          i_sign_d,
    output [31:0]  dst
    // output [31:0]  st
);

    wire               is_signed;
    wire [32:0]        s0_ext;
    wire [32:0]        s1_ext;
    wire signed [32:0] s0_signed;
    wire signed [32:0] s1_signed;
    wire signed [32:0] sum_signed_real;
    wire signed [31:0] sum_signed;
    wire [31:0]        sum_lo;
    wire [31:0]        result;

    assign is_signed = sign_s0 | sign_s1 | i_sign_d;

    // 符号/无符号扩展（组合）
    assign s0_ext = is_signed ? {src0[31], src0} : {1'b0, src0};
    assign s1_ext = is_signed ? {src1[31], src1} : {1'b0, src1};

    // 有符号求和，用于溢出判定；低 32 位为基础结果
    assign s0_signed        = is_signed ? $signed(s0_ext) : s0_ext;
    assign s1_signed        = is_signed ? $signed(s1_ext) : s1_ext;
    assign sum_signed_real  = s0_signed + s1_signed;
    assign sum_signed       = sum_signed_real[31:0];
    assign sum_lo           = sum_signed[31:0];

    // 溢出/饱和处理（只在任一输入被视为有符号时生效）
    // 源寄存器和目的寄存器有一个位有符号数时就将其转化为是有符号数
    assign result = 
        (is_signed  && (sum_signed_real[32] == 1'b1) && (sum_signed_real[31] == 1'b0)) ? 32'h80000000 :
        (is_signed  && (sum_signed_real[32] == 1'b0) && (sum_signed_real[31] == 1'b1)) ? 32'h7FFFFFFF :
        (!is_signed && (sum_signed_real[32] == 1'b1)) ? 32'hFFFFFFFF :
        sum_lo;
            
    assign dst = result;


endmodule
