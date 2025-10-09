`timescale 1ns/1ps
//----------------------------------------------------------------------------
// Filename: fpto_int.v
// Author: [Sunny]
// Editor: [Oliver]
// Date: 2025-8-30
// Version: 1.2
// Description: FP to INT conversion module, Modified the Input/Output port. 
// 结合子字并行模式与16to16转换，组成8个并行16位整数到16位浮点转换器
// 修正输出
//----------------------------------------------------------------------------
module fpto_int (
    // 微指令控制信号
    input  wire         inst_vld,             // 指令有效信号：1=有效，0=无效
    input  wire         src_prec,          // 源寄存器精度：0=16bit，1=32bit
    input  wire         dst_prec,          // 目的寄存器精度：0=16bit，1=32bit
    input  wire         src_pos,           // 源数据位置：0=低位，1=高位（仅在非全精度时有效）
    input  wire         dst_pos,           // 目的数据位置：0=低位，1=高位（仅在非全精度时有效）
    
    // 数据接口
    input  wire [31:0]  in_reg,          // 输入寄存器（浮点数）
    output wire [31:0]  out_reg,         // 输出寄存器（整数）
    output wire         result_vld     // 结果有效信号
);

// 源数据处理
wire [31:0] src_data;                   // 处理后的32位源数据
wire [15:0] src_data_16;                // 提取的16位源数据
wire [31:0] src_data_32;                // 扩展后的32位源数据

// 子字并行处理信号
wire subword_parallel_mode;             // 子字并行模式：32bit输入->16bit输出
wire [15:0] src_low_16, src_high_16;    // 子字并行的源数据
wire [15:0] dst_low_16, dst_high_16;    // 子字并行的目标数据

// 目标数据生成
wire [31:0] dst_data;                   // 最终输出数据
wire [15:0] dst_data_16;                // 16位转换结果
wire [31:0] dst_data_32;                // 32位转换结果

// 浮点数解析信号
wire        src_sign_bit;               // 符号位
wire [7:0]  src_exponent;               // 指数位（用于FP32）
wire [22:0] src_mantissa;               // 尾数位（用于FP32）
wire [4:0]  src_exp_16;                 // 指数位（用于FP16）
wire [9:0]  src_mant_16;                // 尾数位（用于FP16）

// 子字并行模式检测：32bit输入 -> 16bit输出时启用
assign subword_parallel_mode = (src_prec == 1'b0) && (dst_prec == 1'b0);

// 子字并行数据分离
assign src_low_16 = in_reg[15:0];      // 低16位
assign src_high_16 = in_reg[31:16];    // 高16位

// 提取源数据
assign src_data_16 = src_pos ? in_reg[31:16] : in_reg[15:0];
assign src_data_32 = in_reg;
assign src_data = src_prec ? src_data_32 : {16'b0, src_data_16};

// 浮点数位域解析（用于32位浮点数）
assign src_sign_bit = src_data[31];
assign src_exponent = src_data[30:23];
assign src_mantissa = src_data[22:0];

// 16位浮点数位域解析（用于16位浮点数）
assign src_exp_16 = src_data_16[14:10];
assign src_mant_16 = src_data_16[9:0];

//=============== Float to Integer 转换函数 ==================
function [31:0] fp32_to_int32;
    input [31:0] fp_data;
    reg sign;
    reg [7:0] exp;
    reg [22:0] mant;
    reg [8:0] biased_exp;  // 使用更宽的位宽处理有符号计算
    reg [31:0] int_result;
    reg [23:0] significand;
    integer shift_amount;
begin
    sign = fp_data[31];
    exp = fp_data[30:23];
    mant = fp_data[22:0];
    
    // 特殊情况处理
    if (exp == 8'hFF) begin
        // 无穷大或NaN - 根据IEEE标准，都转换为最大负数
        fp32_to_int32 = 32'h80000000;
    end else if (exp == 8'h00) begin
        // 零或非规格化数 - 都转换为0
        fp32_to_int32 = 32'h00000000;
    end else begin
        // 规格化数处理
        biased_exp = {1'b0, exp} - 9'd127;  // 移除偏置127，使用有符号计算
        significand = {1'b1, mant}; // 添加隐含的1
        
        if ($signed(biased_exp) > $signed(9'd30)) begin
            // 指数太大，溢出 - 所有溢出都返回最大负数
            fp32_to_int32 = 32'h80000000;
        end else if ($signed(biased_exp) < $signed(9'd0)) begin
            // 指数小于0，结果为0（小数部分被截断）
            fp32_to_int32 = 32'h00000000;
        end else begin
            // 正常转换
            shift_amount = 23 - biased_exp[7:0];
            if (shift_amount >= 0 && shift_amount < 24) begin
                int_result = significand >> shift_amount;
            end else if (shift_amount < 0 && (-shift_amount) < 9) begin
                int_result = significand << (-shift_amount);
            end else begin
                // 移位量过大，溢出 - 所有溢出都返回最大负数
                fp32_to_int32 = 32'h80000000;
            end
            
            // 检查溢出并应用符号位
            if (sign) begin
                if (int_result > 32'h80000000) begin
                    fp32_to_int32 = 32'h80000000;
                end else begin
                    fp32_to_int32 = (~int_result + 1);
                end
            end else begin
                if (int_result > 32'h7FFFFFFF) begin
                    fp32_to_int32 = 32'h80000000;  // 正溢出也返回最大负数
                end else begin
                    fp32_to_int32 = int_result;
                end
            end
        end
    end
end
endfunction

function [15:0] fp16_to_int16;
    input [15:0] fp_data;
    reg sign;
    reg [4:0] exp;
    reg [9:0] mant;
    reg [5:0] biased_exp;  // 使用更宽的位宽处理有符号计算
    reg [15:0] int_result;
    reg [10:0] significand;
    integer shift_amount;
begin
    sign = fp_data[15];
    exp = fp_data[14:10];
    mant = fp_data[9:0];
    
    // 特殊情况处理
    if (exp == 5'h1F) begin
        // 无穷大或NaN - 都转换为最大负数
        fp16_to_int16 = 16'h8000;
    end else if (exp == 5'h00) begin
        // 零或非规格化数 - 都转换为0
        fp16_to_int16 = 16'h0000;
    end else begin
        // 规格化数处理
        biased_exp = {1'b0, exp} - 6'd15;  // 移除偏置15，使用有符号计算
        significand = {1'b1, mant}; // 添加隐含的1
        
        if ($signed(biased_exp) > $signed(6'd14)) begin
            // 指数太大，溢出
            fp16_to_int16 = sign ? 16'h8000 : 16'h7FFF;
        end else if ($signed(biased_exp) < $signed(6'd0)) begin
            // 指数小于0，结果为0（小数部分被截断）
            fp16_to_int16 = 16'h0000;
        end else begin
            // 正常转换
            shift_amount = 10 - biased_exp[4:0];
            if (shift_amount >= 0 && shift_amount < 11) begin
                int_result = significand >> shift_amount;
            end else if (shift_amount < 0 && (-shift_amount) < 6) begin
                int_result = significand << (-shift_amount);
            end else begin
                // 移位量过大，溢出
                fp16_to_int16 = sign ? 16'h8000 : 16'h7FFF;
            end
            
            // 检查溢出并应用符号位
            if (sign) begin
                if (int_result > 16'h8000) begin
                    fp16_to_int16 = 16'h8000;
                end else begin
                    fp16_to_int16 = (~int_result + 1);
                end
            end else begin
                if (int_result > 16'h7FFF) begin
                    fp16_to_int16 = 16'h7FFF;
                end else begin
                    fp16_to_int16 = int_result[15:0];
                end
            end
        end
    end
end
endfunction

// 32位浮点数转换为16位整数（需要饱和处理）
function [15:0] fp32_to_int16_saturate;
    input [31:0] fp_data;
    reg [31:0] temp_int32;
begin
    temp_int32 = fp32_to_int32(fp_data);
    
    // 饱和处理
    if ($signed(temp_int32) > $signed(32'h00007FFF)) begin
        fp32_to_int16_saturate = 16'h7FFF;    // 正溢出
    end else if ($signed(temp_int32) < $signed(32'hFFFF8000)) begin
        fp32_to_int16_saturate = 16'h8000;    // 负溢出
    end else begin
        fp32_to_int16_saturate = temp_int32[15:0];
    end
end
endfunction

// 16位浮点数转换为32位整数（符号扩展）
function [31:0] fp16_to_int32_extend;
    input [15:0] fp_data;
    reg sign;
    reg [4:0] exp;
    reg [9:0] mant;
    reg [5:0] biased_exp;
    reg [31:0] int_result;
    reg [10:0] significand;
    integer shift_amount;
begin
    sign = fp_data[15];
    exp = fp_data[14:10];
    mant = fp_data[9:0];
    
    // 特殊情况直接处理为32位结果
    if (exp == 5'h1F) begin
        // 无穷大或NaN - 都转换为最大负数
        fp16_to_int32_extend = 32'h80000000;
    end else if (exp == 5'h00) begin
        // 零或非规格化数
        fp16_to_int32_extend = 32'h00000000;
    end else begin
        // 规格化数处理 - 直接转换为32位，不经过16位
        biased_exp = {1'b0, exp} - 6'd15;
        significand = {1'b1, mant};
        
        if ($signed(biased_exp) > $signed(6'd30)) begin
            // 指数太大，INT32溢出
            fp16_to_int32_extend = sign ? 32'h80000000 : 32'h7FFFFFFF;
        end else if ($signed(biased_exp) < $signed(6'd0)) begin
            // 指数小于0，结果为0
            fp16_to_int32_extend = 32'h00000000;
        end else begin
            // 正常转换
            shift_amount = 10 - biased_exp[4:0];
            if (shift_amount >= 0 && shift_amount < 11) begin
                int_result = significand >> shift_amount;
            end else if (shift_amount < 0 && (-shift_amount) < 22) begin
                int_result = significand << (-shift_amount);
            end else begin
                // 移位量过大，溢出
                fp16_to_int32_extend = sign ? 32'h80000000 : 32'h7FFFFFFF;
            end
            
            // 检查溢出并应用符号位
            if (sign) begin
                if (int_result > 32'h80000000) begin
                    fp16_to_int32_extend = 32'h80000000;
                end else begin
                    fp16_to_int32_extend = (~int_result + 1);
                end
            end else begin
                if (int_result > 32'h7FFFFFFF) begin
                    fp16_to_int32_extend = 32'h7FFFFFFF;
                end else begin
                    fp16_to_int32_extend = int_result;
                end
            end
        end
    end
end
endfunction

//===================== 子字并行转换 ====================
// 并行转换低16位和高16位数据（FP16->INT16）
assign dst_low_16 = fp16_to_int16(src_low_16);
assign dst_high_16 = fp16_to_int16(src_high_16);

//===================== 普通转换 ==========================
// 16位转换结果
assign dst_data_16 = src_prec ? fp32_to_int16_saturate(src_data_32) : fp16_to_int16(src_data_16);

// 32位转换结果
assign dst_data_32 = src_prec ? fp32_to_int32(src_data_32) : fp16_to_int32_extend(src_data_16);

// 根据子字并行模式选择输出
wire [31:0] dst_data_16_result;
assign dst_data_16_result = subword_parallel_mode ? 
                           {dst_high_16, dst_low_16} :                                    // 子字并行：组合高低转换结果
                           (dst_pos ? {dst_data_16, 16'h0000} : {16'h0000, dst_data_16}); // 普通模式：根据位置放置

// 选择最终输出数据  
assign dst_data = dst_prec ? dst_data_32 : dst_data_16_result;

// 与输入指令有效信号一致
assign result_vld = inst_vld;

// 指令无效时输出为0
assign out_reg = inst_vld ? dst_data : 32'h0;

endmodule
