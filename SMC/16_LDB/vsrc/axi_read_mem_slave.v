`timescale 1ns/1ps
`default_nettype none

module axi_read_mem_slave #(
    parameter integer AXI_ADDR_W = 64,
    parameter integer AXI_DATA_W = 128,
    parameter integer MEM_DEPTH = 1024,
    parameter integer MAX_OUTSTANDING = 4
)(
    input wire clk,
    input wire rst_n,
    /* AXI 读地址通道 */
    input wire arvalid,
    output wire arready,
    input wire [AXI_ADDR_W-1:0] araddr,
    input wire [7:0] arlen,
    input wire [2:0] arsize,
    input wire [1:0] arburst,
    input wire [3:0] arid,
    /* AXI 读数据通道 */
    output reg rvalid,
    input wire rready,
    output reg [AXI_DATA_W-1:0] rdata,
    output reg rlast,
    output reg [1:0] rresp,
    output reg [3:0] rid
);

localparam integer DATA_BYTES = AXI_DATA_W/8;
localparam integer ADDR_LSB = $clog2(DATA_BYTES);

// 简单内存
reg [AXI_DATA_W-1:0] mem [0:MEM_DEPTH-1];

// 请求队列
typedef struct packed {
    logic [AXI_ADDR_W-1:0] addr;
    logic [7:0] len;
    logic [3:0] id;
    logic [2:0] size;
    logic [1:0] burst;
} axi_request_t;

axi_request_t request_queue [0:MAX_OUTSTANDING-1];
logic [2:0] queue_head = 0;
logic [2:0] queue_tail = 0;
logic queue_empty;
logic queue_full;

assign queue_empty = (queue_head == queue_tail);
assign queue_full = ((queue_tail + 1) % MAX_OUTSTANDING) == queue_head;

// 当前处理的事务
axi_request_t current_request;
logic [7:0] beats_remaining;
logic processing_request = 0;

// 状态定义
typedef enum logic [1:0] {
    ST_IDLE = 2'b00,
    ST_SEND_DATA = 2'b10
} state_t;

state_t state;
state_t state_next;

integer k;

// 内存初始化
initial begin
    for (k = 0; k < MEM_DEPTH; k = k + 1)
        mem[k] = {64'h0123456789ABCDEF, 32'h0, k[31:0]};
end

// arready 改为组合逻辑，确保及时响应
assign arready = !queue_full;

// 地址通道处理
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        queue_head <= 0;
        queue_tail <= 0;
        state <= ST_IDLE;
        state_next <= ST_IDLE;
    end else begin
        state <= state_next;
        
        // 处理地址握手
        if (arvalid && arready) begin
            $display("[SLAVE_AR_DEBUG] time=%0t: addr=%h, len=%d, id=%h, queue_head=%d, queue_tail=%d, processing_request=%b", 
                $time, araddr, arlen, arid, queue_head, queue_tail, processing_request);
            
            // 将请求加入队列
            request_queue[queue_tail].addr <= araddr;
            request_queue[queue_tail].len <= arlen;
            request_queue[queue_tail].id <= arid;
            request_queue[queue_tail].size <= arsize;
            request_queue[queue_tail].burst <= arburst;
            queue_tail <= (queue_tail + 1) % MAX_OUTSTANDING;
        end

        // 状态转换逻辑
        case (state)
            ST_IDLE: begin
                if (!queue_empty) begin
                    state_next <= ST_SEND_DATA;
                end else begin
                    state_next <= ST_IDLE;
                end
            end
            
            ST_SEND_DATA: begin
                // 如果队列空且没有处理请求，返回空闲
                if (queue_empty && !processing_request) begin
                    state_next <= ST_IDLE;
                end else begin
                    state_next <= ST_SEND_DATA;
                end
            end
            
            default: state_next <= ST_IDLE;
        endcase
        
        // 调试信息
        //$display("[DEBUG] time=%0t: state=%b, processing_request=%b, beats_remaining=%d, queue_head=%d, queue_tail=%d",
                 //$time, state, processing_request, beats_remaining, queue_head, queue_tail);
    end
end

// 数据通道处理
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rvalid <= 1'b0;
        rdata <= '0;
        rlast <= 1'b0;
        rresp <= 2'b00;
        rid <= 4'd0;
        beats_remaining <= 0;
        processing_request <= 0;
        current_request.addr <= 0;
        current_request.len <= 0;
        current_request.id <= 0;
        current_request.size <= 0;
        current_request.burst <= 0;
    end else begin
        // 处理握手完成后的信号撤销
        if (rvalid && rready) begin
            rvalid <= 1'b0;
            rlast <= 1'b0;
            $display("[SLAVE_R_DEBUG] time=%0t: data=%h, last=%b, id=%h, beats_remaining=%d, processing_request=%b", 
                    $time, rdata, rlast, rid, beats_remaining, processing_request);
            
            // 减少剩余beat数
            beats_remaining <= beats_remaining - 1;
            
            // 如果这是最后一个beat，结束处理
            if (beats_remaining == 1) begin
                processing_request <= 1'b0;
                beats_remaining <= 0; // 确保计数器清零
                queue_head  <= (queue_head + 1) % MAX_OUTSTANDING;
            end
        end else if (!rready) begin
            // 如果rready无效，撤销rvalid
            rvalid <= 1'b0;
        end
        
        // 处理新请求
        if (!processing_request && !queue_empty) begin
            // 开始处理新请求
            current_request <= request_queue[queue_head];
            beats_remaining <= request_queue[queue_head].len + 1;
            processing_request <= 1'b1;
            queue_head <= (queue_head + 1) % MAX_OUTSTANDING;
            
            // 如果队列为空，重置指针以确保queue_empty正确
            //if (queue_head == queue_tail) begin
               // queue_head <= 0;
               // queue_tail <= 0;
            //end
        end
        
        // 发送数据逻辑
        if (processing_request && !rvalid) begin
            integer word_idx;
            word_idx = current_request.addr >> ADDR_LSB;
            
            if (current_request.addr >= (MEM_DEPTH << ADDR_LSB)) begin
                rdata <= {AXI_DATA_W{1'bx}};
                rresp <= 2'b10; // SLVERR
            end else begin
                rdata <= mem[word_idx];
                rresp <= 2'b00; // OKAY
            end
            
            rid <= current_request.id;
            rvalid <= 1'b1;
            rlast <= (beats_remaining == 1);
            
            // 更新地址
            current_request.addr <= current_request.addr + DATA_BYTES;
        end
    end
end

endmodule