`timescale 1ns/1ps

module axi_read_mem_slave #(
    parameter MEM_SIZE = 4096,     // 内存大小（字节）
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH = 4,        // ID宽度
    parameter LEN_WIDTH = 4        // 长度宽度
)(
    input wire aclk,
    input wire aresetn,
    
    // AXI读地址通道
    input wire [ID_WIDTH-1:0] arid,
    input wire arvalid,
    output reg arready,
    input wire [ADDR_WIDTH-1:0] araddr,
    input wire [LEN_WIDTH-1:0] arlen,
    input wire [2:0] arsize,
    input wire [1:0] arburst,
    
    // AXI读数据通道
    output reg [ID_WIDTH-1:0] rid,
    output reg rvalid,
    input wire rready,
    output reg rlast,
    output reg [DATA_WIDTH-1:0] rdata,
    output reg [1:0] rresp
);

    // 内存数组
    reg [DATA_WIDTH-1:0] memory [0:MEM_SIZE/(DATA_WIDTH/8)-1];
    
    // 内部状态
    reg [LEN_WIDTH-1:0] burst_counter;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [LEN_WIDTH-1:0] current_len;
    reg burst_active;
    
    // 初始化内存（示例数据）
    initial begin
        for (int i = 0; i < MEM_SIZE/(DATA_WIDTH/8); i++) begin
            // 填充有意义的测试数据
            memory[i] = {32'hDEADBEEF, 32'h12345678, 32'hA5A5A5A5, 32'h00000000 + (i * 16)};
        end
        burst_active = 1'b0;
        arready = 1'b1;  // 初始时准备好
        rvalid = 1'b0;
        rlast = 1'b0;
        rresp = 2'b00;
    end
    
    // 读地址通道
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            arready <= 1'b1;
            burst_active <= 1'b0;
            burst_counter <= '0;
            current_addr <= '0;
            current_len <= '0;
        end else begin
            if (arvalid && arready && !burst_active) begin
                // 接受新的读请求
                current_addr <= araddr;
                current_len <= arlen;
                burst_counter <= 0;
                burst_active <= 1'b1;
                arready <= 1'b0; // 暂时不接受新请求
                $display("[AXI_MEM] Read request: addr=%h, len=%d", araddr, arlen);
            end
            
            if (burst_active && rlast && rvalid && rready) begin
                // Burst完成，重新准备接受请求
                burst_active <= 1'b0;
                arready <= 1'b1;
                $display("[AXI_MEM] Burst transfer completed");
            end
        end
    end
    
    // 检查是否包含未知值的辅助函数
    function automatic bit has_x(input [LEN_WIDTH-1:0] value);
        has_x = (^value === 1'bx);
    endfunction

    function automatic bit addr_has_x(input [ADDR_WIDTH-1:0] value);
        addr_has_x = (^value === 1'bx);
    endfunction

    // 读数据通道
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rvalid <= 1'b0;
            rlast <= 1'b0;
            rresp <= 2'b00; // OKAY响应
            rid <= '0;
            rdata <= '0;
        end else begin
            if (burst_active) begin
                if (!rvalid || (rvalid && rready)) begin
                    // 可以发送新数据
                    if (burst_counter <= current_len) begin
                        // 计算内存地址（字节地址转换为内存索引）
                        // 128位 = 16字节，所以除以16得到内存索引
                        reg [LEN_WIDTH-1:0] burst_counter_safe;
                        reg [ADDR_WIDTH-1:0] current_addr_safe;
                        integer mem_index;

                        burst_counter_safe = has_x(burst_counter) ? '0 : burst_counter;
                        current_addr_safe = addr_has_x(current_addr) ? '0 : current_addr;
                        mem_index = (current_addr_safe >> 4) + burst_counter_safe;
                        
                        if ((mem_index >= 0) && (mem_index < MEM_SIZE/(DATA_WIDTH/8))) begin
                            rdata <= memory[mem_index];
                            rvalid <= 1'b1;
                            rid <= arid;
                            rresp <= 2'b00; // OKAY响应
                            
                            // 检查是否是最后一个数据
                            if (burst_counter == current_len) begin
                                rlast <= 1'b1;
                                $display("[AXI_MEM] Sending last data: index=%d, data=%h", 
                                        mem_index, memory[mem_index]);
                            end else begin
                                rlast <= 1'b0;
                                $display("[AXI_MEM] Sending data[%d]: index=%d, data=%h", 
                                        burst_counter, mem_index, memory[mem_index]);
                            end
                            
                            burst_counter <= burst_counter + 1;
                        end else begin
                            // 地址越界 - 返回DECERR
                            rresp <= 2'b11; // DECERR
                            rvalid <= 1'b1;
                            rlast <= 1'b1;
                            rdata <= '0;
                            burst_active <= 1'b0;
                            arready <= 1'b1;
                            $display("[AXI_MEM_ERROR] Address out of range: %h, mem_index=%d, max_index=%d", 
                                    current_addr_safe, mem_index, MEM_SIZE/(DATA_WIDTH/8)-1);
                        end
                    end else begin
                        // Burst完成
                        rvalid <= 1'b0;
                        rlast <= 1'b0;
                        burst_active <= 1'b0;
                        arready <= 1'b1;
                    end
                end
            end else begin
                rvalid <= 1'b0;
                rlast <= 1'b0;
            end
        end
    end

endmodule