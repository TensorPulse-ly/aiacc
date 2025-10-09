module fp32_adder(
    input wire clk,
    input wire [31:0] a,
    input wire [31:0] b,
    output reg [31:0] sum
);

// 提取符号位、指数和尾数部分
wire a_sign = a[31];
wire b_sign = b[31];
wire [7:0] a_exp = a[30:23];
wire [7:0] b_exp = b[30:23];
wire [22:0] a_frac = a[22:0];
wire [22:0] b_frac = b[22:0];

// 特殊值检测
wire a_nan = (a_exp == 8'hFF) && (a_frac != 0);
wire b_nan = (b_exp == 8'hFF) && (b_frac != 0);
wire a_inf = (a_exp == 8'hFF) && (a_frac == 0);
wire b_inf = (b_exp == 8'hFF) && (b_frac == 0);
wire a_zero = (a_exp == 0) && (a_frac == 0);
wire b_zero = (b_exp == 0) && (b_frac == 0);
wire a_denorm = (a_exp == 0) && (a_frac != 0);
wire b_denorm = (b_exp == 0) && (b_frac != 0);
wire both_denorm = a_denorm && b_denorm;

// NaN处理
wire is_nan = a_nan || b_nan || (a_inf && b_inf && (a_sign != b_sign));
//wire nan_sign = a_nan ? a_sign : b_sign;
wire nan_sign = (a_nan) ? a_sign : 
               (b_nan) ? b_sign : 
               (a_inf && b_inf) ? (a_sign | b_sign) : 1'b0;
wire[31:0] nan_result = {nan_sign, 31'h7FC00000};

// 无穷大处理
wire is_inf = (a_inf || b_inf) && !is_nan;
wire inf_sign = (a_inf && b_inf) ? (a_sign & b_sign) : 
                (a_inf ? a_sign : b_sign);
wire [31:0] inf_result = {inf_sign, 8'hFF, 23'h0};

// 准备尾数(添加隐藏位)
wire [23:0] a_mant = {!a_denorm, a_frac};
wire [23:0] b_mant = {!b_denorm, b_frac};

// 计算指数差
wire [7:0] exp_diff = (a_exp > b_exp) ? (a_exp - b_exp) : (b_exp - a_exp);
wire [7:0] max_exp = (a_exp > b_exp) ? a_exp : b_exp;

// 对齐尾数
wire [23:0] a_mant_aligned = (a_exp >= b_exp) ? a_mant : (a_mant >> exp_diff);
wire [23:0] b_mant_aligned = (b_exp >= a_exp) ? b_mant : (b_mant >> exp_diff);

// 确定更大的数
wire swap = (a_exp < b_exp) || ((a_exp == b_exp) && (a_mant < b_mant));
wire [23:0] large_mant = swap ? b_mant_aligned : a_mant_aligned;
wire [23:0] small_mant = swap ? a_mant_aligned : b_mant_aligned;
wire large_sign = swap ? b_sign : a_sign;
wire small_sign = swap ? a_sign : b_sign;

// 加法处理
wire [24:0] sum_mant;
wire result_sign;

assign sum_mant = (large_sign == small_sign) ? 
                 (large_mant + small_mant) : 
                 (large_mant - small_mant);
                 
assign result_sign = (sum_mant == 0) ? (a_sign & b_sign) :
                    (large_sign == small_sign) ? large_sign :
                    (large_mant > small_mant) ? large_sign : small_sign;

// 规格化
wire [7:0] leading_one;
assign leading_one = 
    sum_mant[24] ? 24 :
    sum_mant[23] ? 23 :
    sum_mant[22] ? 22 :
    sum_mant[21] ? 21 :
    sum_mant[20] ? 20 :
    sum_mant[19] ? 19 :
    sum_mant[18] ? 18 :
    sum_mant[17] ? 17 :
    sum_mant[16] ? 16 :
    sum_mant[15] ? 15 :
    sum_mant[14] ? 14 :
    sum_mant[13] ? 13 :
    sum_mant[12] ? 12 :
    sum_mant[11] ? 11 :
    sum_mant[10] ? 10 :
    sum_mant[9]  ? 9  :
    sum_mant[8]  ? 8  :
    sum_mant[7]  ? 7  :
    sum_mant[6]  ? 6  :
    sum_mant[5]  ? 5  :
    sum_mant[4]  ? 4  :
    sum_mant[3]  ? 3  :
    sum_mant[2]  ? 2  :
    sum_mant[1]  ? 1  : 0;

// 规格化移位
wire [24:0] shifted_sum = sum_mant << (24 - leading_one);
wire [22:0] norm_frac = shifted_sum[23:1];
wire [7:0] new_exp = max_exp + leading_one - 23;

// 上溢检测
//wire overflow = (new_exp >= 8'hFF);
wire overflow = both_denorm ? 1'b0 : (new_exp >= 8'hFF);
wire [31:0] overflow_result = {result_sign, 8'hFF, 23'h0};

// 舍入处理
wire round_bit = shifted_sum[0];
//wire sticky_bit = |(shifted_sum[22:0] & ((1 << (23 - leading_one)) - 1)); // 简化实现
// 统一使用移位量计算
wire [7:0] shift_amt = 24 - leading_one;
wire sticky_bit = (shift_amt > 0) ? |(sum_mant & ((1 << shift_amt) - 1)) : 0;
wire round_up = round_bit && (sticky_bit || norm_frac[0]); // 向最接近的偶数舍入

// 舍入后的尾数
wire [22:0] rounded_frac = norm_frac + (round_up ? 23'd1 : 23'd0);

// 检查舍入后是否进位
wire carry_out = (rounded_frac == 23'h7FFFFF) && round_up;
wire [22:0] final_frac = carry_out ? 23'h000000 : rounded_frac;
wire [7:0] final_exp_val = carry_out ? new_exp + 8'd1 : new_exp;

// 非规格化数特殊处理
reg [7:0] final_exp;
reg [22:0] final_frac_reg;

always @(*) begin
    if (both_denorm) begin
        if (sum_mant[24]) begin
            // 进位-规格化结果
            final_frac_reg = sum_mant[23:1];
            final_exp = 8'd1; // 最小规格化指数
        end else if (sum_mant[23]) begin
            // 1024≤sum<2048
            final_frac_reg = sum_mant[22:0];
            final_exp = 8'd1; // 最小规格化指数
        end else begin
            // 仍然是非规格化数
            final_frac_reg = sum_mant[22:0];
            final_exp = 8'd0;
        end
    end else begin
        final_frac_reg = final_frac;
        final_exp = final_exp_val;
    end
end

// 最终结果组合
always @(posedge clk) begin
    if (is_nan) begin
        sum <= nan_result;
    end else if (is_inf) begin
        sum <= inf_result;
    end else if (overflow) begin
        sum <= overflow_result;
    end else if (a_zero && b_zero) begin  // 严格零值处理
        sum <= {result_sign, 15'h0};
    end else if (sum_mant == 0) begin
        sum <= {result_sign, 31'h0};
    end else begin
        sum <= {result_sign, final_exp, final_frac_reg};
    end
end

endmodule