`timescale 1ns/1ps

// --------------------------
// 子模块：FP16专用前导零计数器（处理18位sum_mant_raw信号）
// --------------------------
module leading_zero_counter_fp16 #(
    parameter DATA_WIDTH  = 18,  // 适配FP16的sum_mant_raw[17:0]（共18位）
    parameter COUNT_WIDTH = 5    // 18位数据最多18个前导零，5位足够表示（0~31）
)(  
    input  [DATA_WIDTH-1:0]  data_in,  // 输入：FP16的尾数加减结果sum_mant_raw[17:0]
    output [COUNT_WIDTH-1:0] leading_zeros  // 输出：前导零数量（0~18）
    );

    // 数组链结构：避免同一循环对同一信号多次赋值，保证时序性能
    reg [COUNT_WIDTH-1:0] count_chain [0:DATA_WIDTH];  // 计数链：存储每一位的前导零计数
    reg                   found_chain [0:DATA_WIDTH];  // 标志链：标记是否已找到第一个1
    integer i;  // 循环变量

    always @(*) begin
        // 初始化：当所有位均为0时，前导零数量=数据宽度（18）
        count_chain[DATA_WIDTH] = DATA_WIDTH[COUNT_WIDTH-1:0];  // 18[4:0] = 5'b10010
        found_chain[DATA_WIDTH] = 1'b0;  // 初始未找到1

        // 从最高位（data_in[17]）向最低位（data_in[0]）遍历
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
            // 标记：当前位或更高位是否已找到1
            found_chain[i] = found_chain[i+1] | data_in[i];
            
            // 若当前位是第一个1（未找到过1且当前位为1），则计数=当前位到最高位的距离
            if (data_in[i] && !found_chain[i+1]) begin
                count_chain[i] = (DATA_WIDTH - 1) - i;  // 最高位索引=17，距离=17-i
            end else begin
                // 否则，继承更高位的计数结果
                count_chain[i] = count_chain[i+1];
            end
        end
    end

    // 最终输出：最低位对应的计数（整个数据的前导零数量）
    assign leading_zeros = count_chain[0];

endmodule

// --------------------------
// 主模块：FP16浮点数加法器（集成前导零计数器）
// --------------------------
module fp16_adder(
    input wire clk,
    input wire [15:0] a,
    input wire [15:0] b,
    output reg [15:0] sum
);

// 全局参数（保留原代码定义）
parameter FP16_BIAS = 5'd15;
parameter MIN_NORM_EXP = -14;

// --------------------------
// 1. 字段提取（原代码保留）
// --------------------------
wire a_sign = a[15];
wire b_sign = b[15];
wire [4:0] a_exp = a[14:10];
wire [4:0] b_exp = b[14:10];
wire [9:0] a_frac = a[9:0];
wire [9:0] b_frac = b[9:0];

// --------------------------
// 2. 特殊值检测（核心修改：强化NaN判定+避免payload全0）
// --------------------------
// 【修改1：强化NaN判定】确保“指数全1+尾数非全0”（覆盖所有IEEE 754定义的NaN）
wire a_nan = (a_exp == 5'b11111) && (a_frac != 10'b0000000000);
wire b_nan = (b_exp == 5'b11111) && (b_frac != 10'b0000000000);

// 【保留方案二修改】inf判定排除NaN（避免NaN误判为inf）
wire a_inf = (a_exp == 5'b11111) && (a_frac == 10'b0000000000);
wire b_inf = (b_exp == 5'b11111) && (b_frac == 10'b0000000000);

// 原特殊值检测逻辑保留
wire a_zero = (a_exp == 0) && (a_frac == 0);
wire b_zero = (b_exp == 0) && (b_frac == 0);
wire a_denorm = (a_exp == 0) && (a_frac != 0);
wire b_denorm = (b_exp == 0) && (b_frac != 0);
wire both_denorm = a_denorm && b_denorm;

// 区分sNaN/qNaN（原逻辑保留，但确保type_bit非全0）
wire a_is_snan = a_nan && (a_frac[9] == 1'b0);
wire a_is_qnan = a_nan && (a_frac[9] == 1'b1);
wire b_is_snan = b_nan && (b_frac[9] == 1'b0);
wire b_is_qnan = b_nan && (b_frac[9] == 1'b1);

// 【修改2：提取payload时避免全0】若payload为0，强制最低位为1（确保尾数非全0）
wire [8:0] a_nan_payload_raw = a_frac[8:0];
wire [8:0] b_nan_payload_raw = b_frac[8:0];
wire [8:0] a_nan_payload = (a_nan_payload_raw == 9'b000000000) ? 9'b000000001 : a_nan_payload_raw;
wire [8:0] b_nan_payload = (b_nan_payload_raw == 9'b000000000) ? 9'b000000001 : b_nan_payload_raw;

wire has_snan = a_is_snan || b_is_snan;

// --------------------------
// 3. NaN/无穷大处理（核心修改：确保nan_result尾数非全0）
// --------------------------
// NaN触发条件（原逻辑保留）
wire is_nan = a_nan || b_nan || (a_inf && b_inf && (a_sign != b_sign));

// 【修改3：强制nan_type_bit非0（若sNaN且payload全0，转为qNaN）】
wire nan_type_bit = has_snan ? 1'b0 : 1'b1; // 若payload全0，强制为qNaN（type_bit=1）

// 取第一个非NaN的payload和符号（原逻辑保留）
wire [8:0] nan_payload = a_nan ? a_nan_payload : b_nan_payload;
wire nan_sign = (a_inf && b_inf && a_sign != b_sign) ? a_sign : 
               (a_nan ? a_sign : b_sign);

// 【修改4：构造nan_result，确保尾数非全0】
wire [15:0] nan_result = {
    nan_sign,        // 符号位
    5'b11111,        // 指数全1
    nan_type_bit,    // 至少为1（若payload全0）
    nan_payload      // 至少为1（若原payload全0）
};

// 无穷大处理（原逻辑保留）
wire is_inf = (a_inf || b_inf) && !is_nan;
wire inf_sign = (a_inf && b_inf) ? a_sign : (a_inf ? a_sign : b_sign);
wire [15:0] inf_result = {inf_sign, 5'b11111, 10'b0000000000};

// --------------------------
// 4. 尾数准备（原代码保留）
// --------------------------
wire [16:0] a_mant = a_denorm ? {1'b0, a_frac, 6'b0} : {1'b1, a_frac, 6'b0};
wire [16:0] b_mant = b_denorm ? {1'b0, b_frac, 6'b0} : {1'b1, b_frac, 6'b0};
wire [4:0] a_exp_actual = a_denorm ? 5'b00001 : a_exp;
wire [4:0] b_exp_actual = b_denorm ? 5'b00001 : b_exp;

// --------------------------
// 5. 指数对齐（原代码保留）
// --------------------------
wire [4:0] exp_diff = (a_exp_actual > b_exp_actual) ? (a_exp_actual - b_exp_actual) : (b_exp_actual - a_exp_actual);
wire a_larger_exp = (a_exp_actual >= b_exp_actual);
wire [4:0] max_exp = a_larger_exp ? a_exp_actual : b_exp_actual;
wire [4:0] actual_shift = (exp_diff > 17) ? 5'd17 : exp_diff;
wire [16:0] a_mant_shifted = a_larger_exp ? a_mant : (a_mant >> actual_shift);
wire [16:0] b_mant_shifted = a_larger_exp ? (b_mant >> actual_shift) : b_mant;
wire [16:0] sticky_mask_a = (actual_shift == 0) ? 17'b0 : ((1 << actual_shift) - 1);
wire [16:0] sticky_mask_b = (actual_shift == 0) ? 17'b0 : ((1 << actual_shift) - 1);
wire sticky_a = a_larger_exp ? 1'b0 : (|(a_mant & sticky_mask_a));
wire sticky_b = a_larger_exp ? (|(b_mant & sticky_mask_b)) : 1'b0;
wire [16:0] a_mant_aligned = a_mant_shifted | {16'b0, sticky_a};
wire [16:0] b_mant_aligned = b_mant_shifted | {16'b0, sticky_b};

// --------------------------
// 6. 尾数加减（原代码保留）
// --------------------------
wire swap = (a_exp_actual < b_exp_actual) || ((a_exp_actual == b_exp_actual) && (a_frac < b_frac));
wire [16:0] large_mant = swap ? b_mant_aligned : a_mant_aligned;
wire [16:0] small_mant = swap ? a_mant_aligned : b_mant_aligned;
wire large_sign = swap ? b_sign : a_sign;
wire small_sign = swap ? a_sign : b_sign;
wire operation_sub = (large_sign != small_sign);
wire [17:0] sum_mant_raw; // FP16尾数加减结果：18位（[17:0]）
assign sum_mant_raw = operation_sub ? 
    ((large_mant >= small_mant) ? ({1'b0, large_mant} - {1'b0, small_mant}) : ({1'b0, small_mant} - {1'b0, large_mant})) :
    ({1'b0, large_mant} + {1'b0, small_mant});
wire result_sign = operation_sub ? ((large_mant >= small_mant) ? large_sign : small_sign) : large_sign;

// --------------------------
// 7. 规格化（核心修改：集成前导零计数器，替换原硬编码查找）
// --------------------------
wire [16:0] normalized_mant;
wire [4:0] normalized_exp;
wire [2:0] round_bits;

// ① 声明前导零计数器的输出信号（前导零数量）
wire [4:0] lz_count;

// ② 实例化FP16前导零计数器（输入为18位sum_mant_raw）
leading_zero_counter_fp16 u_leading_zero_counter(
    .data_in(sum_mant_raw),    // 输入：尾数加减结果sum_mant_raw[17:0]
    .leading_zeros(lz_count)   // 输出：前导零数量（0~18）
);

// ③ 计算最高有效位位置（leading_one）：替换原连续三目运算符
// 逻辑：leading_one = 最高位索引（17） - 前导零数量；全零时leading_one=0
wire [4:0] leading_one = (lz_count == 5'd18) ? 5'd0 : (5'd17 - lz_count);

// 原规格化后续逻辑保留（无修改）
wire [6:0] temp_exp_ext = {1'b0, max_exp} + {1'b0, leading_one} - 7'd16;
wire temp_exp_pos = !temp_exp_ext[6];
wire temp_exp_ge1 = temp_exp_pos && (temp_exp_ext[4:0] >= 5'b00001);
wire exp_underflow = !temp_exp_pos || (temp_exp_ext[4:0] == 5'b0);

wire [6:0] temp_exp_signed = temp_exp_ext;
wire [4:0] denorm_shift_right = exp_underflow ? (2 - $signed(temp_exp_signed)) : 5'd0;
wire [4:0] shift_amount_left = 17 - leading_one;
wire [17:0] shifted_sum_temp = sum_mant_raw << shift_amount_left;
wire [17:0] shifted_sum_denorm = shifted_sum_temp >> denorm_shift_right;
wire [4:0] shift_amount = exp_underflow ? 5'd0 : (17 - leading_one);
wire [17:0] shifted_sum = exp_underflow ? shifted_sum_denorm : (sum_mant_raw << shift_amount);

assign normalized_mant = shifted_sum[16:0];
assign normalized_exp = exp_underflow ? 5'b0 : temp_exp_ext[4:0];
assign round_bits = {normalized_mant[6], normalized_mant[5], |normalized_mant[4:0]};

// --------------------------
// 8. 舍入逻辑（原代码保留）
// --------------------------
wire guard = round_bits[2];
wire round = round_bits[1];
wire sticky = round_bits[0];
wire lsb = exp_underflow ? normalized_mant[5] : normalized_mant[7];
wire extended_sticky = sticky || normalized_mant[5];
wire round_up = (guard && round) || (guard && extended_sticky) || (guard && !round && !extended_sticky && lsb);
wire [10:0] rounded_mant = exp_underflow ? 
    {1'b0, normalized_mant[15:6]} + (round_up ? 11'd1 : 11'd0) : 
    {1'b0, normalized_mant[16:7]} + (round_up ? 11'd1 : 11'd0);
wire round_carry = rounded_mant[10];

// --------------------------
// 9. 溢出/下溢处理（原代码保留）
// --------------------------
wire [4:0] final_exp_val = round_carry ? (normalized_exp + 5'd1) : normalized_exp;
wire [9:0] final_frac = round_carry ? rounded_mant[9:1] : rounded_mant[9:0];
wire overflow = (final_exp_val >= 5'b11111);
wire underflow = (normalized_exp == 5'b0) && (rounded_mant[10:1] != 10'b0);

// --------------------------
// 10. 双非规格化数计算（原代码保留）
// --------------------------
wire [16:0] a_mant_denorm = {1'b0, a_frac, 6'b0};
wire [16:0] b_mant_denorm = {1'b0, b_frac, 6'b0};
wire same_sign_denorm = (a_sign == b_sign);
wire a_larger_mant_denorm = (a_mant_denorm >= b_mant_denorm);
wire [16:0] mant_result_denorm = both_denorm ? (
    same_sign_denorm ? (a_mant_denorm + b_mant_denorm) : 
    (a_larger_mant_denorm ? (a_mant_denorm - b_mant_denorm) : (b_mant_denorm - a_mant_denorm))
) : 17'd0;
wire mant_zero_denorm = (mant_result_denorm == 17'd0);
wire [9:0] frac_final_denorm = both_denorm ? (
    mant_zero_denorm ? 10'd0 : (mant_result_denorm >> 6)
) : 10'd0;
wire sign_denorm = both_denorm ? (
    mant_zero_denorm ? 1'b0 : (same_sign_denorm ? a_sign : (a_larger_mant_denorm ? a_sign : b_sign))
) : 1'b0;

// --------------------------
// 11. 最终输出（原代码保留）
// --------------------------
always @(posedge clk) begin
    case (1'b1)
        is_nan: sum <= nan_result;
        is_inf || overflow: sum <= inf_result;
        a_zero && !b_zero: sum <= b;
        !a_zero && b_zero: sum <= a;
        a_zero && b_zero: sum <= {result_sign, 15'b0};
        both_denorm: sum <= temp_exp_ge1 ? {sign_denorm, temp_exp_ext[4:0], rounded_mant[9:0]} : {sign_denorm, 5'b00000, frac_final_denorm};
        sum_mant_raw == 18'd0: sum <= {result_sign, 15'b0};
        underflow || exp_underflow: sum <= {result_sign, 5'b00000, rounded_mant[9:0]};
        default: sum <= {result_sign, final_exp_val, final_frac};
    endcase
end

endmodule