`include "../define/fp32_defines.vh"

module fp32_aligner #(
    parameter NUM_INPUTS = 8
) (
    input wire [NUM_INPUTS-1:0] signs,
    input wire [NUM_INPUTS*`FP32_EXP_WIDTH-1:0] exponents_flat,  // 8-bit x8
    input wire [NUM_INPUTS*`FP32_MANT_WIDTH-1:0] mantissas_flat, // 23-bit x8
    input wire [NUM_INPUTS-1:0] is_zeros,
    input wire [NUM_INPUTS-1:0] is_infs,
    input wire [NUM_INPUTS-1:0] is_nans,

    output wire [`FP32_EXP_WIDTH-1:0] max_exponent,
    output wire [NUM_INPUTS*`ALIGNED_MANT_WIDTH-1:0] aligned_mantissas_flat, // 27-bit x8
    output wire [NUM_INPUTS-1:0] effective_signs
);


genvar i;
// 阶段1：======================找到最大指数========================
wire [NUM_INPUTS-1:0] valid_for_max_exp;
wire [`FP32_EXP_WIDTH-1:0] max_exp_stages [0:NUM_INPUTS];

generate
    for (i = 0; i < NUM_INPUTS; i = i + 1) begin : gen_max_exp
        assign valid_for_max_exp[i] = !is_zeros[i] && !is_infs[i] && !is_nans[i];
    end
endgenerate

// 计算最大指数 
assign max_exp_stages[0] = 0;
generate
    for (i = 0; i < NUM_INPUTS; i = i + 1) begin : gen_max_exp_stages
        wire [`FP32_EXP_WIDTH-1:0] current_exp_for_max = exponents_flat[(i+1)*`FP32_EXP_WIDTH-1 : i*`FP32_EXP_WIDTH];
        assign max_exp_stages[i+1] = valid_for_max_exp[i] && (current_exp_for_max > max_exp_stages[i]) ? 
                                    current_exp_for_max : max_exp_stages[i];
    end
endgenerate

assign max_exponent = max_exp_stages[NUM_INPUTS];


// 阶段2：===================30位尾数对齐核心逻辑====================
generate
    for (i = 0; i < NUM_INPUTS; i = i + 1) begin : align_gen
        // --- 输入信号分解 ---
        wire [`FP32_EXP_WIDTH-1:0] current_exp = exponents_flat[i*`FP32_EXP_WIDTH +: `FP32_EXP_WIDTH];
        wire [`FP32_MANT_WIDTH-1:0] orig_mant = mantissas_flat[i*`FP32_MANT_WIDTH +: `FP32_MANT_WIDTH];
        //区分normal和denormal的指数
        wire [`FP32_EXP_WIDTH-1:0] effective_biased_exp;
        assign effective_biased_exp = (current_exp == 0 && !is_zeros[i] && max_exponent != 0) ? 1'b1 : current_exp;
        
        // --- 指数差计算 ---
        wire [`FP32_EXP_WIDTH:0] exp_diff = (effective_biased_exp < max_exponent) ? 
                                     (max_exponent - effective_biased_exp) : 
                                     {(`FP32_EXP_WIDTH+1){1'b0}}; // 只计算需要右移的情况
        
        // --- 有效移位量控制 ---
        localparam SHIFT_LIMIT = `ALIGNED_MANT_WIDTH; // 27位最大移位
        wire [$clog2(`ALIGNED_MANT_WIDTH+1)-1:0] shift_amount = 
            (exp_diff > SHIFT_LIMIT) ? SHIFT_LIMIT : exp_diff;
        
        // --- 尾数扩展--- 
        wire has_implied_bit = !is_zeros[i] && (current_exp != 0); // 规格化数隐含位1，非规格化数隐含位0
        wire [`FP32_MANT_WIDTH:0] mant_with_implied = {has_implied_bit, orig_mant}; // 24位
        wire [`ALIGNED_MANT_WIDTH-1:0] extended_mant = {mant_with_implied, {`GUARD_BITS{1'b0}}}; // 24+3=27位
        
        // --- 移位与粘滞位计算 ---
        wire [`ALIGNED_MANT_WIDTH-1:0] shifted_mant;
        wire sticky_bit;
        wire complete_shift = (shift_amount >= `ALIGNED_MANT_WIDTH);
        
        // 右移操作 
        assign shifted_mant = complete_shift ? 
                            {`ALIGNED_MANT_WIDTH{1'b0}} : 
                            (extended_mant >> shift_amount);
                            
        // 粘滞位计算 
        assign sticky_bit = complete_shift ? 
                          |extended_mant : 
                          |(extended_mant & ((1 << shift_amount) - 1));
        
        // --- 对齐后的尾数组合 ---
        wire [`ALIGNED_MANT_WIDTH-1:0] aligned_mant;
        assign aligned_mant = (is_zeros[i] | is_infs[i] | is_nans[i]) ? 
                             {`ALIGNED_MANT_WIDTH{1'b0}} : 
                             {shifted_mant[`ALIGNED_MANT_WIDTH-1:1],  // 保留高26位
                              shifted_mant[0] | sticky_bit};          // 最低位合并粘滞位
        
        // --- 输出连接 ---
        assign aligned_mantissas_flat[i*`ALIGNED_MANT_WIDTH +: `ALIGNED_MANT_WIDTH] = aligned_mant;
        
    end
endgenerate

assign effective_signs = signs;

endmodule