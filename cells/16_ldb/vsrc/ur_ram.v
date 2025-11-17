module ur_ram #(
    parameter UR_DEPTH = 2048,     // UR深度
    parameter DATA_WIDTH = 128,    // 数据宽度
    parameter ADDR_WIDTH = 11      // 地址宽度
)(
    input wire clk,
    input wire rst_n,
    
    // 写接口
    input wire we,
    input wire [5:0] smc_id,       // SMC标识
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] wdata,
    
    // 读接口（用于验证）
    input wire re,
    input wire [ADDR_WIDTH-1:0] raddr,
    output reg [DATA_WIDTH-1:0] rdata,
    
    // 调试输出
    output reg [DATA_WIDTH-1:0] debug_data
);

// 用户寄存器内存（为每个SMC分配独立空间）
reg [DATA_WIDTH-1:0] ur_memory [0:UR_DEPTH-1];

// 写操作
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 可选的初始化
    end else begin
        if (we) begin
            ur_memory[addr] <= wdata;
            $display("[UR_RAM] Write: SMC%d, addr=%h, data=%h", smc_id, addr, wdata);
        end
    end
end

// 读操作
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rdata <= '0;
    end else begin
        if (re) begin
            rdata <= ur_memory[raddr];
        end
    end
end

// 调试输出（总是输出最近写入的数据）
always @(posedge clk) begin
    if (we) begin
        debug_data <= wdata;
    end
end

// 初始化（可选）
initial begin
    for (int i = 0; i < UR_DEPTH; i++) begin
        ur_memory[i] = '0;
    end
end

endmodule