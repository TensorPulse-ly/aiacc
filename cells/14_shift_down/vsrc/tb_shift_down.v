//----------------------------------------------------------------------------
// Filename: tb_shift_down.v
// Author: [Oliver]
// Date: 2025-8-15
// Version: 1.0
// Description: Testbench for shift_down module
//----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_shift_down();

    // 测试参数
    parameter CLK_PERIOD = 10;
    parameter TEST_SMC_ID = 3; // 测试用SMC ID
    parameter PARAM_UR_WORD_CNT = 4;
    
    // 信号定义
    reg clk;
    reg rst_n;
    reg [133:0] crd_shiftdn_in;
    reg [127:0] dvr_shiftdn_in;
    wire [133:0] crd_shiftdn_out;
    
    // 输入输出信号分解
    wire        in_vld     = crd_shiftdn_in[133];
    wire [127:0] in_data   = crd_shiftdn_in[132:5];
    wire [4:0]  in_smc_id = crd_shiftdn_in[4:0];
    
    wire        out_vld     = crd_shiftdn_out[133];
    wire [127:0] out_data   = crd_shiftdn_out[132:5];
    wire [4:0]  out_smc_id = crd_shiftdn_out[4:0];
    
    // 实例化被测模块
    shift_down #(
        .SMC_ID(TEST_SMC_ID),
        .PARAM_UR_WORD_CNT(PARAM_UR_WORD_CNT)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .crd_shiftdn_in(crd_shiftdn_in),
        .dvr_shiftdn_in(dvr_shiftdn_in),
        .crd_shiftdn_out(crd_shiftdn_out)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // 测试主程序
    initial begin
        // 初始化
        rst_n = 0;
        crd_shiftdn_in = 134'd0;
        dvr_shiftdn_in = 128'd0;
        
        // 测试1: 复位功能
        reset_test();
        
        // 测试2: 指令传递测试 (SMC_ID > 模块SMC_ID)
        instruction_pass_test();
        
        // 测试3: 数据保存测试 (SMC_ID匹配)
        data_save_test();
        
        // 测试4: SMC_ID小于模块ID测试
        smc_smaller_test();
        
        // 测试5: 多周期连续测试
        multi_cycle_test();
        
        // 测试6: 无效指令测试
        invalid_instruction_test();
        
        $display("\nAll shift_down tests passed!");
        $finish;
    end
    
    // ========== 测试任务定义 ==========
    
    // 测试1: 复位功能验证
    task reset_test;
    begin
        $display("\n=== Test 1: Reset Function ===");
        
        // 应用复位
        @(negedge clk);
        rst_n = 0;
        repeat(2) @(negedge clk);
        
        // 检查复位后输出
        if (crd_shiftdn_out !== 134'd0) begin
            $error("Reset failed: Output not zero");
            $display("  crd_shiftdn_out = %h", crd_shiftdn_out);
            $finish;
        end
        
        // 释放复位
        @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        
        $display("Reset test passed");
    end
    endtask
    
    // 测试2: 指令传递测试 (SMC_ID > 模块SMC_ID)
    task instruction_pass_test;
    begin
        $display("\n=== Test 2: Instruction Pass Test (SMC_ID > module SMC_ID) ===");
        
        // Case 2.1: SMC_ID > 模块SMC_ID (应该传递指令)
        send_instruction(1, 128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, TEST_SMC_ID + 1);
        @(posedge clk); // 等待输出更新
        #1;
        check_output(1, 128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, TEST_SMC_ID + 1);
        
        // Case 2.2: 另一个SMC_ID > 模块SMC_ID
        send_instruction(1, 128'hB6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6, TEST_SMC_ID + 2);
        @(posedge clk); // 等待输出更新
        #1;
        check_output(1, 128'hB6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6, TEST_SMC_ID + 2);
        
        $display("Instruction pass test passed");
    end
    endtask
    
    // 测试3: 数据保存测试 (SMC_ID匹配)
    task data_save_test;
    begin
        $display("\n=== Test 3: Data Save Test (SMC_ID match) ===");
        
        // 设置dvr输入数据
        dvr_shiftdn_in = 128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0;
        
        // Case 3.1: SMC_ID匹配 (应该保存dvr_shiftdn_in)
        send_instruction(1, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, TEST_SMC_ID);
        @(posedge clk); // 等待输出更新
        #1;
        check_output(1, 128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, TEST_SMC_ID);
        
        // Case 3.2: 再次匹配 (使用新的dvr数据)
        dvr_shiftdn_in = 128'hCAFE_BABE_CAFE_BABE_CAFE_BABE_CAFE_BABE;
        send_instruction(1, 128'h0000_0000_0000_0000_0000_0000_0000_0000, TEST_SMC_ID);
        @(posedge clk); // 等待输出更新
        #1;
        check_output(1, 128'hCAFE_BABE_CAFE_BABE_CAFE_BABE_CAFE_BABE, TEST_SMC_ID);
        
        $display("Data save test passed");
    end
    endtask
    
    // 测试4: SMC_ID小于模块ID测试
    task smc_smaller_test;
    begin
        $display("\n=== Test 4: SMC_ID Smaller Test ===");
        
        // 步骤1: 设置初始状态 (使用匹配指令)
        dvr_shiftdn_in = 128'h1111_1111_1111_1111_1111_1111_1111_1111;
        send_instruction(1, 128'h0000_0000_0000_0000_0000_0000_0000_0000, TEST_SMC_ID);
        // 等待输出更新
        @(posedge clk);
        #1; // 确保输出稳定
        check_output(1, 128'h1111_1111_1111_1111_1111_1111_1111_1111, TEST_SMC_ID);
        
        // 步骤2: 设置dvr输入（应该被忽略）
        dvr_shiftdn_in = 128'hBAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0_BAD0;
        
        // Case 4.1: SMC_ID < 模块SMC_ID (应该保持之前的值)
        send_instruction(1, 128'h2222_2222_2222_2222_2222_2222_2222_2222, TEST_SMC_ID - 1);
        // 等待输出稳定
        @(posedge clk);
        #1;
        check_output(1, 128'h1111_1111_1111_1111_1111_1111_1111_1111, TEST_SMC_ID);
        
        // 额外检查：确保输出不是dvr_shiftdn_in
        if (out_data === dvr_shiftdn_in) begin
            $error("Design incorrectly used dvr_shiftdn_in when SMC_ID < module SMC_ID");
            $display("  out_data = %h", out_data);
            $display("  dvr_shiftdn_in = %h", dvr_shiftdn_in);
            $finish;
        end
        
        // Case 4.2: 再次尝试 (应该仍然保持)
        send_instruction(1, 128'h3333_3333_3333_3333_3333_3333_3333_3333, TEST_SMC_ID - 2);
        // 等待输出稳定
        @(posedge clk);
        #1;
        check_output(1, 128'h1111_1111_1111_1111_1111_1111_1111_1111, TEST_SMC_ID);
        
        $display("SMC_ID smaller test passed");
    end
    endtask
    
    // 测试5: 多周期连续测试
    task multi_cycle_test;
    begin
        $display("\n=== Test 5: Multi-cycle Test ===");
        
        // 序列1: 传递 (SMC_ID > 模块ID)
        dvr_shiftdn_in = 128'h0000_0000_0000_0000_0000_0000_0000_0000; // 应该被忽略
        send_instruction(1, 128'h4444_4444_4444_4444_4444_4444_4444_4444, TEST_SMC_ID + 1);
        @(posedge clk);
        #1;
        check_output(1, 128'h4444_4444_4444_4444_4444_4444_4444_4444, TEST_SMC_ID + 1);
        
        // 序列2: 保存 (SMC_ID匹配)
        dvr_shiftdn_in = 128'h5555_5555_5555_5555_5555_5555_5555_5555;
        send_instruction(1, 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, TEST_SMC_ID);
        @(posedge clk);
        #1;
        check_output(1, 128'h5555_5555_5555_5555_5555_5555_5555_5555, TEST_SMC_ID);
        
        // 序列3: 保持 (SMC_ID < 模块ID)
        dvr_shiftdn_in = 128'h6666_6666_6666_6666_6666_6666_6666_6666; // 应该被忽略
        send_instruction(1, 128'h7777_7777_7777_7777_7777_7777_7777_7777, TEST_SMC_ID - 1);
        @(posedge clk);
        #1;
        check_output(1, 128'h5555_5555_5555_5555_5555_5555_5555_5555, TEST_SMC_ID);
        
        // 序列4: 再次传递 (SMC_ID > 模块ID)
        send_instruction(1, 128'h8888_8888_8888_8888_8888_8888_8888_8888, TEST_SMC_ID + 3);
        @(posedge clk);
        #1;
        check_output(1, 128'h8888_8888_8888_8888_8888_8888_8888_8888, TEST_SMC_ID + 3);
        
        $display("Multi-cycle test passed");
    end
    endtask
    
    // 测试6: 无效指令测试
    task invalid_instruction_test;
    begin
        $display("\n=== Test 6: Invalid Instruction Test ===");
        
        // 初始有效指令
        dvr_shiftdn_in = 128'h9999_9999_9999_9999_9999_9999_9999_9999;
        send_instruction(1, 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, TEST_SMC_ID);
        @(posedge clk);
        #1;
        check_output(1, 128'h9999_9999_9999_9999_9999_9999_9999_9999, TEST_SMC_ID);
        
        // Case 6.1: 无效指令 (vld=0) - 应该保持之前的值
        send_instruction(0, 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, TEST_SMC_ID);
        @(posedge clk);
        #1;
        check_output(1, 128'h9999_9999_9999_9999_9999_9999_9999_9999, TEST_SMC_ID);
        
        // Case 6.2: 无效指令 + 不同SMC_ID
        send_instruction(0, 128'hCCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC, TEST_SMC_ID + 1);
        @(posedge clk);
        #1;
        check_output(1, 128'h9999_9999_9999_9999_9999_9999_9999_9999, TEST_SMC_ID);
        
        $display("Invalid instruction test passed");
    end
    endtask
    
    // 发送指令任务
    task send_instruction;
        input vld;
        input [127:0] data;
        input [4:0] smc_id;
    begin
        @(negedge clk);
        crd_shiftdn_in = {vld, data, smc_id};
        $display("[%t] TB: Sent instruction: vld=%b, data=%32h, smc_id=%d", 
                 $time, vld, data, smc_id);
    end
    endtask
    
    // 检查输出任务
    task check_output;
        input exp_vld;
        input [127:0] exp_data;
        input [4:0] exp_smc_id;
    begin
        // 在时钟边沿后立即检查
        if (out_vld !== exp_vld || out_data !== exp_data || out_smc_id !== exp_smc_id) begin
            $error("TB: Output mismatch at time %t", $time);
            $display("  Expected: vld=%b, data=%32h, smc_id=%d", 
                     exp_vld, exp_data, exp_smc_id);
            $display("  Actual:   vld=%b, data=%32h, smc_id=%d", 
                     out_vld, out_data, out_smc_id);
            $display("  Input:    vld=%b, data=%32h, smc_id=%d", 
                     in_vld, in_data, in_smc_id);
            $display("  DVR Input: %32h", dvr_shiftdn_in);
            $finish;
        end
        else begin
            $display("[%t] TB: Output matched: vld=%b, data=%32h, smc_id=%d", 
                     $time, out_vld, out_data, out_smc_id);
        end
    end
    endtask

    // 波形记录
    initial begin
        $dumpfile("tb_shift_down.vcd");
        $dumpvars(0, tb_shift_down);
    end
endmodule