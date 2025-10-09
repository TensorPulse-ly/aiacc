`timescale 1ns/1ps

`default_nettype none

module tb_ldb;

// 时钟 / 复位
reg clk = 0;
always #5 clk = ~clk;

reg rst_n = 0;
initial #15 rst_n = 1;

// LDB 指令接口
reg [127:0] cru_ldb_i_reg = 128'b0;
wire [127:0] cru_ldb_i = cru_ldb_i_reg;
reg [1:0] crd_ldb_i_reg = 2'b11; // 初始化为 {vld=1, done=1}
wire [1:0] crd_ldb_i = crd_ldb_i_reg;

// UR监控信号
wire ur_we;
wire [10:0] ur_addr;
wire [127:0] ur_wdata;

axi_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .cru_ldb_i(cru_ldb_i),
    .crd_ldb_i(crd_ldb_i),
    .cru_ldb_o(),
    .crd_ldb_o(),
    .ur_we(ur_we),
    .ur_addr(ur_addr),
    .ur_wdata(ur_wdata)
);

// 内存初始化
initial begin
    integer i;
    reg [31:0] temp_addr;
    
    // 等待复位完成
    @(posedge rst_n);
    repeat(50) @(posedge clk);
    
    // 初始化内存数据模式
    $display("初始化内存数据模式...");
    for (i = 0; i < 1024; i = i + 1) begin
        temp_addr = i * 16;
        dut.u_axi_slave.mem[i] = {
            32'hDEAD_BEEF, // 固定前缀
            temp_addr,     // 地址信息
            32'hCAFE_BABE, // 固定中缀
            temp_addr + 32'd1 // 地址+1信息
        };
    end
    $display("内存初始化完成");
end

// 监控UR写入
initial begin
    forever begin
        @(posedge clk);
        if (ur_we) begin
            $display("[UR_WRITE] time=%0t: addr=%h, data=%h", 
                     $time, ur_addr, ur_wdata);
        end
    end
end

task automatic send_ldb_packet(
    input [63:0] gr_base_addr,
    input [15:0] brst,
    input [3:0] byte_strb,
    input [5:0] smc_strb,
    input [7:0] ur_id,
    input [10:0] ur_addr
);
    begin
        // 等待LDB进入IDLE状态
        wait_ldb_idle();
        
        // 构造指令包 - 使用新的位布局
        cru_ldb_i_reg = {
            1'b1,           // valid [127]
            smc_strb,       // smc_strb [126:121]
            byte_strb,      // byte_strb [120:117]
            brst,           // burst length [116:101]
            gr_base_addr,   // global base address [100:37] (64位)
            ur_id,          // ur_id [36:29]
            ur_addr,        // ur_addr [28:18]
            18'b0           // reserved [17:0]
        };
        
        $display("[LDB_PACKET] time=%0t: Sent: brst=%d, byte_strb=%h, smc_strb=%b, gr_base_addr=%h",
                 $time, brst, byte_strb, smc_strb, gr_base_addr);
    end
endtask

task automatic clear_ldb_packet;
    cru_ldb_i_reg[127] = 1'b0;
    $display("[LDB_PACKET] time=%0t: Cleared instruction packet", $time);
endtask

task automatic wait_ldb_idle;
    integer timeout;
    timeout = 0;
    
    // 等待 LDB 进入 IDLE 状态
    while (dut.u_ldb.state_q != dut.u_ldb.IDLE && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
        
        // 添加调试信息
        if (timeout % 10 == 0) begin
            $display("[WAIT_IDLE] time=%0t: 当前状态=%s, 超时计数=%d",
                $time, dut.u_ldb.state2str(dut.u_ldb.state_q), timeout);
        end
    end
    
    if (timeout >= 100) begin
        $display("等待LDB空闲超时");
        // 强制清除指令包，尝试恢复
        clear_ldb_packet();
    end else begin
        $display("LDB已进入IDLE状态");
    end
endtask

task automatic wait_ldb_done;
    integer timeout;
    timeout = 0;
    
    // 等待 LDB 返回 IDLE 状态
    while (dut.u_ldb.state_q != dut.u_ldb.IDLE && timeout < 1000) begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    
    if (timeout >= 1000) begin
        $display("等待LDB完成超时");
    end else begin
        $display("LDB已完成处理，返回IDLE状态");
    end
endtask
/*
// 全流程测试任务
task automatic test_full_integration;
    $display("==================== 开始全流程集成测试 ====================");
    
    // 测试1: 单beat传输，全字节使能
    $display("测试1: 单beat传输，全字节使能");
    send_ldb_packet(
        64'h0000,   // gr_base_addr
        16'd2,      // brst = 1 beat
        4'h0,       // 全字节使能
        6'b000001,  // smc_strb = SMC0 enabled
        8'd1,       // ur_id
        11'd0       // ur_addr
    );
    
    // 等待LDB处理完成
    wait_ldb_done();
    
    // 添加额外延迟以确保所有操作完成
    repeat(10) @(posedge clk);
    
    // 清除指令包
    clear_ldb_packet();
    
    // 添加间隔
    repeat(10) @(posedge clk);
    
    // 测试2: 多beat传输，全字节使能
    $display("测试2: 多beat传输, 全字节使能");
    send_ldb_packet(
        64'h0000,   // gr_base_addr
        16'd4,      // brst = 4 beats
        4'h0,       // 全字节使能
        6'b000001,  // smc_strb = SMC0 enabled
        8'd1,       // ur_id
        11'd10       // ur_addr
    );
    
    // 等待LDB处理完成
    wait_ldb_done();
    
    // 添加额外延迟以确保所有操作完成
    repeat(10) @(posedge clk);
    
    // 清除指令包
    clear_ldb_packet();
    
    $display("==================== 全流程集成测试完成 ====================");
endtask
*/
// 全流程测试任务
task automatic test_full_integration;
    $display("==================== 开始全流程集成测试 ====================");

    // 测试1: 单beat传输，全字节使能 (原有测试)
    $display("测试1: 单beat传输，全字节使能");
    send_ldb_packet(
        64'h0000,      // gr_base_addr
        16'd2,         // brst = 2 beats
        4'h0,          // 全字节使能
        6'b000001,     // smc_strb = SMC0 enabled
        8'd1,          // ur_id
        11'd0          // ur_addr
    );
    wait_ldb_done();
    repeat(10) @(posedge clk);
    clear_ldb_packet();
    repeat(10) @(posedge clk);

    // 测试2: 多beat传输，全字节使能 (原有测试)
    $display("测试2: 多beat传输, 全字节使能");
    send_ldb_packet(
        64'h0000,      // gr_base_addr
        16'd4,         // brst = 4 beats
        4'h0,          // 全字节使能
        6'b000001,     // smc_strb = SMC0 enabled
        8'd1,          // ur_id
        11'd10         // ur_addr
    );
    wait_ldb_done();
    repeat(10) @(posedge clk);
    clear_ldb_packet();
    repeat(10) @(posedge clk);

    // 新增测试: 使用循环测试所有字节使能模式
    $display("测试3: 测试所有字节使能模式");
    for (int i = 0; i < 16; i = i + 1) begin
        $display("测试字节使能模式: %h", i);
        send_ldb_packet(
            64'h0000,      // gr_base_addr
            16'd3,         // brst = 3 beats
            i[3:0],        // 当前字节使能模式
            6'b000001,     // smc_strb = SMC0 enabled
            8'd1,          // ur_id
            11'd20 + i*5   // ur_addr (递增以避免地址冲突)
        );
        wait_ldb_done();
        repeat(10) @(posedge clk);
        clear_ldb_packet();
        repeat(10) @(posedge clk);
    end

    $display("==================== 全流程集成测试完成 ====================");
endtask

// 主测试序列
initial begin
    @(posedge rst_n);
    repeat(50) @(posedge clk);
    
    $display("开始全流程LDB测试...");
    
    // 运行全流程集成测试
    test_full_integration;
    
    $display("所有全流程测试完成!");

    // 等待一段时间再结束仿真，确保所有操作完成
    repeat(100) @(posedge clk);
    $finish;
end

// 指定 VCD 文件名
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_ldb);
    // 添加LDB模块的所有信号
    $dumpvars(1, dut.u_ldb);
end

// 监控AXI事务
initial begin
    forever begin
        @(posedge clk);
        
        // 监控AXI地址通道
        if (dut.u_axi_master.arvalid && dut.u_axi_master.arready) begin
            $display("[AXI_AR] time=%0t: addr=%h, len=%d",
                     $time, dut.u_axi_master.araddr, dut.u_axi_master.arlen + 1);
        end
        
        // 监控AXI数据通道
        if (dut.u_axi_master.rvalid && dut.u_axi_master.rready) begin
            $display("[AXI_R] time=%0t: data=%h, last=%b",
                     $time, dut.u_axi_master.rdata, dut.u_axi_master.rlast);
        end
        
        // 监控LDB状态
        if (dut.u_ldb.state_q != dut.u_ldb.state_d) begin
            $display("[LDB_STATE] time=%0t: %s -> %s",
                     $time, 
                     dut.u_ldb.state2str(dut.u_ldb.state_q),
                     dut.u_ldb.state2str(dut.u_ldb.state_d));
        end
    end
end

endmodule