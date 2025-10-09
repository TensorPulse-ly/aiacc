//-----------------------------------------------------------------------------
// Filename: wallace_tree_5_inputs.v
// Author: sunny
// Date: 2025-8-13
// Version: 2.1
// Description: 5-input Wallace Tree multiplier for FP32 adder tree.
//              Implements 3-layer compression: 5→4→3→2 using full adders.
//-----------------------------------------------------------------------------
`include "../define/fp32_defines.vh"

module wallace_tree_5_inputs #(
    parameter NUM_INPUTS = 5,                  // 输入操作数数量
    parameter WIDTH = `FULL_SUM_WIDTH          // 数据位宽 
) (
    input  wire [NUM_INPUTS*WIDTH-1:0] data_in,  // 扁平化输入数据
    output wire [WIDTH+1:0] final_result         // 最终求和结果 
);

    // 输入数据解包
    wire [WIDTH-1:0] inputs [0:NUM_INPUTS-1];
    genvar i;
    generate
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin : unpack_inputs
            assign inputs[i] = data_in[(i+1)*WIDTH-1 : i*WIDTH];
        end
    endgenerate

    // 第1层：将5个输入压缩为4个输出 (5→4)
    wire [WIDTH-1:0] layer1 [0:3];
    genvar b;
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer1_compress
            
            wire [4:0] input_bits = {
                inputs[4][b], inputs[3][b], inputs[2][b], inputs[1][b], inputs[0][b]
            };

            // 全加器：处理位[2:0]
            wire fa_sum, fa_carry;
            full_adder fa (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .c(input_bits[2]), 
                .sum(fa_sum), 
                .carry(fa_carry)
            );

            // 第1层输出
            assign layer1[0][b] = fa_sum;        // 全加器的和
            assign layer1[1][b] = input_bits[3]; // 直通位3
            assign layer1[2][b] = input_bits[4]; // 直通位4
            assign layer1[3][b] = fa_carry;      // 全加器的进位
        end
    endgenerate

    // 第2层：将4个输入压缩为3个输出 (4→3)
    wire [WIDTH-1:0] layer2 [0:2];
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer2_compress
            // 安全处理进位传播（避免负索引）
            wire carry_from_prev;
            if (b == 0) begin
                assign carry_from_prev = 1'b0;
            end else begin
                assign carry_from_prev = layer1[3][b-1];
            end
            
            // 收集此位置的4个输入位
            wire [3:0] input_bits = {
                carry_from_prev,      // 前一位全加器的进位
                layer1[0][b],         // 全加器的和
                layer1[1][b],         // 直通位3
                layer1[2][b]          // 直通位4
            };

            // 全加器：处理位[2:0]
            wire fa_sum, fa_carry;
            full_adder fa (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .c(input_bits[2]), 
                .sum(fa_sum), 
                .carry(fa_carry)
            );

            // 第2层输出
            assign layer2[0][b] = fa_sum;        // 全加器的和
            assign layer2[1][b] = input_bits[3]; // 直通位
            assign layer2[2][b] = fa_carry;      // 全加器的进位
        end
    endgenerate

    // 第3层：将3个输入压缩为2个输出 (3→2)
    wire [WIDTH-1:0] sum_out, carry_out;
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer3_compress
            // 安全处理进位传播（避免负索引）
            wire carry_from_prev;
            if (b == 0) begin
                assign carry_from_prev = 1'b0;
            end else begin
                assign carry_from_prev = layer2[2][b-1];
            end
            
            // 收集此位置的3个输入位
            wire [2:0] input_bits = {
                carry_from_prev,      // 前一位全加器的进位
                layer2[0][b],         // 全加器的和
                layer2[1][b]          // 直通位
            };

            // 全加器：处理所有3位
            wire fa_sum, fa_carry;
            full_adder fa (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .c(input_bits[2]), 
                .sum(fa_sum), 
                .carry(fa_carry)
            );

            // 最终层输出
            assign sum_out[b] = fa_sum;     // 和
            assign carry_out[b] = fa_carry; // 进位
        end
    endgenerate

    //=========================================================================
    // 最终加法阶段
    //=========================================================================
    
    wire [WIDTH:0] sum_extended = {1'b0, sum_out};      // 零扩展和
    wire [WIDTH:0] carry_extended = {carry_out, 1'b0};  // 进位左移1位
    
    final_adder #(
        .WIDTH(WIDTH + 1)  // 处理最终进位
    ) u_final_adder (
        .a(sum_extended),
        .b(carry_extended),
        .sum(final_result)
    );

endmodule
