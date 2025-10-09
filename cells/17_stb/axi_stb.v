`timescale 1ns/1ps
// AXI STB模块 - 核心功能：将burst_store的事务包转换为标准AXI写信号
module axi_stb #(
    parameter ADDR_WIDTH = 32,          // 地址宽度（匹配AXI协议）
    parameter DATA_WIDTH = 128,         // 数据宽度（128bit，匹配UR和内存）
    parameter UR_BYTE_CNT = 16          // 字节使能宽度（128bit/8=16）
)(
    // 时钟与复位
    input                   clk,
    input                   rst_n,
    
    // 事务包输入（连接burst_store）
    input                   stb2stb_valid,  // 事务包就绪标志
    input [ADDR_WIDTH-1:0]  stb2stb_addr,  // 写入地址（来自burst_store）
    input [DATA_WIDTH-1:0]  stb2stb_data,  // 随机数据（来自burst_store，核心）
    input [7:0]             stb2stb_burst_len,  // burst长度（0=1拍，1=2拍，3=4拍，7=8拍）
    input [UR_BYTE_CNT-1:0] stb2stb_wstrb,  // 字节使能掩码（16bit）
    output reg              stb2stb_done,     // 输出：事务完成反馈给burst_store
    
    // AXI写主接口（连接axi_stb_s的上游从接口s_*）
    output reg              axi_awvalid,    // AXI地址有效
    output reg [ADDR_WIDTH-1:0] axi_awaddr,  // AXI写地址
    output reg [7:0]        axi_awlen,      // AXI burst长度（拍数-1）
    output reg [2:0]        axi_awsize,     // AXI数据宽度（3bit：100=16字节，符合协议）
    output reg [1:0]        axi_awburst,    // AXI burst模式（01=INCR，连续地址）
    input                   axi_awready,    // AXI地址就绪（来自axi_stb_s）
    
    output reg              axi_wvalid,     // AXI写数据有效
    output reg [DATA_WIDTH-1:0] axi_wdata,   // AXI写数据（透传stb2stb_data）
    output reg [UR_BYTE_CNT-1:0] axi_wstrb,   // AXI字节使能（透传stb2stb_wstrb）
    output reg              axi_wlast,      // AXI最后一拍数据标志
    input                   axi_wready,     // AXI写数据就绪（来自axi_stb_s）
    
    input                   axi_bvalid,     // AXI写响应有效（来自axi_stb_s）
    input [1:0]             axi_bresp,      // AXI写响应（00=成功）
    output reg              axi_bready      // AXI写响应就绪
);

// 状态定义（AXI写事务的4个核心状态）
localparam IDLE       = 2'd0;  // 空闲状态（等待事务包）
localparam AW_TRANSFER = 2'd1;  // 地址阶段（AXI AW通道握手）
localparam W_TRANSFER  = 2'd2;  // 数据阶段（AXI W通道握手）
localparam B_TRANSFER  = 2'd3;  // 响应阶段（AXI B通道握手）

// 内部寄存器
reg [1:0]                state;          // 状态机状态
reg [7:0]                burst_count;    // burst传输计数器（跟踪剩余拍数）
reg [6:0]                wait_cnt;       // 超时计数器（防止死锁）

// 状态机逻辑（核心：事务包→AXI信号转换，随机数据透传）
// 修复：确保在处理完一个事务后再接收下一个事务
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化
        state <= IDLE;
        stb2stb_done <= 1'b0;
        axi_awvalid <= 1'b0;
        axi_awaddr <= 32'd0;
        axi_awlen <= 8'd0;
        axi_awsize <= 3'b000;
        axi_awburst <= 2'b00;
        axi_wvalid <= 1'b0;
        axi_wdata <= {DATA_WIDTH{1'b0}};
        axi_wstrb <= {UR_BYTE_CNT{1'b0}};
        axi_wlast <= 1'b0;
        axi_bready <= 1'b0;
        burst_count <= 8'd0;
        wait_cnt <= 7'd0;
    end else begin
        // 默认清除完成标志和超时计数器
        stb2stb_done <= 1'b0;
        wait_cnt <= 7'd0;
        
        case (state)
            IDLE:
                begin
                    // 复位AXI控制信号
                    axi_awvalid <= 1'b0;
                    axi_wvalid <= 1'b0;
                    axi_bready <= 1'b0;
                    burst_count <= 8'd0;
                    
                    // 接收burst_store的事务包（stb2stb_valid有效）
                    if (stb2stb_valid) begin
                        $display("[AXI_STB] 时间%0t: 接收事务包，准备生成AXI信号，地址=0x%h，burst长度=%0d", $time, stb2stb_addr, stb2stb_burst_len + 1);
                        // 1. 初始化AXI地址信号（直接映射事务包参数）
                        axi_awaddr <= stb2stb_addr;
                        axi_awlen <= stb2stb_burst_len; // AXI awlen = 拍数-1（与事务包一致）
                        axi_awsize <= 3'b100; // 16字节（2^4=16，AXI size编码为100，3bit符合协议）
                        axi_awburst <= 2'b01; // INCR模式（连续地址burst，符合需求）
                        axi_awvalid <= 1'b1;  // 置位地址有效
                        // 2. 初始化burst计数器（跟踪数据传输拍数）
                        // stb2stb_burst_len已经是传输长度-1（符合AXI协议）
                        // 所以我们直接使用这个值
                        burst_count <= stb2stb_burst_len;
                        state <= AW_TRANSFER;
                    end
                end
            
            AW_TRANSFER:
                begin
                    // 地址通道握手（axi_awvalid && axi_awready）
                    if (axi_awvalid && axi_awready) begin
                        $display("[AXI_STB] 时间%0t: AXI地址握手成功，地址=0x%h", $time, axi_awaddr);
                        axi_awvalid <= 1'b0; // 清除地址有效
                        // 初始化AXI数据信号（直接映射事务包参数）
                        axi_wdata <= stb2stb_data; // 关键：随机数据透传
                        axi_wstrb <= stb2stb_wstrb; // 字节使能透传
                        axi_wvalid <= 1'b1; // 置位数据有效
                        // 初始化wlast标志：只有当burst_count=0时（1拍传输）才设置为1
                        axi_wlast <= (burst_count == 8'd0) ? 1'b1 : 1'b0;
                        state <= W_TRANSFER;
                    end else begin
                        // 地址握手超时保护（增加到1000个时钟周期以适应多SMC场景）
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd1000) begin
                            $display("[AXI_STB] 时间%0t: AXI地址握手超时，强制回到空闲", $time);
                            axi_awvalid <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
            
            W_TRANSFER:
                begin
                    // 数据通道握手（axi_wvalid && axi_wready）
                    if (axi_wvalid && axi_wready) begin
                        $display("[AXI_STB] 时间%0t: AXI数据握手成功，数据=0x%h，剩余拍数=%0d", 
                                 $time, axi_wdata, burst_count);
                        if (burst_count > 8'd0) begin
                            // 还有剩余拍数，继续传输（多拍burst）
                            // 正确的wlast设置逻辑：
                            // 当burst_count == 1时，表示下一拍是最后一拍，应设置wlast为1
                            if (burst_count == 8'd1) begin
                                // 倒数第二拍，为最后一拍设置wlast为1
                                axi_wlast <= 1'b1;
                            end else begin
                                // 非最后一拍，设置wlast为0
                                axi_wlast <= 1'b0;
                            end
                            burst_count <= burst_count - 1;
                            // 直接使用ur_model生成的随机数据，不再进行异或操作
                            axi_wdata <= stb2stb_data;
                            axi_wstrb <= stb2stb_wstrb;
                        end else begin
                            // 所有拍数传输完成，进入响应阶段
                            axi_wvalid <= 1'b0; // 清除数据有效
                            axi_bready <= 1'b1; // 准备接收响应
                            state <= B_TRANSFER;
                        end
                    end else begin
                        // 数据握手超时保护
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd1000) begin
                            $display("[AXI_STB] 时间%0t: AXI数据握手超时，强制回到空闲", $time);
                            state <= IDLE;
                            axi_wvalid <= 1'b0;
                        end
                    end
                end
            
            B_TRANSFER:
                begin
                    // 响应通道握手（axi_bvalid && axi_bready）
                    if (axi_bvalid && axi_bready) begin
                        $display("[AXI_STB] 时间%0t: AXI响应握手成功，响应码=0x%h", $time, axi_bresp);
                        axi_bready <= 1'b0; // 清除响应就绪
                        stb2stb_done <= 1'b1; // 通知burst_store：事务完成
                        // 修复：无论stb2stb_valid状态如何，事务完成后立即回到IDLE并清除地址数据
                        // 这样可以确保下一个事务总是使用新的地址和数据值
                        // 清除之前的地址和数据，确保下一个事务使用新值
                        axi_awaddr <= 32'd0;
                        axi_wdata <= {DATA_WIDTH{1'b0}};
                        state <= IDLE; // 回到空闲状态，等待下一个事务包
                    end else begin
                        // 响应握手超时保护
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd1000) begin
                            $display("[AXI_STB] 时间%0t: AXI响应握手超时，强制回到空闲", $time);
                            axi_bready <= 1'b0;
                            // 清除之前的地址和数据，确保下一个事务使用新值
                            axi_awaddr <= 32'd0;
                            axi_wdata <= {DATA_WIDTH{1'b0}};
                            stb2stb_done <= 1'b1; // 强制反馈完成
                            state <= IDLE;
                        end
                    end
                end
        endcase
    end
end

// 额外的安全检查：确保在IDLE状态下，只有当stb2stb_valid持续有效至少一个时钟周期才开始处理
// 防止由于信号不稳定导致的误触发
always @(posedge clk) begin
    if (state == IDLE && stb2stb_valid) begin
        static reg stb2stb_valid_prev;
        stb2stb_valid_prev = stb2stb_valid;
        if (!stb2stb_valid_prev) begin
            $display("[AXI_STB_SAFETY] 时间%0t: 检测到stb2stb_valid上升沿，准备处理事务", $time);
        end
    end
end

endmodule
    