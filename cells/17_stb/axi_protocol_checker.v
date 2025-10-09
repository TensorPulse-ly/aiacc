`timescale 1ns/1ps
// AXI协议检查器 - 监控AXI写通道是否符合协议规范
module axi_protocol_checker #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128
)(
    input                   clk,
    input                   rst_n,
    
    // AXI写通道信号（监控对象）
    input                   axi_awvalid,
    input                   axi_awready,
    input [ADDR_WIDTH-1:0]  axi_awaddr,
    input                   axi_wvalid,
    input                   axi_wready,
    input [DATA_WIDTH-1:0]  axi_wdata,
    input [DATA_WIDTH/8-1:0] axi_wstrb,
    input                   axi_wlast,
    input                   axi_bvalid,
    input                   axi_bready,
    input [1:0]             axi_bresp,
    
    // 错误输出
    output reg              protocol_error,
    output reg [3:0]        error_code
);

// 错误代码定义
localparam NO_ERROR         = 4'h0;
localparam AWVALID_STUCK    = 4'h1; // AWVALID持续有效超过100周期未握手
localparam WVALID_STUCK     = 4'h2; // WVALID持续有效超过100周期未握手
localparam BVALID_STUCK     = 4'h3; // BVALID持续有效超过100周期未握手
localparam WLAST_MISMATCH   = 4'h4; // WLAST与burst长度不匹配（未实现完整检测）
localparam INVALID_BRESP    = 4'h5; // 无效的BRESP值
localparam AWVALID_BEFORE_W = 4'h6; // WVALID在AWVALID之前有效（协议违规）
localparam BVALID_BEFORE_W  = 4'h7; // BVALID在WLAST之前有效（协议违规）

// 内部寄存器
reg [6:0] awvalid_cnt;      // AWVALID超时计数器
reg [6:0] wvalid_cnt;       // WVALID超时计数器
reg [6:0] bvalid_cnt;       // BVALID超时计数器
reg       aw_handshaked;    // AW通道已握手标志
reg       w_last_seen;      // 已检测到WLAST标志
reg [3:0] error_code_reg;   // 错误代码寄存器

// 组合逻辑：错误检测
always @(*) begin
    protocol_error = 1'b0;
    error_code = NO_ERROR;
    
    // 优先级：先检测超时错误，再检测协议顺序错误
    if (awvalid_cnt >= 7'd100) begin
        protocol_error = 1'b1;
        error_code = AWVALID_STUCK;
    end else if (wvalid_cnt >= 7'd100) begin
        protocol_error = 1'b1;
        error_code = WVALID_STUCK;
    end else if (bvalid_cnt >= 7'd100) begin
        protocol_error = 1'b1;
        error_code = BVALID_STUCK;
    end else if (|axi_bresp[1:0] & ~axi_bresp[0]) begin
        // 无效的响应码（AXI协议定义BRESP[1:0]合法值为00、01、10）
        protocol_error = 1'b1;
        error_code = INVALID_BRESP;
    end else if (axi_wvalid && !aw_handshaked) begin
        // WVALID在AW通道握手前有效（协议违规）
        protocol_error = 1'b1;
        error_code = AWVALID_BEFORE_W;
    end else if (axi_bvalid && !w_last_seen) begin
        // BVALID在WLAST出现前有效（协议违规）
        protocol_error = 1'b1;
        error_code = BVALID_BEFORE_W;
    end
end

// 时序逻辑：计数器和标志更新
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        awvalid_cnt <= 7'd0;
        wvalid_cnt <= 7'd0;
        bvalid_cnt <= 7'd0;
        aw_handshaked <= 1'b0;
        w_last_seen <= 1'b0;
    end else begin
        // AWVALID超时计数
        if (axi_awvalid && !axi_awready) begin
            awvalid_cnt <= awvalid_cnt + 1;
        end else begin
            awvalid_cnt <= 7'd0;
        end
        
        // WVALID超时计数
        if (axi_wvalid && !axi_wready) begin
            wvalid_cnt <= wvalid_cnt + 1;
        end else begin
            wvalid_cnt <= 7'd0;
        end
        
        // BVALID超时计数
        if (axi_bvalid && !axi_bready) begin
            bvalid_cnt <= bvalid_cnt + 1;
        end else begin
            bvalid_cnt <= 7'd0;
        end
        
        // AW通道握手标志
        if (axi_awvalid && axi_awready) begin
            aw_handshaked <= 1'b1;
        end else if (!rst_n) begin
            aw_handshaked <= 1'b0;
        end
        
        // WLAST检测标志
        if (axi_wvalid && axi_wready && axi_wlast) begin
            w_last_seen <= 1'b1;
        end else if (!rst_n) begin
            w_last_seen <= 1'b0;
        end
        
        // 错误发生时打印信息
        if (protocol_error && error_code != NO_ERROR) begin
            case (error_code)
                AWVALID_STUCK:
                    $display("[PROTOCOL_ERROR] 时间%0t: AWVALID持续有效未握手（超过100周期）", $time);
                WVALID_STUCK:
                    $display("[PROTOCOL_ERROR] 时间%0t: WVALID持续有效未握手（超过100周期）", $time);
                BVALID_STUCK:
                    $display("[PROTOCOL_ERROR] 时间%0t: BVALID持续有效未握手（超过100周期）", $time);
                INVALID_BRESP:
                    $display("[PROTOCOL_ERROR] 时间%0t: 无效的BRESP值=0x%h", $time, axi_bresp);
                AWVALID_BEFORE_W:
                    $display("[PROTOCOL_ERROR] 时间%0t: WVALID在AW通道握手前有效（协议违规）", $time);
                BVALID_BEFORE_W:
                    $display("[PROTOCOL_ERROR] 时间%0t: BVALID在WLAST出现前有效（协议违规）", $time);
            endcase
        end
    end
end

endmodule
    