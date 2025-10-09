`timescale 1ns/1ps

module tb_shift_up();

    // 测试参数
    parameter CLK_PERIOD = 10;
    parameter TEST_SMC_ID = 2;  // 测试用SMC ID
    parameter PARAM_UR_WORD_CNT = 4; // 用户寄存器字数
    
    // 信号定义
    reg clk;
    reg rst_n;
    reg [134:0] cru_shiftup_in;
    wire [127:0] dr_shiftup_out;
    wire [134:0] cru_shiftup_out;
    
    // 指令字段定义
    wire        in_vld       = cru_shiftup_in[134];
    wire [127:0] in_data     = cru_shiftup_in[133:6];
    wire [4:0]  in_smc_id   = cru_shiftup_in[5:1];
    wire        in_broadcast = cru_shiftup_in[0];
    
    // 输出字段定义
    wire        out_vld       = cru_shiftup_out[134];
    wire [127:0] out_data     = cru_shiftup_out[133:6];
    wire [4:0]  out_smc_id   = cru_shiftup_out[5:1];
    wire        out_broadcast = cru_shiftup_out[0];
    
    // 实例化被测模块
    shift_up #(
        .SMC_ID(TEST_SMC_ID),
        .PARAM_UR_WORD_CNT(PARAM_UR_WORD_CNT)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .cru_shiftup_in(cru_shiftup_in),
        .dr_shiftup_out(dr_shiftup_out),
        .cru_shiftup_out(cru_shiftup_out)
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
        cru_shiftup_in = 135'd0;
        
        // 测试1: 复位功能
        reset_test();
        
        // 测试2: 指令传递测试 (SMC_ID匹配)
        instruction_pass_test();
        
        // 测试3: 广播模式测试
        broadcast_test();
        
        // 测试4: SMC_ID不匹配测试
        smc_mismatch_test();
        
        // 测试5: 多周期连续测试
        multi_cycle_test();
        
        // 测试6: 无效指令测试
        invalid_instruction_test();
        
        $display("\nAll tests passed!");
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
        @(negedge clk);
        
        // 检查复位后输出
        if (dr_shiftup_out !== 128'd0 || cru_shiftup_out !== 135'd0) begin
            $error("Reset failed: Outputs not zero");
            $display("  dr_shiftup_out = %h", dr_shiftup_out);
            $display("  cru_shiftup_out = %h", cru_shiftup_out);
            $finish;
        end
        
        // 释放复位
        @(negedge clk);
        rst_n = 1;
        
        // 检查保持复位值
        @(negedge clk);
        if (dr_shiftup_out !== 128'd0 || cru_shiftup_out !== 135'd0) begin
            $error("Reset release failed");
            $finish;
        end
        
        $display("Reset test passed");
    end
    endtask
    
    // 测试2: 指令传递测试
    task instruction_pass_test;
    begin
        $display("\n=== Test 2: Instruction Pass Test ===");
        
        // Case 2.1: 匹配SMC_ID (等于)
        send_instruction(1, 128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, TEST_SMC_ID, 0);
        check_cru_output(1, 128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5, TEST_SMC_ID, 0);
        check_dr_output(128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5); // 应更新
        
        // Case 2.2: 匹配SMC_ID (大于)
        send_instruction(1, 128'hB6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6, TEST_SMC_ID + 1, 0);
        check_cru_output(1, 128'hB6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6, TEST_SMC_ID + 1, 0);
        check_dr_output(128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5); // 不应更新
        
        // Case 2.3: 不匹配SMC_ID (小于)
        send_instruction(1, 128'hC7C7_C7C7_C7C7_C7C7_C7C7_C7C7_C7C7_C7C7, TEST_SMC_ID - 1, 0);
        check_cru_output(1, 128'hB6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6_B6B6, TEST_SMC_ID + 1, 0); // 应保持前值
        check_dr_output(128'hA5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5_A5A5); // 应保持前值
        
        $display("Instruction pass test passed");
    end
    endtask
    
    // 测试3: 广播模式测试
    task broadcast_test;
    begin
        $display("\n=== Test 3: Broadcast Mode Test ===");
        
        // Case 3.1: 广播有效 + SMC_ID匹配
        send_instruction(1, 128'h1111_1111_1111_1111_1111_1111_1111_1111, TEST_SMC_ID, 1);
        check_cru_output(1, 128'h1111_1111_1111_1111_1111_1111_1111_1111, TEST_SMC_ID, 1);
        check_dr_output(128'h1111_1111_1111_1111_1111_1111_1111_1111); // 应更新
        
        // Case 3.2: 广播有效 + SMC_ID不匹配
        send_instruction(1, 128'h2222_2222_2222_2222_2222_2222_2222_2222, TEST_SMC_ID + 5, 1);
        check_cru_output(1, 128'h2222_2222_2222_2222_2222_2222_2222_2222, TEST_SMC_ID + 5, 1);
        check_dr_output(128'h2222_2222_2222_2222_2222_2222_2222_2222); // 广播应更新
        
        // Case 3.3: 广播无效 + SMC_ID不匹配
        send_instruction(1, 128'h3333_3333_3333_3333_3333_3333_3333_3333, TEST_SMC_ID + 3, 0);
        check_cru_output(1, 128'h3333_3333_3333_3333_3333_3333_3333_3333, TEST_SMC_ID + 3, 0);
        check_dr_output(128'h2222_2222_2222_2222_2222_2222_2222_2222); // 应保持前值
        
        $display("Broadcast test passed");
    end
    endtask
    
    // 测试4: SMC_ID不匹配测试
    task smc_mismatch_test;
    begin
        $display("\n=== Test 4: SMC_ID Mismatch Test ===");
        
        // 修复：先发送一条无效指令清除状态
        send_instruction(0, 128'h0, 0, 0);
        @(negedge clk);
        
        // 初始状态 - 增加额外等待周期
        send_instruction(1, 128'h4444_4444_4444_4444_4444_4444_4444_4444, TEST_SMC_ID, 0);
        @(negedge clk); // 增加等待周期
        check_dr_output(128'h4444_4444_4444_4444_4444_4444_4444_4444);
        
        // 发送不匹配指令
        send_instruction(1, 128'h5555_5555_5555_5555_5555_5555_5555_5555, TEST_SMC_ID + 10, 0);
        @(negedge clk); // 增加等待周期
        check_cru_output(1, 128'h5555_5555_5555_5555_5555_5555_5555_5555, TEST_SMC_ID + 10, 0);
        check_dr_output(128'h4444_4444_4444_4444_4444_4444_4444_4444);
        
        // 发送另一个不匹配指令
        send_instruction(1, 128'h6666_6666_6666_6666_6666_6666_6666_6666, TEST_SMC_ID - 1, 0);
        @(negedge clk); // 增加等待周期
        check_cru_output(1, 128'h5555_5555_5555_5555_5555_5555_5555_5555, TEST_SMC_ID + 10, 0);
        check_dr_output(128'h4444_4444_4444_4444_4444_4444_4444_4444);
    end
    endtask
    
    // 测试5: 多周期连续测试
    task multi_cycle_test;
    begin
        $display("\n=== Test 5: Multi-cycle Test ===");
        
        // 序列1: 匹配+广播
        send_instruction(1, 128'h7777_7777_7777_7777_7777_7777_7777_7777, TEST_SMC_ID, 1);
        check_cru_output(1, 128'h7777_7777_7777_7777_7777_7777_7777_7777, TEST_SMC_ID, 1);
        check_dr_output(128'h7777_7777_7777_7777_7777_7777_7777_7777);
        
        // 序列2: 匹配+非广播
        send_instruction(1, 128'h8888_8888_8888_8888_8888_8888_8888_8888, TEST_SMC_ID, 0);
        check_cru_output(1, 128'h8888_8888_8888_8888_8888_8888_8888_8888, TEST_SMC_ID, 0);
        check_dr_output(128'h8888_8888_8888_8888_8888_8888_8888_8888);
        
        // 序列3: 不匹配+广播
        send_instruction(1, 128'h9999_9999_9999_9999_9999_9999_9999_9999, TEST_SMC_ID + 8, 1);
        check_cru_output(1, 128'h9999_9999_9999_9999_9999_9999_9999_9999, TEST_SMC_ID + 8, 1);
        check_dr_output(128'h9999_9999_9999_9999_9999_9999_9999_9999); // 广播应更新
        
        // 序列4: 不匹配+非广播
        send_instruction(1, 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, TEST_SMC_ID + 3, 0);
        check_cru_output(1, 128'hAAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA_AAAA, TEST_SMC_ID + 3, 0);
        check_dr_output(128'h9999_9999_9999_9999_9999_9999_9999_9999); // 应保持
        
        $display("Multi-cycle test passed");
    end
    endtask
    
    // 测试6: 无效指令测试
    task - invalid_instruction_test;
    begin
        $display("\n=== Test 6: Invalid Instruction Test ===");
        
        // 初始有效指令
        send_instruction(1, 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, TEST_SMC_ID, 0);
        check_dr_output(128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB);
        
        // 发送无效指令
        send_instruction(0, 128'hCCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC_CCCC, TEST_SMC_ID, 0);
        check_cru_output(1, 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, TEST_SMC_ID, 0); // 应保持
        check_dr_output(128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB); // 应保持
        
        // 发送另一个无效指令
        send_instruction(0, 128'hDDDD_DDDD_DDDD_DDDD_DDDD_DDDD_DDDD_DDDD, TEST_SMC_ID + 5, 1);
        check_cru_output(1, 128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB, TEST_SMC_ID, 0); // 应保持
        check_dr_output(128'hBBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB_BBBB); // 应保持
        
        $display("Invalid instruction test passed");
    end
    endtask
    
    // 发送指令任务
    task send_instruction;
        input vld;
        input [127:0] data;
        input [4:0] smc_id;
        input broadcast;
    begin
        @(negedge clk);
        cru_shiftup_in = {vld, data, smc_id, broadcast};
        $display("Sent instruction: vld=%b, data=%32h, smc_id=%d, broadcast=%b",
                 vld, data, smc_id, broadcast);
    end
    endtask
    
    // 检查CRU输出任务
    task check_cru_output;
        input exp_vld;
        input [127:0] exp_data;
        input [4:0] exp_smc_id;
        input exp_broadcast;
    begin
        @(negedge clk); // 等待输出稳定
        if (out_vld !== exp_vld || out_data !== exp_data || 
            out_smc_id !== exp_smc_id || out_broadcast !== exp_broadcast) begin
            $error("CRU output mismatch!");
            $display("  Expected: vld=%b, data=%32h, smc_id=%d, broadcast=%b",
                     exp_vld, exp_data, exp_smc_id, exp_broadcast);
            $display("  Actual:   vld=%b, data=%32h, smc_id=%d, broadcast=%b",
                     out_vld, out_data, out_smc_id, out_broadcast);
            $finish;
        end
        else begin
            $display("CRU output matched: vld=%b, data=%32h, smc_id=%d, broadcast=%b",
                     out_vld, out_data, out_smc_id, out_broadcast);
        end
    end
    endtask
    
    // 检查DR输出任务
    task check_dr_output;
    input [127:0] exp_data;
    begin
        @(negedge clk);
        $display("[DEBUG] Check DR at %t: Exp=%h, Act=%h", 
                $time, exp_data, dr_shiftup_out);
                
        if (dr_shiftup_out !== exp_data) begin
            $error("DR output mismatch!");
            // 显示更多状态信息
            $display("  Current state: vld_reg=%b, broadcast_reg=%b, smc_id_reg=%d, SMC_ID=%d",
                    out_vld, out_broadcast, out_smc_id, TEST_SMC_ID);
            $display("  Expected: data=%32h", exp_data);
            $display("  Actual:   data=%32h", dr_shiftup_out);
            $finish;
        end
        else begin
            $display("DR output matched: data=%32h", dr_shiftup_out);
        end
    end
    endtask

    // 波形记录
    initial begin
        $dumpfile("tb_shift_up.vcd");
        $dumpvars(0, tb_shift_up);
    end

endmodule