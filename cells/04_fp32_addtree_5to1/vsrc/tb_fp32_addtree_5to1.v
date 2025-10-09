//-----------------------------------------------------------------------------
// Filename: tb_fp32_addtree_5to1.v
// Author: sunny
// Date: 2025-8-25
// Version: 2.0
// Description: Verify the functional correctness of fp32_adder_tree_final
//-----------------------------------------------------------------------------
`timescale 1ns / 1ps
`include "../define/fp32_defines.vh"

module tb_fp32_addtree_5to1;

    parameter CLK_PERIOD = 10;
    parameter NUM_LANES  = 8;
    parameter RESET_CYCLES = 10;
    parameter ULP_TOLERANCE = 8;
    parameter NUM_RANDOM_TESTS = 1000;
    parameter RANDOM_SEED = 12345;

    import "DPI-C" function int unsigned fp32_add_5_softfloat(
        input int unsigned i0, input int unsigned i1, input int unsigned i2,
        input int unsigned i3, input int unsigned i4
    );

    // 时钟和复位
    reg clk, rst_n, cru_fp32_addtree5to1;
    
    // 输入数据寄存器
    reg [127:0] dvr_fp32_addtree5to1_s [0:7];
    
    // 输出数据线
    wire [127:0] dr_fp32_addtree5to1_d0, dr_fp32_addtree5to1_d1;
    
    // 测试变量
    integer test_count, pass_count, fail_count;
    reg test_passed_for_all_lanes;
    reg [`FP32_WIDTH-1:0] old_fp32 [0:NUM_LANES-1];
    reg [`FP32_WIDTH-1:0] expected_result [0:NUM_LANES-1];
    reg [`FP32_WIDTH-1:0] actual_result [0:NUM_LANES-1];
    reg [`FP32_WIDTH-1:0] test_data [0:NUM_LANES-1][0:3];
    
    integer log_file;

    // 实例化被测设计
    fp32_adder_tree_final dut (
        .clk(clk),
        .rst_n(rst_n),
        .cru_fp32addtree5to1(cru_fp32_addtree5to1),
        .dvr_fp32addtree5to1_s0(dvr_fp32_addtree5to1_s[0]),
        .dvr_fp32addtree5to1_s1(dvr_fp32_addtree5to1_s[1]),
        .dvr_fp32addtree5to1_s2(dvr_fp32_addtree5to1_s[2]),
        .dvr_fp32addtree5to1_s3(dvr_fp32_addtree5to1_s[3]),
        .dvr_fp32addtree5to1_s4(dvr_fp32_addtree5to1_s[4]),
        .dvr_fp32addtree5to1_s5(dvr_fp32_addtree5to1_s[5]),
        .dvr_fp32addtree5to1_s6(dvr_fp32_addtree5to1_s[6]),
        .dvr_fp32addtree5to1_s7(dvr_fp32_addtree5to1_s[7]),
        .dr_fp32addtree5to1_d0(dr_fp32_addtree5to1_d0),
        .dr_fp32addtree5to1_d1(dr_fp32_addtree5to1_d1)
    );

    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // 复位任务
    task reset_dut;
        begin
            rst_n = 1'b0;
            cru_fp32_addtree5to1 = 1'b0;
            for (integer i = 0; i < 8; i = i + 1) begin
                dvr_fp32_addtree5to1_s[i] = '0;
            end
            #(CLK_PERIOD);
            rst_n = 1'b1;
        end
    endtask

    // 计算并加载寄存器任务
    task calculate_and_load_regs;
        input [`FP32_WIDTH-1:0] new_inputs [0:NUM_LANES-1][0:3];
        reg [127:0] local_s [0:7];
        integer x, k, y_index, bit_pos;
        reg [`FP32_WIDTH-1:0] fp_val;
    begin
        // 初始化局部寄存器
        for (integer i = 0; i < 8; i = i + 1) begin
            local_s[i] = '0;
        end
        
        // 计算寄存器值
        for (x = 0; x < NUM_LANES; x = x + 1) begin
            for (k = 0; k < 4; k = k + 1) begin
                y_index = 4*x + k;
                bit_pos = y_index * 4;
                fp_val = new_inputs[x][k];
                
                local_s[0][bit_pos +: 4] = fp_val[ 3 :  0];
                local_s[1][bit_pos +: 4] = fp_val[ 7 :  4];
                local_s[2][bit_pos +: 4] = fp_val[11 :  8];
                local_s[3][bit_pos +: 4] = fp_val[15 : 12];
                local_s[4][bit_pos +: 4] = fp_val[19 : 16];
                local_s[5][bit_pos +: 4] = fp_val[23 : 20];
                local_s[6][bit_pos +: 4] = fp_val[27 : 24];
                local_s[7][bit_pos +: 4] = fp_val[31 : 28];
            end
        end
        
        // 加载到实际寄存器
        for (integer i = 0; i < 8; i = i + 1) begin
            dvr_fp32_addtree5to1_s[i] = local_s[i];
        end
    end
    endtask

    // 计算期望值任务
    task compute_expected_values;
        integer x;
    begin
        for (x = 0; x < NUM_LANES; x = x + 1) begin
            old_fp32[x] = {dr_fp32_addtree5to1_d1[x*16 +: 16], dr_fp32_addtree5to1_d0[x*16 +: 16]};
            expected_result[x] = fp32_add_5_softfloat(
                test_data[x][0], test_data[x][1], test_data[x][2], test_data[x][3], old_fp32[x]
            );
        end
    end
    endtask

    // 检查结果任务
    task check_results;
        input [1023:0] test_name;
        input integer test_num;
        output reg passed;
        integer x;
        reg lane_passed;
        reg [`FP32_WIDTH-1:0] diff;
    begin
        passed = 1'b1;
        $fdisplay(log_file, "\n--- Test %0d: %0s ---", test_num, test_name);// 使用%0s格式控制符，自动截断到空字符

        for (x = 0; x < NUM_LANES; x = x + 1) begin
            actual_result[x] = {dr_fp32_addtree5to1_d1[x*16 +: 16], dr_fp32_addtree5to1_d0[x*16 +: 16]};
            
            // ULP 容差比较逻辑
            lane_passed = 1'b0;
            
            // 1. 检查是否都是NaN
            if ((expected_result[x][30:23] == 8'hff && expected_result[x][22:0] != 0) &&
                (actual_result[x][30:23] == 8'hff && actual_result[x][22:0] != 0)) begin
                lane_passed = 1'b1;
            // 2. 检查是否完全相等
            end else if (actual_result[x] === expected_result[x]) begin
                lane_passed = 1'b1;
            // 3. 检查是否在ULP容差范围内
            end else begin
                // 计算差值的绝对值
                if ($signed(actual_result[x]) > $signed(expected_result[x])) begin
                    diff = actual_result[x] - expected_result[x];
                end else begin 
                    diff = expected_result[x] - actual_result[x];
                end
                
                if (diff <= ULP_TOLERANCE) begin
                    lane_passed = 1'b1;
                    $fdisplay(log_file, "INFO: Lane %0d PASSED with ULP tolerance. Diff = %0d", x, diff);
                end
            end

            if (!lane_passed) begin
                $fdisplay(log_file, "ERROR: Lane %0d MISMATCH! Actual: 0x%h, Expected: 0x%h, diff:0x%d", x, actual_result[x], expected_result[x], diff);
                passed = 1'b0;
            end
        end

        if (passed) begin
            $fdisplay(log_file, "RESULT: PASSED!");
        end else begin
            $fdisplay(log_file, "RESULT: FAILED!");
        end
    end
    endtask

    // 运行并检查任务
    task run_and_check;
        input [1023:0] test_name;
        input [`FP32_WIDTH-1:0] new_inputs [0:NUM_LANES-1][0:3];
        reg passed;
    begin
        test_count = test_count + 1;
        
        // 更新测试数据
        for (integer i = 0; i < NUM_LANES; i = i + 1) begin
            for (integer j = 0; j < 4; j = j + 1) begin
                test_data[i][j] = new_inputs[i][j];
            end
        end
        
        // 计算期望值
        compute_expected_values();
        
        // 加载数据并触发计算
        calculate_and_load_regs(new_inputs);
        @(posedge clk); 
        cru_fp32_addtree5to1 = 1'b1; 
        #(1); 
        cru_fp32_addtree5to1 = 1'b0;
        @(posedge clk); // 等待一个时钟周期确保结果稳定

        // 检查结果
        check_results(test_name, test_count, passed); 
            if (passed) begin
                pass_count = pass_count + 1;
                for (integer x = 0; x < NUM_LANES; x = x + 1) begin
                    $fdisplay(log_file, "  Lane %0d Inputs: %h, %h, %h, %h, %h. Results: Actual=0x%h, Expected=0x%h",
             x, test_data[x][0], test_data[x][1], test_data[x][2], test_data[x][3], old_fp32[x], actual_result[x], expected_result[x]);
                end
        end else begin
            fail_count = fail_count + 1;
                for (integer x = 0; x < NUM_LANES; x = x + 1) begin
                    $fdisplay(log_file, "  Lane %0d Inputs: %h, %h, %h, %h, %h. Results: Actual=0x%h, Expected=0x%h",
             x, test_data[x][0], test_data[x][1], test_data[x][2], test_data[x][3], old_fp32[x], actual_result[x], expected_result[x]);
                end
            end
    end
    endtask

    // 固定测试任务
    task fixed_test_suite;
        begin
            // 测试用例数组
            reg [1023:0] test_names [0:15];
            reg [`FP32_WIDTH-1:0] test_inputs [0:15][0:NUM_LANES-1][0:3];
            
            // 测试用例 0: 简单加法 (1+2+3+4+0 = 10)
            test_names[0] = "Simple Addition (1+2+3+4+0 = 10)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[0][i][0] = 32'h3f800000; // 1.0
                test_inputs[0][i][1] = 32'h40000000; // 2.0
                test_inputs[0][i][2] = 32'h40400000; // 3.0
                test_inputs[0][i][3] = 32'h40800000; // 4.0
            end
            
            // 测试用例 1: 累加 (0.5*4 + 10 = 12)
            test_names[1] = "Accumulation (0.5*4 + 10 = 12)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[1][i][0] = 32'h3f000000; // 0.5
                test_inputs[1][i][1] = 32'h3f000000; // 0.5
                test_inputs[1][i][2] = 32'h3f000000; // 0.5
                test_inputs[1][i][3] = 32'h3f000000; // 0.5
            end
            
            // 测试用例 2: 混合符号 (-5.0*4 + 12 = -8)
            test_names[2] = "Mixed Signs (-5.0*4 + 12 = -8)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[2][i][0] = 32'hc0a00000; // -5.0
                test_inputs[2][i][1] = 32'hc0a00000; // -5.0
                test_inputs[2][i][2] = 32'hc0a00000; // -5.0
                test_inputs[2][i][3] = 32'hc0a00000; // -5.0
            end
            
            // 测试用例 3: 归零 (8+8-8 = 8)
            test_names[3] = "Cancellation (8+8-8 = 8)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[3][i][0] = 32'h41000000; // 8.0
                test_inputs[3][i][1] = 32'h41000000; // 8.0
                test_inputs[3][i][2] = 32'h00000000; // 0.0
                test_inputs[3][i][3] = 32'h00000000; // 0.0
            end
        
            // 测试用例 4: 无穷大传播 (+Inf + 100 + 0 = +Inf)
            test_names[4] = "Infinity (+Inf + 100 + 0 = +Inf)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[4][i][0] = 32'h7f800000; // +Inf
                test_inputs[4][i][1] = 32'h42c80000; // 100.0
                test_inputs[4][i][2] = 32'h00000000; // 0.0
                test_inputs[4][i][3] = 32'h00000000; // 0.0
            end
            
            // 测试用例 5: 无穷大抵消 (+Inf + (-Inf) = NaN)
            test_names[5] = "Inf Cancellation (+Inf + (-Inf) = NaN)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[5][i][0] = 32'hff800000; // -Inf
                test_inputs[5][i][1] = 32'h00000000; // 0.0
                test_inputs[5][i][2] = 32'h00000000; // 0.0
                test_inputs[5][i][3] = 32'h00000000; // 0.0
            end
            
            // 测试用例 6: NaN 传播 (NaN + 100 + 0 = NaN)
            test_names[6] = "NaN Propagation (NaN + 100 + 0 = NaN)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[6][i][0] = 32'h7fc00000; // NaN
                test_inputs[6][i][1] = 32'h42c80000; // 100.0
                test_inputs[6][i][2] = 32'h00000000; // 0.0
                test_inputs[6][i][3] = 32'h00000000; // 0.0
            end
            
            // 测试用例 7: 溢出 (MAX_FLOAT * 4 + 0 -> +Inf)
            test_names[7] = "Overflow (MAX_FLOAT * 4 + 0 -> +Inf)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[7][i][0] = 32'h7f7fffff; // 最大浮点数
                test_inputs[7][i][1] = 32'h7f7fffff; // 最大浮点数
                test_inputs[7][i][2] = 32'h7f7fffff; // 最大浮点数
                test_inputs[7][i][3] = 32'h7f7fffff; // 最大浮点数
            end
            
            // 测试用例 8: 次正规数 (4 * MIN_SUBNORMAL)
            test_names[8] = "Subnormal Numbers (4 * MIN_SUBNORMAL)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[8][i][0] = 32'h00000001; // 最小次正规数
                test_inputs[8][i][1] = 32'h00000001; // 最小次正规数
                test_inputs[8][i][2] = 32'h00000001; // 最小次正规数
                test_inputs[8][i][3] = 32'h00000001; // 最小次正规数
            end
            
            // 测试用例 9: 正负零
            test_names[9] = "Positive and Negative Zeros";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[9][i][0] = 32'h80000000; // -0.0
                test_inputs[9][i][1] = 32'h00000000; // +0.0
                test_inputs[9][i][2] = 32'h80000000; // -0.0
                test_inputs[9][i][3] = 32'h00000000; // +0.0
            end
            
            // 测试用例 10: 精度测试 (1.0 + 3e-6)
            test_names[10] = "Precision Test (1.0 + 3e-6)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[10][i][0] = 32'h3f800000; // 1.0
                test_inputs[10][i][1] = 32'h358637bd; // 非常小的数 (1e-6)
                test_inputs[10][i][2] = 32'h358637bd; // 非常小的数 (1e-6)
                test_inputs[10][i][3] = 32'h358637bd; // 非常小的数 (1e-6)
            end
            
            // 测试用例 11: 大数加小数
            test_names[11] = "Large + Small Number";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[11][i][0] = 32'h7f7fffff; // 最大正规数
                test_inputs[11][i][1] = 32'h00000001; // 最小次正规数
                test_inputs[11][i][2] = 32'h00000000; // 0.0
                test_inputs[11][i][3] = 32'h00000000; // 0.0
            end
            
            // 测试用例 12: 随机值测试 (5 -10 +10 -1 = 4)
            test_names[12] = "Random Values (5 -10 +10 -1 = 4)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[12][i][0] = 32'h40a00000; // 5.0
                test_inputs[12][i][1] = 32'hc1200000; // -10.0
                test_inputs[12][i][2] = 32'h41200000; // 10.0
                test_inputs[12][i][3] = 32'hbf800000; // -1.0
            end
            
            // 测试用例 13: 符号位测试 (-1 -1 +1 +1 = 0)
            test_names[13] = "Sign Bit Test (-1 -1 +1 +1 = 0)";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[13][i][0] = 32'hbf800000; // -1.0
                test_inputs[13][i][1] = 32'hbf800000; // -1.0
                test_inputs[13][i][2] = 32'h3f800000; // 1.0
                test_inputs[13][i][3] = 32'h3f800000; // 1.0
            end
            
            // 测试用例 14: 特殊NaN值
            test_names[14] = "Special NaN Values";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[14][i][0] = 32'h7f800001; // 信号NaN
                test_inputs[14][i][1] = 32'h7fc00000; // 安静NaN
                test_inputs[14][i][2] = 32'h42c80000; // 100.0
                test_inputs[14][i][3] = 32'h00000000; // 0.0
            end
            
            // 测试用例 15: 边界值测试
            test_names[15] = "Boundary Values Test";
            for (integer i = 0; i < NUM_LANES; i = i + 1) begin
                test_inputs[15][i][0] = 32'h00800000; // 最小正规数
                test_inputs[15][i][1] = 32'h7f7fffff; // 最大正规数
                test_inputs[15][i][2] = 32'h7f800000; // 正无穷
                test_inputs[15][i][3] = 32'hff800000; // 负无穷
            end
            
            // 执行所有16个测试用例
            for (integer t = 0; t < 5; t = t + 1) begin
                run_and_check(test_names[t], test_inputs[t]);
            end

            for (integer t = 5; t < 16; t = t + 1) begin
                run_and_check(test_names[t], test_inputs[t]);
                reset_dut();
                @(posedge clk);
            end
        end
    endtask
    // 随机测试任务
    task random_test_suite;
        integer random_seed_gen;
        integer rand_pass_count;
        integer rand_fail_count;
        integer i;
        reg passed;
    begin
        $fdisplay(log_file, "\n--- Starting Random Test Suite (%0d iterations) ---", NUM_RANDOM_TESTS);
        
        // 初始化随机种子
        random_seed_gen = $random(RANDOM_SEED);
        
        rand_pass_count = 0;
        rand_fail_count = 0;
        
        for (i = 0; i < NUM_RANDOM_TESTS; i = i + 1) begin
            if (i % 8 == 0) begin
                $fdisplay(log_file, "\n--- Starting new group of 8 tests (Test #%0d). Resetting DUT. ---", i + test_count + 1);
                reset_dut();
                @(posedge clk); // 等待一个时钟周期
            end
            // 为所有通道生成随机输入
            for (integer lane = 0; lane < NUM_LANES; lane = lane + 1) begin
                for (integer j = 0; j < 4; j = j + 1) begin
                    test_data[lane][j] = $random;
                end
            end
            
            // 计算期望值
            compute_expected_values();
            
            // 加载数据并触发计算
            calculate_and_load_regs(test_data);
            @(posedge clk);
            cru_fp32_addtree5to1 = 1'b1;
            #(1);
            cru_fp32_addtree5to1 = 1'b0;
            @(posedge clk); // 等待一个时钟周期确保结果稳定
            
            // 检查结果
            check_results($sformatf("Random Test %0d", i+1), test_count + i + 1, passed);
            
            if (passed) begin
                rand_pass_count = rand_pass_count + 1;
                $fdisplay(log_file, "Random Test %0d Details:", i+1);
                for (integer x = 0; x < NUM_LANES; x = x + 1) begin
                    $fdisplay(log_file, "  Lane %0d Inputs: %h, %h, %h, %h, %h. Results: Actual=0x%h, Expected=0x%h",
             x, test_data[x][0], test_data[x][1], test_data[x][2], test_data[x][3], old_fp32[x], actual_result[x], expected_result[x]);
                end
            end else begin
                rand_fail_count = rand_fail_count + 1;
                // 打印失败的测试详情
                $fdisplay(log_file, "Random Test %0d Details:", i+1);
                for (integer x = 0; x < NUM_LANES; x = x + 1) begin
                    $fdisplay(log_file, "  Lane %0d Inputs: %h, %h, %h, %h, %h. Results: Actual=0x%h, Expected=0x%h",
             x, test_data[x][0], test_data[x][1], test_data[x][2], test_data[x][3], old_fp32[x], actual_result[x], expected_result[x]);
                end
            end
        end
        
        // 将随机测试结果计入总数
        pass_count = pass_count + rand_pass_count;
        fail_count = fail_count + rand_fail_count;
        test_count = test_count + NUM_RANDOM_TESTS;

        $fdisplay(log_file, "\n================ SUMMARY ================");
        $fdisplay(log_file, "Total Tests: %0d", test_count);
        $fdisplay(log_file, "Passed: %0d", pass_count);
        $fdisplay(log_file, "Failed: %0d", fail_count);
        $fdisplay(log_file, "=======================================");
    end
    endtask

    // 主测试流程
    initial begin
        // 打开日志文件
        log_file = $fopen("sim.log", "w");

        // 初始化变量
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        
        for (integer i = 0; i < NUM_LANES; i = i + 1) begin
            old_fp32[i] = '0;
            expected_result[i] = '0;
            actual_result[i] = '0;
        end
        /*
        // 设置波形文件
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_fp32_addtree_5to1);
        */
        // 复位DUT
        reset_dut();
        @(posedge clk);
        //#(CLK_PERIOD);
        
        // 执行固定测试
        fixed_test_suite ();
        // 执行随机测试
        random_test_suite();

        // 显示测试摘要
        $display("\n================ SUMMARY ================");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        $display("=======================================");
        
        // 关闭日志文件
        $fclose(log_file);
        
        $finish;
    end

endmodule