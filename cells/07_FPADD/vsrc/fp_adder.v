//---------------------------------------------------------------------
// Filename: fp_adder.v
// Author: cypher
// Date: 2025-8-5
// Version: 1.1
// Description: This is a module that supports parallel addition of subwords.
//---------------------------------------------------------------------

`timescale 1ns/1ps

module fpadd #(
    parameter PARAM_DR_FPADD_CNT = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [127:0] dvr_fpadd_s0,
    input  wire [127:0] dvr_fpadd_s1,
    output reg  [127:0] dr_fpadd_d,
    output reg  [127:0] dr_fpadd_st,
    input  wire [3:0]   cru_fpadd   // 微指令端口
);

    // 微指令字段解析（支持源/目的精度独立配置）
    wire inst_valid    = cru_fpadd[0];
    wire src_precision = cru_fpadd[1];  // 0=16bit, 1=32bit
    wire dst_precision = cru_fpadd[2];  // 0=16bit, 1=32bit
    wire update_status = cru_fpadd[3];

    // 状态机定义
    parameter STATE_IDLE = 2'b00;
    parameter STATE_PROC = 2'b01;
    parameter STATE_WAIT = 2'b10;
    parameter STATE_DONE = 2'b11;

    reg [1:0] current_state, next_state;

    // 寄存器
    reg [127:0] src0_reg, src1_reg;
    reg         src_precision_reg, dst_precision_reg;
    reg [127:0] result_reg;
    wire [127:0] subword_result;

    // 辅助函数：FP16比较
    function [2:0] cmp_fp16;
        input [15:0] a, b;
        reg a_sign, b_sign;
        reg [4:0] a_exp, b_exp;
        reg [9:0] a_frac, b_frac;
        begin
            a_sign = a[15]; a_exp = a[14:10]; a_frac = a[9:0];
            b_sign = b[15]; b_exp = b[14:10]; b_frac = b[9:0];

            if ({a[15:0]} == 16'h0000 || {a[15:0]} == 16'h8000) begin
                if ({b[15:0]} == 16'h0000 || {b[15:0]} == 16'h8000)
                    cmp_fp16 = 3'b010;  // both zero
                else if (b_sign)
                    cmp_fp16 = 3'b100;  // b < 0
                else
                    cmp_fp16 = 3'b001;  // b > 0
            end
            else if ({b[15:0]} == 16'h0000 || {b[15:0]} == 16'h8000) begin
                if (a_sign)
                    cmp_fp16 = 3'b001;  // a < 0
                else
                    cmp_fp16 = 3'b100;  // a > 0
            end
            else begin
                if (a_sign < b_sign)          cmp_fp16 = 3'b100;
                else if (a_sign > b_sign)     cmp_fp16 = 3'b001;
                else begin
                    if (a_exp > b_exp)        cmp_fp16 = a_sign ? 3'b001 : 3'b100;
                    else if (a_exp < b_exp)   cmp_fp16 = a_sign ? 3'b100 : 3'b001;
                    else begin
                        if (a_frac > b_frac)  cmp_fp16 = a_sign ? 3'b001 : 3'b100;
                        else if (a_frac < b_frac) cmp_fp16 = a_sign ? 3'b100 : 3'b001;
                        else                  cmp_fp16 = 3'b010;
                    end
                end
            end
        end
    endfunction

    // 辅助函数：FP32比较
    function [2:0] cmp_fp32;
        input [31:0] a, b;
        reg a_sign, b_sign;
        reg [7:0] a_exp, b_exp;
        reg [22:0] a_frac, b_frac;
        begin
            a_sign = a[31]; a_exp = a[30:23]; a_frac = a[22:0];
            b_sign = b[31]; b_exp = b[30:23]; b_frac = b[22:0];

            if ({a[31:0]} == 32'h00000000 || {a[31:0]} == 32'h80000000) begin
                if ({b[31:0]} == 32'h00000000 || {b[31:0]} == 32'h80000000)
                    cmp_fp32 = 3'b010;
                else if (b_sign)
                    cmp_fp32 = 3'b100;
                else
                    cmp_fp32 = 3'b001;
            end
            else if ({b[31:0]} == 32'h00000000 || {b[31:0]} == 32'h80000000) begin
                if (a_sign)
                    cmp_fp32 = 3'b001;
                else
                    cmp_fp32 = 3'b100;
            end
            else begin
                if (a_sign < b_sign)          cmp_fp32 = 3'b100;
                else if (a_sign > b_sign)     cmp_fp32 = 3'b001;
                else begin
                    if (a_exp > b_exp)        cmp_fp32 = a_sign ? 3'b001 : 3'b100;
                    else if (a_exp < b_exp)   cmp_fp32 = a_sign ? 3'b100 : 3'b001;
                    else begin
                        if (a_frac > b_frac)  cmp_fp32 = a_sign ? 3'b001 : 3'b100;
                        else if (a_frac < b_frac) cmp_fp32 = a_sign ? 3'b100 : 3'b001;
                        else                  cmp_fp32 = 3'b010;
                    end
                end
            end
        end
    endfunction

    // 状态寄存器布局：128bit，但有效位如下
    // 目的精度=16bit: 8组×3bit，分别位于 16*k+2:16*k
    // 目的精度=32bit: 4组×3bit，分别位于 32*k+2:32*k
    integer k;

    // 时序逻辑：状态机 + 寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state      <= STATE_IDLE;
            src0_reg           <= 128'b0;
            src1_reg           <= 128'b0;
            src_precision_reg  <= 1'b0;
            dst_precision_reg  <= 1'b0;
            result_reg         <= 128'b0;
            dr_fpadd_d         <= 128'b0;
            dr_fpadd_st        <= 128'b0;
        end
        else begin
            current_state <= next_state;

            if (current_state == STATE_IDLE && inst_valid) begin
                src0_reg          <= dvr_fpadd_s0;
                src1_reg          <= dvr_fpadd_s1;
                src_precision_reg <= src_precision;
                dst_precision_reg <= dst_precision;
            end

            if (current_state == STATE_WAIT) begin
                result_reg <= subword_result;
            end

            if (current_state == STATE_DONE) begin
                dr_fpadd_d  <= result_reg;
                dr_fpadd_st <= 128'b0;  // 先清零，再写入有效位

                if (update_status) begin
                    if (dst_precision_reg == 1'b0) begin      // 目的=16bit → 8×FP16
                        for (k = 0; k < 8; k = k + 1) begin
                            dr_fpadd_st[16*k +: 3] <= cmp_fp16(src0_reg[16*k +:16],
                                                              src1_reg[16*k +:16]);
                        end
                    end
                    else begin                                // 目的=32bit → 4×FP32
                        for (k = 0; k < 4; k = k + 1) begin
                            dr_fpadd_st[32*k +: 3] <= cmp_fp32(src0_reg[32*k +:32],
                                                              src1_reg[32*k +:32]);
                        end
                    end
                end
            end
        end
    end

    // 组合逻辑：状态机转移
    always @(*) begin
        next_state = current_state;
        case (current_state)
            STATE_IDLE: next_state = inst_valid ? STATE_PROC : STATE_IDLE;
            STATE_PROC: next_state = STATE_WAIT;
            STATE_WAIT: next_state = STATE_DONE;
            STATE_DONE: next_state = STATE_IDLE;
            default:    next_state = STATE_IDLE;
        endcase
    end


    subword_adder u_subword_adder (
        .clk       (clk),
        .rst_n     (rst_n),
        .src0      (src0_reg),
        .src1      (src1_reg),
        .mode_flag (src_precision_reg), // 0=16bit×8, 1=32bit×4
        .result    (subword_result)
    );

endmodule