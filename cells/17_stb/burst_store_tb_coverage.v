`timescale 1ns/1ps
// 增强型测试平台：提高axi_stb、axi_stb_s和burst_store模块的覆盖率
module burst_store_tb_coverage #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter SMC_COUNT = 6
)(
    input                   clk,
    input                   rst_n,
    input                   tb_en,
    output                  tb_done
);

// STB接口信号声明
reg                      stb_u_valid;
reg [SMC_COUNT-1:0]      stb_u_smc_strb;
reg [3:0]                stb_u_byte_strb;
reg [1:0]                stb_u_brst;
reg [ADDR_WIDTH-1:0]     stb_u_gr_base_addr;
reg [3:0]                stb_u_ur_id;
reg [10:0]               stb_u_ur_addr;
wire                     stb_d_valid;
wire                     stb_d_done;
reg                      stb_d_ready;
wire                     protocol_error;
wire [3:0]               error_code;

// 错误注入控制信号（reg类型，可在always块中赋值）
reg                      ur_err_inject;
reg [3:0]                ur_err_type;
reg [10:0]               ur_err_addr_mask;

// 内部信号
reg [31:0] cycle_count;
reg [3:0] test_case;
reg [31:0] error_count;
reg        tb_done_reg;
wire [2:0] burst_store_state;
reg [2:0] prev_burst_store_state;

// 随机测试相关信号
reg [31:0] random_test_count;
reg [31:0] random_seed;

// 输出赋值
assign tb_done = tb_done_reg;

// 时钟与复位生成
reg clk_gen;
reg rst_n_gen;
reg tb_en_gen;
initial begin
    clk_gen = 0;
    rst_n_gen = 0;
    tb_en_gen = 0;
    random_seed = 32'd123456789;
    
    // 复位序列
    #100;
    rst_n_gen = 1;
    $display("[TB_COVERAGE] 时间%0t: 复位释放，准备启动测试", $time);
    
    // 启动测试
    #100;
    tb_en_gen = 1;
    $display("[TB_COVERAGE] 时间%0t: tb_en置1，开始执行覆盖率增强测试用例", $time);
    
    // 仿真超时保护 - 增加到20ms，确保有足够时间执行增强型测试
    #20000000;  // 20ms
    $display("[TB_COVERAGE] 时间%0t: 仿真超时（20ms），强制结束", $time);
    $finish;
end

// 50MHz时钟
always #10 clk_gen = ~clk_gen;

// 信号连接
assign clk = clk_gen;
assign rst_n = rst_n_gen;
assign tb_en = tb_en_gen;

// 实例化顶层模块
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
    
    // 错误注入控制连接
    .ur_err_inject(ur_err_inject),
    .ur_err_type(ur_err_type),
    .ur_err_addr_mask(ur_err_addr_mask),
    .stb_d_ready(stb_d_ready),
    
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
        $display("[TB_COVERAGE_ERROR] 时间%0t: 检测到AXI协议错误，错误码=0x%h（累计错误数=%0d）", 
                 $time, error_code, error_count + 1);
    end
end

// 存储前一周期的状态值
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_burst_store_state <= 3'b000;
    end else begin
        prev_burst_store_state <= burst_store_state;
    end
end

// 测试用例执行（增强型覆盖率测试）
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
        stb_d_ready <= 1'b1; // 始终准备接收完成信号
        tb_done_reg <= 1'b0;
        test_case <= 4'd0;
        random_test_count <= 32'd0;
    end else if (tb_en && !tb_done_reg) begin
        case (test_case)
            4'd0:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试初始化完成，准备执行覆盖率增强测试", $time);
                    $display("==================================================\n");
                    test_case <= 4'd1;
                end
            
            // 测试用例1：基本功能测试
            4'd1:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例1 - 基本功能测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000001;  // SMC0使能
                    stb_u_byte_strb    = 4'h0;       // 全字节有效
                    stb_u_brst         = 2'b00;      // burst长度=1拍
                    stb_u_gr_base_addr = 32'h00001000;
                    stb_u_ur_id        = 4'd0;
                    stb_u_ur_addr      = 11'h000;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    $display("[TB_COVERAGE] 时间%0t: 等待burst_store指令完成", $time);
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case1
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case1;
                                    disable wait_done_case1;
                                end
                            end
                        end
                        begin: timeout_case1
                            repeat(1000) @(posedge clk);
                            disable wait_done_case1;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例1超时", $time);
                            test_case <= 4'd2;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd1) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例1完成", $time);
                        test_case <= 4'd2;
                    end
                end
            
            // 测试用例2：多拍burst测试
            4'd2:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例2 - 多拍burst测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000010;  // SMC1使能
                    stb_u_byte_strb    = 4'h0;
                    stb_u_brst         = 2'b10;      // burst长度=4拍
                    stb_u_gr_base_addr = 32'h00002000;
                    stb_u_ur_id        = 4'd1;
                    stb_u_ur_addr      = 11'h010;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case2
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case2;
                                    disable wait_done_case2;
                                end
                            end
                        end
                        begin: timeout_case2
                            repeat(2000) @(posedge clk);
                            disable wait_done_case2;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例2超时", $time);
                            test_case <= 4'd3;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd2) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例2完成", $time);
                        test_case <= 4'd3;
                    end
                end
            
            // 测试用例3：多SMC测试
            4'd3:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例3 - 多SMC测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000111;  // SMC0~SMC2使能
                    stb_u_byte_strb    = 4'h0;
                    stb_u_brst         = 2'b01;      // burst长度=2拍
                    stb_u_gr_base_addr = 32'h00003000;
                    stb_u_ur_id        = 4'd2;
                    stb_u_ur_addr      = 11'h020;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case3
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case3;
                                    disable wait_done_case3;
                                end
                            end
                        end
                        begin: timeout_case3
                            repeat(3000) @(posedge clk);
                            disable wait_done_case3;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例3超时", $time);
                            test_case <= 4'd4;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd3) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例3完成", $time);
                        test_case <= 4'd4;
                    end
                end
            
            // 测试用例4：部分字节写入测试
            4'd4:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例4 - 部分字节写入测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000001;  // SMC0使能
                    stb_u_byte_strb    = 4'h3;       // 低2字节有效
                    stb_u_brst         = 2'b00;
                    stb_u_gr_base_addr = 32'h00004000;
                    stb_u_ur_id        = 4'd3;
                    stb_u_ur_addr      = 11'h030;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case4
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case4;
                                    disable wait_done_case4;
                                end
                            end
                        end
                        begin: timeout_case4
                            repeat(1000) @(posedge clk);
                            disable wait_done_case4;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例4超时", $time);
                            test_case <= 4'd5;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd4) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例4完成", $time);
                        test_case <= 4'd5;
                    end
                end
            
            // 测试用例5：全SMC测试
            4'd5:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例5 - 全SMC测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b111111;  // 所有SMC使能
                    stb_u_byte_strb    = 4'h0;
                    stb_u_brst         = 2'b00;
                    stb_u_gr_base_addr = 32'h00005000;
                    stb_u_ur_id        = 4'd4;
                    stb_u_ur_addr      = 11'h040;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case5
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case5;
                                    disable wait_done_case5;
                                end
                            end
                        end
                        begin: timeout_case5
                            repeat(3000) @(posedge clk);
                            disable wait_done_case5;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例5超时", $time);
                            test_case <= 4'd6;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd5) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例5完成", $time);
                        test_case <= 4'd6;
                    end
                end
            
            // 测试用例6：最大burst长度测试
            4'd6:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例6 - 最大burst长度测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b000001;
                    stb_u_byte_strb    = 4'h0;
                    stb_u_brst         = 2'b11;      // burst长度=16拍
                    stb_u_gr_base_addr = 32'h00006000;
                    stb_u_ur_id        = 4'd5;
                    stb_u_ur_addr      = 11'h050;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case6
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case6;
                                    disable wait_done_case6;
                                end
                            end
                        end
                        begin: timeout_case6
                            repeat(5000) @(posedge clk);
                            disable wait_done_case6;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例6超时", $time);
                            test_case <= 4'd7;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd6) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例6完成", $time);
                        test_case <= 4'd7;
                    end
                end
            
            // 测试用例7：高地址访问测试
            4'd7:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例7 - 高地址访问测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b111111;
                    stb_u_byte_strb    = 4'h0;
                    stb_u_brst         = 2'b01;
                    stb_u_gr_base_addr = 32'hF0000000;
                    stb_u_ur_id        = 4'd6;
                    stb_u_ur_addr      = 11'h060;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case7
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case7;
                                    disable wait_done_case7;
                                end
                            end
                        end
                        begin: timeout_case7
                            repeat(3000) @(posedge clk);
                            disable wait_done_case7;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例7超时", $time);
                            test_case <= 4'd8;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd7) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例7完成", $time);
                        test_case <= 4'd8;
                    end
                end
            
            // 测试用例8：交错访问测试
            4'd8:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例8 - 交错访问测试", $time);
                    $display("==================================================\n");
                    stb_u_valid        = 1'b1;
                    stb_u_smc_strb     = 6'b111111;
                    stb_u_byte_strb    = 4'h0;
                    stb_u_brst         = 2'b10;
                    stb_u_gr_base_addr = 32'h00007000;
                    stb_u_ur_id        = 4'd7;
                    stb_u_ur_addr      = 11'h070;
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case8
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case8;
                                    disable wait_done_case8;
                                end
                            end
                        end
                        begin: timeout_case8
                            repeat(5000) @(posedge clk);
                            disable wait_done_case8;
                            $display("[TB_COVERAGE] 时间%0t: 测试用例8超时", $time);
                            test_case <= 4'd9;
                        end
                    join
                    
                    // 如果没有超时，继续执行下一个测试用例
                    if (test_case == 4'd8) begin
                        $display("[TB_COVERAGE] 时间%0t: 测试用例8完成", $time);
                        test_case <= 4'd9;
                    end
                end
            
            // 测试用例9：随机测试（新增）
            4'd9:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例9 - 随机测试（测试次数: %0d）", $time, random_test_count + 1);
                    $display("==================================================\n");
                    
                    // 更新随机种子
                    random_seed = {$random(random_seed)};
                    
                    // 增强型随机测试策略
                    stb_u_valid        = 1'b1;
                    
                    // 策略1: 前1000次集中测试边界条件
                    if (random_test_count < 1000) begin
                        case (random_test_count % 10)
                            0: begin
                                // 测试最小burst长度
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = 2'b00;  // burst长度=1拍
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            1: begin
                                // 测试最大burst长度
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = 2'b11;  // burst长度=16拍
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            2: begin
                                // 测试最低地址
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = 32'h00000000;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = 11'h000;
                            end
                            3: begin
                                // 测试最高地址
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = 11'h7FF;
                            end
                            4: begin
                                // 测试特定SMC组合 - 针对burst_store模块
                                stb_u_smc_strb     = 6'b000001;  // 仅SMC0
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            5: begin
                                // 测试特定SMC组合 - 针对burst_store模块
                                stb_u_smc_strb     = 6'b111111;  // 所有SMC
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            6: begin
                                // 测试特定SMC组合 - 针对burst_store模块
                                stb_u_smc_strb     = 6'b010101;  // 间隔SMC
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            7: begin
                                // 测试特殊字节使能 - 针对axi_stb模块
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = 4'hF;  // 全字节使能
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            8: begin
                                // 测试特殊字节使能 - 针对axi_stb模块
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = 4'h3;  // 低2字节使能
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                            9: begin
                                // 测试特定ID - 针对axi_stb_s模块
                                stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                                stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                                stb_u_brst         = {$random(random_seed)} & 2'b11;
                                stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                                stb_u_ur_id        = 4'd0;  // 最小ID
                                stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                            end
                        endcase
                    end
                    // 策略2: 后1500次使用正常随机测试，但增加参数多样性
                    else begin
                        stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                        stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                        
                        // 增加大burst长度的概率
                        if ($random(random_seed) % 3 == 0) begin
                            stb_u_brst = 2'b11;  // 优先选择最大burst长度
                        end else begin
                            stb_u_brst = {$random(random_seed)} & 2'b11;
                        end
                        
                        stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                        stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                        stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                    end
                    
                    // 确保至少有一个SMC被使能
                    if (stb_u_smc_strb == 0) begin
                        stb_u_smc_strb = 1 << ({$random(random_seed)} % SMC_COUNT);
                    end
                    
                    $display("[TB_COVERAGE] 时间%0t: 随机参数配置 - SMC_STRB=0x%h, BYTE_STRB=0x%h, BRST=0x%h, BASE_ADDR=0x%h",
                             $time, stb_u_smc_strb, stb_u_byte_strb, stb_u_brst, stb_u_gr_base_addr);
                    
                    @(posedge clk);
                    stb_u_valid        = 1'b0;
                    
                    // 等待burst_store完成
                    fork
                        begin: wait_done_case9
                            while (1) begin
                                @(posedge clk);
                                if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                    $display("[TB_COVERAGE] 时间%0t: 检测到burst_store已完成（状态从4→0）", $time);
                                    disable timeout_case9;
                                    disable wait_done_case9;
                                end
                            end
                        end
                        begin: timeout_case9
                            repeat(5000) @(posedge clk);
                            disable wait_done_case9;
                            $display("[TB_COVERAGE] 时间%0t: 随机测试超时", $time);
                            random_test_count <= random_test_count + 1;
                            // 执行2001次随机测试
                            if (random_test_count >= 2000) begin
                                test_case <= 4'd10;
                            end else begin
                                // 短暂延迟后继续下一次随机测试
                                repeat(100) @(posedge clk);
                                test_case <= 4'd9;
                            end
                        end
                    join
                    
                    // 如果没有超时，继续执行下一次随机测试或结束
                    if (test_case == 4'd9) begin
                        $display("[TB_COVERAGE] 时间%0t: 随机测试完成", $time);
                        random_test_count <= random_test_count + 1;
                        
                        // 执行3000次随机测试，增加次数提高覆盖率
                        if (random_test_count >= 2999) begin
                            test_case <= 4'd10;
                        end else begin
                            // 短暂延迟后继续下一次随机测试
                            repeat(100) @(posedge clk);
                            test_case <= 4'd9;
                        end
                    end
                end
            
            // 测试用例10：错误注入测试
            4'd10:
                begin
                    integer err_count;
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例10 - 错误注入测试", $time);
                    $display("==================================================\n");
                    
                    // 错误注入配置
                    for (err_count = 0; err_count < 1000; err_count = err_count + 1) begin
                        // 随机配置错误注入
                        logic [3:0] err_type = {$random(random_seed)} & 4'b1111;
                        logic [10:0] err_addr_mask = {$random(random_seed)} & 11'b11111111111;
                        
                        // 配置错误注入信号
                          ur_err_inject = 1'b1;
                          ur_err_type = err_type;
                          ur_err_addr_mask = err_addr_mask;
                        
                        $display("[TB_COVERAGE] 时间%0t: 错误注入配置 - 类型=0x%h, 地址掩码=0x%h", 
                                 $time, err_type, err_addr_mask);
                        
                        // 等待错误注入生效
                        repeat(5) @(posedge clk);
                        ur_err_inject = 1'b0;
                        
                        // 发送随机事务触发可能的错误
                        stb_u_valid        = 1'b1;
                        stb_u_smc_strb     = {$random(random_seed)} & {SMC_COUNT{1'b1}};
                        if (stb_u_smc_strb == 0) begin
                            stb_u_smc_strb = 1 << ({$random(random_seed)} % SMC_COUNT);
                        end
                        stb_u_byte_strb    = {$random(random_seed)} & 4'b1111;
                        stb_u_brst         = {$random(random_seed)} & 2'b11;
                        stb_u_gr_base_addr = {$random(random_seed)} & 32'h0007F800;
                        stb_u_ur_id        = {$random(random_seed)} & 4'b1111;
                        stb_u_ur_addr      = {$random(random_seed)} & 11'b11111111111;
                        
                        @(posedge clk);
                        stb_u_valid        = 1'b0;
                        
                        // 等待事务完成
                        fork
                            begin: wait_done_case10
                                while (1) begin
                                    @(posedge clk);
                                    if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                        disable timeout_case10;
                                        disable wait_done_case10;
                                    end
                                end
                            end
                            begin: timeout_case10
                                repeat(5000) @(posedge clk);
                                disable wait_done_case10;
                                $display("[TB_COVERAGE] 时间%0t: 错误注入测试超时", $time);
                            end
                        join
                        
                        // 短暂延迟
                        repeat(100) @(posedge clk);
                    end
                    
                    $display("[TB_COVERAGE] 时间%0t: 测试用例10完成", $time);
                    test_case <= 4'd11;
                end
            
            // 测试用例11：并发访问测试
            4'd11:
                begin
                    integer concurrent_count;
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 测试用例11 - 并发访问测试", $time);
                    $display("==================================================\n");
                    

                    for (concurrent_count = 0; concurrent_count < 5; concurrent_count = concurrent_count + 1) begin
                        $display("[TB_COVERAGE] 时间%0t: 并发测试轮次 %0d", $time, concurrent_count + 1);
                        
                        // 同时发送4个不同ID的事务
                        fork
                            begin
                                stb_u_valid        = 1'b1;
                                stb_u_smc_strb     = 6'b000001;
                                stb_u_byte_strb    = 4'h0;
                                stb_u_brst         = 2'b01;
                                stb_u_gr_base_addr = 32'h00010000;
                                stb_u_ur_id        = 4'd0;
                                stb_u_ur_addr      = 11'h080;
                                
                                @(posedge clk);
                                stb_u_valid        = 1'b0;
                            end
                            begin
                                #1;
                                stb_u_valid        = 1'b1;
                                stb_u_smc_strb     = 6'b000010;
                                stb_u_byte_strb    = 4'h0;
                                stb_u_brst         = 2'b10;
                                stb_u_gr_base_addr = 32'h00020000;
                                stb_u_ur_id        = 4'd1;
                                stb_u_ur_addr      = 11'h090;
                                
                                @(posedge clk);
                                stb_u_valid        = 1'b0;
                            end
                            begin
                                #2;
                                stb_u_valid        = 1'b1;
                                stb_u_smc_strb     = 6'b000100;
                                stb_u_byte_strb    = 4'h0;
                                stb_u_brst         = 2'b11;
                                stb_u_gr_base_addr = 32'h00030000;
                                stb_u_ur_id        = 4'd2;
                                stb_u_ur_addr      = 11'h0A0;
                                
                                @(posedge clk);
                                stb_u_valid        = 1'b0;
                            end
                            begin
                                #3;
                                stb_u_valid        = 1'b1;
                                stb_u_smc_strb     = 6'b001000;
                                stb_u_byte_strb    = 4'h0;
                                stb_u_brst         = 2'b00;
                                stb_u_gr_base_addr = 32'h00040000;
                                stb_u_ur_id        = 4'd3;
                                stb_u_ur_addr      = 11'h0B0;
                                
                                @(posedge clk);
                                stb_u_valid        = 1'b0;
                            end
                        join
                        
                        // 等待所有事务完成
                        fork
                            begin: wait_all_done
                                integer txn_done_count = 0;
                                while (txn_done_count < 4) begin
                                    @(posedge clk);
                                    if (prev_burst_store_state == 3'd4 && burst_store_state == 3'd0) begin
                                        // 每次完成一个事务就增加计数器
                                        txn_done_count = txn_done_count + 1;
                                    end
                                end
                                disable timeout_all_done;
                            end
                            begin: timeout_all_done
                                repeat(20000) @(posedge clk);
                                $display("[TB_COVERAGE] 时间%0t: 并发测试超时", $time);
                            end
                        join
                        
                        // 短暂延迟
                        repeat(500) @(posedge clk);
                    end
                    
                    $display("[TB_COVERAGE] 时间%0t: 测试用例11完成", $time);
                    test_case <= 4'd12;
                end
            
            // 所有测试用例完成
            4'd12:
                begin
                    $display("\n==================================================");
                    $display("[TB_COVERAGE] 时间%0t: 覆盖率增强测试所有用例已执行完毕", $time);
                    $display("累计协议错误数: %0d", error_count);
                    $display("==================================================\n");
                    
                    // 等待一段时间，确保所有事务完成
                    repeat(1000) @(posedge clk);
                    
                    // 结束测试
                    tb_done_reg <= 1'b1;
                    $finish;
                end
        endcase
    end
end

// 监控关键信号变化（调试用）
always @(posedge clk) begin
    if (tb_en) begin
        // 打印burst_store状态变化
        if (prev_burst_store_state !== burst_store_state) begin
            $display("[TB_COVERAGE_MON] 时间%0t: burst_store状态变化 - 前状态=%d → 当前状态=%d", 
                     $time, prev_burst_store_state, burst_store_state);
            $display("[TB_COVERAGE_MON] 时间%0t: stb_d_ready=%b, stb_d_valid=%b, stb_d_done=%b",
                     $time, stb_d_ready, stb_d_valid, stb_d_done);
        end
        
        // 监控stb_d信号变化
        if (stb_d_valid || stb_d_done) begin
            $display("[TB_COVERAGE_MON] 时间%0t: 检测到stb_d信号 - stb_d_valid=%b, stb_d_done=%b, stb_d_ready=%b", 
                     $time, stb_d_valid, stb_d_done, stb_d_ready);
        end
        
        // 监控axi_stb状态
        if (u_axi_top.axi_stb_inst.state !== u_axi_top.axi_stb_inst.state) begin
            $display("[TB_COVERAGE_MON] 时间%0t: axi_stb状态变化", $time);
        end
        
        // 监控axi_stb_s状态
        if (u_axi_top.axi_stb_s_inst.state !== u_axi_top.axi_stb_s_inst.state) begin
            $display("[TB_COVERAGE_MON] 时间%0t: axi_stb_s状态变化", $time);
        end
    end
end

endmodule