`timescale 1ns/1ps

// --------------------------
// 子模块：FP32专用前导零计数器（处理31位sum_mant_raw信号）
// --------------------------
module leading_zero_counter_fp32 #(
    parameter DATA_WIDTH  = 31,  // 适配FP32的sum_mant_raw[30:0]（共31位）
    parameter COUNT_WIDTH = 5    // 31位数据最多31个前导零，5位足够表示（0~31）
)(  
    input  [DATA_WIDTH-1:0]  data_in,  // 输入：FP32的尾数加减结果sum_mant_raw[30:0]
    output [COUNT_WIDTH-1:0] leading_zeros  // 输出：前导零数量（0~31）
    );

    // 数组链结构：避免同一循环对同一信号多次赋值，保证时序性能
    reg [COUNT_WIDTH-1:0] count_chain [0:DATA_WIDTH];  // 计数链：存储每一位的前导零计数
    reg                   found_chain [0:DATA_WIDTH];  // 标志链：标记是否已找到第一个1
    integer i;  // 循环变量

    always @(*) begin
        // 初始化：当所有位均为0时，前导零数量=数据宽度（31）
        count_chain[DATA_WIDTH] = DATA_WIDTH[COUNT_WIDTH-1:0];  // 31[4:0] = 5'b11111
        found_chain[DATA_WIDTH] = 1'b0;  // 初始未找到1

        // 从最高位（data_in[30]）向最低位（data_in[0]）遍历
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
            // 标记：当前位或更高位是否已找到1
            found_chain[i] = found_chain[i+1] | data_in[i];
            
            // 若当前位是第一个1（未找到过1且当前位为1），则计数=当前位到最高位的距离
            if (data_in[i] && !found_chain[i+1]) begin
                count_chain[i] = (DATA_WIDTH - 1) - i;  // 最高位索引=30，距离=30-i
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
// 主模块：FP32浮点数加法器（集成前导零计数器）
// --------------------------
module fp32_adder(
    input wire clk,
    input wire [31:0] a,    // 32位浮点数输入A
    input wire [31:0] b,    // 32位浮点数输入B
    output reg [31:0] sum   // 32位浮点数加法结果
);

// --------------------------
// 1. 全局参数（对齐FP16格式：明确标注偏置与最小规格化指数）
// --------------------------
parameter FP32_BIAS = 8'd127;       // FP32指数偏置（2^(8-1)-1，对应FP16的5'd15）
parameter MIN_NORM_EXP = -126;      // 最小规格化指数（1 - 127，对应FP16的-14）

// --------------------------
// 2. 字段提取（对齐FP16结构：信号命名、位宽适配32位）
// --------------------------
wire a_sign = a[31];                 // 符号位（bit31，对应FP16的bit15）
wire b_sign = b[31];
wire [7:0] a_exp = a[30:23];         // 指数位（8bit，bit30-23，对应FP16的bit14-10）
wire [7:0] b_exp = b[30:23];
wire [22:0] a_frac = a[22:0];        // 尾数位（23bit，bit22-0，对应FP16的bit9-0）
wire [22:0] b_frac = b[22:0];

// --------------------------
// 3. 特殊值检测（对齐FP16核心修改：强化NaN判定+避免payload全0）
// --------------------------
// 【修改1：强化NaN判定】符合IEEE 754：指数全1 + 尾数非全0（覆盖所有NaN场景）
wire a_nan = (a_exp == 8'b11111111) && (a_frac != 23'b00000000000000000000000);
wire b_nan = (b_exp == 8'b11111111) && (b_frac != 23'b00000000000000000000000);

// 【保留FP16方案：Inf判定排除NaN】避免将NaN误判为Inf
wire a_inf = (a_exp == 8'b11111111) && (a_frac == 23'b00000000000000000000000);
wire b_inf = (b_exp == 8'b11111111) && (b_frac == 23'b00000000000000000000000);

// 原特殊值逻辑保留（对齐FP16结构，仅位宽适配）
wire a_zero = (a_exp == 8'b0) && (a_frac == 23'b0);                // 零值：指数全0+尾数全0
wire b_zero = (b_exp == 8'b0) && (b_frac == 23'b0);
wire a_denorm = (a_exp == 8'b0) && (a_frac != 23'b0);              // 非规格化数：指数全0+尾数非0
wire b_denorm = (b_exp == 8'b0) && (b_frac != 23'b0);
wire both_denorm = a_denorm && b_denorm;                            // 双非规格化数场景

// 【对齐FP16：区分sNaN（信号NaN）/qNaN（静默NaN）】
wire a_is_snan = a_nan && (a_frac[22] == 1'b0);  // sNaN：尾数最高位（bit22）=0（无隐含1）
wire a_is_qnan = a_nan && (a_frac[22] == 1'b1);  // qNaN：尾数最高位（bit22）=1（含隐含1）
wire b_is_snan = b_nan && (b_frac[22] == 1'b0);
wire b_is_qnan = b_nan && (b_frac[22] == 1'b1);

// 【修改2：提取payload避免全0】若payload全0，强制最低位为1（确保NaN尾数非全0，对齐FP16）
wire [21:0] a_nan_payload_raw = a_frac[21:0];  // payload取尾数低22位（排除bit22类型位）
wire [21:0] b_nan_payload_raw = b_frac[21:0];
wire [21:0] a_nan_payload = (a_nan_payload_raw == 22'b0) ? 22'b1 : a_nan_payload_raw;
wire [21:0] b_nan_payload = (b_nan_payload_raw == 22'b0) ? 22'b1 : b_nan_payload_raw;

// 【对齐FP16：标记是否存在sNaN】用于后续NaN类型判定
wire has_snan = a_is_snan || b_is_snan;

// --------------------------
// 4. NaN/无穷大处理（对齐FP16核心修改：确保NaN合规）
// --------------------------
// 优化后：嵌套式条件（所有子条件均可达）
wire has_inf = a_inf || b_inf;          // 先判断“是否有inf”（可触发0/1）
wire is_double_inf = a_inf && b_inf;    // 判断“是否双inf”（可触发0/1）
wire is_opposite_inf = is_double_inf && (a_sign != b_sign); // 判断“双inf是否异号”（可触发0/1）
wire is_nan = a_nan || b_nan || is_opposite_inf; // 最终NaN判定

// 【修改3：强制NaN类型位非0】若sNaN且payload全0，转为qNaN（对齐FP16规则）
wire nan_type_bit = has_snan ? 1'b0 : 1'b1;  // sNaN=0，qNaN=1（payload全0时强制qNaN）

// 【对齐FP16：取第一个非NaN的payload和符号】确保有效信息不丢失
wire [21:0] nan_payload = a_nan ? a_nan_payload : b_nan_payload;
wire nan_sign = (a_inf && b_inf && a_sign != b_sign) ? a_sign : 
               (a_nan ? a_sign : b_sign);

// 【修改4：构造合规NaN结果】确保尾数非全0（对齐FP16结构，32位位宽适配）
wire [31:0] nan_result = {
    nan_sign,                // 符号位
    8'b11111111,             // 指数全1（特殊值标识）
    nan_type_bit, nan_payload// 尾数：1位类型位 + 22位payload（确保非全0）
};

// 【对齐FP16：无穷大处理】与NaN互斥，尾数全0
wire is_inf = (a_inf || b_inf) && !is_nan;
wire inf_sign = (a_inf && b_inf) ? a_sign : (a_inf ? a_sign : b_sign);
wire [31:0] inf_result = {inf_sign, 8'b11111111, 23'b0};

// --------------------------
// 5. 尾数准备（对齐FP16逻辑：扩展6位用于舍入，适配32位）
// --------------------------
// 非规格化数：隐含位为0；规格化数：隐含位为1，尾数扩展6位（与FP16的6位扩展一致）
wire [29:0] a_mant = a_denorm ? {1'b0, a_frac, 6'b0} : {1'b1, a_frac, 6'b0};
wire [29:0] b_mant = b_denorm ? {1'b0, b_frac, 6'b0} : {1'b1, b_frac, 6'b0};
// 非规格化数视为指数1（对应实际指数：1 - 127 = -126，对齐FP16的“指数0→1”规则）
wire [7:0] a_exp_actual = a_denorm ? 8'd1 : a_exp;
wire [7:0] b_exp_actual = b_denorm ? 8'd1 : b_exp;

// --------------------------
// 6. 指数对齐（对齐FP16逻辑：小指数尾数右移，计算sticky位）
// --------------------------
// 计算指数差，确定需对齐的移位量
wire [7:0] exp_diff = (a_exp_actual > b_exp_actual) ? (a_exp_actual - b_exp_actual) : (b_exp_actual - a_exp_actual);
wire a_larger_exp = (a_exp_actual >= b_exp_actual);
wire [7:0] max_exp = a_larger_exp ? a_exp_actual : b_exp_actual;  // 对齐到较大指数
wire [4:0] actual_shift = (exp_diff > 30) ? 8'd30 : exp_diff;     // 最大移位30（30位尾数，对齐FP16的17位限制）

// 小指数尾数右移（对齐到最大指数）
wire [29:0] a_mant_shifted = a_larger_exp ? a_mant : (a_mant >> actual_shift);
wire [29:0] b_mant_shifted = a_larger_exp ? (b_mant >> actual_shift) : b_mant;

// 计算sticky位（被丢弃位是否有1，对齐FP16的sticky逻辑）
wire [29:0] sticky_mask_a = (actual_shift == 0) ? 30'b0 : ((1 << actual_shift) - 1);
wire [29:0] sticky_mask_b = (actual_shift == 0) ? 30'b0 : ((1 << actual_shift) - 1);
wire sticky_a = a_larger_exp ? 1'b0 : (|(a_mant & sticky_mask_a));
wire sticky_b = a_larger_exp ? (|(b_mant & sticky_mask_b)) : 1'b0;

// 对齐后尾数（包含sticky位，确保精度不丢失）
wire [29:0] a_mant_aligned = a_mant_shifted | {29'b0, sticky_a};
wire [29:0] b_mant_aligned = b_mant_shifted | {29'b0, sticky_b};

// --------------------------
// 7. 尾数加减（对齐FP16逻辑：符号不同则减法，处理大小数交换）
// --------------------------
// 交换逻辑：确保large_mant是较大的尾数（指数小或指数相等时尾数小则交换）
wire swap = (a_exp_actual < b_exp_actual) || ((a_exp_actual == b_exp_actual) && (a_frac < b_frac));
wire [29:0] large_mant = swap ? b_mant_aligned : a_mant_aligned;
wire [29:0] small_mant = swap ? a_mant_aligned : b_mant_aligned;
wire large_sign = swap ? b_sign : a_sign;
wire small_sign = swap ? a_sign : b_sign;
wire operation_sub = (large_sign != small_sign);  // 符号不同→减法，相同→加法

// 31位结果（30位尾数 + 1位进位，对应FP16的18位sum_mant_raw）
wire [30:0] sum_mant_raw;
assign sum_mant_raw = operation_sub ? 
    ((large_mant >= small_mant) ? ({1'b0, large_mant} - {1'b0, small_mant}) : ({1'b0, small_mant} - {1'b0, large_mant})) :
    ({1'b0, large_mant} + {1'b0, small_mant});
// 结果符号：减法时取较大数符号，加法时取共同符号
wire result_sign = operation_sub ? ((large_mant >= small_mant) ? large_sign : small_sign) : large_sign;

// --------------------------
// 8. 规格化（核心修改：集成前导零计数器，替换原硬编码查找）
// --------------------------
wire [29:0] normalized_mant;  // 规格化后尾数（30位）
wire [7:0] normalized_exp;    // 规格化后指数（8位）
wire [2:0] round_bits;        // 舍入位（3位：guard+round+sticky）

// ① 声明前导零计数器的输出信号（前导零数量）
wire [4:0] lz_count;

// ② 实例化FP32前导零计数器（输入为31位sum_mant_raw）
leading_zero_counter_fp32 u_leading_zero_counter(
    .data_in(sum_mant_raw),    // 输入：尾数加减结果sum_mant_raw[30:0]
    .leading_zeros(lz_count)   // 输出：前导零数量（0~31）
);

// ③ 计算最高有效位位置（leading_one）：替换原连续三目运算符
// 逻辑：leading_one = 最高位索引（30） - 前导零数量；全零时leading_one=0
wire [4:0] leading_one = (lz_count == 5'd31) ? 5'd0 : (5'd30 - lz_count);

// 指数调整（30位尾数的偏移量为29=30-1，对应FP16的16=17-1）
wire [8:0] temp_exp_ext = {1'b0, max_exp} + {1'b0, leading_one} - 9'd29;
wire temp_exp_pos = !temp_exp_ext[8];          // 指数是否为正
wire temp_exp_ge1 = temp_exp_pos && (temp_exp_ext[7:0] >= 8'b1);  // 指数≥1（规格化）
wire exp_underflow = !temp_exp_pos || (temp_exp_ext[7:0] == 8'b0); // 指数下溢

// 非规格化数补偿：右移调整尾数（对齐FP16的denorm_shift逻辑）
wire [8:0] temp_exp_signed = temp_exp_ext;
wire [4:0] denorm_shift_right = exp_underflow ? (2 - $signed(temp_exp_signed)) : 8'd0;
wire [4:0] shift_amount_left = 30 - leading_one;  // 尾数左移量（对齐到最高有效位）
wire [30:0] shifted_sum_temp = sum_mant_raw << shift_amount_left;
wire [30:0] shifted_sum_denorm = shifted_sum_temp >> denorm_shift_right;
wire [4:0] shift_amount = exp_underflow ? 8'd0 : (30 - leading_one);
wire [30:0] shifted_sum = exp_underflow ? shifted_sum_denorm : (sum_mant_raw << shift_amount);

// 规格化输出（提取尾数和指数）
assign normalized_mant = shifted_sum[29:0];
assign normalized_exp = exp_underflow ? 8'b0 : temp_exp_ext[7:0];
assign round_bits = {normalized_mant[6], normalized_mant[5], |normalized_mant[4:0]};  // 舍入位（扩展6位的低3位）

// --------------------------
// 9. 舍入逻辑（完全对齐FP16的四舍五入规则）
// --------------------------
wire guard = round_bits[2];    // 保护位（扩展位最高位）
wire round = round_bits[1];    // 舍入位
wire sticky = round_bits[0];   // 粘滞位

// 区分非规格化/规格化数的LSB位置（对齐FP16逻辑）
wire lsb = exp_underflow ? normalized_mant[5] : normalized_mant[7];

// 扩展Sticky位判断（包含bit5的有效位，对齐FP16）
wire extended_sticky = sticky || normalized_mant[5];

// 舍入条件（四舍五入规则，与FP16完全一致）
wire round_up = (guard && round) || (guard && extended_sticky) || (guard && !round && !extended_sticky && lsb);

// 尾数舍入（非规格化/规格化数截取范围适配32位，对齐FP16逻辑）
wire [23:0] rounded_mant = exp_underflow ? 
    {1'b0, normalized_mant[28:6]} + (round_up ? 24'd1 : 24'd0) :  // 非规格化：保留23位（28:6）
    {1'b0, normalized_mant[29:7]} + (round_up ? 24'd1 : 24'd0);   // 规格化：保留23位（29:7）

wire round_carry = rounded_mant[23];  // 舍入进位（需调整指数）

// --------------------------
// 10. 溢出/下溢处理（对齐FP16逻辑，适配32位指数）
// --------------------------
wire [7:0] final_exp_val = round_carry ? (normalized_exp + 8'd1) : normalized_exp;
wire [22:0] final_frac = round_carry ? rounded_mant[22:0] : rounded_mant[22:0];  // 23位尾数
wire overflow = (final_exp_val >= 8'b11111111);  // 指数全1→溢出（输出Inf）
wire underflow = (normalized_exp == 8'b0) && (rounded_mant[22:0] != 23'b0);      // 下溢（输出非规格化数）

// --------------------------
// 11. 双非规格化数计算（对齐FP16结构，适配32位尾数）
// --------------------------
wire [29:0] a_mant_denorm = {1'b0, a_frac, 6'b0};
wire [29:0] b_mant_denorm = {1'b0, b_frac, 6'b0};
wire same_sign_denorm = (a_sign == b_sign);
wire a_larger_mant_denorm = (a_mant_denorm >= b_mant_denorm);

// 双非规格化数加减（对齐FP16逻辑）
wire [29:0] mant_result_denorm = both_denorm ? (
    same_sign_denorm ? (a_mant_denorm + b_mant_denorm) : 
    (a_larger_mant_denorm ? (a_mant_denorm - b_mant_denorm) : (b_mant_denorm - a_mant_denorm))
) : 30'd0;

wire mant_zero_denorm = (mant_result_denorm == 30'd0);
// 非规格化结果尾数（右移6位去除扩展位，对齐FP16）
wire [22:0] frac_final_denorm = both_denorm ? (
    mant_zero_denorm ? 23'd0 : (mant_result_denorm >> 6)
) : 23'd0;
// 非规格化结果符号（对齐FP16逻辑）
wire sign_denorm = both_denorm ? (
    mant_zero_denorm ? 1'b0 : (same_sign_denorm ? a_sign : (a_larger_mant_denorm ? a_sign : b_sign))
) : 1'b0;

// --------------------------
// 12. 最终输出（对齐FP16的case优先级，适配32位）
// --------------------------
always @(posedge clk) begin
    case (1'b1)
        // 1. 最高优先级：NaN场景（输出合规NaN）
        is_nan: sum <= nan_result;

        // 2. 次高优先级：无穷大/溢出场景（输出标准Inf）
        is_inf || overflow: sum <= inf_result;

        // 3. 单零场景（直接输出非零数）
        a_zero && !b_zero: sum <= b;
        !a_zero && b_zero: sum <= a;

        // 4. 双零场景（输出带符号零）
        a_zero && b_zero: sum <= {result_sign, 31'b0};

        // 5. 双非规格化数场景（输出非规格化结果）
        both_denorm: sum <= temp_exp_ge1 ? {sign_denorm, temp_exp_ext[7:0], rounded_mant[22:0]} : {sign_denorm, 8'b0, frac_final_denorm};

        // 6. 运算结果为零场景（输出带符号零）
        sum_mant_raw == 31'd0: sum <= {result_sign, 31'b0};

        // 7. 下溢场景（输出非规格化数）
        underflow || exp_underflow: sum <= {result_sign, 8'b0, rounded_mant[22:0]};

        // 8. 默认场景：正常规格化运算（输出规格化数）
        default: sum <= {result_sign, final_exp_val, final_frac};
    endcase
end

endmodule