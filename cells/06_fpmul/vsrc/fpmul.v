`timescale 1ns / 1ps

module fpmul (
    // 全局信号
    input  wire        clk,         
    input  wire        rst_n,      

    input  wire [127:0] dvr_fpmul_s0,  
    input  wire [127:0] dvr_fpmul_s1,  
    input  wire [2:0]   cru_fpmul,     

    output reg  [127:0] dr_fpmul_d     
);

    wire inst_valid = cru_fpmul[2];                  
    wire src_precision_is_32b = cru_fpmul[1];        
    wire dst_precision_is_32b = cru_fpmul[0];        

    wire [127:0] result_comb;

    //------------------------------------------------------------------
    // 并行浮点乘法通道生成（Generate 块）
    //------------------------------------------------------------------

    genvar i;  
    generate
        
        for (i = 0; i < 4; i = i + 1) begin : fpmul_lanes
            
            wire [31:0] s0_lane = dvr_fpmul_s0[i*32 +: 32];  
            wire [31:0] s1_lane = dvr_fpmul_s1[i*32 +: 32];  
            
            // --- 32 位浮点乘法单元实例化 ---
            wire [31:0] result_32;  
            fp32_multiplier u_fp32_mul (
                .a(s0_lane),        
                .b(s1_lane),        
                .result(result_32)  
            );

            // --- 16 位浮点乘法单元实例化 ---

            wire [15:0] result_16_low;  
            fp16_multiplier u_fp16_mul_low (
                .a(s0_lane[15:0]),      
                .b(s1_lane[15:0]),     
                .result(result_16_low)  
            );

            
            wire [15:0] result_16_high;  
            fp16_multiplier u_fp16_mul_high (
                .a(s0_lane[31:16]),      
                .b(s1_lane[31:16]),      
                .result(result_16_high)  
            );

            assign result_comb[i*32 +: 32] = (src_precision_is_32b) ? result_32 :  {result_16_high, result_16_low};  
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dr_fpmul_d <= 128'b0;
        end else begin
            if (inst_valid) begin
                dr_fpmul_d <= result_comb;
            end
        end
    end

endmodule

module fp16_multiplier (
    input  wire [15:0] a,                    
    input  wire [15:0] b,                    
    output wire [15:0] result                
);

    localparam FP16_EXP_WIDTH  = 5;          
    localparam FP16_MANT_WIDTH = 10;        
    localparam FP16_BIAS       = 15;         

    wire sign_a = a[15];
    wire sign_b = b[15];
    wire [FP16_EXP_WIDTH-1:0]  exp_a  = a[14:10];
    wire [FP16_EXP_WIDTH-1:0]  exp_b  = b[14:10];
    wire [FP16_MANT_WIDTH-1:0] mant_a = a[9:0];
    wire [FP16_MANT_WIDTH-1:0] mant_b = b[9:0];

    // =========================== 特殊值检测 =========================
    wire a_is_zero    = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero    = (exp_b == 0) && (mant_b == 0);
    wire output_is_zero = a_is_zero || b_is_zero;

    wire a_is_inf     = (exp_a == 5'b11111) && (mant_a == 0);
    wire b_is_inf     = (exp_b == 5'b11111) && (mant_b == 0);
    wire output_is_inf = (a_is_inf || b_is_inf) && !output_is_zero;

    wire a_is_nan     = (exp_a == 5'b11111) && (mant_a != 0);
    wire b_is_nan     = (exp_b == 5'b11111) && (mant_b != 0);
    wire inf_times_zero = (a_is_inf && b_is_zero) || (b_is_inf && a_is_zero);
    wire output_is_nan  = a_is_nan || b_is_nan || inf_times_zero;

    wire a_is_denorm  = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm  = (exp_b == 0) && (mant_b != 0);

    wire sign_out = sign_a ^ sign_b;          // 结果符号位

    // =========================== 尾数处理 ===========================
    // 添加隐藏位
    wire [FP16_MANT_WIDTH:0] mant_a_with_hidden = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
    wire [FP16_MANT_WIDTH:0] mant_b_with_hidden = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};

    // 尾数相乘
    wire [21:0] mant_product = mant_a_with_hidden * mant_b_with_hidden;

    // 规格化检测
    wire is_normalized = mant_product[21];
    
    // 非规格化输入处理标志
    wire denormal_input = a_is_denorm || b_is_denorm;
    
    // 前导零计数（用于非规格化数处理）
    wire [4:0] leading_zeros;
    leading_zero_counter #(
        .DATA_WIDTH(22),
        .COUNT_WIDTH(5)
    ) lzc_inst (
        .data_in(mant_product),
        .leading_zeros(leading_zeros)
    );

    // 尾数移位处理
    wire [21:0] normalized_mant;
    assign normalized_mant = denormal_input ? (mant_product << leading_zeros) :
        is_normalized ? (mant_product >> 1) : 
        mant_product;

    // 基础尾数提取
    wire [FP16_MANT_WIDTH-1:0] base_mantissa;
    assign base_mantissa = denormal_input ? normalized_mant[20:11] :
                            is_normalized ? mant_product[20:11] :
                            mant_product[19:10];

    // Guard / Round / Sticky
    wire guard_bit, round_bit, sticky_bit;
    assign guard_bit  = denormal_input ? normalized_mant[10] :
                        is_normalized ? mant_product[10] :
                        mant_product[9];
    assign round_bit  = denormal_input ? normalized_mant[9] :
                        is_normalized ? mant_product[9] :
                        mant_product[8];
    assign sticky_bit = denormal_input ? (|normalized_mant[8:0]) :
                        is_normalized ? (|mant_product[8:0]) :
                        (|mant_product[7:0]);

    // Round to Nearest Even (ties to even)
    wire should_round = guard_bit & (round_bit | sticky_bit | (~round_bit & ~sticky_bit & base_mantissa[0]));
    wire [10:0] rounded_mantissa = base_mantissa + should_round;
    wire rounding_overflow = rounded_mantissa[10];
    
    // 最终尾数选择
    wire [9:0] final_mantissa = rounding_overflow ? 10'b0 : rounded_mantissa[9:0];

    // =========================== 指数计算 ===========================
    // 计算无偏指数
    wire signed [7:0] exp_a_unbiased = a_is_denorm ? -14 : {3'b000, exp_a} - FP16_BIAS;
    wire signed [7:0] exp_b_unbiased = b_is_denorm ? -14 : {3'b000, exp_b} - FP16_BIAS;

    // 输出无偏指数
    wire signed [7:0] exp_out_unbiased = exp_a_unbiased + exp_b_unbiased;
    
    // 指数调整量计算
    wire signed [7:0] exp_adjustment;
    assign exp_adjustment = denormal_input ? 
            -{{3{1'b0}}, leading_zeros} + {7'b0, normalized_mant[21]} :
            is_normalized ? 8'd1 : 8'd0;

    // 未考虑正常数舍入的临时指数, 用来判断结果类型 (正常/非正常)
    wire signed [7:0] exp_pre_round = exp_out_unbiased + exp_adjustment + FP16_BIAS;
    
    // 最终的偏置指数
    wire signed [7:0] exp_out_biased = exp_pre_round + (rounding_overflow ? 8'd1 : 8'd0);

    // 对下溢的处理更加精确
    wire exponent_overflow = exp_out_biased > 30;  // 溢出判断使用最终指数
    wire exponent_underflow = exp_pre_round < 1;   // 下溢判断使用未舍入的指数
    
    // 非规格化结果处理
    wire result_is_denormal = (exp_pre_round <= 0) && (exp_pre_round >= -24) && (mant_product != 0);

    // 对应需要右移的位数
    wire [5:0] denormal_shift = (exp_pre_round <= 0) ? (1 - exp_pre_round) : 6'd0;
/*
   wire [25:0] extended_mantissa = result_is_denormal//【24:0】不行50w个有2个错误
        ? {2'b01, base_mantissa, guard_bit, round_bit, sticky_bit, 11'b0}
        : 26'h2FFFFFF; // 当不产生非规格化数时，赋一个任意的、能让信号翻转的值
*/
    wire [25:0] extended_mantissa = {2'b01, base_mantissa, guard_bit, round_bit, sticky_bit, 11'b0};

    wire [25:0] pre_shifted = (denormal_shift == 0) ? extended_mantissa : (extended_mantissa >> denormal_shift);

    // 提取移位后新的尾数及 G/R/S 
    wire [9:0] denormal_mantissa_raw = pre_shifted[23:14];
    wire denormal_guard  = pre_shifted[13];
    wire denormal_round  = pre_shifted[12];
    wire denormal_sticky = |pre_shifted[11:0];

    // RNE (ties to even) 舍入规则
    wire denormal_should_round = denormal_guard & (denormal_round | denormal_sticky | (~denormal_round & ~denormal_sticky & denormal_mantissa_raw[0]));
    wire [10:0] denormal_rounded = denormal_mantissa_raw + denormal_should_round;
    wire [9:0] denormal_mantissa = denormal_rounded[9:0];
    wire denormal_overflow = denormal_rounded[10];

    // 最终尾数选择   
    wire [FP16_MANT_WIDTH-1:0] computed_mantissa;
    assign computed_mantissa = result_is_denormal ? denormal_mantissa[9:0] : final_mantissa;

    // =========================== 结果组装 ===========================
    // 尾数输出选择 - 考虑非规格化数舍入溢出
    wire [FP16_MANT_WIDTH-1:0] mantissa_out;
    assign mantissa_out = 
        output_is_nan    ? {1'b1, {(FP16_MANT_WIDTH-1){1'b0}}} :
        output_is_zero   ? {FP16_MANT_WIDTH{1'b0}} :            
        output_is_inf    ? {FP16_MANT_WIDTH{1'b0}} :            
        exponent_overflow ? {FP16_MANT_WIDTH{1'b0}} :           
        (exponent_underflow && !result_is_denormal) ? {FP16_MANT_WIDTH{1'b0}} :                           
        (result_is_denormal && denormal_overflow) ? {FP16_MANT_WIDTH{1'b0}} :
        computed_mantissa;                                      

    // 指数输出选择 - 考虑非规格化数舍入溢出
    wire [FP16_EXP_WIDTH-1:0] exponent_out;
    assign exponent_out = 
        output_is_nan    ? 5'd31 :                              
        output_is_zero   ? 5'd0 :                               
        output_is_inf    ? 5'd31 :                              
        exponent_overflow ? 5'd31 :                             
        (exponent_underflow && !result_is_denormal) ? 5'd0 :    
        (result_is_denormal && denormal_overflow) ? 5'd1 :      
        result_is_denormal ? 5'd0 :                             
        exp_out_biased[4:0];                                    
    
    // 输出结果组装
    assign result = {sign_out, exponent_out, mantissa_out};

endmodule

// 前导零计数器模块
module leading_zero_counter #(
    parameter DATA_WIDTH  = 22,
    parameter COUNT_WIDTH = 5
)(
    input  wire [DATA_WIDTH-1:0]  data_in,
    output wire [COUNT_WIDTH-1:0] leading_zeros
);
    
    reg [COUNT_WIDTH-1:0] count;
    integer i;
    
    always @(*) begin
        count = DATA_WIDTH;
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
            if (data_in[i]) begin
                count = DATA_WIDTH - 1 - i;
                break;
            end
        end
    end
    
    assign leading_zeros = count;

endmodule

module fp32_multiplier (
    input  wire [31:0] a,      
    input  wire [31:0] b,      
    output wire [31:0] result  
);

    localparam FP32_EXP_WIDTH  = 8;
    localparam FP32_MANT_WIDTH = 23;
    localparam FP32_BIAS       = 127;

    wire sign_a = a[31];
    wire sign_b = b[31];
    wire [FP32_EXP_WIDTH-1:0]  exp_a  = a[30:23];
    wire [FP32_EXP_WIDTH-1:0]  exp_b  = b[30:23];
    wire [FP32_MANT_WIDTH-1:0] mant_a = a[22:0];
    wire [FP32_MANT_WIDTH-1:0] mant_b = b[22:0];

    // =========================== 特殊值检测 =========================
    wire a_is_zero    = (exp_a == 0) && (mant_a == 0);
    wire b_is_zero    = (exp_b == 0) && (mant_b == 0);
    wire output_is_zero = a_is_zero || b_is_zero;

    wire a_is_inf     = (exp_a == 8'b11111111) && (mant_a == 0);
    wire b_is_inf     = (exp_b == 8'b11111111) && (mant_b == 0);
    wire output_is_inf = (a_is_inf || b_is_inf) && !output_is_zero;

    wire a_is_nan     = (exp_a == 8'b11111111) && (mant_a != 0);
    wire b_is_nan     = (exp_b == 8'b11111111) && (mant_b != 0);
    wire inf_times_zero = (a_is_inf && b_is_zero) || (b_is_inf && a_is_zero);
    wire output_is_nan  = a_is_nan || b_is_nan || inf_times_zero;

    wire a_is_denorm  = (exp_a == 0) && (mant_a != 0);
    wire b_is_denorm  = (exp_b == 0) && (mant_b != 0);

    wire sign_out = sign_a ^ sign_b;          

    // =========================== 尾数处理 ===========================
    // 添加隐藏位
    wire [FP32_MANT_WIDTH:0] mant_a_with_hidden = a_is_denorm ? {1'b0, mant_a} : {1'b1, mant_a};
    wire [FP32_MANT_WIDTH:0] mant_b_with_hidden = b_is_denorm ? {1'b0, mant_b} : {1'b1, mant_b};

    // 尾数相乘 (24位 x 24位 = 48位)
    wire [47:0] mant_product = mant_a_with_hidden * mant_b_with_hidden;

    // 规格化检测
    wire is_normalized = mant_product[47];
    
    // 非规格化输入处理标志
    wire denormal_input = a_is_denorm || b_is_denorm;
    
    // 前导零计数（用于非规格化数处理）
    wire [5:0] leading_zeros;
    leading_zero_counter_fp32 #(
        .DATA_WIDTH(48),
        .COUNT_WIDTH(6)
    ) lzc_inst (
        .data_in(mant_product),
        .leading_zeros(leading_zeros)
    );

    // 尾数移位处理
    wire [47:0] normalized_mant;
    assign normalized_mant = denormal_input ? (mant_product << leading_zeros):
           is_normalized ? (mant_product >> 1) : mant_product;

    // 基础尾数提取
    wire [FP32_MANT_WIDTH-1:0] base_mantissa;
    assign base_mantissa = denormal_input ? normalized_mant[46:24] : 
           is_normalized ? mant_product[46:24] : mant_product[45:23];
    
    // Guard / Round / Sticky 位计算
    wire guard_bit, round_bit, sticky_bit;
    assign guard_bit = denormal_input ? normalized_mant[23] :
        is_normalized ? mant_product[23] : mant_product[22];

    assign round_bit = denormal_input ? normalized_mant[22] :
        is_normalized ? mant_product[22] : mant_product[21];

    assign sticky_bit = denormal_input ? (|normalized_mant[21:0]) :
        is_normalized ? (|mant_product[21:0]) : (|mant_product[20:0]);

    // Round to Nearest Even 
    wire should_round = guard_bit & (round_bit | sticky_bit | (~round_bit & ~sticky_bit & base_mantissa[0]));
    wire [23:0] rounded_mantissa = base_mantissa + should_round;
    wire rounding_overflow = rounded_mantissa[23];//溢出标志位
    
    // 最终尾数选择
    wire [22:0] final_mantissa = rounding_overflow ? 23'b0 : rounded_mantissa[22:0];

    // =========================== 指数计算 ===========================
    // 计算无偏指数
    wire signed [9:0] exp_a_unbiased = a_is_denorm ? -126 : {2'b00, exp_a} - FP32_BIAS;
    wire signed [9:0] exp_b_unbiased = b_is_denorm ? -126 : {2'b00, exp_b} - FP32_BIAS;

    // 输出无偏指数
    wire signed [9:0] exp_out_unbiased = exp_a_unbiased + exp_b_unbiased;
    
    // 指数调整量计算
    wire signed [9:0] exp_adjustment;
    assign exp_adjustment = denormal_input ? 
            -{{4{1'b0}}, leading_zeros} + {9'b0, normalized_mant[47]} :
            (is_normalized ? 10'd1 : 10'd0);

    wire signed [9:0] exp_pre_round = exp_out_unbiased + exp_adjustment + FP32_BIAS;

    // 最终指数，考虑舍入溢出
    wire signed [9:0] exp_out_biased = exp_pre_round + (rounding_overflow ? 10'd1 : 10'd0);
    // 指数溢出和下溢检测
    wire exponent_overflow = exp_out_biased > 254;
    wire exponent_underflow = exp_pre_round < 1;
    // 非规格化结果处理
    wire result_is_denormal = (exp_pre_round <= 0) && (exp_pre_round >= -149) && (mant_product != 0);

    // 非规格化数的右移位数
    wire [7:0] denormal_shift = (exp_pre_round <= 0) ? (1 - exp_pre_round) : 8'd0;
    wire [48:0] extended_mantissa = {2'b01, base_mantissa, guard_bit, round_bit, sticky_bit, 21'b0} ;
                             
    wire [48:0] pre_shifted = (denormal_shift == 0) ? extended_mantissa : (extended_mantissa >> denormal_shift);

    // 提取舍入位 
    wire [22:0] denormal_mantissa_raw = pre_shifted[46:24];
    wire denormal_guard = pre_shifted[23];
    wire denormal_round = pre_shifted[22]; 
    wire denormal_sticky = |pre_shifted[21:0];
    
    // 精确的舍入判断
    wire denormal_should_round = denormal_guard & (denormal_round | denormal_sticky | (~denormal_round & ~denormal_sticky & denormal_mantissa_raw[0]));
    
    wire [22:0] denormal_rounded = denormal_mantissa_raw + denormal_should_round;
    //wire [22:0] denormal_mantissa = denormal_rounded[22:0]; 
    
    // 检查非规格化数舍入后是否变为规格化数
    //wire denormal_overflow = denormal_rounded[23];
    
    // 最终尾数选择 
    wire [FP32_MANT_WIDTH-1:0] computed_mantissa;
    assign computed_mantissa = result_is_denormal ? denormal_rounded : final_mantissa;

    // =========================== 结果组装 ===========================
    wire [FP32_MANT_WIDTH-1:0] mantissa_out;
    assign mantissa_out = 
        output_is_nan    ? {1'b1, {(FP32_MANT_WIDTH-1){1'b0}}} : // NaN
        output_is_zero   ? {FP32_MANT_WIDTH{1'b0}} :             // 零
        output_is_inf    ? {FP32_MANT_WIDTH{1'b0}} :             // 无穷大
        exponent_overflow ? {FP32_MANT_WIDTH{1'b0}} :            // 溢出到无穷大
        (exponent_underflow && !result_is_denormal) ? {FP32_MANT_WIDTH{1'b0}} :   // 下溢到零
        //(result_is_denormal && denormal_overflow) ? {FP32_MANT_WIDTH{1'b0}} : // 非规格化数舍入后变为规格化数
        computed_mantissa;                                       // 正常情况

    // 指数输出选择 - 考虑非规格化数舍入溢出
    wire [FP32_EXP_WIDTH-1:0] exponent_out;
    assign exponent_out = 
        output_is_nan    ? 8'd255 :                              // NaN
        output_is_zero   ? 8'd0 :                                // 零
        output_is_inf    ? 8'd255 :                              // 无穷大
        exponent_overflow ? 8'd255 :                             // 溢出到无穷大
        (exponent_underflow && !result_is_denormal) ? 8'd0 :     // 下溢到零
        //(result_is_denormal && denormal_overflow) ? 8'd1 :       // 非规格化数舍入后变为规格化数
        result_is_denormal ? 8'd0 :                              // 非规格化数
        exp_out_biased[7:0];                                     // 正常情况
    
    // 输出结果组装
    assign result = {sign_out, exponent_out, mantissa_out};

endmodule

// FP32专用前导零计数器模块
module leading_zero_counter_fp32 #(
    parameter DATA_WIDTH  = 48,
    parameter COUNT_WIDTH = 6
)(
    input  wire [DATA_WIDTH-1:0]  data_in,
    output wire [COUNT_WIDTH-1:0] leading_zeros
);
    
    reg [COUNT_WIDTH-1:0] count;
    integer i;
    
    always @(*) begin
        count = DATA_WIDTH;
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
            if (data_in[i]) begin
                count = DATA_WIDTH - 1 - i;
                break;
            end
        end
    end
    
    assign leading_zeros = count;

endmodule