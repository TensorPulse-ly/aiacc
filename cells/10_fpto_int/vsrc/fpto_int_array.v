//----------------------------------------------------------------------------
// Filename: fpto_int_array.v
// Author: [Sunny]
// Editor: [Oliver]
// Date: 2025-8-30
// Version: 1.2
// Description: FP to INT conversion module, Modified the Input/Output port. 
// 修正输出
//----------------------------------------------------------------------------
`timescale 1ns / 1ps
module fpto_int_array (
    input clk,                  // 时钟输入
    input rst_n,                // 低有效复位

    input wire [127:0] dvr_fptoint_s_in,    // 输入数据寄存器
    input wire [4:0]   cru_fptoint_in,      // 上行指令寄存器
    output reg [127:0] dr_fptoint_d_out     // 输出数据寄存器
);

// 微指令解析
wire inst_vld = cru_fptoint_in[4];      // 指令有效信号
wire src_prec = cru_fptoint_in[3];       // 源寄存器精度：0=16bit，1=32bit
wire dst_prec = cru_fptoint_in[2];       // 目的寄存器精度：0=16bit，1=32bit
wire src_pos = cru_fptoint_in[1];        // 源数据位置：0=低位，1=高位（仅在非全精度时有效）
wire dst_pos = cru_fptoint_in[0];        // 目的数据位置：0=低位，1=高位（仅在非全精度时有效）

// 实例化4个FPtoINT单元

wire [31:0]  in_reg_0 = dvr_fptoint_s_in[127:96];        // 输入寄存器0（浮点数）
wire [31:0]  in_reg_1 = dvr_fptoint_s_in[95:64];         // 输入寄存器1（浮点数）
wire [31:0]  in_reg_2 = dvr_fptoint_s_in[63:32];         // 输入寄存器2（浮点数）
wire [31:0]  in_reg_3 = dvr_fptoint_s_in[31:0];          // 输入寄存器3（浮点数）
   
wire [31:0]  out_reg_0;       // 输出寄存器0（整数）
wire [31:0]  out_reg_1;       // 输出寄存器1（整数）
wire [31:0]  out_reg_2;       // 输出寄存器2（整数）
wire [31:0]  out_reg_3;       // 输出寄存器3（整数）

wire [3:0]   result_vld;     // 结果有效信号（4位）

fpto_int unit_0 (
    .inst_vld(inst_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_0),
    .out_reg(out_reg_0),
    .result_vld(result_vld[0])
);

fpto_int unit_1 (
    .inst_vld(inst_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_1),
    .out_reg(out_reg_1),
    .result_vld(result_vld[1])
);

fpto_int unit_2 (
    .inst_vld(inst_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_2),
    .out_reg(out_reg_2),
    .result_vld(result_vld[2])
);

fpto_int unit_3 (
    .inst_vld(inst_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg_3),
    .out_reg(out_reg_3),
    .result_vld(result_vld[3])
);

// 输出数据寄存器更新逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dr_fptoint_d_out <= 128'h0; // 复位时清空输出寄存器
    end else begin
        dr_fptoint_d_out[127:96] = out_reg_0;
        dr_fptoint_d_out[95:64] = out_reg_1;
        dr_fptoint_d_out[63:32] = out_reg_2;
        dr_fptoint_d_out[31:0] = out_reg_3;
    end
end

endmodule