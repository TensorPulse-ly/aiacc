//-----------------------------------------------------------------------------
// Filename: fp32_adder_tree_8_inputs.v
// Author: sunny
// Date: 2025-8-20
// Version: 2.0
// Description: Implement an 8-parallel-channel single-precision floating-point 
//              8-input adder tree structure 
//-----------------------------------------------------------------------------
`include "../define/fp32_defines.vh"

module fp32_adder_tree_8_inputs (
    input wire clk,                                      // 时钟
    input wire rst_n,                                    // 低电平有效的复位信号
    input wire [127:0] dvr_fp32addtree8to1_s0,          // 计算输入数据0 
    input wire [127:0] dvr_fp32addtree8to1_s1,          // 计算输入数据1  
    input wire [2:0] cru_fp32addtree8to1,               // 上行指令寄存器 
    
    output reg [127:0] dr_fp32addtree8to1_d              // 输出数据 
);

    localparam NUM_INPUTS = 8;
    genvar i, j, k;
    
    // 指令解析
    wire cmd_valid;
    wire [1:0] dest_reg_idx;
    assign cmd_valid = cru_fp32addtree8to1[2];            // 指令有效位
    assign dest_reg_idx = cru_fp32addtree8to1[1:0];       // 目的寄存器编码
    
    // 每个FP32由对应位置的S0[y]+S1[y]组成
    wire [15:0] s0_16bit_data [0:7];  // S0寄存器的8个16bit数据段
    wire [15:0] s1_16bit_data [0:7];  // S1寄存器的8个16bit数据段
    
    // 解包S0寄存器 - 8个16bit段
    assign s0_16bit_data[0] = dvr_fp32addtree8to1_s0[15:0];
    assign s0_16bit_data[1] = dvr_fp32addtree8to1_s0[31:16];
    assign s0_16bit_data[2] = dvr_fp32addtree8to1_s0[47:32];
    assign s0_16bit_data[3] = dvr_fp32addtree8to1_s0[63:48];
    assign s0_16bit_data[4] = dvr_fp32addtree8to1_s0[79:64];
    assign s0_16bit_data[5] = dvr_fp32addtree8to1_s0[95:80];
    assign s0_16bit_data[6] = dvr_fp32addtree8to1_s0[111:96];
    assign s0_16bit_data[7] = dvr_fp32addtree8to1_s0[127:112];
    
    // 解包S1寄存器 - 8个16bit段  
    assign s1_16bit_data[0] = dvr_fp32addtree8to1_s1[15:0];
    assign s1_16bit_data[1] = dvr_fp32addtree8to1_s1[31:16];
    assign s1_16bit_data[2] = dvr_fp32addtree8to1_s1[47:32];
    assign s1_16bit_data[3] = dvr_fp32addtree8to1_s1[63:48];
    assign s1_16bit_data[4] = dvr_fp32addtree8to1_s1[79:64];
    assign s1_16bit_data[5] = dvr_fp32addtree8to1_s1[95:80];
    assign s1_16bit_data[6] = dvr_fp32addtree8to1_s1[111:96];
    assign s1_16bit_data[7] = dvr_fp32addtree8to1_s1[127:112];
    
    // 组合8个FP32输入：FP32[y] = {S1[y], S0[y]}
    wire [`FP32_WIDTH-1:0] current_fp_input [0:NUM_INPUTS-1];
    assign current_fp_input[0] = {s1_16bit_data[0], s0_16bit_data[0]};
    assign current_fp_input[1] = {s1_16bit_data[1], s0_16bit_data[1]};
    assign current_fp_input[2] = {s1_16bit_data[2], s0_16bit_data[2]};
    assign current_fp_input[3] = {s1_16bit_data[3], s0_16bit_data[3]};
    assign current_fp_input[4] = {s1_16bit_data[4], s0_16bit_data[4]};
    assign current_fp_input[5] = {s1_16bit_data[5], s0_16bit_data[5]};
    assign current_fp_input[6] = {s1_16bit_data[6], s0_16bit_data[6]};
    assign current_fp_input[7] = {s1_16bit_data[7], s0_16bit_data[7]};

    // --- 1. Unpack ---
    wire [`FP32_EXP_WIDTH-1:0] temp_exponent [0:NUM_INPUTS-1];
    wire [`FP32_MANT_WIDTH-1:0] temp_mantissa [0:NUM_INPUTS-1];
    wire [NUM_INPUTS-1:0] signs;
    wire [NUM_INPUTS*`FP32_EXP_WIDTH-1:0] exponents_flat;
    wire [NUM_INPUTS*`FP32_MANT_WIDTH-1:0] mantissas_flat;
    wire [NUM_INPUTS-1:0] is_zeros;
    wire [NUM_INPUTS-1:0] is_infs;
    wire [NUM_INPUTS-1:0] is_nans;

    // --- 判断是否有任何有效正输入 ---
    wire any_valid_positive;
    wire no_positive_contribution_present;
    assign any_valid_positive = |(~is_nans & ~is_infs & ~signs);
    assign no_positive_contribution_present = ~any_valid_positive;

    generate
        for (i = 0; i < NUM_INPUTS; i = i + 1) begin : unpack_gen
            fp32_unpacker unpacker_inst (
                .fp_in(current_fp_input[i]),
                .sign(signs[i]),
                .exponent(temp_exponent[i]),
                .mantissa(temp_mantissa[i]),
                .is_zero(is_zeros[i]),
                .is_inf(is_infs[i]),
                .is_nan(is_nans[i])
            );

            assign exponents_flat[(i+1)*`FP32_EXP_WIDTH-1 : i*`FP32_EXP_WIDTH] = temp_exponent[i];
            assign mantissas_flat[(i+1)*`FP32_MANT_WIDTH-1 : i*`FP32_MANT_WIDTH] = temp_mantissa[i];
        end
    endgenerate

    // --- 2. 处理输入特殊值 ---
    wire any_nan_in;
    wire [NUM_INPUTS-1:0] is_pos_inf;
    wire [NUM_INPUTS-1:0] is_neg_inf;
    wire any_pos_inf;
    wire any_neg_inf;
    wire result_is_nan_condition;
    wire result_is_inf_condition;
    wire result_inf_sign;
    
    assign any_nan_in = |is_nans;
    assign is_pos_inf = is_infs & ~signs;
    assign is_neg_inf = is_infs & signs;
    assign any_pos_inf = |is_pos_inf;
    assign any_neg_inf = |is_neg_inf;
    assign result_is_nan_condition = any_nan_in || (any_pos_inf && any_neg_inf);
    assign result_is_inf_condition = !result_is_nan_condition && (any_pos_inf ^ any_neg_inf);
    assign result_inf_sign = any_neg_inf;

    // --- 3. Align ---
    wire [`FP32_EXP_WIDTH-1:0] max_exponent;
    wire [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] aligned_mantissas_flat;
    wire [NUM_INPUTS-1:0] effective_signs;

    fp32_aligner #(
        .NUM_INPUTS(NUM_INPUTS)
    ) aligner_inst (
        .signs(signs),
        .exponents_flat(exponents_flat),
        .mantissas_flat(mantissas_flat),
        .is_zeros(is_zeros),
        .is_infs(is_infs),
        .is_nans(is_nans),
        .max_exponent(max_exponent),
        .aligned_mantissas_flat(aligned_mantissas_flat),
        .effective_signs(effective_signs)
    );

    // --- 4. 准备华莱士树输入 ---
    wire [`FULL_SUM_WIDTH-1:0] pos_mants [0:NUM_INPUTS-1];
    wire [`FULL_SUM_WIDTH-1:0] neg_mants [0:NUM_INPUTS-1];
    
    generate
        for (j = 0; j < NUM_INPUTS; j = j + 1) begin : pos_neg_group
            wire [`ALIGNED_MANT_WIDTH-1:0] this_aligned_mantissa;
            wire [`FULL_SUM_WIDTH-1:0] mantissa_ext;
            assign this_aligned_mantissa = aligned_mantissas_flat[(j+1)*`ALIGNED_MANT_WIDTH-1 : j*`ALIGNED_MANT_WIDTH];
            assign mantissa_ext = {1'b0, this_aligned_mantissa};
            assign pos_mants[j] = (effective_signs[j] == 1'b0) ? mantissa_ext : {`FULL_SUM_WIDTH{1'b0}};
            assign neg_mants[j] = (effective_signs[j] == 1'b1) ? mantissa_ext : {`FULL_SUM_WIDTH{1'b0}};
        end
    endgenerate

    // --- 准备华莱士树输入数据 ---
    wire [NUM_INPUTS*`FULL_SUM_WIDTH-1:0] pos_mants_flat;
    wire [NUM_INPUTS*`FULL_SUM_WIDTH-1:0] neg_mants_flat;

    generate
        for (k = 0; k < NUM_INPUTS; k = k + 1) begin : flatten_mants
            assign pos_mants_flat[(k+1)*`FULL_SUM_WIDTH-1 : k*`FULL_SUM_WIDTH] = pos_mants[k];
            assign neg_mants_flat[(k+1)*`FULL_SUM_WIDTH-1 : k*`FULL_SUM_WIDTH] = neg_mants[k];
        end
    endgenerate

    // --- 使用华莱士树累加正负尾数 ---
    wire [`FULL_SUM_WIDTH+1:0] pos_sum;
    wire [`FULL_SUM_WIDTH+1:0] neg_sum;

    wallace_tree_8_inputs #(
        .NUM_INPUTS(NUM_INPUTS),
        .WIDTH(`FULL_SUM_WIDTH)
    ) wallace_pos_sum_inst (
        .data_in(pos_mants_flat),
        .final_result(pos_sum)
    );

    wallace_tree_8_inputs #(
        .NUM_INPUTS(NUM_INPUTS),
        .WIDTH(`FULL_SUM_WIDTH)
    ) wallace_neg_sum_inst (
        .data_in(neg_mants_flat),
        .final_result(neg_sum)
    );

    // --- 结果做差 ---
    wire signed [`FULL_SUM_WIDTH+1:0] wallace_final_result;
    assign wallace_final_result = $signed(pos_sum) - $signed(neg_sum);

    // --- 7. +0 -0 处理---
    wire result_sign;
    wire [`FULL_SUM_WIDTH+1:0] result_mant_raw;
    assign result_sign = (wallace_final_result == 0) ? no_positive_contribution_present : (wallace_final_result < 0);
    assign result_mant_raw = result_sign ? -wallace_final_result : wallace_final_result;

    // --- 8. 规格化与舍入 ---
    wire [`FP32_WIDTH-1:0] normalized_fp_out;
    wire norm_overflow;
    wire norm_underflow;
    wire norm_zero_out;

    fp32_normalizer_rounder #(
        .IN_WIDTH(`FULL_SUM_WIDTH + 2) 
    ) normalizer_rounder_inst (
        .mant_raw(result_mant_raw),   
        .exp_in(max_exponent),
        .sign_in(result_sign),
        .fp_out(normalized_fp_out),
        .overflow(norm_overflow),
        .underflow(norm_underflow),
        .zero_out(norm_zero_out)
    );

    // --- 9. 最终结果打包与选择 ---
    wire packer_sign;
    wire [`FP32_EXP_WIDTH-1:0] packer_exp;
    wire [`FP32_MANT_WIDTH-1:0] packer_mant;
    wire is_zero_out;
    wire final_special_sign;
    wire [`FP32_WIDTH-1:0] fp_sum_result;
    
    assign packer_sign = normalized_fp_out[`FP32_WIDTH-1];
    assign packer_exp = normalized_fp_out[`FP32_WIDTH-2 : `FP32_MANT_WIDTH];
    assign packer_mant = normalized_fp_out[`FP32_MANT_WIDTH-1 : 0];
    assign is_zero_out = !result_is_nan_condition && !result_is_inf_condition && !norm_overflow && norm_zero_out;
    assign final_special_sign = (result_is_inf_condition || norm_overflow) ? (result_is_inf_condition ? result_inf_sign : result_sign)
                              : is_zero_out ? result_sign
                              : packer_sign;

    fp32_packer packer_inst (
        .final_sign(final_special_sign),
        .final_exponent(packer_exp),  
        .final_mantissa(packer_mant),
        .result_is_zero(is_zero_out),
        .result_is_inf(result_is_inf_condition || norm_overflow),
        .result_is_nan(result_is_nan_condition),
        .fp_out(fp_sum_result)
    );
    
    // 输出组合逻辑
    always @(*) begin
        dr_fp32addtree8to1_d = 128'b0; // 默认输出为0
        if (cmd_valid) begin
            // 根据目的寄存器编码更新对应的32bit段
            case (dest_reg_idx)
                2'b00: dr_fp32addtree8to1_d[31:0]   = fp_sum_result;
                2'b01: dr_fp32addtree8to1_d[63:32]  = fp_sum_result;
                2'b10: dr_fp32addtree8to1_d[95:64]  = fp_sum_result;
                2'b11: dr_fp32addtree8to1_d[127:96] = fp_sum_result;
            endcase
        end
    end

endmodule
