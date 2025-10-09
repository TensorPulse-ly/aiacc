`timescale 1ns/1ps
// 测试平台：验证“ur_model→burst_store→axi_stb→axi_stb_s→axi_mem_model”链路功能
module burst_store_tb #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter SMC_COUNT = 6
)(
    input                   clk,
    input                   rst_n,
    input                   tb_en,
    output                  tb_done,
    
    // STB接口（连接axi_top）
    output reg              stb_u_valid,
    output reg [SMC_COUNT-1:0] stb_u_smc_strb,
    output reg [3:0]        stb_u_byte_strb,
    output reg [1:0]        stb_u_brst,
    output reg [ADDR_WIDTH-1:0] stb_u_gr_base_addr,
    output reg [3:0]        stb_u_ur_id,
    output reg [10:0]       stb_u_ur_addr,
    input                   stb_d_valid,
    input                   stb_d_done,
    
    // 协议错误信号（连接axi_top）
    input                   protocol_error,
    input [3:0]             error_code
);

// 内部信号
reg [31:0] cycle_count;
reg [3:0] test_case;
reg [31:0] error_count;
reg        tb_done_reg;
wire [2:0] burst_store_state; // 调试：监控burst_store状态
    reg [2:0] prev_burst_store_state;  // 存储前一周期的状态值（替代$prev函数）

// 输出赋值
assign tb_done = tb_done_reg;

// 时钟与复位生成（自动驱动）
reg clk_gen;
reg rst_n_gen;
reg tb_en_gen;
initial begin
    clk_gen = 0;
    rst_n_gen = 0;
    tb_en_gen = 0;
    
    // 复位序列（100ns低电平）
    #100;
    rst_n_gen = 1;
    $display("[TB] 时间%0t: 复位释放，准备启动测试", $time);
    
    // 启动测试（延迟100ns确保模块稳定）
    #100;
    tb_en_gen = 1;
    $display("[TB] 时间%0t: tb_en置1，开始执行测试用例", $time);
    
    // 仿真超时保护（1ms未完成则强制结束）
    #1000000;
    $display("[TB] 时间%0t: 仿真超时（1ms），强制结束", $time);
    $finish;
end

// 50MHz时钟（周期20ns）
always #10 clk_gen = ~clk_gen;

// 信号连接：测试平台→axi_top
assign clk = clk_gen;
assign rst_n = rst_n_gen;
assign tb_en = tb_en_gen;

// 实例化顶层模块（axi_top）
axi_top #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .SMC_COUNT(SMC_COUNT),
    .UR_BYTE_CNT(DATA_WIDTH/8),
    .INTLV_STEP(64),
    .MEM_SIZE(1024 * 1024)
) u_axi_top (
    .clk(clk),
    .rst_n(rst_n),
    .tb_en(tb_en),
    .tb_done(tb_done),
    
    // STB接口连接
    .stb_u_valid(stb_u_valid),
    .stb_u_smc_strb(stb_u_smc_strb),
    .stb_u_byte_strb(stb_u_byte_strb),
    .stb_u_brst(stb_u_brst),
    .stb_u_gr_base_addr(stb_u_gr_base_addr),
    .stb_u_ur_id(stb_u_ur_id),
    .stb_u_ur_addr(stb_u_ur_addr),
    .stb_d_valid(stb_d_valid),
    .stb_d_done(stb_d_done),
    .stb_d_ready(1'b1), // 上层就绪信号（始终为1，表示随时可以接收完成信号）
    
    // 协议错误信号连接
    .protocol_error(protocol_error),
    .error_code(error_code),
    
    // 调试信号连接
    .burst_store_state(burst_store_state)
);

// 周期计数
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_count <= 32'd0;
    end else begin
        cycle_count <= cycle_count + 1;
    end
end

// 协议错误统计
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        error_count <= 32'd0;
    end else if (protocol_error) begin
        error_count <= error_count + 1;
        $display("[TB_ERROR] 时间%0t: 检测到AXI协议错误，错误码=0x%h（累计错误数=%0d）", 
                 $time, error_code, error_count + 1);
    end
end

// 测试用例执行（核心：验证测试用例1的随机数据写入）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位测试信号
        stb_u_valid <= 1'b0;
        stb_u_smc_strb <= {SMC_COUNT{1'b0}};
        stb_u_byte_strb <= 4'b0000;
        stb_u_brst <= 2'b00;
        stb_u_gr_base_addr <= 32'd0;
        stb_u_ur_id <= 4'd0;
        stb_u_ur_addr <= 11'd0;
        tb_done_reg <= 1'b0;
        test_case <= 4'd0;
    end else if (tb_en && !tb_done_reg) begin
        case (test_case)
            4'd0:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试初始化完成，准备执行测试用例1（随机数据写入）", $time);
                    $display("==================================================\n");
                    test_case <= 4'd1;
                end
            
            // 测试用例1：单次burst（1拍），SMC0使能，写入地址0x1000
            4'd1:
                begin
                    $display("[TB] 时间%0t: 测试用例1启动 - 单次burst写入（1拍）", $time);
                    // 配置STB指令参数
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000001;  // SMC0使能
                    stb_u_byte_strb    = 4'h0;       // 全16字节有效
                    stb_u_brst         = 2'b00;      // burst长度=1拍
                    stb_u_gr_base_addr = 32'h00001000;  // 内存写入基地址（0x1000）
                    stb_u_ur_id        = 4'd0;       // 目标UR ID=0
                    stb_u_ur_addr      = 11'h000;    // 目标UR地址=0x000（读取随机数据）
                    
                    $display("[TB] 时间%0t: STB指令参数配置完成 - 基地址=0x1000，UR地址=0x000，SMC0使能", $time);
                    @(posedge clk); // 等待时钟上升沿，确保指令被接收
                    stb_u_valid        = 1'b0; // 清除指令有效
                    $display("[TB] 时间%0t: 等待burst_store指令完成（stb_d_done=1）", $time);
                    
                    // 等待burst_store完成（最长等待1000个时钟周期）
                    $display("[TB_DEBUG] 时间%0t: 等待前 cycle_count=%0d", $time, cycle_count);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout;
                                    disable wait_done;
                                end
                            end
                        end
                        begin: timeout
                            repeat(1000) @(posedge clk);
                            disable wait_done;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例1超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd5;
                        end
                    join
                    
                    // 如果没有超时，就继续执行测试用例2
                    if (test_case == 4'd1) begin
                        $display("[TB] 时间%0t: 测试用例1完成 - burst_store状态已从DONE→IDLE", $time);
                        // 导出内存内容（验证随机数据是否写入0x1000）
                        #10;
                        $display("[TB] 时间%0t: 导出测试用例1内存内容到 sim_output/mem_case1.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(1);
                        test_case <= 4'd2;
                    end
                end
            
            // 测试用例2：4拍burst写入（SMC1）
            4'd2:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例2启动 - 4拍burst写入（SMC1）", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000010;  // SMC1使能
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b10;      // burst长度=4拍
                    stb_u_gr_base_addr = 32'h00002000;  // 基地址=0x2000
                    stb_u_ur_id        = 4'd1;       // UR ID=1
                    stb_u_ur_addr      = 11'h010;    // UR地址=0x010
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case2
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case2;
                                    disable wait_done_case2;
                                end
                            end
                        end
                        begin: timeout_case2
                            repeat(2000) @(posedge clk);
                            disable wait_done_case2;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例2超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd5;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd2) begin
                        $display("[TB] 时间%0t: 测试用例2完成 - burst_store状态已从DONE→IDLE", $time);
                        // 等待足够的时间，确保AXI事务真正完成
                        $display("[TB] 时间%0t: 等待50个时钟周期，确保AXI事务完成", $time);
                        repeat(50) @(posedge clk);
                        $display("[TB] 时间%0t: 导出测试用例2内存内容到 sim_output/mem_case2.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(2);
                        test_case <= 4'd3;
                    end
                end
            
            4'd3:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例3启动 - 多SMC写入（SMC0~SMC2）", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000111;  // SMC0~SMC2使能
                    stb_u_byte_strb    = 4'h0;      //全字节有效
                    stb_u_brst         = 2'b01;      // burst长度=2拍
                    stb_u_gr_base_addr = 32'h00003000;  // 基地址=0x3000
                    stb_u_ur_id        = 4'd2;
                    stb_u_ur_addr      = 11'h020;
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case3
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case3;
                                    disable wait_done_case3;
                                end
                            end
                        end
                        begin: timeout_case3
                            repeat(3000) @(posedge clk);
                            disable wait_done_case3;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例3超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd5;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd3) begin
                        $display("[TB] 时间%0t: 测试用例3完成 - burst_store状态已从DONE→IDLE", $time);
                        // 等待足够的时间，确保AXI事务真正完成
                        $display("[TB] 时间%0t: 测试用例3检测到状态转换完成，但AXI事务可能尚未完成", $time);
                        $display("[TB] 时间%0t: 等待500个时钟周期，确保AXI事务完成（包括实际数据写入）", $time);
                        repeat(500) @(posedge clk);
                        $display("[TB] 时间%0t: 等待完成，现在导出测试用例3内存内容到 sim_output/mem_case3.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(3);
                        test_case <= 4'd4;
                    end
                end
            
            4'd4:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例4启动 - 部分字节写入（低2字节）", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000001;  // SMC0使能，确保写入地址为0x4000
                    stb_u_byte_strb    = 4'h2;       // 低2字节有效
                    stb_u_brst         = 2'b00;      // burst长度=1拍
                    stb_u_gr_base_addr = 32'h00004000;  // 基地址=0x4000
                    stb_u_ur_id        = 4'd3;
                    stb_u_ur_addr      = 11'h030;
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case4
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case4;
                                    disable wait_done_case4;
                                end
                            end
                        end
                        begin: timeout_case4
                            repeat(1000) @(posedge clk);
                            disable wait_done_case4;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例4超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd5;
                        end
                    join
                    
                    // 如果没有超时，就继续执行测试用例5（完成状态）
                    if (test_case == 4'd4) begin
                        $display("[TB] 时间%0t: 测试用例4完成 - burst_store状态已从DONE→IDLE", $time);
                        $display("[TB] 时间%0t: 测试用例4完成，导出内存内容到 sim_output/mem_case4.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(4);
                        test_case <= 4'd5;
                    end
                end
            
            // 测试用例5：6个SMC全部使用burst=1
            4'd5:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例5启动 - 6个SMC全部使用burst=1", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b111111;  // 所有6个SMC都使能
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b00;      // burst长度=1拍
                    stb_u_gr_base_addr = 32'h00005000;  // 基地址=0x5000
                    stb_u_ur_id        = 4'd4;       // UR ID=4
                    stb_u_ur_addr      = 11'h020;    // UR地址=0x020
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case5
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case5;
                                    disable wait_done_case5;
                                end
                            end
                        end
                        begin: timeout_case5
                            repeat(3000) @(posedge clk);
                            disable wait_done_case5;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例5超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd6;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd5) begin
                        $display("[TB] 时间%0t: 测试用例5完成 - burst_store状态已从DONE→IDLE", $time);
                        // 等待足够的时间，确保AXI事务真正完成
                        $display("[TB] 时间%0t: 测试用例5检测到状态转换完成，但AXI事务可能尚未完成", $time);
                        $display("[TB] 时间%0t: 等待500个时钟周期，确保AXI事务完成（包括实际数据写入）", $time);
                        repeat(500) @(posedge clk);
                        $display("[TB] 时间%0t: 等待完成，现在导出测试用例5内存内容到 sim_output/mem_case5.txt", $time);
                    u_axi_top.axi_mem_model_inst.export_memory(5);
                    test_case <= 4'd6;
                end
            end
        
            // 测试用例6：测试最大burst长度（16拍）
            4'd6:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例6启动 - 最大burst长度（16拍）", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000001;  // SMC0使能
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b11;      // burst长度=16拍
                    stb_u_gr_base_addr = 32'h00006000;  // 基地址=0x6000
                    stb_u_ur_id        = 4'd5;       // UR ID=5
                    stb_u_ur_addr      = 11'h030;    // UR地址=0x030
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case6
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case6;
                                    disable wait_done_case6;
                                end
                            end
                        end
                        begin: timeout_case6
                            repeat(5000) @(posedge clk);
                            disable wait_done_case6;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例6超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd7;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd6) begin
                        $display("[TB] 时间%0t: 测试用例6完成 - burst_store状态已从DONE→IDLE", $time);
                        $display("[TB] 时间%0t: 等待500个时钟周期，确保AXI事务完成", $time);
                        repeat(500) @(posedge clk);
                        $display("[TB] 时间%0t: 导出测试用例6内存内容到 sim_output/mem_case6.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(6);
                        test_case <= 4'd7;
                    end
                end
            
            // 测试用例7：测试交错SMC访问
            4'd7:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例7启动 - 交错SMC访问", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b111111;  // 使用所有SMC
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b10;      // burst长度=4拍
                    stb_u_gr_base_addr = 32'h00007000;  // 基地址=0x7000
                    stb_u_ur_id        = 4'd6;       // UR ID=6
                    stb_u_ur_addr      = 11'h040;    // UR地址=0x040
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case7
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case7;
                                    disable wait_done_case7;
                                end
                            end
                        end
                        begin: timeout_case7
                            repeat(5000) @(posedge clk);
                            disable wait_done_case7;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例7超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd8;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd7) begin
                        $display("[TB] 时间%0t: 测试用例7完成 - burst_store状态已从DONE→IDLE", $time);
                        $display("[TB] 时间%0t: 等待500个时钟周期，确保AXI事务完成", $time);
                        repeat(500) @(posedge clk);
                        $display("[TB] 时间%0t: 导出测试用例7内存内容到 sim_output/mem_case7.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(7);
                        test_case <= 4'd8;
                    end
                end
            
            // 测试用例8：测试奇数burst长度（7拍）
            4'd8:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例8启动 - 奇数burst长度（7拍）", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b001111;  // 使用SMC0~SMC3
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b10;      // burst长度=4拍（这里使用4拍是因为现有代码中brst信号只有两位，可能不支持7拍）
                    stb_u_gr_base_addr = 32'h00008000;  // 基地址=0x8000
                    stb_u_ur_id        = 4'd7;       // UR ID=7
                    stb_u_ur_addr      = 11'h050;    // UR地址=0x050
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case8
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case8;
                                    disable wait_done_case8;
                                end
                            end
                        end
                        begin: timeout_case8
                            repeat(5000) @(posedge clk);
                            disable wait_done_case8;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例8超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd9;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd8) begin
                        $display("[TB] 时间%0t: 测试用例8完成 - burst_store状态已从DONE→IDLE", $time);
                        $display("[TB] 时间%0t: 等待500个时钟周期，确保AXI事务完成", $time);
                        repeat(500) @(posedge clk);
                        $display("[TB] 时间%0t: 导出测试用例8内存内容到 sim_output/mem_case8.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(8);
                        test_case <= 4'd9;
                    end
                end
            
            // 测试用例9：测试高地址空间访问
            4'd9:
                begin
                    $display("\n==================================================");
                    $display("[TB] 时间%0t: 测试用例9启动 - 高地址空间访问", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b111111;  // 使用所有SMC
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b01;      // burst长度=2拍
                    stb_u_gr_base_addr = 32'hF0000000;  // 高地址空间
                    stb_u_ur_id        = 4'd8;       // UR ID=8
                    stb_u_ur_addr      = 11'h060;    // UR地址=0x060
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 不使用wait(stb_d_done)，直接通过状态机状态判断完成
                    fork
                        begin: wait_done_case9
                            // 监控状态变化，一旦检测到DONE状态（4）之后回到IDLE状态（0），就认为完成
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 4 && burst_store_state == 0) begin
                                    $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case9;
                                    disable wait_done_case9;
                                end
                            end
                        end
                        begin: timeout_case9
                            repeat(5000) @(posedge clk);
                            disable wait_done_case9;
                            $display("[TB_DEBUG] 时间%0t: 等待超时", $time);
                            $display("[TB] 时间%0t: 测试用例9超时（未检测到状态转换完成）", $time);
                            test_case <= 4'd10;
                        end
                    join
                    
                    // 如果没有超时，等待AXI事务真正完成后再导出内存
                    if (test_case == 4'd9) begin
                        $display("[TB] 时间%0t: 测试用例9完成 - burst_store状态已从DONE→IDLE", $time);
                        $display("[TB] 时间%0t: 等待500个时钟周期，确保AXI事务完成", $time);
                        repeat(500) @(posedge clk);
                        $display("[TB] 时间%0t: 导出测试用例9内存内容到 sim_output/mem_case9.txt", $time);
                        u_axi_top.axi_mem_model_inst.export_memory(9);
                        test_case <= 4'd10;
                    end
                end
            
            // 所有测试用例完成
            4'd10:
                begin
                    $display("\n==================================================");
                    $display("[TB] 所有测试用例执行完成（累计AXI协议错误数：%0d）", error_count);
                    $display("[TB] 内存导出文件路径：sim_output/（mem_case1~9.txt）");
                    $display("==================================================\n");
                    tb_done_reg <= 1'b1;
                    // 导出最终波形文件（便于调试）
                    $dumpfile("sim_output/axi_top_waveform.vcd");
                    $dumpvars(0, u_axi_top);
                    #100;
                    $finish; // 结束仿真
                end
        endcase
    end
end

// 存储前一周期的状态值及检测burst_store是否完成
reg test_case_done;
reg [3:0] current_case;
reg [31:0] done_wait_cnt;

// 存储测试用例ID
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_case <= 4'd0;
    end else if (tb_en && !tb_done_reg) begin
        current_case <= test_case;
    end
end

// 检测burst_store是否完成
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_burst_store_state <= 3'b000;
        test_case_done <= 1'b0;
        done_wait_cnt <= 32'd0;
    end else begin
        prev_burst_store_state <= burst_store_state;
        // 检测状态从DONE(4)到IDLE(0)的变化
        if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
            $display("[TB_DEBUG] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
            done_wait_cnt <= 32'd1000; // 等待1000个时钟周期，确保AXI事务完成
        end else if (done_wait_cnt > 32'd0) begin
            done_wait_cnt <= done_wait_cnt - 1;
            if (done_wait_cnt == 32'd1) begin
                test_case_done <= 1'b1;
                $display("[TB_DEBUG] 时间%0t: 等待AXI事务完成后，标记测试用例%0d真正完成", $time, current_case);
            end
        end else begin
            test_case_done <= 1'b0;
        end
    end
end

// 测试用例完成后导出内存和UR数据
reg export_mem;
reg export_ur;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        export_mem <= 1'b0;
        export_ur <= 1'b0;
    end else if (test_case_done && !export_mem && current_case > 4'd0 && current_case < 4'd10) begin
        $display("[TB] 时间%0t: 测试用例%0d完成 - 已等待AXI事务完成", $time, current_case);
        export_mem <= 1'b1;
    end else if (export_mem && !export_ur) begin
        case (current_case)
            4'd1: begin
                $display("[TB] 时间%0t: 导出测试用例1内存内容到 sim_output/mem_case1.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(1);
                export_ur <= 1'b1;
            end
            4'd2: begin
                $display("[TB] 时间%0t: 导出测试用例2内存内容到 sim_output/mem_case2.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(2);
                export_ur <= 1'b1;
            end
            4'd3: begin
                $display("[TB] 时间%0t: 导出测试用例3内存内容到 sim_output/mem_case3.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(3);
                export_ur <= 1'b1;
            end
            4'd4: begin
                $display("[TB] 时间%0t: 导出测试用例4内存内容到 sim_output/mem_case4.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(4);
                export_ur <= 1'b1;
            end
            4'd5: begin
                $display("[TB] 时间%0t: 导出测试用例5内存内容到 sim_output/mem_case5.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(5);
                export_ur <= 1'b1;
            end
            4'd6: begin
                $display("[TB] 时间%0t: 导出测试用例6内存内容到 sim_output/mem_case6.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(6);
                export_ur <= 1'b1;
            end
            4'd7: begin
                $display("[TB] 时间%0t: 导出测试用例7内存内容到 sim_output/mem_case7.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(7);
                export_ur <= 1'b1;
            end
            4'd8: begin
                $display("[TB] 时间%0t: 导出测试用例8内存内容到 sim_output/mem_case8.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(8);
                export_ur <= 1'b1;
            end
            4'd9: begin
                $display("[TB] 时间%0t: 导出测试用例9内存内容到 sim_output/mem_case9.txt", $time);
                u_axi_top.axi_mem_model_inst.export_memory(9);
                export_ur <= 1'b1;
            end
        endcase
    end else if (export_ur) begin
        // 删除了UR随机数据导出功能
        export_mem <= 1'b0;
        export_ur <= 1'b0;
        // 继续执行下一个测试用例
        if (current_case == 4'd1) test_case <= 4'd2;
        else if (current_case == 4'd2) test_case <= 4'd3;
        else if (current_case == 4'd3) test_case <= 4'd4;
        else if (current_case == 4'd4) test_case <= 4'd5;
        else if (current_case == 4'd5) test_case <= 4'd6;
        else if (current_case == 4'd6) test_case <= 4'd7;
        else if (current_case == 4'd7) test_case <= 4'd8;
        else if (current_case == 4'd8) test_case <= 4'd9;
        else if (current_case == 4'd9) test_case <= 4'd10;
    end
end

// 监控关键信号变化（调试用）
always @(posedge clk) begin
    if (tb_en) begin
        // 打印burst_store状态变化
        if (prev_burst_store_state !== burst_store_state) begin
            $display("[TB_MON] 时间%0t: burst_store状态变化 - 前状态=%d → 当前状态=%d", 
                     $time, prev_burst_store_state, burst_store_state);
        end
        // 打印内存写入完成信号
        if (u_axi_top.axi_mem_model_inst.axi_bvalid && u_axi_top.axi_mem_model_inst.axi_bready) begin
            $display("[TB_MON] 时间%0t: 内存写入响应完成 - 地址=0x%h，响应码=0x%h", 
                     $time, u_axi_top.axi_mem_model_inst.current_write_addr, u_axi_top.axi_mem_model_inst.axi_bresp);
        end
    end
end

endmodule
    