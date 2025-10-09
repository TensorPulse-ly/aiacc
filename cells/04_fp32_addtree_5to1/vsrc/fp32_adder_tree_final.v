//-----------------------------------------------------------------------------
// Filename: fp32_adder_tree_final.v
// Author: sunny
// Date: 2025-8-20
// Version: 2.0
// Description: Implement 8 parallel channel single precision floating point 
//              5 input adder tree structure with accumulation function
//-----------------------------------------------------------------------------
`include "../define/fp32_defines.vh"

module fp32_adder_tree_final (
    input  wire        clk,
    input  wire        rst_n,              
    input  wire        cru_fp32addtree5to1,  // Instruction valid

    // 8x128-bit Source Registers
    input  wire [127:0] dvr_fp32addtree5to1_s0,
    input  wire [127:0] dvr_fp32addtree5to1_s1,
    input  wire [127:0] dvr_fp32addtree5to1_s2,
    input  wire [127:0] dvr_fp32addtree5to1_s3,
    input  wire [127:0] dvr_fp32addtree5to1_s4,
    input  wire [127:0] dvr_fp32addtree5to1_s5,
    input  wire [127:0] dvr_fp32addtree5to1_s6,
    input  wire [127:0] dvr_fp32addtree5to1_s7,

    // 2x128-bit Destination Registers
    output reg  [127:0] dr_fp32addtree5to1_d0,
    output reg  [127:0] dr_fp32addtree5to1_d1
);

    //----------------------------------------------------------------------
    // Parameter and Genvar Declarations
    //----------------------------------------------------------------------
    localparam NUM      = 8;
    localparam NUM_INPUTS = 5;
    genvar i, j, k;

    //----------------------------------------------------------------------
    // 1) Unpack Inputs and Core Computation Logic (8 Parallel Channels)
    //----------------------------------------------------------------------
    wire [`FP32_WIDTH-1:0] add_result [0:NUM-1];

    generate
        for (i = 0; i < NUM; i = i + 1) begin : gen_tree
            
            //--- Stage 0a: Unpack 4 new inputs from 8x128-bit registers ---
            wire [`FP32_WIDTH-1:0] fp_new [0:3];
            for (k = 0; k < 4; k = k + 1) begin : gen_unpack_bits
                integer y_index = 4*i + k;
                integer bit_pos = y_index * 4;
                assign fp_new[k] = {
                    dvr_fp32addtree5to1_s7[bit_pos +: 4], 
                    dvr_fp32addtree5to1_s6[bit_pos +: 4],
                    dvr_fp32addtree5to1_s5[bit_pos +: 4], 
                    dvr_fp32addtree5to1_s4[bit_pos +: 4],
                    dvr_fp32addtree5to1_s3[bit_pos +: 4], 
                    dvr_fp32addtree5to1_s2[bit_pos +: 4],
                    dvr_fp32addtree5to1_s1[bit_pos +: 4], 
                    dvr_fp32addtree5to1_s0[bit_pos +: 4]
                };
            end

            //--- Stage 0b: Get 5th input ---
            wire [`FP32_WIDTH-1:0] old_fp32;
            assign old_fp32 = {dr_fp32addtree5to1_d1[i*16 +: 16],
                               dr_fp32addtree5to1_d0[i*16 +: 16]};

            //--- Stage 0c: Combine 5 inputs ---
            wire [`FP32_WIDTH-1:0] full_fp_in [0:NUM_INPUTS-1];
            assign full_fp_in[0] = fp_new[0];
            assign full_fp_in[1] = fp_new[1];
            assign full_fp_in[2] = fp_new[2];
            assign full_fp_in[3] = fp_new[3];
            assign full_fp_in[4] = old_fp32;

            //--- Stage 1: Unpack ---
            wire [`FP32_EXP_WIDTH-1:0] temp_exponent [0:NUM_INPUTS-1];
            wire [`FP32_MANT_WIDTH-1:0] temp_mantissa [0:NUM_INPUTS-1];
            wire [NUM_INPUTS-1:0] signs, is_zeros, is_infs, is_nans;
            wire [NUM_INPUTS*`FP32_EXP_WIDTH-1:0] exponents_flat;
            wire [NUM_INPUTS*`FP32_MANT_WIDTH-1:0] mantissas_flat;

            for (j = 0; j < NUM_INPUTS; j = j + 1) begin : unpack_gen
                fp32_unpacker unpacker_inst (
                    .fp_in(full_fp_in[j]), 
                    .sign(signs[j]), 
                    .exponent(temp_exponent[j]),
                    .mantissa(temp_mantissa[j]), 
                    .is_zero(is_zeros[j]),
                    .is_inf(is_infs[j]), 
                    .is_nan(is_nans[j])
                );
                assign exponents_flat[j*`FP32_EXP_WIDTH +: `FP32_EXP_WIDTH] = temp_exponent[j];
                assign mantissas_flat[j*`FP32_MANT_WIDTH +: `FP32_MANT_WIDTH] = temp_mantissa[j];
            end

            //--- Stage 2: Handle Special Cases ---
            wire any_nan_in = |is_nans;
            wire [NUM_INPUTS-1:0] is_pos_inf = is_infs & ~signs;
            wire [NUM_INPUTS-1:0] is_neg_inf = is_infs & signs;
            wire any_pos_inf = |is_pos_inf;
            wire any_neg_inf = |is_neg_inf;
            wire result_is_nan_condition = any_nan_in || (any_pos_inf && any_neg_inf);
            wire result_is_inf_condition = !result_is_nan_condition && (any_pos_inf || any_neg_inf);
            wire result_inf_sign = any_neg_inf;
            wire any_valid_positive = |(~is_nans & ~is_infs & ~signs);
            wire no_positive_contribution_present = ~any_valid_positive;

            //--- Stage 3: Align Mantissas ---
            wire [`FP32_EXP_WIDTH-1:0] max_exponent;
            wire [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] aligned_mantissas_flat;
            wire [NUM_INPUTS-1:0] effective_signs;
            fp32_aligner #(.NUM_INPUTS(NUM_INPUTS)) aligner_inst (
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

            //--- Stage 4: Separate Mantissas ---
            wire [NUM_INPUTS*`FULL_SUM_WIDTH-1:0] pos_mants_flat;
            wire [NUM_INPUTS*`FULL_SUM_WIDTH-1:0] neg_mants_flat;
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin : pos_neg_group
                wire [`ALIGNED_MANT_WIDTH-1:0] this_aligned_mantissa = aligned_mantissas_flat[j*`ALIGNED_MANT_WIDTH +: `ALIGNED_MANT_WIDTH];
                wire [`FULL_SUM_WIDTH-1:0] mantissa_ext = {1'b0, this_aligned_mantissa};
                assign pos_mants_flat[j*`FULL_SUM_WIDTH +: `FULL_SUM_WIDTH] = (effective_signs[j] == 1'b0) ? mantissa_ext : {`FULL_SUM_WIDTH{1'b0}};   
                assign neg_mants_flat[j*`FULL_SUM_WIDTH +: `FULL_SUM_WIDTH] = (effective_signs[j] == 1'b1) ? mantissa_ext : {`FULL_SUM_WIDTH{1'b0}};
            end

            //--- Stage 5: Sum Mantissas ---
            wire [`FULL_SUM_WIDTH+1:0] pos_sum, neg_sum;
            wallace_tree_5_inputs #(.NUM_INPUTS(NUM_INPUTS), .WIDTH(`FULL_SUM_WIDTH)) wallace_pos (
                .data_in(pos_mants_flat), 
                .final_result(pos_sum)
            );
            wallace_tree_5_inputs #(.NUM_INPUTS(NUM_INPUTS), .WIDTH(`FULL_SUM_WIDTH)) wallace_neg (
                .data_in(neg_mants_flat), 
                .final_result(neg_sum)
            );

            //--- Stage 6: Final Subtraction ---
            wire signed [`FULL_SUM_WIDTH+1:0] final_sum_signed = $signed(pos_sum) - $signed(neg_sum);
            wire result_sign = (final_sum_signed == 0) ? no_positive_contribution_present : (final_sum_signed < 0);
            wire [`FULL_SUM_WIDTH+1:0] result_mant_raw = result_sign ? -final_sum_signed : final_sum_signed;

            //--- Stage 7: Normalize & Round ---
            wire [`FP32_WIDTH-1:0] normalized_fp_out;
            wire norm_overflow, norm_underflow, norm_zero_out;
            fp32_normalizer_rounder #(.IN_WIDTH(`FULL_SUM_WIDTH + 2)) normalizer_inst (
                .mant_raw(result_mant_raw), 
                .exp_in(max_exponent), 
                .sign_in(result_sign),
                .fp_out(normalized_fp_out), 
                .overflow(norm_overflow),
                .underflow(norm_underflow), 
                .zero_out(norm_zero_out)
            );

            //--- Stage 8: Pack Final Result ---
            wire packer_sign = normalized_fp_out[`FP32_WIDTH-1];
            wire [`FP32_EXP_WIDTH-1:0] packer_exp = normalized_fp_out[`FP32_WIDTH-2 : `FP32_MANT_WIDTH];
            wire [`FP32_MANT_WIDTH-1:0] packer_mant = normalized_fp_out[`FP32_MANT_WIDTH-1 : 0];
            wire is_zero_out = !result_is_nan_condition && !result_is_inf_condition && !norm_overflow && norm_zero_out;
            wire final_sign_for_packer = (result_is_inf_condition || norm_overflow) ?
                                         (result_is_inf_condition ? result_inf_sign : result_sign) :
                                         (is_zero_out ? result_sign : packer_sign);
            fp32_packer packer_inst (
                .final_sign(final_sign_for_packer), 
                .final_exponent(packer_exp), 
                .final_mantissa(packer_mant),
                .result_is_zero(is_zero_out), 
                .result_is_inf(result_is_inf_condition || norm_overflow),
                .result_is_nan(result_is_nan_condition), 
                .fp_out(add_result[i])
            );
        end
    endgenerate

    //----------------------------------------------------------------------
    // 3) Output Registers
    //----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dr_fp32addtree5to1_d0 <= 128'd0;
            dr_fp32addtree5to1_d1 <= 128'd0;
        end else if (cru_fp32addtree5to1) begin
            integer out_idx;
            for (out_idx = 0; out_idx < 8; out_idx = out_idx + 1) begin
                dr_fp32addtree5to1_d0[out_idx*16 +: 16] <= add_result[out_idx][15:0];
                dr_fp32addtree5to1_d1[out_idx*16 +: 16] <= add_result[out_idx][31:16];
            end
        end
    end

endmodule