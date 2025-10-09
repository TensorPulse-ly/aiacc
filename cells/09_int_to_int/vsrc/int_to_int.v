//----------------------------------------------------------------------------
// Filename: int_to_int.v
// Author: [Oliver]
// Date: 2025-8-28
// Version: 1.0
// Description: INT to INT conversion module
//----------------------------------------------------------------------------
`timescale 1ns / 1ps
module int_to_int
(
    input wire instr_vld,              // 指令有效信号
    input wire src_prec,               // 源寄存器精度：0=16bit，1=32bit
    input wire dst_prec,               // 目的寄存器精度：0=16bit，1=32bit
    input wire src_signed,             // 源数据符号位：0=无符号，1=有符号
    input wire dst_signed,             // 目的数据符号位：0=无符号，1=有符号
    input wire src_pos,           // 源数据位置：0=低位，1=高位（仅在非全精度时有效）
    input wire dst_pos,           // 目的数据位置：0=低位，1=高位（仅在非全精度时有效）
    input wire [31:0] in_reg,          // 输入寄存器（整数）

    output wire [31:0] out_reg,        // 输出寄存器（整数）
    output wire result_vld             // 结果有效信号
);

// 内部信号
wire [15:0] src_data_16;            // 提取的16位源数据
wire [31:0] src_data_32;            // 提取的32位源数据
wire [31:0] dst_data;               // 最终输出数据
wire [15:0] dst_data_32to16;        // 32位到16位转换结果
wire [31:0] dst_data_32to16_out;    // 32位到16位输出结果
wire [31:0] dst_data_32to32;        // 32位到32位转换结果
wire [31:0] dst_data_16to32;        // 16位到32位转换结果

// 提取源数据
assign src_data_16 = src_pos ? in_reg[31:16] : in_reg[15:0];
assign src_data_32 = in_reg;

// 数据处理
// 32位到32位（4路INT32toINT32）
assign dst_data_32to32 = src_signed ? 
                        (dst_signed ? s32_to_s32(src_data_32) : s32_to_u32(src_data_32)) :
                        (dst_signed ? u32_to_s32(src_data_32) : u32_to_u32(src_data_32));
// 32位到16位（4路INT32toINT16）
assign dst_data_32to16 = src_signed ? 
                        (dst_signed ? s32_to_s16(src_data_32) : s32_to_u16(src_data_32)) :
                        (dst_signed ? u32_to_s16(src_data_32) : u32_to_u16(src_data_32));
// 16位到32位（4路INT16toINT32）
assign dst_data_16to32 = src_signed ? 
                        (dst_signed ? s16_to_s32(src_data_16) : s16_to_u32(src_data_16)) :
                        (dst_signed ? u16_to_s32(src_data_16) : u16_to_u32(src_data_16));
// 子字并行（8路INT16toINT16）
wire [15:0] src_data_16_low;        // 16位源数据低位
wire [15:0] src_data_16_high;       // 16位源数据高位
wire [15:0] dst_data_16_low;        // 16位结果低位
wire [15:0] dst_data_16_high;       // 16位结果高位

assign src_data_16_low = in_reg[15:0];
assign src_data_16_high = in_reg[31:16];
assign dst_data_16_low = src_signed ? 
                        (dst_signed ? s16_to_s16(src_data_16_low) : s16_to_u16(src_data_16_low)) :
                        (dst_signed ? u16_to_s16(src_data_16_low) : u16_to_u16(src_data_16_low));
assign dst_data_16_high = src_signed ? 
                        (dst_signed ? s16_to_s16(src_data_16_high) : s16_to_u16(src_data_16_high)) :
                        (dst_signed ? u16_to_s16(src_data_16_high) : u16_to_u16(src_data_16_high));

// 结果有效信号
assign result_vld = instr_vld;

// 结果选择
assign dst_data_32to16_out = dst_pos ? {dst_data_32to16, 16'b0} : {16'b0, dst_data_32to16};
assign dst_data = src_prec ? 
                 (dst_prec ? dst_data_32to32 : dst_data_32to16_out):
                 (dst_prec ? dst_data_16to32 : {dst_data_16_high, dst_data_16_low});

// 指令无效时输出原始数据
assign out_reg = instr_vld ? dst_data : 32'h00000000;

//=========s/u_32/16 -> s/u_32/16转换函数=========
//===============s/u_32 -> s/u_32================
function [31:0] s32_to_s32;
    input [31:0] data_in;
    begin
        s32_to_s32 = data_in; // 有符号32位到有符号32位，直接传递
    end
endfunction

function [31:0] s32_to_u32;
    input [31:0] data_in;
    begin
        if (data_in[31] == 1'b1) // 负数转换为0（0负溢出）
            s32_to_u32 = 32'b0;
        else
            s32_to_u32 = data_in; // 非负数直接传递
    end
endfunction

function [31:0] u32_to_s32;
    input [31:0] data_in;
    begin
        if (data_in[31] == 1'b1) // 超过有符号32位范围，转换为最大值（正溢出）
            u32_to_s32 = 32'h7FFFFFFF;
        else
            u32_to_s32 = data_in; // 在范围内直接传递
    end
endfunction

function [31:0] u32_to_u32;
    input [31:0] data_in;
    begin
        u32_to_u32 = data_in; // 无符号32位到无符号32位，直接传递
    end
endfunction

//===============s/u_16 -> s/u_16================
function [15:0] s16_to_s16;
    input [15:0] data_in;
    begin
        s16_to_s16 = data_in; // 有符号16位到有符号16位，直接传递
    end
endfunction

function [15:0] s16_to_u16;
    input [15:0] data_in;
    begin
        if (data_in[15] == 1'b1) // 负数转换为0（0负溢出）
            s16_to_u16 = 16'b0;
        else
            s16_to_u16 = data_in; // 非负数直接传递
    end
endfunction

function [15:0] u16_to_s16;
    input [15:0] data_in;
    begin
        if (data_in[15] == 1'b1) // 超过有符号16位范围，转换为最大值（正溢出）
            u16_to_s16 = 16'h7FFF;
        else
            u16_to_s16 = data_in; // 在范围内直接传递
    end
endfunction

function [15:0] u16_to_u16;
    input [15:0] data_in;
    begin
        u16_to_u16 = data_in; // 无符号16位到无符号16位，直接传递
    end
endfunction

//===============s/u_16 -> s/u_32================
function [31:0] s16_to_s32;
    input [15:0] data_in;
    begin
        s16_to_s32 = { {16{data_in[15]}}, data_in }; // 符号扩展
    end
endfunction

function [31:0] s16_to_u32;
    input [15:0] data_in;
    begin
        if (data_in[15] == 1'b1) // 负数转换为0（0负溢出）
            s16_to_u32 = 32'b0;
        else
            s16_to_u32 = {16'b0, data_in}; // 非负数零扩展
    end
endfunction

function [31:0] u16_to_s32;
    input [15:0] data_in;
    begin
        u16_to_s32 = {16'b0, data_in}; // 在范围内零扩展
    end
endfunction

function [31:0] u16_to_u32;
    input [15:0] data_in;
    begin
        u16_to_u32 = {16'b0, data_in}; // 无符号16位零扩展到无符号32位
    end
endfunction

//===============s/u_32 -> s/u_16================
function [15:0] s32_to_s16;
    input [31:0] data_in;
    begin   //有符号数比较
        if ($signed(data_in) > $signed(32'sh00007FFF)) // 超过有符号16位范围，转换为最大值（正溢出）
            s32_to_s16 = 16'h7FFF;
        else if ($signed(data_in) < $signed(32'shFFFF8000)) // 小于有符号16位范围，转换为最小值（负溢出）
            s32_to_s16 = 16'h8000;
        else
            s32_to_s16 = data_in[15:0]; // 在范围内直接截断
    end
endfunction

function [15:0] s32_to_u16;
    input [31:0] data_in;
    begin
        if (data_in[31] == 1'b1) // 负数转换为0（0负溢出）
            s32_to_u16 = 16'b0;
        else if (data_in > 32'h0000FFFF) // 超过无符号16位范围，转换为最大值（正溢出）
            s32_to_u16 = 16'hFFFF;
        else
            s32_to_u16 = data_in[15:0]; // 在范围内直接截断
    end
endfunction

function [15:0] u32_to_s16;
    input [31:0] data_in;
    begin
        if (data_in > 32'h00007FFF) // 超过有符号16位范围，转换为最大值（正溢出）
            u32_to_s16 = 16'h7FFF;
        else
            u32_to_s16 = data_in[15:0]; // 在范围内直接截断
    end
endfunction

function [15:0] u32_to_u16;
    input [31:0] data_in;
    begin
        if (data_in > 32'h0000FFFF) // 超过无符号16位范围，转换为最大值（正溢出）
            u32_to_u16 = 16'hFFFF;
        else
            u32_to_u16 = data_in[15:0]; // 在范围内直接截断
    end
endfunction

endmodule