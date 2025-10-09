`include "../define/fp32_defines.vh"

module fp32_normalizer_rounder #(
    parameter IN_WIDTH = `FULL_SUM_WIDTH + 1  
) (
    input wire [IN_WIDTH-1:0] mant_raw,            // 原始尾数结果（绝对值）
    input wire [`FP32_EXP_WIDTH-1:0] exp_in,      // 输入指数（最大指数）
    input wire sign_in,                            // 输入符号 

    output wire [`FP32_WIDTH-1:0] fp_out,         // 最终FP32结果 32位
    output reg overflow,                           // 上溢标志
    output reg underflow,                          // 下溢标志
    output reg zero_out                            // 精确零标志
);

//=============================================================================
// 参数和常量定义
//=============================================================================
localparam TARGET_POS        = `FP32_MANT_WIDTH + 1;        // 24位（含隐藏位）
localparam NORM_MANT_WIDTH   = TARGET_POS + `GUARD_BITS;    // 27位
localparam EXP_MAX           = ((1<<`FP32_EXP_WIDTH) - 1);  // 255
localparam ZERO_EXP          = {`FP32_EXP_WIDTH{1'b0}};     // 8'h00

//=============================================================================
// 内部信号声明
//=============================================================================
// 输出寄存器
reg [`FP32_WIDTH-1:0] fp_out_reg;
assign fp_out = fp_out_reg;

// 规格化相关信号
reg [`FP32_EXP_WIDTH:0] adjusted_exp;                  // 调整后的指数（9位）
reg [NORM_MANT_WIDTH-1:0] normalized_mant;             // 规格化后的尾数（27位）
reg [IN_WIDTH+`GUARD_BITS-1:0] extended_mant;          // 扩展尾数（含保护位）
integer current_msb_pos;                               // 原始尾数最高有效位位置
integer logical_shift;                                 // 移位量（正=右移，负=左移）

// 舍入相关信号
reg [`FP32_MANT_WIDTH-1:0] rounded_mant;               // 舍入后的尾数（23位）
reg [`FP32_EXP_WIDTH:0] final_exp;                     // 最终指数（9位）
reg carry_out_rounding;                                // 舍入进位标志
reg g, r, s, lsb;                                      // Guard, Round, Sticky, LSB位
reg round_up;                                          // 舍入向上标志

// 次正规数处理信号
reg [NORM_MANT_WIDTH-1:0] denorm_mant;                 // 次正规数尾数
integer denorm_shift;                                  // 次正规数移位量
reg [`FP32_MANT_WIDTH:0] dn_mant24_pre;               // 次正规数24位预处理
reg [`FP32_MANT_WIDTH:0] dn_mant24_rounded;           // 次正规数24位舍入结果
reg dn_g, dn_r, dn_s, dn_lsb, dn_round_up, dn_carry24;

// 辅助信号
reg temp_sticky;
reg sticky;                                            // 粘滞位
reg is_denorm_input;                                   // 判断输入是否为非规格化数的标志
reg [IN_WIDTH-1:0] denorm_shifted;                     // 次正规数移位临时变量
integer sticky_i;

//=============================================================================
// 主规格化逻辑
//=============================================================================
always @(*) begin 
    // 初始化默认值
    zero_out = 1'b0;
    overflow = 1'b0;
    underflow = 1'b0;
    adjusted_exp = {(`FP32_EXP_WIDTH+1){1'b0}};
    normalized_mant = {NORM_MANT_WIDTH{1'b0}};
    current_msb_pos = -1;
    sticky = 1'b0;
    
    // 判断输入是否为非规格化数：指数为0且尾数不为0
    is_denorm_input = (exp_in == 0 && mant_raw != 0);
    
    // 扩展尾数以便处理
    extended_mant = {mant_raw, {`GUARD_BITS{1'b0}}}; 

    // 检查是否为零
    if (mant_raw == 0) begin
        zero_out = 1'b1;
    end else begin
        // 查找最高有效位（MSB）位置
        current_msb_pos = IN_WIDTH - 1;
        while (current_msb_pos >= 0 && !mant_raw[current_msb_pos]) begin
            current_msb_pos = current_msb_pos - 1;
        end

        // 计算规格化所需的移位量
        logical_shift = current_msb_pos - (TARGET_POS - 1); 
        
        // 执行规格化移位
        if (logical_shift > 0) begin 
            // 右移：计算被移出的sticky位
            temp_sticky = 1'b0;
            for (sticky_i = 0; sticky_i < logical_shift; sticky_i = sticky_i + 1) begin
                if (sticky_i < (IN_WIDTH + `GUARD_BITS)) begin
                    temp_sticky = temp_sticky | extended_mant[sticky_i];
                end
            end
            sticky = temp_sticky;
            normalized_mant = extended_mant >> logical_shift;
        end else if (logical_shift < 0) begin 
            // 左移
            normalized_mant = extended_mant << (-logical_shift);
        end else begin
            // 无需移位
            normalized_mant = extended_mant;
        end

        // 指数调整逻辑
        if (is_denorm_input) begin
            // 对于非规格化数输入的特殊处理
            if (current_msb_pos < TARGET_POS - 1) begin
                adjusted_exp = 0; // 结果依然是非规格化数
            end else begin
                adjusted_exp = 1 + logical_shift - `GUARD_BITS; // 非规格化数变为规格化数
            end
        end else begin
            // 对于规格化数输入，正常调整指数
            adjusted_exp = exp_in + logical_shift - `GUARD_BITS;
        end
    end
end

//=============================================================================
// 舍入逻辑（Round to Nearest Even）
//=============================================================================
always @(*) begin
    // 提取23位尾数作为初始值
    rounded_mant = normalized_mant[NORM_MANT_WIDTH-1:`GUARD_BITS];
    final_exp = adjusted_exp;
    carry_out_rounding = 1'b0;

    if (!zero_out) begin
        // 提取Guard, Round, Sticky, LSB位（使用前3个guard bits进行舍入）
        g   = normalized_mant[`GUARD_BITS-1];              // Guard位（第5位）
        r   = normalized_mant[`GUARD_BITS-2];              // Round位（第4位）
        s   = |normalized_mant[`GUARD_BITS-3:0] | sticky; // Sticky位（第3位及以下）+ 移位sticky
        lsb = rounded_mant[0];                             // 最低有效位

        // Round to Nearest Even判断：
        // 1. G=1 且 (R=1 或 S=1)：向上舍入
        // 2. G=1, R=0, S=0, LSB=1：向上舍入（偶数对齐）
        round_up = (g & (r | s)) | (g & ~r & ~s & lsb);

        if (round_up) begin
            {carry_out_rounding, rounded_mant} = rounded_mant + 1;
            
            // 处理舍入进位
            if (carry_out_rounding) begin
                rounded_mant = {1'b1, {`FP32_MANT_WIDTH-1{1'b0}}};
                final_exp = final_exp + 1;
            end
        end
    end
end

//=============================================================================
// 最终结果封装
//=============================================================================
always @(*) begin
    if (zero_out) begin
        // 零的情况
        fp_out_reg = {sign_in, ZERO_EXP, {`FP32_MANT_WIDTH{1'b0}}};
        underflow = 1'b0;
        overflow = 1'b0;
        
    end else if (final_exp >= EXP_MAX) begin
        // 上溢：输出无穷大
        fp_out_reg = {sign_in, {`FP32_EXP_WIDTH{1'b1}}, {`FP32_MANT_WIDTH{1'b0}}};
        overflow = 1'b1;
        underflow = 1'b0;
        
    end else if (final_exp <= 0) begin
        // 下溢：处理次正规数
        underflow = 1'b1;
        overflow = 1'b0;
        
        if (is_denorm_input && final_exp == 0) begin
            // 输入为非规格化数且结果仍为非规格化数的情况
            denorm_shifted = mant_raw >> `GUARD_BITS;
            fp_out_reg = {sign_in, ZERO_EXP, denorm_shifted[`FP32_MANT_WIDTH-1:0]};
        end else begin 
            // 其他下溢情况：执行次正规数舍入
            denorm_shift = 1 - final_exp;
            denorm_mant = normalized_mant;
            
            // 计算被移出的额外sticky位
            temp_sticky = 1'b0;
            for (sticky_i = 0; sticky_i < denorm_shift; sticky_i = sticky_i + 1) begin
                if (sticky_i < NORM_MANT_WIDTH) begin
                    temp_sticky = temp_sticky | denorm_mant[sticky_i];
                end
            end
            
            // 执行次正规数右移
            denorm_mant = denorm_mant >> denorm_shift;
            
            // 在次正规数窗口执行舍入
            dn_mant24_pre = denorm_mant[NORM_MANT_WIDTH-1:`GUARD_BITS];
            dn_g = denorm_mant[`GUARD_BITS-1];
            dn_r = denorm_mant[`GUARD_BITS-2];
            dn_s = (|denorm_mant[`GUARD_BITS-3:0]) | temp_sticky;
            dn_lsb = dn_mant24_pre[0];

            dn_round_up = (dn_g & (dn_r | dn_s)) | (dn_g & ~dn_r & ~dn_s & dn_lsb);
            {dn_carry24, dn_mant24_rounded} = dn_mant24_pre + (dn_round_up ? 1'b1 : 1'b0);

            if (dn_carry24) begin
                // 次正规数舍入进位：升级为最小正规数
                fp_out_reg = {sign_in, {`FP32_EXP_WIDTH{1'b0}} | 8'd1, {`FP32_MANT_WIDTH{1'b0}}};
            end else begin
                // 保持次正规数
                fp_out_reg = {sign_in, ZERO_EXP, dn_mant24_rounded[`FP32_MANT_WIDTH-1:0]};
            end
        end
        
    end else begin
        // 正常数
        fp_out_reg = {sign_in, final_exp[`FP32_EXP_WIDTH-1:0], rounded_mant};
        underflow = 1'b0;
        overflow = 1'b0;
    end
end

endmodule