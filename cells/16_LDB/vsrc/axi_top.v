`timescale 1ns/1ps

`default_nettype none

module axi_top #(
    parameter AXI_ADDR_W = 64,
    parameter AXI_DATA_W = 128,
    parameter AXI_ID_W = 4,
    parameter MEM_DEPTH = 1024,
    parameter UR_BYTE_CNT = 16,
    parameter GR_INTLV = 64
)(
    input wire clk,
    input wire rst_n,
    
    // LDB指令接口
    input wire [127:0] cru_ldb_i,
    input wire [1:0] crd_ldb_i,
    output wire [127:0] cru_ldb_o,
    output wire [1:0] crd_ldb_o,
    
    // UR接口
    output wire ur_we,
    output wire [10:0] ur_addr,
    output wire [127:0] ur_wdata
);

// AXI 通道信号
wire arvalid;
wire arready;
wire [AXI_ADDR_W-1:0] araddr;
wire [7:0] arlen;
wire [2:0] arsize;
wire [1:0] arburst;
wire [AXI_ID_W-1:0] arid;
wire rvalid;
wire rready;
wire [AXI_DATA_W-1:0] rdata;
wire rlast;
wire [1:0] rresp;
wire [AXI_ID_W-1:0] rid;

// LDB控制信号
wire ldb_axi_req_valid;
wire ldb_axi_req_ready;
wire [AXI_ADDR_W-1:0] ldb_axi_req_addr;
wire [8:0] ldb_axi_req_len;
wire ldb_axi_req_done;
wire ldb_axi_req_err;

// AXI数据输出
wire axi_out_valid;
wire [AXI_DATA_W-1:0] axi_out_data;
wire axi_out_last;

// 协议检查器错误输出
wire [3:0] checker_error_code;
wire [AXI_ID_W-1:0] checker_error_id;

// 实例化 LDB（控制中枢）
ldb #(
    .param_ur_byte_cnt(UR_BYTE_CNT),
    .param_gr_intlv_addr(GR_INTLV),
    .param_smc_cnt(1),
    .ur_addr_w(11),
    .gr_addr_w(AXI_ADDR_W), // 使用AXI地址位宽
    .brst_w(16)
) u_ldb (
    .clk(clk),
    .rst_n(rst_n),
    .cru_ldb_i(cru_ldb_i),
    .crd_ldb_i(crd_ldb_i),
    .axi_req_valid(ldb_axi_req_valid),
    .axi_req_ready(ldb_axi_req_ready),
    .axi_req_addr(ldb_axi_req_addr),
    .axi_req_len(ldb_axi_req_len),
    .axi_req_done(ldb_axi_req_done),
    .axi_req_err(ldb_axi_req_err),
    .axi_data_valid(axi_out_valid),
    .axi_data(axi_out_data),
    .axi_data_last(axi_out_last),
    .ur_we(ur_we),
    .ur_addr(ur_addr),
    .ur_wdata(ur_wdata),
    .cru_ldb_o(cru_ldb_o),
    .crd_ldb_o(crd_ldb_o)
);

// 实例化 AXI Master（纯传输层）
ldb_axi_read_master #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .AXI_ID_W(AXI_ID_W),
    .MAX_LEN(255),
    .MEM_DEPTH(MEM_DEPTH),
    .MAX_OUTSTANDING(1)
) u_axi_master (
    .clk(clk),
    .rst_n(rst_n),
    // LDB控制接口
    .req_valid(ldb_axi_req_valid),
    .req_ready(ldb_axi_req_ready),
    .req_addr(ldb_axi_req_addr),
    .req_len(ldb_axi_req_len),
    .req_done(ldb_axi_req_done),
    .req_err(ldb_axi_req_err),
    // AXI 读地址通道
    .arvalid(arvalid),
    .arready(arready),
    .araddr(araddr),
    .arlen(arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arid(arid),
    .arqos(),
    .arlock(),
    .arcache(),
    .arprot(),
    // AXI 读数据通道
    .rvalid(rvalid),
    .rready(rready),
    .rdata(rdata),
    .rlast(rlast),
    .rresp(rresp),
    .rid(rid),
    // 用户流输出（连接到LDB）
    .out_valid(axi_out_valid),
    .out_ready(1'b1), // LDB总是准备好接收数据
    .out_data(axi_out_data),
    .out_last(axi_out_last)
);

// 实例化 AXI Slave（内存模型）
axi_read_mem_slave #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .MEM_DEPTH(MEM_DEPTH),
    .MAX_OUTSTANDING(4)
) u_axi_slave (
    .clk(clk),
    .rst_n(rst_n),
    .arvalid(arvalid),
    .arready(arready),
    .araddr(araddr),
    .arlen(arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arid(arid),
    .rvalid(rvalid),
    .rready(rready),
    .rdata(rdata),
    .rlast(rlast),
    .rresp(rresp),
    .rid(rid)
);

// 实例化协议检查器
axi_protocol_checker #(
    .AXI_ADDR_W(AXI_ADDR_W),
    .AXI_DATA_W(AXI_DATA_W),
    .AXI_ID_W(AXI_ID_W),
    .TIMEOUT_CYCLES(100)
) u_protocol_checker (
    .clk(clk),
    .rst_n(rst_n),
    .arvalid(arvalid),
    .arready(arready),
    .araddr(araddr),
    .arlen(arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arid(arid),
    .rvalid(rvalid),
    .rready(rready),
    .rdata(rdata),
    .rlast(rlast),
    .rresp(rresp),
    .rid(rid),
    .error_code(checker_error_code),
    .error_id(checker_error_id)
);

// 实例化 UR_RAM
ur_ram #(
    .ADDR_W(11),
    .DATA_W(128)
) u_ur (
    .clk(clk),
    .we(ur_we),
    .addr(ur_addr),
    .wdata(ur_wdata),
    .rdata() // 未连接读取端口
);

endmodule