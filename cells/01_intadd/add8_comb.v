`timescale 1ns / 1ps

module add8_comb (
    input  [3:0] src0,
    input  [3:0] src1,
    input  [3:0] src2,
    // input          sign_s0,
    input          sign_s1,
    input          sign_s2,
    input          i_sign_d,
    output [3:0] dst0,
    output [3:0] dst1
);
    wire       is_signed;
    wire [7:0] concat_val;
    wire [8:0] s2_ext;
    wire [8:0] concat_val_ext;
    wire signed [8:0] s2_val;
    wire signed [8:0] add_val;
    wire signed [8:0] sum_signed_real;
    wire signed [7:0] sum_signed;
    wire [7:0] sum_clipped;

    assign is_signed = sign_s1 | sign_s2 | i_sign_d;

    // 将u1和u0连接成8位值
    assign concat_val = {src1, src0};

    assign s2_ext = is_signed ? {{5{src2[3]}}, src2} : {5'b00000, src2};
    assign concat_val_ext = is_signed ? {concat_val[7], concat_val} : {1'b0, concat_val};

    assign s2_val = is_signed ? $signed(s2_ext) : s2_ext;
    assign add_val = is_signed ? $signed(concat_val_ext) : concat_val_ext;

    assign sum_signed_real = s2_val + add_val;
    assign sum_signed = sum_signed_real[7:0];

    // 处理溢出或下溢 - 完全匹配C代码的条件判断
    assign sum_clipped = 
            (is_signed && (sum_signed_real[8] == 1'b1) && (sum_signed_real[7] == 1'b0)) ? 8'h80 :
            (is_signed && (sum_signed_real[8] == 1'b0) && (sum_signed_real[7] == 1'b1)) ? 8'h7F :
            (!is_signed && (sum_signed_real[8] == 1'b1)) ? 8'hFF :
            sum_signed;

    // 输出低4位和高4位
    assign dst0 = sum_clipped[3:0];
    assign dst1 = sum_clipped[7:4];

endmodule