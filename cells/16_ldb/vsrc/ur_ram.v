
module ur_ram #(
    parameter ADDR_W = 11,
    parameter DATA_W = 128
)(
    input  wire               clk,
    input  wire               we,
    input  wire [ADDR_W-1:0]  addr,
    input  wire [DATA_W-1:0]  wdata,
    output wire [DATA_W-1:0]  rdata
);
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    // 同步写操作：在时钟上升沿，如果写使能有效，将数据写入指定地址
    always @(posedge clk) if (we) mem[addr] <= wdata;
    // 异步读操作：地址addr变化后，立即输出对应地址的数据
    assign rdata = mem[addr];
endmodule
