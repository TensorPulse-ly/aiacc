//-----------------------------------------------------------------------------
// Filename: tb_fp32_adder_tree_8_inputs.v
// Author: sunny
// Date: 2025-8-6
// Version: 2.0
// Description: Testbench for 8-input FP32 adder tree with SoftFloat reference model validation.
//-----------------------------------------------------------------------------

`timescale 1ns/1ps
`include "../define/fp32_defines.vh"

module tb_fp32_adder_tree_8_inputs;

    //==========================================================================
    // 参数定义
    //==========================================================================
    parameter CLK_PERIOD = 10;
    parameter NUM_INPUTS = 8;
    parameter FP32_WIDTH = `FP32_WIDTH;
    parameter EXP_WIDTH = `FP32_EXP_WIDTH;
    parameter MANT_WIDTH = `FP32_MANT_WIDTH;
    parameter BIAS = `FP32_BIAS;

    // SoftFloat 舍入模式常量
    parameter SOFTFLOAT_ROUND_NEAR_EVEN = 0;
    parameter SOFTFLOAT_ROUND_MINMAG    = 1;
    parameter SOFTFLOAT_ROUND_MIN       = 2;
    parameter SOFTFLOAT_ROUND_MAX       = 3;
    parameter SOFTFLOAT_ROUND_NEAR_MAXMAG = 4;

    // 测试控制常量
    parameter NUM_FIXED_TESTS = 41;
    parameter NUM_RANDOM_TESTS = 1000;
    parameter RANDOM_SEED = 12345;
    
    //异常标志说明
    //inexact   = (flags & 32'h01) != 0;
    //underflow = (flags & 32'h02) != 0; 
    //overflow  = (flags & 32'h04) != 0;
    //div_zero  = (flags & 32'h08) != 0;
    //invalid   = (flags & 32'h10) != 0;

    // 时钟和复位信号
    reg clk;
    reg rst_n;
    
    // DUT输入输出信号 
    reg [127:0] dvr_fp32addtree8to1_s0;          // 计算输入数据0 
    reg [127:0] dvr_fp32addtree8to1_s1;          // 计算输入数据1 
    reg [2:0] cru_fp32addtree8to1;               // 上行指令寄存器 
    wire [127:0] dr_fp32addtree8to1_d;           // 输出寄存器 
    
    // 组合逻辑信号
    wire [FP32_WIDTH-1:0] fp_sum [0:3];  // 4个输出寄存器的结果
    wire is_nan_out [0:3];
    wire is_inf_out [0:3];
    
    // 从输出寄存器提取结果 - 支持4个寄存器
    assign fp_sum[0] = dr_fp32addtree8to1_d[31:0];    // 寄存器0
    assign fp_sum[1] = dr_fp32addtree8to1_d[63:32];   // 寄存器1
    assign fp_sum[2] = dr_fp32addtree8to1_d[95:64];   // 寄存器2
    assign fp_sum[3] = dr_fp32addtree8to1_d[127:96];  // 寄存器3
    
    genvar reg_idx;
    generate
        for (reg_idx = 0; reg_idx < 4; reg_idx = reg_idx + 1) begin : gen_status_signals
            assign is_nan_out[reg_idx] = (fp_sum[reg_idx][30:23] == 8'hFF) && (fp_sum[reg_idx][22:0] != 23'b0);
            assign is_inf_out[reg_idx] = (fp_sum[reg_idx][30:23] == 8'hFF) && (fp_sum[reg_idx][22:0] == 23'b0);
        end
    endgenerate

    // 内部测试变量
    reg match_found;
    reg [31:0] expected_fp32_from_softfloat;
    reg [31:0] softfloat_flags;

    // 文件操作变量
    integer sim_log;
    integer pass_count;
    integer fail_count;

    // 循环变量声明
    integer i, j;
    integer rand_i, rand_j;

    // 随机测试变量
    integer random_pass_count;
    integer random_fail_count;
    reg [31:0] random_inputs [0:NUM_INPUTS-1];
    reg [31:0] random_expected;
    reg [31:0] random_flags;

    // 测试用例数据存储 - 使用二维数组
    reg [FP32_WIDTH-1:0] test_inputs [0:NUM_FIXED_TESTS-1][0:NUM_INPUTS-1];

    //==========================================================================
    // DPI-C接口声明 - 与C函数的接口
    //==========================================================================
    
    // DPI-C 导入声明
    import "DPI-C" function int unsigned fp32_add_8_softfloat(
        input int unsigned input0, input int unsigned input1, 
        input int unsigned input2, input int unsigned input3,
        input int unsigned input4, input int unsigned input5, 
        input int unsigned input6, input int unsigned input7);
    
    import "DPI-C" function void set_softfloat_rounding_mode(
        input int unsigned mode);
    
    import "DPI-C" function void clear_softfloat_flags();
    
    import "DPI-C" function int unsigned get_softfloat_flags();

    //==========================================================================
    // 被测模块实例化
    //==========================================================================

    fp32_adder_tree_8_inputs u_fp32_adder_tree_8_inputs (
        .clk(clk),
        .rst_n(rst_n),
        .dvr_fp32addtree8to1_s0(dvr_fp32addtree8to1_s0),
        .dvr_fp32addtree8to1_s1(dvr_fp32addtree8to1_s1),
        .cru_fp32addtree8to1(cru_fp32addtree8to1),
        .dr_fp32addtree8to1_d(dr_fp32addtree8to1_d)
    );

    //==========================================================================
    // 时钟生成
    //==========================================================================
    
    always begin
        clk = 1'b0;
        #(CLK_PERIOD/2);
        clk = 1'b1;
        #(CLK_PERIOD/2);
    end

    //==========================================================================
    // 比较函数
    //==========================================================================
    
    function compare_results;
        input [31:0] expected;
        input [31:0] actual;
        input [31:0] flags;
        
        // 局部变量声明
        reg temp_match_found;
        reg temp_is_inexact;
        reg temp_is_expected_nan;
        reg temp_is_actual_nan;
        reg [31:0] temp_diff;
        reg [31:0] temp_abs_diff;
        
        begin
            temp_match_found = 1'b0;
            temp_is_inexact = (flags & 32'h00000001) != 1'b0;
            temp_is_expected_nan = (expected[30:23] == 8'hFF) && (expected[22:0] != 23'b0);
            temp_is_actual_nan = (actual[30:23] == 8'hFF) && (actual[22:0] != 23'b0);
            
            // 计算差值
            if (actual > expected) begin
                temp_diff = actual - expected;
            end else begin
                temp_diff = expected - actual;
            end
            temp_abs_diff = temp_diff;
            
            // NaN 比较
            if (temp_is_expected_nan && temp_is_actual_nan) begin
                temp_match_found = 1'b1;
            end
            // 精确匹配
            else if (actual === expected) begin
                temp_match_found = 1'b1;
            end
            // 不精确结果的容差比较 - 允许更大的容差
            else if (temp_is_inexact) begin
                // 对于8输入的加法树，允许最多8 ULP的误差Units in the Last Place
                if (temp_abs_diff <= 32'd8) begin
                    temp_match_found = 1'b1;
                end
            end
            // 对于非不精确结果，不允许误差 
            else begin
                if (temp_abs_diff == 32'd0) begin
                    temp_match_found = 1'b1;
                end
            end

            compare_results = temp_match_found;
        end
    endfunction

    // 结果打印任务 
    task print_test_result;
        input integer test_num;
        input [31:0] expected;
        input [31:0] actual;
        input [31:0] flags;
        input match;
        input is_random;
        input integer reg_idx;
        
        // 局部变量
        reg temp_is_inexact;
        reg [31:0] temp_diff;
        
        begin
            temp_is_inexact = (flags & 32'h00000001) != 1'b0;
            if (actual > expected) begin
                temp_diff = actual - expected;
            end else begin
                temp_diff = expected - actual;
            end
            
            if (match) begin
                if (is_random && (test_num % 5 != 0)) begin
                    // 随机测试只打印前10个和每5个
                end else begin
                    if ((expected[30:23] == 8'hFF) && (expected[22:0] != 23'b0) &&
                        (actual[30:23] == 8'hFF) && (actual[22:0] != 23'b0)) begin
                        $fdisplay(sim_log, "%s %0d (Reg%0d): PASS (NaN): expected=%h (flags=%h), actual=%h",
                                 is_random ? "随机测试" : "测试用例", test_num, reg_idx, expected, flags, actual);
                    end else if (actual === expected) begin
                        $fdisplay(sim_log, "%s %0d (Reg%0d): PASS: expected=%h (flags=%h), actual=%h",
                                 is_random ? "随机测试" : "测试用例", test_num, reg_idx, expected, flags, actual);
                    end else begin
                        $fdisplay(sim_log, "%s %0d (Reg%0d): PASS: expected=%h (flags=%h), actual=%h (±%0d ULP tolerance)",
                                 is_random ? "随机测试" : "测试用例", test_num, reg_idx, expected, flags, actual, temp_diff);
                    end
                end
            end else begin
                $fdisplay(sim_log, "%s %0d (Reg%0d): FAIL: expected=%h (flags=%h), actual=%h (diff=%0d ULP)",
                         is_random ? "随机测试" : "测试用例", test_num, reg_idx, expected, flags, actual, temp_diff);
            end
        end
    endtask

    // 设置测试输入任务 - 支持指定目标寄存器
    task set_test_inputs;
        input integer test_case;
        input integer target_reg;  // 目标寄存器索引 (0-3)
        begin
            // 每个FP32数据分为高16bit(S1[y])和低16bit(S0[y])
            // FP32[y] = {S1[y][15:0], S0[y][15:0]}
            dvr_fp32addtree8to1_s0 = {test_inputs[test_case][7][15:0],   // S0[7] - FP32[7]的低16bit
                                     test_inputs[test_case][6][15:0],    // S0[6] - FP32[6]的低16bit
                                     test_inputs[test_case][5][15:0],    // S0[5] - FP32[5]的低16bit
                                     test_inputs[test_case][4][15:0],    // S0[4] - FP32[4]的低16bit
                                     test_inputs[test_case][3][15:0],    // S0[3] - FP32[3]的低16bit
                                     test_inputs[test_case][2][15:0],    // S0[2] - FP32[2]的低16bit
                                     test_inputs[test_case][1][15:0],    // S0[1] - FP32[1]的低16bit
                                     test_inputs[test_case][0][15:0]};   // S0[0] - FP32[0]的低16bit
            
            dvr_fp32addtree8to1_s1 = {test_inputs[test_case][7][31:16],  // S1[7] - FP32[7]的高16bit
                                     test_inputs[test_case][6][31:16],   // S1[6] - FP32[6]的高16bit
                                     test_inputs[test_case][5][31:16],   // S1[5] - FP32[5]的高16bit
                                     test_inputs[test_case][4][31:16],   // S1[4] - FP32[4]的高16bit
                                     test_inputs[test_case][3][31:16],   // S1[3] - FP32[3]的高16bit
                                     test_inputs[test_case][2][31:16],   // S1[2] - FP32[2]的高16bit
                                     test_inputs[test_case][1][31:16],   // S1[1] - FP32[1]的高16bit
                                     test_inputs[test_case][0][31:16]};  // S1[0] - FP32[0]的高16bit
            
            // 发送指令到指定的目标寄存器
            case (target_reg)
                0: cru_fp32addtree8to1 = 3'b100; // 指令有效，目标寄存器编码=00
                1: cru_fp32addtree8to1 = 3'b101; // 指令有效，目标寄存器编码=01
                2: cru_fp32addtree8to1 = 3'b110; // 指令有效，目标寄存器编码=10
                3: cru_fp32addtree8to1 = 3'b111; // 指令有效，目标寄存器编码=11
                default: cru_fp32addtree8to1 = 3'b100; // 默认寄存器0
            endcase
            
            // 等待一个时钟周期，让设计处理数据
            @(posedge clk);
            

        end
    endtask

    // 测试用例初始化任务
    task initialize_test_cases;
        begin
            // 基本测试用例
            initialize_basic_tests();
            // 特殊值测试用例
            initialize_special_cases();
            // 精度测试用例
            initialize_precision_cases();
            // 溢出测试用例
            initialize_overflow_cases();
        end
    endtask

    // 基本测试用例初始化
    task initialize_basic_tests;
        begin
            // 测试用例 0: 基本正数加法 (1+2+3+4+5+6+7+8=36)
            test_inputs[0][0] = 32'h3f800000; // 1.0
            test_inputs[0][1] = 32'h40000000; // 2.0
            test_inputs[0][2] = 32'h40400000; // 3.0
            test_inputs[0][3] = 32'h40800000; // 4.0
            test_inputs[0][4] = 32'h40a00000; // 5.0
            test_inputs[0][5] = 32'h40c00000; // 6.0
            test_inputs[0][6] = 32'h40e00000; // 7.0
            test_inputs[0][7] = 32'h41000000; // 8.0

            // 测试用例 1: 正负数混合 (结果应为0)
            test_inputs[1][0] = 32'h41200000; // 10.0
            test_inputs[1][1] = 32'hc1200000; // -10.0
            test_inputs[1][2] = 32'h40a00000; // 5.0
            test_inputs[1][3] = 32'hc0a00000; // -5.0
            test_inputs[1][4] = 32'h3f800000; // 1.0
            test_inputs[1][5] = 32'hbf800000; // -1.0
            test_inputs[1][6] = 32'h40000000; // 2.0
            test_inputs[1][7] = 32'hc0000000; // -2.0

            // 测试用例 2-3: 零值测试
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[2][j] = 32'h00000000; // +0.0
                test_inputs[3][j] = 32'h80000000; // -0.0
            end
        end
    endtask

    // 特殊值测试用例初始化
    task initialize_special_cases;
        begin
            // 测试用例 4: 正负零混合
            test_inputs[4][0] = 32'h00000000; // +0.0
            test_inputs[4][1] = 32'h80000000; // -0.0
            test_inputs[4][2] = 32'h00000000; // +0.0
            test_inputs[4][3] = 32'h80000000; // -0.0
            test_inputs[4][4] = 32'h00000000; // +0.0
            test_inputs[4][5] = 32'h80000000; // -0.0
            test_inputs[4][6] = 32'h00000000; // +0.0
            test_inputs[4][7] = 32'h80000000; // -0.0

            // 测试用例 5: 无穷大测试
            test_inputs[5][0] = 32'h7f800000; // +Inf
            for (j = 1; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[5][j] = 32'h3f800000; // 1.0
            end

            // 测试用例 6: 负无穷大测试
            test_inputs[6][0] = 32'hff800000; // -Inf
            for (j = 1; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[6][j] = 32'h3f800000; // 1.0
            end

            // 测试用例 7: NaN测试
            test_inputs[7][0] = 32'h7fc00000; // qNaN
            for (j = 1; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[7][j] = 32'h3f800000; // 1.0
            end
        end
    endtask

    // 精度测试用例初始化
    task initialize_precision_cases;
        begin
            // 测试用例 8-13: 各种精度测试
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[8][j] = 32'h00800000;  // 最小正规格化数
                test_inputs[9][j] = 32'h7f7fffff;  // 最大正规格化数
                test_inputs[10][j] = 32'h00000001; // 最小正非规格化数
                test_inputs[11][j] = 32'h00000100; // 小的非规格化数
                test_inputs[12][j] = 32'h7f000000; // 很大的数
                test_inputs[13][j] = 32'h3f000000; // 0.5
            end
            
            // 测试用例 14-20: 边界值测试
            test_inputs[14][0] = 32'h3f7fffff; // 接近1.0的数
            test_inputs[14][1] = 32'h3f800001; // 略大于1.0的数
            for (j = 2; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[14][j] = 32'h00000000; // 0.0
            end
            
            // 测试用例 15: 小数加法精度测试
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[15][j] = 32'h3e800000; // 0.25
            end
            
            // 测试用例 16: 不同指数的数相加
            test_inputs[16][0] = 32'h3f800000; // 1.0
            test_inputs[16][1] = 32'h40000000; // 2.0
            test_inputs[16][2] = 32'h40800000; // 4.0
            test_inputs[16][3] = 32'h41000000; // 8.0
            test_inputs[16][4] = 32'h41800000; // 16.0
            test_inputs[16][5] = 32'h42000000; // 32.0
            test_inputs[16][6] = 32'h42800000; // 64.0
            test_inputs[16][7] = 32'h43000000; // 128.0
            
            // 测试用例 17: 很小的数相加
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[17][j] = 32'h34000000; // 很小的正数
            end
            
            // 测试用例 18: 正负数混合 - 应该接近零但不为零
            test_inputs[18][0] = 32'h41200000; // 10.0
            test_inputs[18][1] = 32'hc1200000; // -10.0
            test_inputs[18][2] = 32'h3f800000; // 1.0
            test_inputs[18][3] = 32'hbf800000; // -1.0
            test_inputs[18][4] = 32'h3e800000; // 0.25
            test_inputs[18][5] = 32'hbe800000; // -0.25
            test_inputs[18][6] = 32'h3e000000; // 0.125
            test_inputs[18][7] = 32'hbe000000; // -0.125
            
            // 测试用例 19: 非规格化数测试
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[19][j] = 32'h00000010; // 小的非规格化数
            end
            
            // 测试用例 20-30: 更多的精度和边界测试
            for (i = 20; i <= 30; i = i + 1) begin
                for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                    // 创建不同的测试模式
                    if (i == 20) begin
                        test_inputs[i][j] = 32'h3dcccccd; // 0.1
                    end else if (i == 21) begin
                        test_inputs[i][j] = 32'h3e4ccccd; // 0.2
                    end else if (i == 22) begin
                        test_inputs[i][j] = 32'h3e99999a; // 0.3
                    end else if (i == 23) begin
                        test_inputs[i][j] = 32'h3ecccccd; // 0.4
                    end else if (i == 24) begin
                        test_inputs[i][j] = 32'h3f19999a; // 0.6
                    end else if (i == 25) begin
                        test_inputs[i][j] = 32'h3f333333; // 0.7
                    end else if (i == 26) begin
                        test_inputs[i][j] = 32'h3f4ccccd; // 0.8
                    end else if (i == 27) begin
                        test_inputs[i][j] = 32'h3f666666; // 0.9
                    end else if (i == 28) begin
                        // 混合正负小数
                        test_inputs[i][j] = (j % 2 == 0) ? 32'h3dcccccd : 32'hbdcccccd; // ±0.1
                    end else if (i == 29) begin
                        // 渐增数列
                        case (j)
                            0: test_inputs[i][j] = 32'h3f800000; // 1.0
                            1: test_inputs[i][j] = 32'h3fc00000; // 1.5
                            2: test_inputs[i][j] = 32'h40000000; // 2.0
                            3: test_inputs[i][j] = 32'h40200000; // 2.5
                            4: test_inputs[i][j] = 32'h40400000; // 3.0
                            5: test_inputs[i][j] = 32'h40600000; // 3.5
                            6: test_inputs[i][j] = 32'h40800000; // 4.0
                            7: test_inputs[i][j] = 32'h40900000; // 4.5
                        endcase
                    end else begin // i == 30
                        // 负数测试
                        test_inputs[i][j] = 32'hbf800000; // -1.0
                    end
                end
            end
            
            // 测试用例 31-39: 边界和特殊情况
            for (i = 31; i < 40; i = i + 1) begin
                for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                    if (i == 31) begin
                        // 交替正负1
                        test_inputs[i][j] = (j % 2 == 0) ? 32'h3f800000 : 32'hbf800000;
                    end else if (i == 32) begin
                        // 所有-1
                        test_inputs[i][j] = 32'hbf800000; // -1.0
                    end else if (i == 33) begin
                        // 大指数差异测试
                        test_inputs[i][j] = (j == 0) ? 32'h47800000 : 32'h3f800000; // 65536.0 vs 1.0
                    end else if (i == 34) begin
                        // Pi/8 近似值
                        test_inputs[i][j] = 32'h3ec90fdb; // π/8 ≈ 0.39269...
                    end else if (i == 35) begin
                        // e/8 近似值
                        test_inputs[i][j] = 32'h3e2df854; // e/8 ≈ 0.33969...
                    end else begin
                        // 其他测试用例设为随机但固定的值
                        test_inputs[i][j] = 32'h3f800000 + (i * 1000 + j * 100); // 变化的值
                    end
                end
            end
        end
    endtask

    // 溢出测试用例初始化
    task initialize_overflow_cases;
        begin
            // 测试用例 40: 溢出测试 - 应该产生INF
            for (j = 0; j < NUM_INPUTS; j = j + 1) begin
                test_inputs[40][j] = 32'h7F7FFFFF; // 最大正规格化数
            end
        end
    endtask

    //==========================================================================
    // 测试执行任务
    //==========================================================================
    
    // 执行固定测试用例 - 测试所有4个输出寄存器
    task execute_fixed_tests;
        integer reg_idx;
        begin
            $fdisplay(sim_log, "\n=== Starting Fixed Test Cases ===");

            for (i = 0; i < NUM_FIXED_TESTS; i = i + 1) begin
                // 对每个测试用例，测试所有4个输出寄存器
                for (reg_idx = 0; reg_idx < 4; reg_idx = reg_idx + 1) begin
                    // 设置输入到指定寄存器
                    set_test_inputs(i, reg_idx);

                    // 清除 SoftFloat 异常标志
                    clear_softfloat_flags();

                    // 通过 DPI-C 从 SoftFloat 获取期望结果
                    expected_fp32_from_softfloat = fp32_add_8_softfloat(
                        test_inputs[i][0], test_inputs[i][1], test_inputs[i][2], test_inputs[i][3],
                        test_inputs[i][4], test_inputs[i][5], test_inputs[i][6], test_inputs[i][7]);
                    softfloat_flags = get_softfloat_flags();

                    // 等待DUT处理（等待时钟和寄存器更新）
                    @(posedge clk);
                    #1; // 小延迟确保信号稳定
                    
                    // 停止指令
                    cru_fp32addtree8to1 = 3'b0;

                    // 比较结果 - 使用对应寄存器的输出
                    match_found = compare_results(expected_fp32_from_softfloat, fp_sum[reg_idx], softfloat_flags);

                    // 打印结果
                    print_test_result(i, expected_fp32_from_softfloat, fp_sum[reg_idx], softfloat_flags, match_found, 1'b0, reg_idx);

                    // 更新计数器
                    if (match_found) begin
                        pass_count = pass_count + 1;
                    end else begin
                        fail_count = fail_count + 1;
                        // 输出输入值用于调试
                        $fdisplay(sim_log, "输入: %h %h %h %h %h %h %h %h",
                                 test_inputs[i][0], test_inputs[i][1], test_inputs[i][2], test_inputs[i][3],
                                 test_inputs[i][4], test_inputs[i][5], test_inputs[i][6], test_inputs[i][7]);
                    end

                    #10;
                end
            end

            // 输出固定测试统计信息
            $fdisplay(sim_log, "\nFixed Test Cases Summary:");
            $fdisplay(sim_log, "Total fixed tests: %0d", pass_count + fail_count);
            $fdisplay(sim_log, "Passed: %0d", pass_count);
            $fdisplay(sim_log, "Failed: %0d", fail_count);
        end
    endtask

    // 执行指令控制测试 - 专门测试指令编码和控制逻辑
    task execute_instruction_tests;
        integer cmd_test;
        integer test_case;
        begin
            $fdisplay(sim_log, "\n=== Starting Instruction Control Tests ===");
            
            test_case = 0; // 使用第一个测试用例：1+2+3+4+5+6+7+8=36
            
            // 测试1: 指令有效位测试
            $fdisplay(sim_log, "\n--- Testing Command Valid Bit ---");
            
            // 设置输入数据
            dvr_fp32addtree8to1_s0 = {test_inputs[test_case][7][15:0],   
                                     test_inputs[test_case][6][15:0],    
                                     test_inputs[test_case][5][15:0],    
                                     test_inputs[test_case][4][15:0],    
                                     test_inputs[test_case][3][15:0],    
                                     test_inputs[test_case][2][15:0],    
                                     test_inputs[test_case][1][15:0],    
                                     test_inputs[test_case][0][15:0]};   
            
            dvr_fp32addtree8to1_s1 = {test_inputs[test_case][7][31:16],  
                                     test_inputs[test_case][6][31:16],   
                                     test_inputs[test_case][5][31:16],   
                                     test_inputs[test_case][4][31:16],   
                                     test_inputs[test_case][3][31:16],   
                                     test_inputs[test_case][2][31:16],   
                                     test_inputs[test_case][1][31:16],   
                                     test_inputs[test_case][0][31:16]};  
            
            // 调试：打印输入数据
            $fdisplay(sim_log, "Input data S0: 0x%h", dvr_fp32addtree8to1_s0);
            $fdisplay(sim_log, "Input data S1: 0x%h", dvr_fp32addtree8to1_s1);
            $fdisplay(sim_log, "Expected FP32 inputs: %h %h %h %h %h %h %h %h",
                     test_inputs[test_case][0], test_inputs[test_case][1], test_inputs[test_case][2], test_inputs[test_case][3],
                     test_inputs[test_case][4], test_inputs[test_case][5], test_inputs[test_case][6], test_inputs[test_case][7]);
            
            @(posedge clk);
            #1;
            
            // 测试无效指令（cmd_valid = 0）
            cru_fp32addtree8to1 = 3'b000; // 指令无效
            @(posedge clk);
            #1;
            
            // 检查所有输出寄存器应该为0
            if (dr_fp32addtree8to1_d == 128'b0) begin
                $fdisplay(sim_log, "Invalid Command Test: PASS - All outputs are zero when cmd_valid=0");
                pass_count = pass_count + 1;
            end else begin
                $fdisplay(sim_log, "Invalid Command Test: FAIL - Outputs not zero when cmd_valid=0 (0x%h)", dr_fp32addtree8to1_d);
                fail_count = fail_count + 1;
            end
            
            // 测试2: 各种指令编码测试
            $fdisplay(sim_log, "\n--- Testing Instruction Encoding ---");
            
            for (cmd_test = 0; cmd_test < 4; cmd_test = cmd_test + 1) begin // 只测试有效的寄存器编码
                // 发送指令并保持
                cru_fp32addtree8to1 = {1'b1, cmd_test[1:0]}; // cmd_valid=1, dest_reg_idx=cmd_test[1:0]
                @(posedge clk);
                @(posedge clk); // 等待两个时钟周期确保处理完成
                #1; // 小延迟确保信号稳定
                
                $fdisplay(sim_log, "Instruction 3'b1%2b: DR_output=0x%h", cmd_test[1:0], dr_fp32addtree8to1_d);
                $fdisplay(sim_log, "  fp_sum[0]=0x%h, fp_sum[1]=0x%h, fp_sum[2]=0x%h, fp_sum[3]=0x%h", 
                         fp_sum[0], fp_sum[1], fp_sum[2], fp_sum[3]);
                
                // 验证输出位置
                case (cmd_test[1:0])
                    2'b00: begin
                        if (fp_sum[0] != 32'b0 && fp_sum[1] == 32'b0 && fp_sum[2] == 32'b0 && fp_sum[3] == 32'b0) begin
                            $fdisplay(sim_log, "Reg0 Target: PASS - Output in correct register (0x%h)", fp_sum[0]);
                            pass_count = pass_count + 1;
                        end else begin
                            $fdisplay(sim_log, "Reg0 Target: FAIL - Output in wrong register");
                            fail_count = fail_count + 1;
                        end
                    end
                    2'b01: begin
                        if (fp_sum[0] == 32'b0 && fp_sum[1] != 32'b0 && fp_sum[2] == 32'b0 && fp_sum[3] == 32'b0) begin
                            $fdisplay(sim_log, "Reg1 Target: PASS - Output in correct register (0x%h)", fp_sum[1]);
                            pass_count = pass_count + 1;
                        end else begin
                            $fdisplay(sim_log, "Reg1 Target: FAIL - Output in wrong register");
                            fail_count = fail_count + 1;
                        end
                    end
                    2'b10: begin
                        if (fp_sum[0] == 32'b0 && fp_sum[1] == 32'b0 && fp_sum[2] != 32'b0 && fp_sum[3] == 32'b0) begin
                            $fdisplay(sim_log, "Reg2 Target: PASS - Output in correct register (0x%h)", fp_sum[2]);
                            pass_count = pass_count + 1;
                        end else begin
                            $fdisplay(sim_log, "Reg2 Target: FAIL - Output in wrong register");
                            fail_count = fail_count + 1;
                        end
                    end
                    2'b11: begin
                        if (fp_sum[0] == 32'b0 && fp_sum[1] == 32'b0 && fp_sum[2] == 32'b0 && fp_sum[3] != 32'b0) begin
                            $fdisplay(sim_log, "Reg3 Target: PASS - Output in correct register (0x%h)", fp_sum[3]);
                            pass_count = pass_count + 1;
                        end else begin
                            $fdisplay(sim_log, "Reg3 Target: FAIL - Output in wrong register");
                            fail_count = fail_count + 1;
                        end
                    end
                endcase
                
                // 停止指令并清零，为下一次测试准备
                cru_fp32addtree8to1 = 3'b0;
                @(posedge clk);
                #10;
            end
            
            // 测试3: 指令时序测试
            $fdisplay(sim_log, "\n--- Testing Instruction Timing ---");
            
            // 清零
            cru_fp32addtree8to1 = 3'b0;
            @(posedge clk);
            #10;
            
            // 发送指令到寄存器0并保持
            cru_fp32addtree8to1 = 3'b100;
            @(posedge clk);
            @(posedge clk); // 等待两个时钟周期
            #1;
            
            // 检查输出
            $fdisplay(sim_log, "After instruction: fp_sum[0]=0x%h, DR_output=0x%h", fp_sum[0], dr_fp32addtree8to1_d);
            if (fp_sum[0] != 32'b0) begin
                $fdisplay(sim_log, "Timing Test: PASS - Output appears after 2 clock cycles (0x%h)", fp_sum[0]);
                pass_count = pass_count + 1;
            end else begin
                $fdisplay(sim_log, "Timing Test: FAIL - No output after 2 clock cycles");
                fail_count = fail_count + 1;
            end
            
            // 停止指令，检查输出是否清零（组合逻辑应该立即响应）
            cru_fp32addtree8to1 = 3'b0;
            #1; // 很短的延迟，因为是组合逻辑
            
            $fdisplay(sim_log, "After stop: DR_output=0x%h", dr_fp32addtree8to1_d);
            if (dr_fp32addtree8to1_d == 128'b0) begin
                $fdisplay(sim_log, "Command Stop Test: PASS - Output cleared when command stops");
                pass_count = pass_count + 1;
            end else begin
                $fdisplay(sim_log, "Command Stop Test: FAIL - Output not cleared when command stops");
                fail_count = fail_count + 1;
            end
            
            $fdisplay(sim_log, "Instruction control tests completed.");
        end
    endtask

    // 执行寄存器功能测试 - 验证所有4个输出寄存器的独立性
    task execute_register_tests;
        integer reg_idx;
        integer test_case;
        begin
            $fdisplay(sim_log, "\n=== Starting Register Functionality Tests ===");
            
            test_case = 0; // 使用第一个测试用例
            
            // 清零所有寄存器
            dvr_fp32addtree8to1_s0 = 128'b0;
            dvr_fp32addtree8to1_s1 = 128'b0;
            cru_fp32addtree8to1 = 3'b0;
            @(posedge clk);
            #10;
            
            // 测试每个寄存器的独立性
            for (reg_idx = 0; reg_idx < 4; reg_idx = reg_idx + 1) begin
                $fdisplay(sim_log, "Testing Register %0d independence...", reg_idx);
                
                // 设置输入到指定寄存器
                set_test_inputs(test_case, reg_idx);
                
                // 等待DUT处理 - 给足够时间完成浮点运算
                @(posedge clk);
                @(posedge clk);
                #1;
                
                // 检查只有目标寄存器有输出，其他寄存器为0
                if (fp_sum[reg_idx] != 32'b0) begin
                    $fdisplay(sim_log, "Register %0d: PASS - Output present (0x%h)", reg_idx, fp_sum[reg_idx]);
                    pass_count = pass_count + 1;
                end else begin
                    $fdisplay(sim_log, "Register %0d: FAIL - No output", reg_idx);
                    fail_count = fail_count + 1;
                end
                
                // 检查其他寄存器是否为0
                for (j = 0; j < 4; j = j + 1) begin
                    if (j != reg_idx) begin
                        if (fp_sum[j] == 32'b0) begin
                            $fdisplay(sim_log, "Register %0d (non-target): PASS - Correctly zero", j);
                        end else begin
                            $fdisplay(sim_log, "Register %0d (non-target): FAIL - Unexpected output (0x%h)", j, fp_sum[j]);
                            fail_count = fail_count + 1;
                        end
                    end
                end
                
                // 停止指令
                cru_fp32addtree8to1 = 3'b0;
                @(posedge clk);
                #1;
                
                #10;
            end
            
            $fdisplay(sim_log, "Register functionality tests completed.");
        end
    endtask

    // 执行随机测试
    task execute_random_tests;
        begin
            $fdisplay(sim_log, "\n=== Starting Random Tests ===");

            // 初始化随机测试计数器
            random_pass_count = 0;
            random_fail_count = 0;

            // 初始化随机种子
            $srandom(RANDOM_SEED);

            for (rand_i = 0; rand_i < NUM_RANDOM_TESTS; rand_i = rand_i + 1) begin
                // 生成随机输入
                for (rand_j = 0; rand_j < NUM_INPUTS; rand_j = rand_j + 1) begin
                    random_inputs[rand_j] = $random;
                end

                // 设置输入到DUT - 按照新接口规范：每个FP32分为高低16bit
                dvr_fp32addtree8to1_s0 = {random_inputs[7][15:0],   // S0[7] - FP32[7]的低16bit
                                         random_inputs[6][15:0],    // S0[6] - FP32[6]的低16bit
                                         random_inputs[5][15:0],    // S0[5] - FP32[5]的低16bit
                                         random_inputs[4][15:0],    // S0[4] - FP32[4]的低16bit
                                         random_inputs[3][15:0],    // S0[3] - FP32[3]的低16bit
                                         random_inputs[2][15:0],    // S0[2] - FP32[2]的低16bit
                                         random_inputs[1][15:0],    // S0[1] - FP32[1]的低16bit
                                         random_inputs[0][15:0]};   // S0[0] - FP32[0]的低16bit
                
                dvr_fp32addtree8to1_s1 = {random_inputs[7][31:16],  // S1[7] - FP32[7]的高16bit
                                         random_inputs[6][31:16],   // S1[6] - FP32[6]的高16bit
                                         random_inputs[5][31:16],   // S1[5] - FP32[5]的高16bit
                                         random_inputs[4][31:16],   // S1[4] - FP32[4]的高16bit
                                         random_inputs[3][31:16],   // S1[3] - FP32[3]的高16bit
                                         random_inputs[2][31:16],   // S1[2] - FP32[2]的高16bit
                                         random_inputs[1][31:16],   // S1[1] - FP32[1]的高16bit
                                         random_inputs[0][31:16]};  // S1[0] - FP32[0]的高16bit
                
                // 发送指令到目标寄存器0
                cru_fp32addtree8to1 = 3'b100; // 指令有效，目标寄存器编码=00

                // 清除 SoftFloat 异常标志
                clear_softfloat_flags();

                // 通过 DPI-C 从 SoftFloat 获取期望结果
                random_expected = fp32_add_8_softfloat(
                    random_inputs[0], random_inputs[1], random_inputs[2], random_inputs[3],
                    random_inputs[4], random_inputs[5], random_inputs[6], random_inputs[7]);
                random_flags = get_softfloat_flags();

                // 等待DUT处理（等待时钟和寄存器更新）
                @(posedge clk);
                #1; // 小延迟确保信号稳定
                
                // 停止指令
                cru_fp32addtree8to1 = 3'b0;

                // 比较结果 - 使用寄存器0进行随机测试
                match_found = compare_results(random_expected, fp_sum[0], random_flags);

                // 打印结果（有选择性地）
                print_test_result(rand_i, random_expected, fp_sum[0], random_flags, match_found, 1'b1, 0);

                // 更新计数器
                if (match_found) begin
                    random_pass_count = random_pass_count + 1;
                end else begin
                    random_fail_count = random_fail_count + 1;
                    // 输出输入值用于调试
                    $fdisplay(sim_log, "输入: %h %h %h %h %h %h %h %h",
                             random_inputs[0], random_inputs[1], random_inputs[2], random_inputs[3],
                             random_inputs[4], random_inputs[5], random_inputs[6], random_inputs[7]);
                end

                #1; // 较短的延迟以加快随机测试

            end

            // 输出随机测试统计信息
            $fdisplay(sim_log, "\nRandom Test Summary:");
            $fdisplay(sim_log, "Total random tests: %0d", random_pass_count + random_fail_count);
            $fdisplay(sim_log, "Passed: %0d", random_pass_count);
            $fdisplay(sim_log, "Failed: %0d", random_fail_count);
            if (NUM_RANDOM_TESTS > 0) begin
                $fdisplay(sim_log, "Pass rate: %0d/%0d (%.1f%%)",
                         random_pass_count, NUM_RANDOM_TESTS,
                         (random_pass_count * 100.0) / NUM_RANDOM_TESTS);
            end
        end
    endtask

    // 打印最终统计信息
    task print_final_statistics;
        begin
            $fdisplay(sim_log, "\n=== Overall Test Summary ===");
            $fdisplay(sim_log, "Fixed tests - Passed: %0d, Failed: %0d", pass_count, fail_count);
            $fdisplay(sim_log, "Random tests - Passed: %0d, Failed: %0d", random_pass_count, random_fail_count);
            $fdisplay(sim_log, "Total tests: %0d", pass_count + fail_count + random_pass_count + random_fail_count);
            $fdisplay(sim_log, "Total passed: %0d", pass_count + random_pass_count);
            $fdisplay(sim_log, "Total failed: %0d", fail_count + random_fail_count);

            if ((fail_count + random_fail_count) == 0) begin
                $fdisplay(sim_log, "\nPASSED: All test cases passed!");
                $display("SIMULATION PASSED: All test cases passed!");
            end else begin
                $fdisplay(sim_log, "\nFAILED: %0d test cases failed", fail_count + random_fail_count);
                $display("SIMULATION FAILED: %0d test cases failed", fail_count + random_fail_count);
            end
        end
    endtask

    //==========================================================================
    // 主测试序列
    //==========================================================================
    
    initial begin
        // 初始化信号
        clk = 1'b0;
        rst_n = 1'b0;
        dvr_fp32addtree8to1_s0 = 128'b0;
        dvr_fp32addtree8to1_s1 = 128'b0;
        cru_fp32addtree8to1 = 3'b0;
        pass_count = 0;
        fail_count = 0;

        // 波形文件设置
        /*`ifdef DUMP_FSDB
            $fsdbDumpfile("sim_softfloat.fsdb");
            $fsdbDumpvars(0, tb_fp32_adder_tree_8_inputs);
            $display("FSDB波形文件已启用: sim_softfloat.fsdb");
        `endif*/
       /* $dumpfile("waveform.vcd");
        $dumpvars(0, tb_fp32_adder_tree_8_inputs);
        $display("信息：VCD波形记录已启用，将生成 waveform.vcd 文件。");
       */
        // 日志文件设置
        sim_log = $fopen("sim_softfloat.log", "w");
        if (sim_log == 0) begin
            $display("Error: Could not open sim_softfloat.log");
            $finish;
        end
        $fdisplay(sim_log, "FP32 Adder Tree SoftFloat Simulation started at time %t", $time);

        // 设置 SoftFloat 舍入模式
        set_softfloat_rounding_mode(SOFTFLOAT_ROUND_NEAR_EVEN);

        // 初始化测试用例数据
        initialize_test_cases();

        // 系统复位
        #20;
        rst_n = 1'b1;
        #10;

        // 执行指令控制测试
        execute_instruction_tests();
        
        // 执行寄存器功能测试
        execute_register_tests();
        
        // 执行固定测试用例
        execute_fixed_tests();

        // 执行随机测试
        execute_random_tests();

        // 输出最终统计
        print_final_statistics();

        // 清理并结束仿真
        $fclose(sim_log);
        $finish;
    end

endmodule
