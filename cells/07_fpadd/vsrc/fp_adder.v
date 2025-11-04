//---------------------------------------------------------------------
// Filename: inttofp.v
// Author: cypher
// Date: 2025-11-4
// Version: 1.3
// Description: This is a module that supports fp16+fp16 or fp32+fp32.
//---------------------------------------------------------------------
`timescale 1ns/1ps

module fpadd #(
    parameter PARAM_DR_FPADD_CNT = 4  // 加法器数量：32bit→4个，16bit→8个
)(
    input  wire        clk,
    input  wire        rst_n,
    // 新增：SMC编号（5bit，符合AIACC架构v0.2.7定义，取值0~31）
    input  wire [4:0]  smc_id,
    // 原有输入：源操作数与微指令
    input  wire [127:0] dvr_fpadd_s0,  // 源操作数0
    input  wire [127:0] dvr_fpadd_s1,  // 源操作数1
    input  wire [3:0]   cru_fpadd,     // 4bit微指令：[3]更新状态,[2]目的精度,[1]源精度,[0]指令有效
    // 原有输出：加法结果与状态
    output reg  [127:0] dr_fpadd_d,    // 加法结果输出
    output reg  [127:0] dr_fpadd_st,   // 状态寄存器输出
    // 新增：CRU-FPADD上行输出（4bit寄存器，符合AIACC架构v0.2.7的CRU级联逻辑）
    output reg  [3:0]   cru_fpadd_o    
);

    // 微指令解析（不变）
    wire inst_valid     = cru_fpadd[0];
    wire src_prec       = cru_fpadd[1];
    wire dest_prec      = cru_fpadd[2];
    wire update_status  = cru_fpadd[3];
    wire inst_trigger   = inst_valid;  // 指令触发条件
    wire mode_flag      = src_prec;  // 0=16bit模式，1=32bit模式（仅触发时有效）

    // 状态机定义（不变）
    parameter STATE_IDLE = 2'b00;  // 空闲
    parameter STATE_WAIT = 2'b01;  // 等待加法结果（仅停留1拍，与计算并行）
    parameter STATE_DONE = 2'b10;  // 结果输出

    // 内部寄存器（不变）
    reg [1:0] current_state, next_state;
    reg [127:0] src0_reg, src1_reg;  // 输入数据锁存
    reg         mode_flag_reg;       // 精度模式锁存
    reg [127:0] result_reg;          // 结果缓存

    wire [127:0] subword_result;     // 子字加法器输出

    // --------------------------- 比较函数（完全不变） ---------------------------
    function [2:0] cmp_fp16;
        input [15:0] a, b;
        reg a_s, b_s;
        reg [4:0] a_e, b_e;
        reg [9:0] a_f, b_f;
        begin
            a_s = a[15]; a_e = a[14:10]; a_f = a[9:0];
            b_s = b[15]; b_e = b[14:10]; b_f = b[9:0];

            if ((a == 16'h0000) || (a == 16'h8000)) begin
                if ((b == 16'h0000) || (b == 16'h8000)) cmp_fp16 = 3'b010;
                else cmp_fp16 = b_s ? 3'b100 : 3'b001;
            end
            else if ((b == 16'h0000) || (b == 16'h8000)) begin
                cmp_fp16 = a_s ? 3'b001 : 3'b100;
            end
            else begin
                if (a_s != b_s) cmp_fp16 = a_s ? 3'b001 : 3'b100;
                else begin
                    if (a_e != b_e) cmp_fp16 = (a_e > b_e) ? (a_s ? 3'b001 : 3'b100) : (a_s ? 3'b100 : 3'b001);
                    else begin
                        cmp_fp16 = (a_f > b_f) ? (a_s ? 3'b001 : 3'b100) : (a_f < b_f ? (a_s ? 3'b100 : 3'b001) : 3'b010);
                    end
                end
            end
        end
    endfunction

    function [2:0] cmp_fp32;
        input [31:0] a, b;
        reg a_s, b_s;
        reg [7:0] a_e, b_e;
        reg [22:0] a_f, b_f;
        begin
            a_s = a[31]; a_e = a[30:23]; a_f = a[22:0];
            b_s = b[31]; b_e = b[30:23]; b_f = b[22:0];

            if ((a == 32'h00000000) || (a == 32'h80000000)) begin
                if ((b == 32'h00000000) || (b == 32'h80000000)) cmp_fp32 = 3'b010;
                else cmp_fp32 = b_s ? 3'b100 : 3'b001;
            end
            else if ((b == 32'h00000000) || (b == 32'h80000000)) begin
                cmp_fp32 = a_s ? 3'b001 : 3'b100;
            end
            else begin
                if (a_s != b_s) cmp_fp32 = a_s ? 3'b001 : 3'b100;
                else begin
                    if (a_e != b_e) cmp_fp32 = (a_e > b_e) ? (a_s ? 3'b001 : 3'b100) : (a_s ? 3'b100 : 3'b001);
                    else begin
                        cmp_fp32 = (a_f > b_f) ? (a_s ? 3'b001 : 3'b100) : (a_f < b_f ? (a_s ? 3'b100 : 3'b001) : 3'b010);
                    end
                end
            end
        end
    endfunction

    // --------------------------- 时序逻辑（仅新增cru_fpadd_o处理） ---------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
            src0_reg      <= 128'b0;
            src1_reg      <= 128'b0;
            mode_flag_reg <= 1'b0;
            result_reg    <= 128'b0;
            dr_fpadd_d    <= 128'b0;
            dr_fpadd_st   <= 128'b0;
            // 新增：cru_fpadd_o复位为0（符合寄存器输出初始态）
            cru_fpadd_o   <= 4'b0000;
        end else begin
            current_state <= next_state;

            // 核心修改1：输入锁存不依赖IDLE状态，inst_trigger有效时直接锁存（原有逻辑不变）
            if (inst_trigger) begin
                src0_reg      <= dvr_fpadd_s0;
                src1_reg      <= dvr_fpadd_s1;
                mode_flag_reg <= mode_flag;
            end

            // 核心修改2：result_reg在WAIT状态锁存（原有逻辑不变）
            if (current_state == STATE_WAIT) begin
                result_reg <= subword_result;
            end

            // 核心修改3：新增cru_fpadd_o级联逻辑（符合AIACC架构v0.2.7）
            // 逻辑：本SMC的CRU输出 = 本SMC的CRU输入（上游SMC已驱动cru_fpadd输入）
            cru_fpadd_o <= cru_fpadd;

            // 结果输出（原有逻辑不变）
            if (current_state == STATE_DONE) begin
                dr_fpadd_d  <= result_reg;
                dr_fpadd_st <= 128'b0;

                if (update_status) begin
                    if (mode_flag_reg == 1'b0) begin
                        for (integer k=0; k<8; k=k+1) begin
                            dr_fpadd_st[16*k +: 3] <= cmp_fp16(src0_reg[16*k +:16], src1_reg[16*k +:16]);
                        end
                    end else begin
                        for (integer k=0; k<4; k=k+1) begin
                            dr_fpadd_st[32*k +: 3] <= cmp_fp32(src0_reg[32*k +:32], src1_reg[32*k +:32]);
                        end
                    end
                end
            end
        end
    end

    // --------------------------- 状态机逻辑（完全不变） ---------------------------
    always @(*) begin
        next_state = current_state;
        case (current_state)
            STATE_IDLE:  begin
                next_state = inst_trigger ? STATE_WAIT : STATE_IDLE;
            end
            STATE_WAIT:  begin
                next_state = STATE_DONE;
            end
            STATE_DONE:  begin
                next_state = STATE_IDLE;
            end
            default:     next_state = STATE_IDLE;
        endcase
    end

    // --------------------------- 子字加法器调用（完全不变） ---------------------------
    subword_adder #(
        .PARAM_DR_FPADD_CNT(PARAM_DR_FPADD_CNT)
    ) u_subword_adder (
        .clk(clk),
        .src0(src0_reg),
        .src1(src1_reg),
        .mode_flag(mode_flag_reg),
        .result(subword_result)
    );

endmodule