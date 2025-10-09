`timescale 1ns/1ps
// 内存模型模块 - 核心功能：接收AXI写信号，存储随机数据，支持内容导出
module axi_mem_model #(
    parameter ADDR_WIDTH = 32,          // 地址宽度
    parameter DATA_WIDTH = 128,         // 数据宽度（128bit）
    parameter MEM_SIZE = 1024 * 512    // 内存大小（512KB，地址0~0x80000）
)(
    // 时钟与复位
    input                   clk,
    input                   rst_n,
    
    // AXI从接口（连接axi_stb_s的下游主接口m_*）
    input                   axi_awvalid,    // AXI地址有效（来自axi_stb_s）
    input [ADDR_WIDTH-1:0]  axi_awaddr,    // AXI写地址（来自axi_stb_s）
    input [7:0]             axi_awlen,      // AXI burst长度（来自axi_stb_s）
    input [2:0]             axi_awsize,     // AXI数据宽度（来自axi_stb_s）
    input [1:0]             axi_awburst,    // AXI burst模式（来自axi_stb_s）
    output reg              axi_awready,    // AXI地址就绪（反馈给axi_stb_s）
    
    input                   axi_wvalid,     // AXI写数据有效（来自axi_stb_s）
    input [DATA_WIDTH-1:0]  axi_wdata,      // AXI写数据（含随机数据，核心）
    input [DATA_WIDTH/8-1:0] axi_wstrb,     // AXI字节使能（来自axi_stb_s）
    input                   axi_wlast,      // AXI最后一拍标志（来自axi_stb_s）
    output reg              axi_wready,     // AXI写数据就绪（反馈给axi_stb_s）
    
    output reg              axi_bvalid,     // AXI写响应有效（反馈给axi_stb_s）
    output reg [1:0]        axi_bresp,      // AXI写响应（00=成功）
    input                   axi_bready      // AXI写响应就绪（来自axi_stb_s）
    
    // UR读接口（未使用，注释防止多驱动）
    // input                   ur_re,
    // input [10:0]            ur_addr,
    // output reg [DATA_WIDTH-1:0] ur_rdata
);

// 内存数组（存储数据，512KB大小）
reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE-1];

// 状态定义（AXI从接口的4个核心状态）
localparam IDLE       = 3'd0;  // 空闲状态
localparam WRITE_ADDR = 3'd1;  // 地址接收状态
localparam WRITE_DATA = 3'd2;  // 数据接收状态
localparam WRITE_RESP = 3'd3;  // 响应发送状态

// 内部寄存器
reg [2:0]                state;          // 状态机状态
reg [ADDR_WIDTH-1:0]     current_write_addr; // 当前写入地址
reg [7:0]                burst_count;    // burst计数器（剩余拍数）
reg [6:0]                wait_cnt;       // 超时计数器

// 初始化内存（复位时填充初始值为0，避免干扰随机数据验证）
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        $display("[AXI_MEM_MODEL] 时间%0t: 复位初始化内存，初始值=0xDEADBEEF_00000000_12345678_ABCDEF01", $time);
        for (i = 0; i < MEM_SIZE; i = i + 1) begin
            memory[i] <= 128'hDEADBEEF_00000000_12345678_ABCDEF01;
        end
    end
end

// AXI写状态机逻辑（核心：接收AXI数据，写入内存）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化
        state <= IDLE;
        axi_awready <= 1'b0;
        axi_wready <= 1'b0;
        axi_bvalid <= 1'b0;
        axi_bresp <= 2'b00;
        current_write_addr <= 32'd0;
        burst_count <= 8'd0;
        wait_cnt <= 7'd0;
    end else begin
        // 默认清除超时计数器
        wait_cnt <= 7'd0;
        
        case (state)
            IDLE:
                begin
                    // 准备接收地址
                    axi_awready <= 1'b1;
                    axi_wready <= 1'b0;
                    axi_bvalid <= 1'b0;
                    
                    // 地址有效（axi_awvalid），进入地址接收状态
                    if (axi_awvalid) begin
                        $display("[AXI_MEM_MODEL] 时间%0t: 接收AXI地址，地址=0x%h，burst长度=%0d", 
                                 $time, axi_awaddr, axi_awlen + 1);
                        axi_awready <= 1'b0; // 清除地址就绪
                        current_write_addr <= axi_awaddr; // 锁存当前地址
                        burst_count <= axi_awlen; // 初始化burst计数器（拍数-1）
                        state <= WRITE_ADDR;
                    end
                end
            
            WRITE_ADDR:
                begin
                    // 准备接收数据
                    axi_wready <= 1'b1;
                    
                    // 数据有效（axi_wvalid），开始写入内存
                    if (axi_wvalid) begin
                        // 检查地址是否越界（MEM_SIZE=1MB，地址0~0xFFFFF）
                        if (current_write_addr < MEM_SIZE) begin
                            // 字节使能写入（仅使能位对应字节更新）
                            // 根据字节使能信号axi_wstrb更新内存数据
                            // 为每个字节单独处理使能（修复位运算优先级问题）
                            if (axi_wstrb[0]) begin
                                memory[current_write_addr][7:0] <= axi_wdata[7:0];
                            end
                            if (axi_wstrb[1]) begin
                                memory[current_write_addr][15:8] <= axi_wdata[15:8];
                            end
                            if (axi_wstrb[2]) begin
                                memory[current_write_addr][23:16] <= axi_wdata[23:16];
                            end
                            if (axi_wstrb[3]) begin
                                memory[current_write_addr][31:24] <= axi_wdata[31:24];
                            end
                            if (axi_wstrb[4]) begin
                                memory[current_write_addr][39:32] <= axi_wdata[39:32];
                            end
                            if (axi_wstrb[5]) begin
                                memory[current_write_addr][47:40] <= axi_wdata[47:40];
                            end
                            if (axi_wstrb[6]) begin
                                memory[current_write_addr][55:48] <= axi_wdata[55:48];
                            end
                            if (axi_wstrb[7]) begin
                                memory[current_write_addr][63:56] <= axi_wdata[63:56];
                            end
                            if (axi_wstrb[8]) begin
                                memory[current_write_addr][71:64] <= axi_wdata[71:64];
                            end
                            if (axi_wstrb[9]) begin
                                memory[current_write_addr][79:72] <= axi_wdata[79:72];
                            end
                            if (axi_wstrb[10]) begin
                                memory[current_write_addr][87:80] <= axi_wdata[87:80];
                            end
                            if (axi_wstrb[11]) begin
                                memory[current_write_addr][95:88] <= axi_wdata[95:88];
                            end
                            if (axi_wstrb[12]) begin
                                memory[current_write_addr][103:96] <= axi_wdata[103:96];
                            end
                            if (axi_wstrb[13]) begin
                                memory[current_write_addr][111:104] <= axi_wdata[111:104];
                            end
                            if (axi_wstrb[14]) begin
                                memory[current_write_addr][119:112] <= axi_wdata[119:112];
                            end
                            if (axi_wstrb[15]) begin
                                memory[current_write_addr][127:120] <= axi_wdata[127:120];
                            end
                            // 打印写入信息（验证随机数据是否写入）
                            #1; // 延迟1ns，确保内存更新完成
                            $display("[AXI_MEM_MODEL] 时间%0t: 写入内存成功，地址=0x%h，写入数据=0x%h，写入后数据=0x%h", 
                                     $time, current_write_addr, axi_wdata, memory[current_write_addr]);
                        end else begin
                            $display("[AXI_MEM_MODEL] 时间%0t: 警告：写入地址0x%h越界（内存大小512KB）", $time, current_write_addr);
                        end
                        
                        // 更新burst计数器和地址（INCR模式，地址+16字节）
                        if (burst_count > 8'd0) begin
                            current_write_addr <= current_write_addr + (DATA_WIDTH/8); // 16字节步长
                            burst_count <= burst_count - 1;
                        end
                        
                        // 最后一拍数据写入完成，进入响应状态
                        if (axi_wlast) begin
                            axi_wready <= 1'b0; // 清除数据就绪
                            axi_bvalid <= 1'b1; // 置位响应有效
                            axi_bresp <= 2'b00; // 响应码：成功
                            state <= WRITE_RESP;
                        end
                    end else begin
                        // 数据接收超时保护
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd100) begin
                            $display("[AXI_MEM_MODEL] 时间%0t: 数据接收超时，强制回到空闲", $time);
                            axi_wready <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
            
            WRITE_RESP:
                begin
                    // 响应握手（axi_bvalid && axi_bready）
                    if (axi_bready) begin
                        $display("[AXI_MEM_MODEL] 时间%0t: 发送AXI响应成功，响应码=0x%h", $time, axi_bresp);
                        axi_bvalid <= 1'b0; // 清除响应有效
                        state <= IDLE; // 回到空闲状态
                    end else begin
                        // 响应发送超时保护
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd100) begin
                            $display("[AXI_MEM_MODEL] 时间%0t: 响应发送超时，强制回到空闲", $time);
                            axi_bvalid <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
        endcase
    end
end

// 内存导出任务（根据case_id导出到统一文件，支持测试用例验证）
task export_memory;
    input [3:0] case_id;
    
    integer file, addr;
    reg [3:0] case_id_reg;
    
    // 处理默认case_id（未连接时为0）
    case_id_reg = (^case_id === 1'bx) ? 0 : case_id;
    
    // 确保sim_output目录存在
    $system("mkdir -p /home/zwz/zts/17_stb/sim_output");
    
    // 统一导出到mem.txt文件
    file = $fopen("/home/zwz/zts/17_stb/sim_output/mem.txt", "w");
    $display("[AXI_MEM_MODEL] 时间%0t: 开始导出内存内容到/home/zwz/zts/17_stb/sim_output/mem.txt", $time);
    
    if (file == 0) begin
        $display("[AXI_MEM_MODEL_ERROR] 时间%0t: 无法创建文件", $time);
        return;
    end
    
    // 导出文件头信息
    $fwrite(file, "// 内存内容导出\n// 导出时间: %0t\n// 测试用例ID: %0d\n\n", $time, case_id_reg);
    
    // 导出所有测试用例的写入地址数据
    $fwrite(file, "// 所有测试用例的写入地址数据:\n");
    
    // 测试用例1的写入地址
    $fwrite(file, "// 测试用例1写入地址:\n");
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00001000, memory[32'h00001000]);
    
    // 测试用例2的写入地址
    $fwrite(file, "\n// 测试用例2写入地址:\n");
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00002040, memory[32'h00002040]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00002050, memory[32'h00002050]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00002060, memory[32'h00002060]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00002070, memory[32'h00002070]);
    
    // 测试用例3的写入地址（多SMC写入，INTLV_STEP=64）
    $fwrite(file, "\n// 测试用例3写入地址:\n");
    // SMC0: 0x3000, 0x3010
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00003000, memory[32'h00003000]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00003010, memory[32'h00003010]);
    // SMC1: 0x3040, 0x3050
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00003040, memory[32'h00003040]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00003050, memory[32'h00003050]);
    // SMC2: 0x3080, 0x3090
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00003080, memory[32'h00003080]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00003090, memory[32'h00003090]);
    
    // 测试用例4的写入地址
    $fwrite(file, "\n// 测试用例4写入地址:\n");
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00004000, memory[32'h00004000]);
    
    // 测试用例5的写入地址
    $fwrite(file, "\n// 测试用例5写入地址:\n");
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005000, memory[32'h00005000]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005010, memory[32'h00005010]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005040, memory[32'h00005040]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005050, memory[32'h00005050]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005080, memory[32'h00005080]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005090, memory[32'h00005090]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h000050C0, memory[32'h000050C0]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h000050D0, memory[32'h000050D0]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005100, memory[32'h00005100]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005110, memory[32'h00005110]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005140, memory[32'h00005140]);
    $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00005150, memory[32'h00005150]);
    
    // 测试用例6的写入地址
    $fwrite(file, "\n// 测试用例6写入地址:\n");
    for (addr = 0; addr < 16; addr = addr + 1) begin
        $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00006000 + (addr << 4), memory[32'h00006000 + (addr << 4)]);
    end
    
    // 测试用例7的写入地址
    $fwrite(file, "\n// 测试用例7写入地址:\n");
    for (addr = 0; addr < 4; addr = addr + 1) begin
        $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00007000 + (addr << 4), memory[32'h00007000 + (addr << 4)]);
    end
    
    // 测试用例8的写入地址
    $fwrite(file, "\n// 测试用例8写入地址:\n");
    for (addr = 0; addr < 4; addr = addr + 1) begin
        $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'h00008000 + (addr << 4), memory[32'h00008000 + (addr << 4)]);
    end
    
    // 测试用例9的写入地址
    $fwrite(file, "\n// 测试用例9写入地址:\n");
    for (addr = 0; addr < 2; addr = addr + 1) begin
        if (32'hF0000000 + (addr << 4) < MEM_SIZE) begin
            $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", 32'hF0000000 + (addr << 4), memory[32'hF0000000 + (addr << 4)]);
        end else begin
            $fwrite(file, "Addr: 0x%h, Data: (地址越界)\n", 32'hF0000000 + (addr << 4));
        end
    end
    
    // 导出前10个地址数据
    $fwrite(file, "\n// 前512KB地址的内存内容:\n");
    for (addr = 0; addr < 524288; addr = addr + 1) begin
        $fwrite(file, "Addr: 0x%h, Data: 0x%h\n", addr, memory[addr]);
    end
    
    // 关闭文件
    $fclose(file);
    $display("[AXI_MEM_MODEL] 时间%0t: 内存内容导出完成到/home/zwz/zts/17_stb/sim_output/mem.txt", $time);
endtask
endmodule
    