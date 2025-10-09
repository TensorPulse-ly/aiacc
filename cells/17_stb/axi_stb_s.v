`timescale 1ns/1ps
// AXI信号转发模块 - 核心功能：透传AXI写信号（无逻辑处理）
module axi_stb_s #(
    parameter ADDR_WIDTH = 32,          // 地址宽度
    parameter DATA_WIDTH = 128          // 数据宽度
)(
    // 时钟与复位
    input                   clk,
    input                   rst_n,
    
    // 上游AXI从接口（连接axi_stb的AXI主接口）
    input                   s_awvalid,      // 上游地址有效（来自axi_stb）
    input [ADDR_WIDTH-1:0]  s_awaddr,      // 上游写地址（来自axi_stb）
    input [7:0]             s_awlen,        // 上游burst长度（来自axi_stb）
    input [2:0]             s_awsize,       // 上游数据宽度（来自axi_stb）
    input [1:0]             s_awburst,      // 上游burst模式（来自axi_stb）
    output reg              s_awready,      // 上游地址就绪（反馈给axi_stb）
    
    input                   s_wvalid,       // 上游写数据有效（来自axi_stb）
    input [DATA_WIDTH-1:0]  s_wdata,        // 上游写数据（来自axi_stb，含随机数据）
    input [DATA_WIDTH/8-1:0] s_wstrb,       // 上游字节使能（来自axi_stb）
    input                   s_wlast,        // 上游最后一拍标志（来自axi_stb）
    output reg              s_wready,       // 上游写数据就绪（反馈给axi_stb）
    
    output reg              s_bvalid,       // 上游响应有效（反馈给axi_stb）
    output reg [1:0]        s_bresp,        // 上游响应码（来自下游）
    input                   s_bready,       // 上游响应就绪（来自axi_stb）
    
    // 下游AXI主接口（连接axi_mem_model的AXI从接口）
    output reg              m_awvalid,      // 下游地址有效（转发给axi_mem_model）
    output reg [ADDR_WIDTH-1:0] m_awaddr,  // 下游写地址（转发给axi_mem_model）
    output reg [7:0]        m_awlen,        // 下游burst长度（转发给axi_mem_model）
    output reg [2:0]        m_awsize,       // 下游数据宽度（转发给axi_mem_model）
    output reg [1:0]        m_awburst,      // 下游burst模式（转发给axi_mem_model）
    input                   m_awready,      // 下游地址就绪（来自axi_mem_model）
    
    output reg              m_wvalid,       // 下游写数据有效（转发给axi_mem_model）
    output reg [DATA_WIDTH-1:0] m_wdata,    // 下游写数据（转发s_wdata，含随机数据）
    output reg [DATA_WIDTH/8-1:0] m_wstrb,   // 下游字节使能（转发s_wstrb）
    output reg              m_wlast,        // 下游最后一拍标志（转发s_wlast）
    input                   m_wready,       // 下游写数据就绪（来自axi_mem_model）
    
    input                   m_bvalid,       // 下游响应有效（来自axi_mem_model）
    input [1:0]             m_bresp,        // 下游响应码（来自axi_mem_model）
    output reg              m_bready        // 下游响应就绪（转发给axi_mem_model）
);

// 状态定义（转发流程的4个状态）
localparam IDLE         = 3'd0;  // 空闲状态
localparam FORWARD_AW   = 3'd1;  // 转发地址阶段
localparam FORWARD_W    = 3'd2;  // 转发数据阶段
localparam FORWARD_B    = 3'd3;  // 转发响应阶段

// 内部寄存器
reg [2:0]                state;          // 状态机状态
reg [6:0]                wait_cnt;       // 超时计数器

// 状态机逻辑（核心：上游信号→下游信号，纯透传）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化
        state <= IDLE;
        s_awready <= 1'b0;
        s_wready <= 1'b0;
        s_bvalid <= 1'b0;
        s_bresp <= 2'b00;
        m_awvalid <= 1'b0;
        m_awaddr <= 32'd0;
        m_awlen <= 8'd0;
        m_awsize <= 3'b000;
        m_awburst <= 2'b00;
        m_wvalid <= 1'b0;
        m_wdata <= {DATA_WIDTH{1'b0}};
        m_wstrb <= {DATA_WIDTH/8{1'b0}};
        m_wlast <= 1'b0;
        m_bready <= 1'b0;
        wait_cnt <= 7'd0;
    end else begin
        // 默认清除超时计数器
        wait_cnt <= 7'd0;
        
        case (state)
            IDLE:
                begin
                    // 准备接收上游地址信号
                    s_awready <= 1'b1;
                    s_wready <= 1'b0;
                    m_bready <= 1'b1; // 提前准备接收下游响应
                    
                    // 上游地址有效（s_awvalid），开始转发地址
                    if (s_awvalid) begin
                        $display("[AXI_STB_S] 时间%0t: 接收上游地址信号，准备转发", $time);
                        s_awready <= 1'b0; // 清除上游地址就绪
                        // 1. 转发地址参数到下游
                        m_awaddr <= s_awaddr;
                        m_awlen <= s_awlen;
                        m_awsize <= s_awsize;
                        m_awburst <= s_awburst;
                        m_awvalid <= 1'b1; // 置位下游地址有效
                        state <= FORWARD_AW;
                    end
                end
            
            FORWARD_AW:
                begin
                    // 下游地址握手（m_awvalid && m_awready）
                    if (m_awvalid && m_awready) begin
                        $display("[AXI_STB_S] 时间%0t: 下游地址握手成功，准备转发数据", $time);
                        m_awvalid <= 1'b0; // 清除下游地址有效
                        state <= FORWARD_W;
                    end else begin
                        // 地址转发超时保护
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd100) begin
                            $display("[AXI_STB_S] 时间%0t: 地址转发超时，强制回到空闲", $time);
                            m_awvalid <= 1'b0;
                            s_awready <= 1'b1;
                            state <= IDLE;
                        end
                    end
                end
            
            FORWARD_W:
                begin
                    // 默认设置：准备接收上游数据
                    s_wready <= 1'b1;
                    
                    // 1. 转发数据信号到下游（纯透传）
                    m_wvalid <= s_wvalid;
                    m_wdata <= s_wdata; // 关键：随机数据透传（上游→下游）
                    m_wstrb <= s_wstrb;
                    m_wlast <= s_wlast;
                    
                    // 上游数据握手（s_wvalid && s_wready）且下游就绪（m_wready）
                    if (s_wvalid && m_wready) begin
                        $display("[AXI_STB_S] 时间%0t: 数据转发成功，数据=0x%h，是否最后一拍=%h", 
                                 $time, m_wdata, m_wlast);
                        
                        // 最后一拍数据转发完成，进入响应阶段
                        if (s_wlast) begin
                            state <= FORWARD_B;
                            s_wready <= 1'b0;
                            m_wvalid <= 1'b0;
                        end
                        
                        // 重置超时计数器
                        wait_cnt <= 7'd0;
                    end else if (!s_wvalid) begin
                        // 上游没有数据有效，重置超时计数器
                        wait_cnt <= 7'd0;
                    end else begin
                        // 数据转发超时保护（只有上游有数据但下游长期未就绪时才触发）
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd100) begin
                            $display("[AXI_STB_S] 时间%0t: 数据转发超时，强制回到空闲", $time);
                            m_wvalid <= 1'b0;
                            s_wready <= 1'b0;
                            state <= IDLE;
                        end
                    end
                end
            
            FORWARD_B:
                begin
                    m_bready <= 1'b1; // 准备接收下游响应
                    
                    // 下游响应有效（m_bvalid）
                    if (m_bvalid) begin
                        $display("[AXI_STB_S] 时间%0t: 接收下游响应，响应码=0x%h", $time, m_bresp);
                        // 1. 转发响应到上游
                        s_bvalid <= 1'b1;
                        s_bresp <= m_bresp;
                        m_bready <= 1'b0; // 清除下游就绪，防止重复接收响应
                    end
                    
                    // 上游响应握手（s_bvalid && s_bready）
                    if (s_bvalid && s_bready) begin
                        $display("[AXI_STB_S] 时间%0t: 上游响应握手成功", $time);
                        s_bvalid <= 1'b0; // 清除上游响应有效
                        state <= IDLE; // 回到空闲状态
                    end
                    
                    // 响应转发超时保护
                    if (!m_bvalid && !s_bvalid) begin
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 7'd100) begin
                            $display("[AXI_STB_S] 时间%0t: 响应转发超时，强制回到空闲", $time);
                            m_bready <= 1'b0;
                            s_bvalid <= 1'b0;
                            state <= IDLE;
                        end
                    end else begin
                        wait_cnt <= 7'd0; // 重置超时计数器
                    end
                end
        endcase
    end
end
endmodule
    