// ldb_axi_top.v
`timescale 1ns/1ps
`default_nettype none

`include "DW_axi_gm_cc_constants.vh"
`include "DW_axi_gm_constants.vh"

module ldb_axi_top #(
    parameter param_ur_byte_cnt = 16,
    parameter param_gr_intlv_addr = 32,
    parameter param_smc_cnt = 64,
    parameter ur_addr_w = 11,
    parameter gr_addr_w = 64,
    parameter brst_w = 16
)(
    input wire clk,
    input wire rst_n,
    
    // 指令输入接口
    input wire [127:0] cru_ldb_i,
    input wire [1:0] crd_ldb_i,
    
    // AXI主设备接口（连接到外部AXI总线）
    // AXI写请求
    output wire [`GM_ID-1:0] awid,
    output wire awvalid,
    output wire [`GM_AW-1:0] awaddr,
    output wire [`GM_BW-1:0] awlen,
    output wire [2:0] awsize,
    output wire [1:0] awburst,
    output wire [`GM_W_LTW-1:0] awlock,
    output wire [3:0] awcache,
    output wire [2:0] awprot,
    input  wire awready,
    
    // AXI写数据
    output wire wvalid,
    output wire wlast,
    output wire [`GM_DW-1:0] wdata,
    output wire [`GM_WW-1:0] wstrb,
    input  wire wready,
    
    // AXI写响应
    input  wire [`GM_ID-1:0] bid,
    input  wire bvalid,
    input  wire [1:0] bresp,
    output wire bready,
    
    // AXI读请求
    output wire [`GM_ID-1:0] arid,
    output wire arvalid,
    output wire [`GM_AW-1:0] araddr,
    output wire [`GM_BW-1:0] arlen,
    output wire [2:0] arsize,
    output wire [1:0] arburst,
    output wire [`GM_W_LTW-1:0] arlock,
    output wire [3:0] arcache,
    output wire [2:0] arprot,
    input  wire arready,
    
    // AXI读响应
    input  wire [`GM_ID-1:0] rid,
    input  wire rvalid,
    input  wire rlast,
    input  wire [`GM_DW-1:0] rdata,
    input  wire [1:0] rresp,
    output wire rready,
    
    // UR接口
    output wire ur_we,
    output wire [5:0] smc_index,
    output wire [ur_addr_w-1:0] ur_addr,
    output wire [param_ur_byte_cnt*8-1:0] ur_wdata,
    
    // 响应输出接口
    output wire [127:0] cru_ldb_o,
    output wire [1:0] crd_ldb_o
);

    // LDB到DW_axi_gm的GIF接口信号
    wire [`GM_ID-1:0] mid;
    wire [`GM_AW-1:0] maddr;
    wire mread;
    wire mwrite;
    wire [`GM_BW-1:0] mlen;
    wire [2:0] msize;
    wire [1:0] mburst;
    wire [3:0] mcache;
    wire [2:0] mprot;
    wire [`GM_DW-1:0] mdata;
    wire [`GM_WW-1:0] mwstrb;
    wire saccept;
    
    // DW_axi_gm到LDB的响应信号
    wire [`GM_ID-1:0] sid;
    wire svalid;
    wire slast;
    wire [`GM_DW-1:0] sdata;
    wire [2:0] sresp;
    wire mready;

    // 实例化LDB核心
    ldb #(
        .param_ur_byte_cnt(param_ur_byte_cnt),
        .param_gr_intlv_addr(param_gr_intlv_addr),
        .param_smc_cnt(param_smc_cnt),
        .ur_addr_w(ur_addr_w),
        .gr_addr_w(gr_addr_w),
        .brst_w(brst_w)
    ) u_ldb (
        .clk(clk),
        .rst_n(rst_n),
        
        // 指令输入接口
        .cru_ldb_i(cru_ldb_i),
        .crd_ldb_i(crd_ldb_i),
        
        // GIF接口（连接到DW_axi_gm）
        .mid(mid),
        .maddr(maddr),
        .mread(mread),
        .mwrite(mwrite),
        .mlen(mlen),
        .msize(msize),
        .mburst(mburst),
        .mcache(mcache),
        .mprot(mprot),
        .mdata(mdata),
        .mwstrb(mwstrb),
        .saccept(saccept),
        .sid(sid),
        .svalid(svalid),
        .slast(slast),
        .sdata(sdata),
        .sresp(sresp),
        .mready(mready),
        
        // UR接口
        .ur_we(ur_we),
        .smc_index(smc_index),
        .ur_addr(ur_addr),
        .ur_wdata(ur_wdata),
        
        // 响应输出接口
        .cru_ldb_o(cru_ldb_o),
        .crd_ldb_o(crd_ldb_o)
    );

    // 实例化DW_axi_gm
    DW_axi_gm u_dw_axi_gm (
        .aclk(clk),
        .aresetn(rst_n),
        .gclken(1'b1),  // 始终使能
        
        // Generic Interface (连接到LDB)
        .mid(mid),
        .maddr(maddr),
        .mread(mread),
        .mwrite(mwrite),
        .mlen(mlen),
        .msize(msize),
        .mburst(mburst),
        .mcache(mcache),
        .mprot(mprot),
        .mdata(mdata),
        .mwstrb(mwstrb),
        .saccept(saccept),
        .sid(sid),
        .svalid(svalid),
        .slast(slast),
        .sdata(sdata),
        .sresp(sresp),
        .mready(mready),
        
        // AXI Manager Interface (连接到外部AXI总线)
        // AXI写请求
        .awid(awid),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .awlen(awlen),
        .awsize(awsize),
        .awburst(awburst),
        .awlock(awlock),
        .awcache(awcache),
        .awprot(awprot),
        .awready(awready),
        
        // AXI写数据
        .wvalid(wvalid),
        .wlast(wlast),
        .wdata(wdata),
        .wstrb(wstrb),
        .wready(wready),
        
        // AXI写响应
        .bid(bid),
        .bvalid(bvalid),
        .bresp(bresp),
        .bready(bready),
        
        // AXI读请求
        .arid(arid),
        .arvalid(arvalid),
        .araddr(araddr),
        .arlen(arlen),
        .arsize(arsize),
        .arburst(arburst),
        .arlock(arlock),
        .arcache(arcache),
        .arprot(arprot),
        .arready(arready),
        
        // AXI读响应
        .rid(rid),
        .rvalid(rvalid),
        .rlast(rlast),
        .rdata(rdata),
        .rresp(rresp),
        .rready(rready)
    );

endmodule