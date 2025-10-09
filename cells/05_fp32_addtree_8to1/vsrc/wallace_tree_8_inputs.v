//-----------------------------------------------------------------------------
// Filename: wallace_tree_8_inputs.v
// Author: sunny
// Date: 2025-8-7
// Version: 2.0
// Description: 8-input Wallace Tree multiplier for FP32 adder tree.
//              Implements 4-layer compression: 8→6→4→3→2 using full adders.
//-----------------------------------------------------------------------------
`include "../define/fp32_defines.vh"

module wallace_tree_8_inputs #(
    parameter NUM_INPUTS = 8,                  // 输入操作数数量
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

    // 第1层：将8个输入压缩为6个输出 (8→6)
    wire [WIDTH-1:0] layer1 [0:5];
    genvar b;
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer1_compress
            
            wire [7:0] input_bits = {
                inputs[7][b], inputs[6][b], inputs[5][b], inputs[4][b],
                inputs[3][b], inputs[2][b], inputs[1][b], inputs[0][b]
            };

            // 全加器1：处理位[2:0]
            wire fa1_sum, fa1_carry;
            full_adder fa1 (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .cin(input_bits[2]), 
                .sum(fa1_sum), 
                .cout(fa1_carry)
            );

            // 全加器2：处理位[5:3] 
            wire fa2_sum, fa2_carry;
            full_adder fa2 (
                .a(input_bits[3]), 
                .b(input_bits[4]), 
                .cin(input_bits[5]), 
                .sum(fa2_sum), 
                .cout(fa2_carry)
            );

            // 第1层输出
            assign layer1[0][b] = fa1_sum;        // 全加器1的和
            assign layer1[1][b] = fa2_sum;        // 全加器2的和
            assign layer1[2][b] = input_bits[6];  // 直通位6
            assign layer1[3][b] = input_bits[7];  // 直通位7
            assign layer1[4][b] = fa1_carry;      // 全加器1的进位（用于下一位）
            assign layer1[5][b] = fa2_carry;      // 全加器2的进位（用于下一位）
        end
    endgenerate

    // 第2层：将6个输入压缩为4个输出 (6→4)
    wire [WIDTH-1:0] layer2 [0:3];
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer2_compress
            // 安全处理进位传播（避免负索引）
            wire carry1_from_prev;
            wire carry2_from_prev;
            if (b == 0) begin
                assign carry1_from_prev = 1'b0;
                assign carry2_from_prev = 1'b0;
            end else begin
                assign carry1_from_prev = layer1[4][b-1];
                assign carry2_from_prev = layer1[5][b-1];
            end
            
            // 收集此位置的6个输入位
            wire [5:0] input_bits = {
                carry1_from_prev,     // 前一位全加器1的进位
                carry2_from_prev,     // 前一位全加器2的进位
                layer1[0][b],         // 全加器1的和
                layer1[1][b],         // 全加器2的和
                layer1[2][b],         // 直通位6
                layer1[3][b]          // 直通位7
            };

            // 全加器1：处理位[2:0]
            wire fa1_sum, fa1_carry;
            full_adder fa1 (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .cin(input_bits[2]), 
                .sum(fa1_sum), 
                .cout(fa1_carry)
            );

            // 全加器2：处理位[5:3]
            wire fa2_sum, fa2_carry;
            full_adder fa2 (
                .a(input_bits[3]), 
                .b(input_bits[4]), 
                .cin(input_bits[5]), 
                .sum(fa2_sum), 
                .cout(fa2_carry)
            );

            // 第2层输出
            assign layer2[0][b] = fa1_sum;    // 全加器1的和
            assign layer2[1][b] = fa2_sum;    // 全加器2的和
            assign layer2[2][b] = fa1_carry;  // 全加器1的进位
            assign layer2[3][b] = fa2_carry;  // 全加器2的进位
        end
    endgenerate

    // 第3层：将4个输入压缩为3个输出 (4→3)
    wire [WIDTH-1:0] layer3 [0:2];
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer3_compress
            // 安全处理进位传播（避免负索引）
            wire carry1_from_prev;
            wire carry2_from_prev;
            if (b == 0) begin
                assign carry1_from_prev = 1'b0;
                assign carry2_from_prev = 1'b0;
            end else begin
                assign carry1_from_prev = layer2[2][b-1];
                assign carry2_from_prev = layer2[3][b-1];
            end
            
            // 收集此位置的4个输入位
            wire [3:0] input_bits = {
                carry1_from_prev,     // 前一位全加器1的进位
                carry2_from_prev,     // 前一位全加器2的进位
                layer2[0][b],         // 全加器1的和
                layer2[1][b]          // 全加器2的和
            };

            // 全加器：处理位[2:0]
            wire fa_sum, fa_carry;
            full_adder fa (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .cin(input_bits[2]), 
                .sum(fa_sum), 
                .cout(fa_carry)
            );

            // 第3层输出
            assign layer3[0][b] = fa_sum;        // 全加器的和
            assign layer3[1][b] = input_bits[3]; // 直通位
            assign layer3[2][b] = fa_carry;      // 全加器的进位
        end
    endgenerate

    // 第4层：将3个输入压缩为2个输出 (3→2)
    wire [WIDTH-1:0] sum_out, carry_out;
    generate
        for (b = 0; b < WIDTH; b = b + 1) begin : layer4_compress
            // 安全处理进位传播（避免负索引）
            wire carry_from_prev;
            if (b == 0) begin
                assign carry_from_prev = 1'b0;
            end else begin
                assign carry_from_prev = layer3[2][b-1];
            end
            
            // 收集此位置的3个输入位
            wire [2:0] input_bits = {
                carry_from_prev,      // 前一位全加器的进位
                layer3[0][b],         // 全加器的和
                layer3[1][b]          // 直通位
            };

            // 全加器：处理所有3位
            wire fa_sum, fa_carry;
            full_adder fa (
                .a(input_bits[0]), 
                .b(input_bits[1]), 
                .cin(input_bits[2]), 
                .sum(fa_sum), 
                .cout(fa_carry)
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
