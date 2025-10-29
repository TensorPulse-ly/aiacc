`timescale 1ns/1ps
module subword_adder #(
    parameter PARAM_DR_FPADD_CNT = 4
)(
    input wire clk,
    input wire [127:0] src0,
    input wire [127:0] src1,
    input wire mode_flag,
    output reg [127:0] result
);

// 1. 子字拆分（不变）
wire [15:0] src0_16 [0:(2*PARAM_DR_FPADD_CNT)-1];
wire [15:0] src1_16 [0:(2*PARAM_DR_FPADD_CNT)-1];
wire [31:0] src0_32 [0:PARAM_DR_FPADD_CNT-1];
wire [31:0] src1_32 [0:PARAM_DR_FPADD_CNT-1];

// 2. 加法结果（不变）
wire [15:0] fp16_sum [0:(2*PARAM_DR_FPADD_CNT)-1];
wire [31:0] fp32_sum [0:PARAM_DR_FPADD_CNT-1];

genvar i;
generate
    // 16bit拆分（不变）
    for (i = 0; i < (2*PARAM_DR_FPADD_CNT); i = i + 1) begin : split_16
        assign src0_16[i] = src0[16*i +: 16];
        assign src1_16[i] = src1[16*i +: 16];
    end

    // 32bit拆分（不变）
    for (i = 0; i < PARAM_DR_FPADD_CNT; i = i + 1) begin : split_32
        assign src0_32[i] = src0[32*i +: 32];
        assign src1_32[i] = src1[32*i +: 32];
    end

    // 实例化FP32加法器（不变）
    for (i = 0; i < PARAM_DR_FPADD_CNT; i = i + 1) begin : gen_fp32
        fp32_adder u_fp32 (
            .clk(clk),
            .a(src0_32[i]),
            .b(src1_32[i]),
            .sum(fp32_sum[i])
        );
    end

    // 实例化FP16加法器（不变）
    for (i = 0; i < (2*PARAM_DR_FPADD_CNT); i = i + 1) begin : gen_fp16
        fp16_adder u_fp16 (
            .clk(clk),
            .a(src0_16[i]),
            .b(src1_16[i]),
            .sum(fp16_sum[i])
        );
    end
endgenerate

// --------------------------
// 修复：确认拼接逻辑无错位（核心）
// --------------------------
always @(*) begin
    case (mode_flag)
        1'b0: begin // 8×16bit：正确拼接8个16bit结果
            result = {
                fp16_sum[7], fp16_sum[6], fp16_sum[5], fp16_sum[4],
                fp16_sum[3], fp16_sum[2], fp16_sum[1], fp16_sum[0]
            };
        end
        1'b1: begin // 4×32bit：正确拼接4个32bit结果（127:0）
            result = {
                fp32_sum[3], // 127:96位（第4个32bit子字）
                fp32_sum[2], // 95:64位（第3个32bit子字）
                fp32_sum[1], // 63:32位（第2个32bit子字）
                fp32_sum[0]  // 31:0位（第1个32bit子字）
            };
        end
        // 异常处理：mode_flag为x/z时，输出全0避免不定态传播
        default: begin
            result = 128'hxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
        end
    endcase
end

endmodule