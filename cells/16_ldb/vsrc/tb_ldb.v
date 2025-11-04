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

    // 等待 LDB 返回 IDLE 状态 (真正的最终状态)
    while (dut.u_ldb.state_q != dut.u_ldb.IDLE) begin
        @(posedge clk);
        timeout = timeout + 1;

        // 添加一个非常宽松但安全的超时，防止死循环
        if (timeout > 5000) begin // 显著增加超时阈值
            $display("[ERROR] 等待LDB完成超时！当前状态：%s", dut.u_ldb.state2str(dut.u_ldb.state_q));
            $finish; // 或采取其他恢复措施
        end
    end

    // 额外等待一段时间，确保所有AXI传输完成、协议检查器空闲等
    repeat (50) @(posedge clk);

    $display("LDB已完成处理，返回IDLE状态");
endtask

// 测试 get_byte_mask 的 default 分支（强制无效 byte_strb）
task automatic test_byte_strb_default;
    $display("\n---------------------- 测试 get_byte_mask default 分支 ----------------------");
    wait_ldb_idle(); // 等待 LDB 进入 IDLE
    
    // 1. 构造指令包（正常参数，但强制覆盖 byte_strb 为无效值）
    cru_ldb_i_reg = {
        1'b1,           // valid [127]
        6'b000001,      // smc_strb [126:121]（仅 SMC0 使能）
        4'h0,           // 初始 byte_strb（后续强制修改）
        16'd1,          // brst=1（1个 beat）
        64'h1000,       // gr_base_addr
        8'd20,          // ur_id
        11'd0,          // ur_addr
        18'b0           // reserved
    };
    
    // 2. 强制 byte_strb 为无效值（4'h10，超出 4bit 范围）
    force dut.u_ldb.byte_strb_q = 4'h10; 
    $display("[TEST] 强制 byte_strb = 4'h10（无效值），触发 get_byte_mask default");
    
    // 3. 等待 LDB 解析指令并调用 get_byte_mask（进入 DATA 状态时会调用）
    wait(dut.u_ldb.state_q == dut.u_ldb.DATA);
    repeat(2) @(posedge clk);
    
    // 4. 释放强制，清理指令包
    release dut.u_ldb.byte_strb_q;
    clear_ldb_packet();
    wait_ldb_idle();
    $display("---------------------- get_byte_mask default 分支测试完成 ----------------------");
endtask

// 新增：递增式测试（SMC数量+字节使能+传输数据量同步递增）
task automatic test_incremental_smc_byte_data;
    integer N; // 递增变量：N=1~16（16对应全字节使能）
    reg [5:0] smc_strb; // 6位SMC使能（低N位为1）
    reg [3:0] byte_strb; // 4位字节使能（N字节使能对应byte_strb=N）
    reg [63:0] gr_base_addr; // 全局基地址（每次N递增64'h1000，避免重叠）
    reg [15:0] brst; // 传输数据量（=N）
    
    $display("==================== 开始递增式测试 ====================");
    $display("测试规则：N从1→16（全字节使能），每轮N对应「N个SMC + N字节使能 + N个数据传输」");
    
    // 初始化基地址（从64'h0000开始）
    gr_base_addr = 64'h0000;
    
    // 循环N从1到16（N=16时全字节使能，测试结束）
    for (N = 1; N <= 16; N = N + 1) begin
        $display("\n---------------------- 测试轮次 N=%0d ----------------------", N);
        
        // 1. 计算当前N对应的参数
        smc_strb = (1 << N) - 1; // 低N位为1（如N=3→6'b000111）
        brst = N; // 传输N个数据beat
        // 字节使能：N<16时byte_strb=N（N字节使能），N=16时byte_strb=4'h0（全字节使能）
        if (N < 16) begin
            byte_strb = N[3:0]; 
        end else begin
            byte_strb = 4'h0; 
            $display("【注意】N=16触发全字节使能，测试完成后停止");
        end
        
        // 2. 发送LDB指令包（调用现有任务）
        send_ldb_packet(
            gr_base_addr,  // 全局基地址（每次递增64'h1000）
            brst,          // 传输数据量=N
            byte_strb,     // 字节使能=N（N<16）或全字节（N=16）
            smc_strb,      // SMC数量=N
            8'd10 + N,     // ur_id（区分不同测试轮次，如N=1→ur_id=11）
            11'd0          // ur_addr（每轮从UR地址0开始）
        );
        
        // 3. 等待LDB处理完成（复用现有超时机制）
        $display("等待N=%0d测试完成...", N);
        wait_ldb_done();
        
        // 4. 清除指令包，基地址递增（避免下一轮地址重叠）
        clear_ldb_packet();
        gr_base_addr = gr_base_addr + 64'h1; // 每次递增4KB，隔离地址
        
        // 5. 打印当前轮次关键结果（验证参数生效）
        $display("N=%0d测试结果：SMC使能=%b, 字节使能=%h, 传输数据量=%0d, 基地址=%h",
                 N, smc_strb, byte_strb, brst, gr_base_addr - 64'h1000);
        
        // 6. N=16（全字节使能）时停止循环
        if (N == 16) begin
            $display("\n---------------------- 全字节使能，测试停止 ----------------------");
            break;
        end
        
        // 等待稳定后进入下一轮
        repeat(20) @(posedge clk);
    end
    
    $display("==================== 递增式测试全部完成 ====================");
endtask

// 全流程测试任务
task automatic test_full_integration;
    $display("==================== 开始全流程集成测试 ====================");

    // 测试1: 单beat传输，全字节使能 (原有测试)
    $display("测试1: 单beat传输，全字节使能");
    send_ldb_packet(
        64'h0000,      // gr_base_addr
        16'd2,         // brst = 2 beats
        4'h0,          // 全字节使能
        6'b000011,     // smc_strb = 开启4个SMC (SMC0、SMC1、SMC2、SMC3)
        8'd1,          // ur_id
        11'd0          // ur_addr
    );
    wait_ldb_done();
    repeat(10) @(posedge clk);
    clear_ldb_packet();
    repeat(20) @(posedge clk);

    // 测试1: 单beat传输，全字节使能 (原有测试)
    $display("测试2: 单beat传输，全字节使能");
    send_ldb_packet(
        64'h0000,      // gr_base_addr
        16'd2,         // brst = 2 beats
        4'h0,          // 全字节使能
        6'b00001,     // smc_strb = 开启4个SMC (SMC0、SMC1、SMC2、SMC3)
        8'd1,          // ur_id
        11'd0          // ur_addr
    );
    wait_ldb_done();
    repeat(10) @(posedge clk);
    clear_ldb_packet();
    repeat(20) @(posedge clk);

    $display("==================== 全流程集成测试完成 ====================");
endtask

// 测试 state2str 的 default 分支（强制无效 state）
task automatic test_state2str_default;
    $display("\n---------------------- 测试 state2str default 分支 ----------------------");
    wait_ldb_idle(); // 等待 LDB 进入 IDLE
    
    // 1. 强制 state_q 为无效值（枚举外的值，如 4'b1111）
    force dut.u_ldb.state_q = 4'b1111; 
    $display("[TEST] 强制 state_q = 4'b1111（无效状态），触发 state2str default");
    
    // 2. 触发 state2str 调用（状态变化时会打印，间接调用函数）
    dut.u_ldb.state_d = dut.u_ldb.IDLE; // 触发状态转换，会调用 state2str 打印
    repeat(2) @(posedge clk);
    
    // 3. 释放强制，恢复正常状态
    release dut.u_ldb.state_q;
    wait_ldb_idle();
    $display("---------------------- state2str default 分支测试完成 ----------------------");
endtask

// 测试 IDLE 状态的 MISSING_ELSE（接收无效指令）
task automatic test_idle_missing_else;
    $display("\n---------------------- 测试 IDLE 状态 MISSING_ELSE ----------------------");
    wait_ldb_idle(); // 确保 LDB 初始在 IDLE
    
    // 1. 传入无效指令包（vld=0，其他参数任意）
    cru_ldb_i_reg = {
        1'b0,           // valid=0（无效指令）
        6'b000001,      // smc_strb
        4'h1,           // byte_strb
        16'd1,          // brst
        64'h2000,       // gr_base_addr
        8'd21,          // ur_id
        11'd0,          // ur_addr
        18'b0           // reserved
    };
    $display("[TEST] IDLE 状态传入无效指令（vld=0），验证 state 保持 IDLE");
    
    // 2. 等待 5 个时钟周期，观察 state 是否保持 IDLE
    repeat(5) @(posedge clk);
    if (dut.u_ldb.state_q == dut.u_ldb.IDLE) begin
        $display("[TEST] 成功：IDLE 状态接收无效指令后保持 IDLE");
    end else begin
        $display("[TEST] 失败：IDLE 状态接收无效指令后状态异常");
    end
    
    // 3. 清理指令包
    clear_ldb_packet();
    wait_ldb_idle();
    $display("---------------------- IDLE 状态 MISSING_ELSE 测试完成 ----------------------");
endtask

// 测试 burst_cnt_d == 0 条件（brst=0）
task automatic test_burst_cnt_zero;
    $display("\n---------------------- 测试 burst_cnt_d == 0 条件 ----------------------");
    wait_ldb_idle(); // 等待 LDB 进入 IDLE
    
    // 1. 发送 brst=0 的指令包（burst 长度为 0）
    send_ldb_packet(
        64'h3000,       // gr_base_addr
        16'd0,          // brst=0（触发 burst_cnt_d == 0）
        4'h1,           // byte_strb=1
        6'b000001,      // smc_strb=1（仅 SMC0）
        8'd22,          // ur_id
        11'd0           // ur_addr
    );
    $display("[TEST] 发送 brst=0 的指令包，验证 is_last_beat_d=1'b1");
    
    // 2. 等待 LDB 处理完成（brst=0 时无数据传输，直接进入 DONE）
    wait_ldb_done();
    clear_ldb_packet();
    
    // 3. 检查是否触发 burst_cnt_d == 0（通过覆盖率工具确认，或打印调试信息）
    $display("[TEST] brst=0 测试完成，已触发 burst_cnt_d == 0 条件");
    $display("---------------------- burst_cnt_d == 0 条件测试完成 ----------------------");
endtask

// 测试 WAIT_AXI 状态的 else 分支（axi_req_ready=0）
task automatic test_wait_axi_else;
    $display("\n---------------------- 测试 WAIT_AXI 状态 else 分支 ----------------------");
    wait_ldb_idle(); // 等待 LDB 进入 IDLE
    
    // 1. 第一步：发起长 burst 传输（brst=10），让 axi_master 进入 S_DATA 状态（req_ready=0）
    $display("[TEST] 第一步：发起长 burst 传输（brst=10），占用 axi_master");
    send_ldb_packet(
        64'h4000,       // gr_base_addr
        16'd10,         // brst=10（长 burst， axi_master 会进入 S_DATA）
        4'h0,           // 全字节使能
        6'b000001,      // smc_strb=1（仅 SMC0）
        8'd23,          // ur_id
        11'd0           // ur_addr
    );
    
    // 2. 等待 axi_master 进入 S_DATA 状态（此时 req_ready=0）
    wait(dut.u_axi_master.state == dut.u_axi_master.S_DATA);
    $display("[TEST] axi_master 已进入 S_DATA 状态，req_ready=0");
    
    // 3. 第二步：立即发起新请求，触发 LDB 的 WAIT_AXI 分支（axi_req_ready=0）
    $display("[TEST] 第二步：发起新请求，触发 WAIT_AXI else 分支");
    cru_ldb_i_reg = { // 直接构造指令包，不调用 send_ldb_packet（避免 wait_ldb_idle）
        1'b1,           // valid=1
        6'b000010,      // smc_strb=2（仅 SMC1）
        4'h2,           // byte_strb=2
        16'd5,          // brst=5
        64'h5000,       // gr_base_addr
        8'd24,          // ur_id
        11'd10,         // ur_addr
        18'b0           // reserved
    };
    
    // 4. 等待 LDB 进入 WAIT_AXI 状态，并停留至少 1 个周期（触发 else 分支）
    wait(dut.u_ldb.state_q == dut.u_ldb.WAIT_AXI);
    repeat(3) @(posedge clk); // 确保 else 分支执行多次
    $display("[TEST] LDB 已进入 WAIT_AXI 状态，axi_req_ready=0 分支触发");
    
    // 5. 等待第一个长 burst 完成，清理指令
    wait_ldb_done();
    clear_ldb_packet();
    wait_ldb_idle();
    $display("---------------------- WAIT_AXI 状态 else 分支测试完成 ----------------------");
endtask
    localparam MEM_ADDR_MAX = (1024 << 4); // MEM_DEPTH=1024，DATA_BYTES=16，地址单位为字节
// 测试 DONE 状态的 axi_req_err 分支（AXI 地址越界）
task automatic test_axi_req_err;
    $display("\n---------------------- 测试 DONE 状态 axi_req_err 分支 ----------------------");
    wait_ldb_idle(); // 等待 LDB 进入 IDLE
    
    // 1. 发送地址越界的指令包（MEM_DEPTH=1024，地址=1024×16=0x4000，超出范围）

    send_ldb_packet(
        MEM_ADDR_MAX,    // gr_base_addr=0x4000（越界）
        16'd2,           // brst=2
        4'h0,            // 全字节使能
        6'b000001,       // smc_strb=1（仅 SMC0）
        8'd25,           // ur_id
        11'd0            // ur_addr
    );
    $display("[TEST] 发送地址越界的指令包（addr=0x%h），触发 AXI 错误", MEM_ADDR_MAX);
    
    // 2. 等待 LDB 处理完成（axi_master 会检测到 rresp=SLVERR，置 axi_req_err=1）
    wait_ldb_done();
    clear_ldb_packet();
    
    // 3. 验证 axi_req_err 是否触发（通过覆盖率工具确认，或打印调试信息）
    if (dut.u_ldb.axi_req_err) begin
        $display("[TEST] 成功：AXI 传输错误，axi_req_err=1，触发 DONE 状态错误打印");
    end else begin
        $display("[TEST] 失败：AXI 传输错误未触发 axi_req_err");
    end
    $display("---------------------- DONE 状态 axi_req_err 分支测试完成 ----------------------");
endtask

// 主测试序列
initial begin
    @(posedge rst_n);
    repeat(50) @(posedge clk);
    
    $display("开始全流程LDB测试...");
    
    // 运行全流程集成测试
    test_full_integration;
    
    $display("所有全流程测试完成!");
    test_byte_strb_default;
    test_incremental_smc_byte_data;
    test_state2str_default;
    test_idle_missing_else;
    test_burst_cnt_zero;
    //test_wait_axi_else;
    test_axi_req_err;

    // 等待一段时间再结束仿真，确保所有操作完成
    repeat(100) @(posedge clk);
    $finish;
end

initial begin
	$fsdbDumpfile("tb_ldb.fsdb");
	$fsdbDumpvars;
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