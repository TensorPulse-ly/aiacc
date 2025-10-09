`timescale 1ns/1ps
`default_nettype none

module ldb_axi_read_master #(
    parameter integer AXI_ADDR_W = 64,
    parameter integer AXI_DATA_W = 128,
    parameter integer AXI_ID_W = 4,
    parameter integer MAX_LEN = 255,
    parameter integer MEM_DEPTH = 1024,
    parameter integer MAX_OUTSTANDING = 1
)(
    input wire clk,
    input wire rst_n,
    
    // 简单请求接口
    input wire req_valid,
    output wire req_ready,  // 改为 wire 类型
    input wire [AXI_ADDR_W-1:0] req_addr,
    input wire [8:0] req_len,
    output reg req_done,
    output reg req_err,
    
    // AXI 读地址通道
    output reg arvalid,
    input wire arready,
    output reg [AXI_ADDR_W-1:0] araddr,
    output reg [7:0] arlen,
    output wire [2:0] arsize,
    output wire [1:0] arburst,
    output wire [AXI_ID_W-1:0] arid,
    output wire [3:0] arqos,
    output wire [1:0] arlock,
    output wire [3:0] arcache,
    output wire [2:0] arprot,
    
    // AXI 读数据通道
    input wire rvalid,
    output reg rready,
    input wire [AXI_DATA_W-1:0] rdata,
    input wire rlast,
    input wire [1:0] rresp,
    input wire [AXI_ID_W-1:0] rid,
    
    // 用户流输出
    output reg out_valid,
    input wire out_ready,
    output reg [AXI_DATA_W-1:0] out_data,
    output reg out_last
);

localparam integer DATA_BYTES = AXI_DATA_W / 8;
localparam integer ADDR_LSB = $clog2(DATA_BYTES);

typedef enum reg [1:0] {
    S_IDLE,
    S_AR,
    S_DATA
} state_t;

state_t state;
state_t state_next;

reg [8:0] beats_remaining;
reg error_occurred;
reg [31:0] timeout_counter = 0;

assign arsize = $clog2(DATA_BYTES); // 设置传输大小
assign arburst = 2'b01; // 突发类型固定为增量模式
assign arid = 0; // 简化：ID固定为0
assign arqos = 4'b0000; // QoS固定为0
assign arlock = 2'b00; // 锁类型固定为普通访问
assign arcache = 4'b0011; // Cache属性
assign arprot = 3'b000; // 保护属性

// 关键修复：使用组合逻辑直接驱动 req_ready
assign req_ready = (state == S_IDLE);

// 状态到字符串的转换函数
function string state2str(input state_t s);
    case (s)
        S_IDLE: state2str = "S_IDLE";
        S_AR: state2str = "S_AR";
        S_DATA: state2str = "S_DATA";
        default: state2str = "UNKNOWN";
    endcase
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        state_next <= S_IDLE;
        arvalid <= 1'b0;
        rready <= 1'b0;
        req_done <= 1'b0;
        req_err <= 1'b0;
        out_valid <= 1'b0;
        out_data <= 0;
        out_last <= 0;
        beats_remaining <= 0;
        error_occurred <= 1'b0;
        timeout_counter <= 0;
    end else begin
        req_done <= 1'b0;
        req_err <= 1'b0;
        
        // 处理输出流反压
        if (out_valid && out_ready) begin
            out_valid <= 1'b0;
        end
        
        state <= state_next;
        
        case (state)
            S_IDLE: begin
                timeout_counter <= 0;
                if (req_valid && req_ready) begin
                    if (req_len == 0 || req_len > MAX_LEN) begin
                        // 立即返回错误
                        req_done <= 1'b1;
                        req_err <= 1'b1;
                        state_next <= S_IDLE;
                    end else begin
                        // 接受请求
                        araddr <= req_addr;
                        arlen <= req_len[7:0] - 1'b1;
                        beats_remaining <= req_len;
                        arvalid <= 1'b1;
                        state_next <= S_AR;
                    end
                end else begin
                    state_next <= S_IDLE;
                end
            end
            
            S_AR: begin
                if (arready) begin
                    arvalid <= 1'b0;
                    state_next <= S_DATA;
                end else begin
                    // 添加超时处理
                    if (timeout_counter > 1000) begin
                        arvalid <= 1'b0;
                        state_next <= S_IDLE;
                        req_done <= 1'b1;
                        req_err <= 1'b1;
                    end else begin
                        timeout_counter <= timeout_counter + 1;
                    end
                end
            end
            
            S_DATA: begin
                // 只有在DATA状态且还有数据要接收时才准备好
                rready <= (beats_remaining > 0);
                
                if (rvalid && rready) begin
                    // 检查响应错误
                    if (rresp != 2'b00) begin
                        error_occurred <= 1'b1;
                    end
                    
                    timeout_counter <= 0; // 重置超时计数器
                    
                    // 检查RLAST
                    if (beats_remaining == 1) begin
                        if (!rlast) begin
                            // RLAST不匹配错误
                            req_err <= 1'b1;
                            error_occurred <= 1'b1;
                        end
                    end else begin
                        if (rlast) begin
                            // 提前的RLAST错误
                            req_err <= 1'b1;
                            error_occurred <= 1'b1;
                        end
                    end
                    
                    // 减少剩余beat数
                    beats_remaining <= beats_remaining - 1;
                    
                    // 如果这是最后一个beat，完成事务
                    if (beats_remaining == 1) begin
                        req_done <= 1'b1;
                        req_err <= error_occurred;
                        state_next <= S_IDLE;
                        error_occurred <= 1'b0;
                    end else begin
                        state_next <= S_DATA;
                    end
                    
                    // 处理接收到的数据
                    if (!out_valid || out_ready) begin
                        out_valid <= 1'b1;
                        out_data <= rdata;
                        out_last <= (beats_remaining == 1);
                    end
                end else begin
                    state_next <= S_DATA;
                end
            end
        endcase
    end
end

// 添加调试信息
always @(posedge clk) begin
    if (state == S_AR) begin
        $display("[MASTER_AR] time=%0t: arvalid=%b, arready=%b, timeout=%d",
            $time, arvalid, arready, timeout_counter);
    end
    
    if (state == S_DATA) begin
        $display("[MASTER_R] time=%0t: rvalid=%b, rready=%b, beats_rem=%d",
            $time, rvalid, rready, beats_remaining);
    end
    
    if (out_valid) begin
        $display("[AXI_TO_LDB] 开始等待 AXI 数据");
    end
    
    if (rvalid && rready) begin
        $display("[AXI_TO_LDB] 捕获数据: data=%h", rdata);
        $display("[AXI_DATA_FLOW] 数据已传输: data=%h, last=%b", rdata, rlast);
    end
end

endmodule