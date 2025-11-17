// 在测试平台中添加这个详细的自动检查模块
module automatic_checker #(
    parameter TOTAL_TESTS = 4
)(
    input wire clk,
    input wire rst_n,
    
    // 测试状态输入
    input wire test_start,
    input wire test_end,
    input wire test_pass,
    
    // UR写入监控
    input wire ur_we,
    input wire [5:0] smc_index,
    input wire [10:0] ur_addr,
    input wire [127:0] ur_wdata,
    
    // 预期结果输入
    input wire [5:0] expected_smc,
    input wire [10:0] expected_addr,
    input wire [127:0] expected_data,
    input wire result_match,
    
    // 统计输出
    output reg [31:0] total_checks,
    output reg [31:0] passed_checks,
    output reg [31:0] failed_checks,
    output reg all_tests_passed
);

// 测试状态跟踪
reg [7:0] current_test_id;
reg [31:0] test_checks [0:TOTAL_TESTS-1];
reg [31:0] test_passed [0:TOTAL_TESTS-1];
reg [31:0] test_failed [0:TOTAL_TESTS-1];
reg test_active;

// 初始化
initial begin
    total_checks = 0;
    passed_checks = 0;
    failed_checks = 0;
    all_tests_passed = 1'b1;
    test_active = 1'b0;
    current_test_id = 0;
    
    for (int i = 0; i < TOTAL_TESTS; i++) begin
        test_checks[i] = 0;
        test_passed[i] = 0;
        test_failed[i] = 0;
    end
end

// 测试开始检测
always @(posedge clk) begin
    if (rst_n) begin
        if (test_start && !test_active) begin
            test_active <= 1'b1;
            $display("");
            $display("================================================================");
            $display("                    TEST START                                  ");
            $display("================================================================");
            $display("");
        end
        
        if (test_end && test_active) begin
            test_active <= 1'b0;
            
            // 使用条件语句而不是字符串变量
            if (test_pass) begin
                $display("");
                $display("================================================================");
                $display("                    TEST END: PASSED                            ");
                $display("  Checks: %3d  Passed: %3d  Failed: %3d                    ", 
                         test_checks[current_test_id], test_passed[current_test_id], test_failed[current_test_id]);
                $display("================================================================");
                $display("");
            end else begin
                $display("");
                $display("================================================================");
                $display("                    TEST END: FAILED                            ");
                $display("  Checks: %3d  Passed: %3d  Failed: %3d                    ", 
                         test_checks[current_test_id], test_passed[current_test_id], test_failed[current_test_id]);
                $display("================================================================");
                $display("");
            end
            
            if (current_test_id < TOTAL_TESTS-1) begin
                current_test_id <= current_test_id + 1;
            end
        end
        
        // 统计检查结果
        if (ur_we) begin
            test_checks[current_test_id] <= test_checks[current_test_id] + 1;
            total_checks <= total_checks + 1;
            
            if (result_match) begin
                test_passed[current_test_id] <= test_passed[current_test_id] + 1;
                passed_checks <= passed_checks + 1;
                $display("CHECK PASSED: SMC%0d, addr=%0h", smc_index, ur_addr);
                $display("   Expected: %h", expected_data);
                $display("   Actual:   %h", ur_wdata);
            end else begin
                test_failed[current_test_id] <= test_failed[current_test_id] + 1;
                failed_checks <= failed_checks + 1;
                all_tests_passed <= 1'b0;
                $display("CHECK FAILED: SMC%0d, addr=%0h", smc_index, ur_addr);
                $display("   Expected: %h", expected_data);
                $display("   Actual:   %h", ur_wdata);
                $display("   Expected SMC: %0d, Actual SMC: %0d", expected_smc, smc_index);
                $display("   Expected Addr: %0h, Actual Addr: %0h", expected_addr, ur_addr);
            end
        end
    end else begin
        // 复位
        test_active <= 1'b0;
        current_test_id <= 0;
        total_checks <= 0;
        passed_checks <= 0;
        failed_checks <= 0;
        all_tests_passed <= 1'b1;
        
        for (int i = 0; i < TOTAL_TESTS; i++) begin
            test_checks[i] <= 0;
            test_passed[i] <= 0;
            test_failed[i] <= 0;
        end
    end
end

// 最终总结
task print_final_summary;
    begin
        $display("");
        $display("================================================================");
        $display("                      FINAL TEST SUMMARY                        ");
        $display("================================================================");
        $display(" Total Tests:    %3d", TOTAL_TESTS);
        $display(" Total Checks:   %3d", total_checks);
        $display(" Passed Checks:  %3d", passed_checks);
        $display(" Failed Checks:  %3d", failed_checks);
        
        if (failed_checks == 0) begin
            $display("");
            $display("                  ALL TESTS PASSED!                   ");
        end else begin
            $display("");
            $display("                  SOME TESTS FAILED!                  ");
        end
        $display("================================================================");
        $display("");
    end
endtask

endmodule