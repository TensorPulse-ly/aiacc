module fp16_adder(
    input wire clk,
    input wire[15:0] a,
    input wire[15:0] b,
    output reg[15:0] sum
);

// 提取符号位、指数和尾数部分
wire a_sign = a[15];
wire b_sign = b[15];
wire[4:0] a_exp = a[14:10];
wire[4:0] b_exp = b[14:10];
wire[9:0] a_frac = a[9:0];
wire[9:0] b_frac = b[9:0]; 

// 特殊值检测（优化零值判断）
wire a_nan = (a_exp == 5'h1F) && (a_frac != 0);
wire b_nan = (b_exp == 5'h1F) && (b_frac != 0);
wire a_inf = (a_exp == 5'h1F) && (a_frac == 0);
wire b_inf = (b_exp == 5'h1F) && (b_frac == 0);
wire a_zero = (a_exp == 0) && (a_frac == 0); // 严格零值判断
wire b_zero = (b_exp == 0) && (b_frac == 0); // 严格零值判断
wire a_denorm = (a_exp == 0) && (a_frac != 0);
wire b_denorm = (b_exp == 0) && (b_frac != 0);
wire both_denorm = a_denorm && b_denorm;

// NaN处理
wire is_nan = a_nan || b_nan || (a_inf && b_inf && (a_sign != b_sign));
//wire[15:0] nan_result = 16'h7E00; // 标准NaN
wire nan_sign = a_nan ? a_sign : b_sign;
wire[15:0] nan_result = {nan_sign, 15'h7E00};

// 无穷大处理
wire is_inf = (a_inf || b_inf) && !is_nan;
wire inf_sign = (a_inf && b_inf) ? (a_sign & b_sign) : 
               (a_inf ? a_sign : b_sign);
wire[15:0] inf_result = {inf_sign, 5'h1F, 10'h0};

// 准备尾数(添加隐藏位)
//wire[10:0] a_mant = {!a_denorm, a_frac};
//wire[10:0] b_mant = {!b_denorm, b_frac};
wire[10:0] a_mant = (a_denorm) ? {1'b0, a_frac} : {1'b1, a_frac};
wire[10:0] b_mant = (b_denorm) ? {1'b0, b_frac} : {1'b1, b_frac};

// 计算指数差
wire[4:0] exp_diff = (a_exp > b_exp) ? (a_exp - b_exp) : (b_exp - a_exp);
wire[4:0] max_exp = (a_exp > b_exp) ? a_exp : b_exp;

// 对齐尾数
wire[10:0] a_mant_aligned = (a_exp >= b_exp) ? a_mant : (a_mant >> exp_diff);
wire[10:0] b_mant_aligned = (b_exp >= a_exp) ? b_mant : (b_mant >> exp_diff);

// 确定更大的数
wire swap = (a_exp < b_exp) || ((a_exp == b_exp) && (a_mant < b_mant));
wire[10:0] large_mant = swap ? b_mant_aligned : a_mant_aligned;
wire[10:0] small_mant = swap ? a_mant_aligned : b_mant_aligned;
wire large_sign = swap ? b_sign : a_sign;
wire small_sign = swap ? a_sign : b_sign;

// 加法处理
wire[11:0] sum_mant;
wire result_sign;

assign sum_mant = (large_sign == small_sign) ?
                 (large_mant + small_mant) : 
                 (large_mant - small_mant);
                 
assign result_sign = (sum_mant == 0) ? (a_sign & b_sign) :
                    (large_sign == small_sign) ? large_sign :
                    (large_mant > small_mant) ? large_sign : small_sign;

// 规格化
wire[3:0] leading_one;
assign leading_one = 
    sum_mant[11] ? 11 :
    sum_mant[10] ? 10 :
    sum_mant[9]  ? 9 :
    sum_mant[8]  ? 8 :
    sum_mant[7]  ? 7 :
    sum_mant[6]  ? 6 :
    sum_mant[5]  ? 5 :
    sum_mant[4]  ? 4 :
    sum_mant[3]  ? 3 :
    sum_mant[2]  ? 2 :
    sum_mant[1]  ? 1 : 0;

// 规格化移位
wire[11:0] shifted_sum = sum_mant << (11 - leading_one);
wire[9:0] norm_frac = shifted_sum[10:1];
wire[4:0] new_exp = max_exp + leading_one - 10;

// 舍入逻辑
wire round_bit = shifted_sum[0];
//wire sticky_bit = |shifted_sum[0:0]; // 简化的粘滞位
wire [4:0] shift_amt = 11 - leading_one;
wire sticky_bit = (shift_amt > 0) ? |(sum_mant & ((1 << shift_amt) - 1)) : 0;

wire round_up = round_bit && (sticky_bit || norm_frac[0]); // 向最接近的偶数舍入

// 舍入后的尾数
wire[9:0] rounded_frac = norm_frac + (round_up ? 10'd1 : 10'd0);

// 检查舍入后是否进位
wire carry_out = (rounded_frac == 10'h3FF) && round_up;
wire[9:0] final_frac_val = carry_out ? 10'h000 : rounded_frac;
wire[4:0] new_exp_rounded = new_exp + (carry_out ? 5'd1 : 5'd0);

// 上溢检测
//wire overflow = (new_exp_rounded >= 5'h1F);
wire overflow = both_denorm ? 1'b0 : (new_exp_rounded >= 5'h1F);
wire[15:0] overflow_result = {result_sign, 5'h1F, 10'h0};

// 非规格化数特殊处理
reg[4:0] final_exp;
reg[9:0] final_frac_reg;

always @(*) begin
  if (both_denorm) begin
    if (sum_mant[11]) begin                   // 进位（和≥2048）
      final_frac_reg = sum_mant[10:1];         // 取[10:1]
      final_exp = 5'd1;                      // 规格化
    end else if (sum_mant[10]) begin           // 1024≤sum<2048
      final_frac_reg = sum_mant[9:0];
      final_exp = 5'd1;                      // 规格化
    end else begin                            // sum<1024
      final_frac_reg = sum_mant[9:0];
      final_exp = 5'd0;                      // 保持非规格化
    end
  end else begin
    // 规格化数处理
    final_frac_reg = final_frac_val;
    final_exp = new_exp_rounded;
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
    end else if (a_zero && b_zero) begin  
        sum <= {result_sign, 15'h0};
    end else if (sum_mant == 0) begin
        sum <= {result_sign, 15'h0};
    end else begin
        sum <= {result_sign, final_exp, final_frac_reg};
    end
end

endmodule