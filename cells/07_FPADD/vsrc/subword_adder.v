`timescale 1ns/1ps

module subword_adder (
    input wire clk,
    input wire rst_n,
    input wire [127:0] src0,
    input wire [127:0] src1,
    input wire mode_flag,  // 0=16bit×8, 1=32bit×4
    output reg [127:0] result
);

    // 拆分输入
    wire [15:0] src0_16 [0:7];
    wire [15:0] src1_16 [0:7];
    wire [31:0] src0_32 [0:3];
    wire [31:0] src1_32 [0:3];

    wire [15:0] fp16_sum [0:7];
    wire [31:0] fp32_sum [0:3];

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : split_16
            assign src0_16[i] = src0[16*i +: 16];
            assign src1_16[i] = src1[16*i +: 16];
        end

        for (i = 0; i < 4; i = i + 1) begin : split_32
            assign src0_32[i] = src0[32*i +: 32];
            assign src1_32[i] = src1[32*i +: 32];
        end

        for (i = 0; i < 4; i = i + 1) begin : gen_fp32
            fp32_adder u_fp32 (
                .clk(clk),
                .a(src0_32[i]),
                .b(src1_32[i]),
                .sum(fp32_sum[i])
            );
        end

        for (i = 0; i < 8; i = i + 1) begin : gen_fp16
            fp16_adder u_fp16 (
                .clk(clk),
                .a(src0_16[i]),
                .b(src1_16[i]),
                .sum(fp16_sum[i])
            );
        end
    endgenerate

    always @(*) begin
        case (mode_flag)
            1'b0: begin // 16-bit × 8
                result = {
                    fp16_sum[7],
                    fp16_sum[6],
                    fp16_sum[5],
                    fp16_sum[4],
                    fp16_sum[3],
                    fp16_sum[2],
                    fp16_sum[1],
                    fp16_sum[0]
                };
            end
            1'b1: begin // 32-bit × 4
                result = {
                    fp32_sum[3],
                    fp32_sum[2],
                    fp32_sum[1],
                    fp32_sum[0]
                };
            end
        endcase
    end

endmodule