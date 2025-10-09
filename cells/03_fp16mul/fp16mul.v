`timescale 1ns/1ps
`include "/home/sunny/SMC/global_defines.v"

module fp16mul (
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire [127:0] dvr_fp16mul_s0,
    input  wire [127:0] dvr_fp16mul_s1,
    input  wire [127:0] dvr_fp16mul_s2,
    input  wire [127:0] dvr_fp16mul_s3,
    input  wire [127:0] dvr_fp16mul_s4567,

    output reg  [127:0] dr_fp16mul_d0,
    output reg  [127:0] dr_fp16mul_d1,
    output reg  [127:0] dr_fp16mul_d2,
    output reg  [127:0] dr_fp16mul_d3,
    output reg  [127:0] dr_fp16mul_d4,
    output reg  [127:0] dr_fp16mul_d5,
    output reg  [127:0] dr_fp16mul_d6,
    output reg  [127:0] dr_fp16mul_d7,
    
    // 控制寄存器
    input  wire [1:0]   cru_fp16mul_s0123,   // s0123控制信号
    input  wire [3:0]   cru_fp16mul_s4567,   // s4567控制信号
    input  wire [2:0]   cru_fp16mul          // 乘法计算控制信号
);

// fp16mul相关设计参数
parameter  PARAM_DR_FP16MUL_CNT = 32;      // fp16乘法器数量
parameter PARAM_DR_FP16MUL_S0_CNT = 2;    // s0-s3寄存器数量
parameter PARAM_DR_FP16MUL_S1_CNT = 2;    // s4-s7寄存器数量

// 源寄存器定义 - 广播源（s0-s3）
reg [127:0] dr_s0 [0:PARAM_DR_FP16MUL_S0_CNT-1];  // s0寄存器组
reg [127:0] dr_s1 [0:PARAM_DR_FP16MUL_S0_CNT-1];  // s1寄存器组
reg [127:0] dr_s2 [0:PARAM_DR_FP16MUL_S0_CNT-1];  // s2寄存器组
reg [127:0] dr_s3 [0:PARAM_DR_FP16MUL_S0_CNT-1];  // s3寄存器组

// 源寄存器定义 - 本地源（s4-s7）
reg [127:0] dr_s4 [0:PARAM_DR_FP16MUL_S1_CNT-1];  // s4寄存器组
reg [127:0] dr_s5 [0:PARAM_DR_FP16MUL_S1_CNT-1];  // s5寄存器组
reg [127:0] dr_s6 [0:PARAM_DR_FP16MUL_S1_CNT-1];  // s6寄存器组
reg [127:0] dr_s7 [0:PARAM_DR_FP16MUL_S1_CNT-1];  // s7寄存器组

// 控制信号解析
wire cru_valid  = cru_fp16mul[2];
wire cru_s0_sel = cru_fp16mul[1];//最多支持2个0源寄存器
wire cru_s1_sel = cru_fp16mul[0];//最多支持2个1源寄存器

wire cru_s0123_valid   = cru_fp16mul_s0123[1];
wire cru_s0123_reg_sel = cru_fp16mul_s0123[0];

wire cru_s4567_valid = cru_fp16mul_s4567[3];
wire cru_s4567_high = cru_fp16mul_s4567[2];
wire [1:0] cru_s4567_low = cru_fp16mul_s4567[1:0];

reg [127:0] selected_s0_r, selected_s1_r, selected_s2_r, selected_s3_r;
reg [127:0] selected_s4_r, selected_s5_r, selected_s6_r, selected_s7_r;
reg compute_valid_r; // 延迟一拍后的计算有效，用于写结果

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        selected_s0_r <= 128'b0; selected_s1_r <= 128'b0; selected_s2_r <= 128'b0; selected_s3_r <= 128'b0;
        selected_s4_r <= 128'b0; selected_s5_r <= 128'b0; selected_s6_r <= 128'b0; selected_s7_r <= 128'b0;
        compute_valid_r <= 1'b0;
    end else begin
        // 当本拍收到有效乘法指令时，锁存所选 bank 的数据，结果在下一拍写回
        if (cru_valid) begin
            selected_s0_r <= dr_s0[cru_s0_sel];
            selected_s1_r <= dr_s1[cru_s0_sel];
            selected_s2_r <= dr_s2[cru_s0_sel];
            selected_s3_r <= dr_s3[cru_s0_sel];
            selected_s4_r <= dr_s4[cru_s1_sel];
            selected_s5_r <= dr_s5[cru_s1_sel];
            selected_s6_r <= dr_s6[cru_s1_sel];
            selected_s7_r <= dr_s7[cru_s1_sel];
        end
        compute_valid_r <= cru_valid; // 延迟一拍
    end
end

// 32个fp16乘法器的输出结果
wire [31:0] fp32_results [0:PARAM_DR_FP16MUL_CNT-1];

// 生成32个fp16乘法器实例
genvar i;
generate
    for (i = 0; i < PARAM_DR_FP16MUL_CNT; i = i + 1) begin : fp16_multipliers
        wire [15:0] fp16_a = {selected_s3_r[i*4 +: 4], selected_s2_r[i*4 +: 4], 
                              selected_s1_r[i*4 +: 4], selected_s0_r[i*4 +: 4]};
        wire [15:0] fp16_b = {selected_s7_r[i*4 +: 4], selected_s6_r[i*4 +: 4], 
                              selected_s5_r[i*4 +: 4], selected_s4_r[i*4 +: 4]};
        assign fp32_results[i] = fp16_mul(fp16_a, fp16_b);
    end
endgenerate

// fp16乘法器
function [31:0] fp16_mul;
    input [15:0] a;        
    input [15:0] b;        
    
    // 内部变量
    reg a_sign, b_sign, result_sign;
    reg [4:0] a_exp, b_exp;
    reg [9:0] a_mant, b_mant;
    
    reg a_zero, b_zero;
    reg a_inf, b_inf;
    reg a_nan, b_nan;
    reg a_denorm, b_denorm;
    
    reg result_nan, result_inf, result_zero;
    
    reg [10:0] a_mant_full, b_mant_full;  // 带隐藏位的尾数
    reg [21:0] mant_product;              // 尾数乘积
    reg product_has_overflow;             // 乘积是否溢出
    reg need_denormalize;                 // 需要处理非规格化数
    reg [4:0] leading_zeros;              // 前导零数量
    reg [21:0] normalized_mant;           // 规格化后的尾数
    reg [22:0] final_mantissa;            // 最终尾数
    
    reg [7:0] a_exp_adj, b_exp_adj;       // 调整后的指数
    reg [9:0] result_exp_unbiased;        // 无偏结果指数
    reg [9:0] exp_adjust;                 // 指数调整值
    reg [7:0] result_exp_biased;          // 有偏结果指数
    
    reg [22:0] out_mant;                  // 输出尾数
    reg [7:0] out_exp;                    // 输出指数
    
    // 常量定义
    localparam FP16_BIAS = 15;
    localparam FP32_BIAS = 127;
    localparam FP16_MANT_BITS = 10;
    localparam FP32_MANT_BITS = 23;
    localparam FP16_EXP_BITS = 5;
    localparam FP32_EXP_BITS = 8;
    
    begin
        // 提取输入操作数的各个字段
        a_sign = a[15];
        b_sign = b[15];
        a_exp = a[14:10];
        b_exp = b[14:10];
        a_mant = a[9:0];
        b_mant = b[9:0];

        // 检查特殊输入值
        a_zero = (a_exp == 0) && (a_mant == 0);
        b_zero = (b_exp == 0) && (b_mant == 0);

        a_inf = (a_exp == 5'b11111) && (a_mant == 0);
        b_inf = (b_exp == 5'b11111) && (b_mant == 0);
        
        a_nan = (a_exp == 5'b11111) && (a_mant != 0);
        b_nan = (b_exp == 5'b11111) && (b_mant != 0);
        
        a_denorm = (a_exp == 0) && (a_mant != 0);
        b_denorm = (b_exp == 0) && (b_mant != 0);
        
        result_nan = a_nan || b_nan || (a_inf && b_zero) || (a_zero && b_inf);
        result_inf = (a_inf || b_inf) && !result_nan;
        result_zero = (a_zero || b_zero) && !result_nan && !result_inf;
        
        // 计算结果的符号位
        result_sign = a_sign ^ b_sign;
        
        // 处理尾数的隐藏位
        a_mant_full = a_denorm ? {1'b0, a_mant} : {1'b1, a_mant};
        b_mant_full = b_denorm ? {1'b0, b_mant} : {1'b1, b_mant};

        // 计算尾数乘积
        mant_product = a_mant_full * b_mant_full;
        
        // 检查乘积是否溢出（最高位是否为1）
        product_has_overflow = mant_product[21];
        
        // 确定是否需要非规格化处理
        need_denormalize = a_denorm || b_denorm;
        
        // 计算前导零数量
        leading_zeros = count_leading_zeros(mant_product);
        
        // 规格化尾数
        if (need_denormalize) begin
            normalized_mant = mant_product << leading_zeros;
        end else begin
            normalized_mant = product_has_overflow ? (mant_product >> 1) : mant_product;
        end
        
        // 确定最终尾数值（不储存隐藏位）
        if (need_denormalize) begin
            final_mantissa = {normalized_mant[20:0], 2'b00};
        end else if (product_has_overflow) begin
            final_mantissa = {mant_product[20:0], 2'b00};
        end else begin
            final_mantissa = {mant_product[19:0], 3'b00};
        end
        
        // 计算无偏指数
        a_exp_adj = a_denorm ? -14 : a_exp - FP16_BIAS;
        b_exp_adj = b_denorm ? -14 : b_exp - FP16_BIAS;
        result_exp_unbiased = a_exp_adj + b_exp_adj;
        
        // 计算指数调整值
        if (need_denormalize) begin
            exp_adjust = (mant_product == 0) ? 0 : -leading_zeros + normalized_mant[21];
        end else begin
            exp_adjust = product_has_overflow ? 1 : 0;
        end
        
        // 计算有偏指数
        result_exp_biased = result_exp_unbiased + exp_adjust + FP32_BIAS;
 
        // 确定输出尾数
        if (result_zero) begin
            out_mant = 0;
        end else if (result_inf || result_nan) begin
            out_mant = result_nan ? {1'b1, {22{1'b0}}} : 0;
        end else begin
            out_mant = final_mantissa;
        end
        
        // 确定输出指数
        if (result_zero) begin
            out_exp = 0;
        end else if (result_inf || result_nan) begin
            out_exp = 8'hFF;
        end else begin
            out_exp = result_exp_biased;
        end
        
        // 组合最终结果
        fp16_mul = {result_sign, out_exp, out_mant};
    end
endfunction

// 计算前导零的函数 
function automatic [4:0] count_leading_zeros;
    input [21:0] value;
    reg [4:0] count;
    reg [21:0] temp;
    begin
        count = 0;
        temp = value;
        while (count < 21 && temp[21] == 1'b0 && temp != 0) begin
            count = count + 1;
            temp = temp << 1;
        end
        count_leading_zeros = count;
    end
endfunction 


integer j, k;  

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器
        for (j = 0; j < PARAM_DR_FP16MUL_S0_CNT; j = j + 1) begin
            dr_s0[j] <= 128'b0;
            dr_s1[j] <= 128'b0;
            dr_s2[j] <= 128'b0;
            dr_s3[j] <= 128'b0;
        end
        for (j = 0; j < PARAM_DR_FP16MUL_S1_CNT; j = j + 1) begin
            dr_s4[j] <= 128'b0;
            dr_s5[j] <= 128'b0;
            dr_s6[j] <= 128'b0;
            dr_s7[j] <= 128'b0;
        end
        dr_fp16mul_d0 <= 128'b0;
        dr_fp16mul_d1 <= 128'b0;
        dr_fp16mul_d2 <= 128'b0;
        dr_fp16mul_d3 <= 128'b0;
        dr_fp16mul_d4 <= 128'b0;
        dr_fp16mul_d5 <= 128'b0;
        dr_fp16mul_d6 <= 128'b0;
        dr_fp16mul_d7 <= 128'b0;
    end else begin
        // s0123更新逻辑
        if (cru_s0123_valid) begin
            dr_s0[cru_s0123_reg_sel] <= dvr_fp16mul_s0;
            dr_s1[cru_s0123_reg_sel] <= dvr_fp16mul_s1;
            dr_s2[cru_s0123_reg_sel] <= dvr_fp16mul_s2;
            dr_s3[cru_s0123_reg_sel] <= dvr_fp16mul_s3;
        end
        
        // s4567更新逻辑
        if (cru_s4567_valid) begin
            case (cru_s4567_low)
                2'b00: dr_s4[cru_s4567_high] <= dvr_fp16mul_s4567;
                2'b01: dr_s5[cru_s4567_high] <= dvr_fp16mul_s4567;
                2'b10: dr_s6[cru_s4567_high] <= dvr_fp16mul_s4567;
                2'b11: dr_s7[cru_s4567_high] <= dvr_fp16mul_s4567;
                default: begin
                    $display("WARNING: Invalid cru_s4567_low value %b at time %t", cru_s4567_low, $time);
               end
            endcase
        end
        
        // 结果写回延迟一拍，保证源选择锁存后再计算
        if (compute_valid_r) begin
            for (k = 0; k < PARAM_DR_FP16MUL_CNT; k = k + 1) begin
                dr_fp16mul_d0[k*4 +: 4] <= fp32_results[k][3:0];
                dr_fp16mul_d1[k*4 +: 4] <= fp32_results[k][7:4];
                dr_fp16mul_d2[k*4 +: 4] <= fp32_results[k][11:8];
                dr_fp16mul_d3[k*4 +: 4] <= fp32_results[k][15:12];
                dr_fp16mul_d4[k*4 +: 4] <= fp32_results[k][19:16];
                dr_fp16mul_d5[k*4 +: 4] <= fp32_results[k][23:20];
                dr_fp16mul_d6[k*4 +: 4] <= fp32_results[k][27:24];
                dr_fp16mul_d7[k*4 +: 4] <= fp32_results[k][31:28];
            end
        end
    end
end

endmodule
