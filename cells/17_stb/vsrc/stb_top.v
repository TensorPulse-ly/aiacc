//=========================================================================
// Project:     AIACC
// File:        sbt_top.v
// Module:      sbt_top
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2025-11-6
// Modified:    2025-11-6
// Version:     v0.1
//=========================================================================

// Description:
// sbt top

// Parameters:
// - BYTE_STRB     : Byte valid flag
// - DATA_WIDTH    : Data bus width in bits (default: 128)
// - ADDR_WIDTH    : Address bus width in bits (default: 32)
// - UR_ADDR_WIDTH : User register address bus width in bits (default: 11)
// - INTLV_STEP    : SMC interleave step

//=========================================================================
// Revision History:
// v0.1 - 2025-11-6  - Initial version
//
//=========================================================================
`timescale 1ns/1ps
module stb_top #(
    parameter UR_ADDR_WIDTH     = 11,
    parameter ADDR_WIDTH        = 32,
    parameter DATA_WIDTH        = 128,
    parameter BYTE_STRB         = DATA_WIDTH/8,
    parameter INTLV_STEP        = 128     //SMC  interleave step
) (
    input                           clk,
    input                           rst_n,

    //micro instruction
    input                           i_micro_inst_u_valid,
    input [5:0]                     i_micro_inst_u_smc_strb,
    input [3:0]                     i_micro_inst_u_byte_strb,
    input [1:0]                     i_micro_inst_u_brst,           // （2bit：00=1，01=2，10=4，11=8）
    input [ADDR_WIDTH-1:0]          i_micro_inst_u_gr_base_addr,   // outside sram addr
    input [3:0]                     i_micro_inst_u_ur_id,
    input [UR_ADDR_WIDTH-1:0]       i_micro_inst_u_ur_addr,        //user addr
    output                          o_micro_inst_d_valid,
    output                          o_micro_inst_d_done,

    output                          o_ur_re,
    output [UR_ADDR_WIDTH-1:0]      o_ur_addr,
    input  [DATA_WIDTH-1:0]         i_ur_rdata,
    input  [4:0]                    i_smc_id,

    // AXI write request
    output [3:0]                    awid,
    output                          awvalid,
    output [ADDR_WIDTH-1:0]         awaddr,
    output [3:0]                    awlen,
    output [2:0]                    awsize,
    output [1:0]                    awburst,
    output [0:0]                    awlock,
    output [3:0]                    awcache,
    output [2:0]                    awprot,
    input                           awready,

    // AXI write data
    output                          wvalid,
    output                          wlast,
    output [DATA_WIDTH-1:0]         wdata,
    output [BYTE_STRB-1:0]          wstrb,
    input                           wready,

    // AXI write response
    input [3:0]                     bid,
    input                           bvalid,
    input [1:0]                     bresp,
    output                          bready,  
  
    // AXI read request
    output [3:0]                    arid,
    output                          arvalid,
    output [ADDR_WIDTH-1:0]         araddr,
    output [3:0]                    arlen,
    output [2:0]                    arsize,
    output [1:0]                    arburst,
    output [0:0]                    arlock,
    output [3:0]                    arcache,
    output [2:0]                    arprot,
    input                           arready,

    // AXI read response & read data
    input [3:0]                     rid,
    input                           rvalid,
    input                           rlast,
    input [DATA_WIDTH-1:0]          rdata,
    input [1:0]                     rresp,
    output                          rready,
    output [4:0]                    o_state

);

wire   [3:0]                    w_gm_mid;
wire   [ADDR_WIDTH-1:0]         w_gm_maddr;
wire                            w_gm_mread;
wire                            w_gm_mwrite;
wire   [3:0]                    w_gm_mlen;
wire   [2:0]                    w_gm_msize;
wire   [1:0]                    w_gm_mburst;
wire   [3:0]                    w_gm_mcache;
wire   [2:0]                    w_gm_mport;
wire   [DATA_WIDTH-1:0]         w_gm_mdata;
wire   [BYTE_STRB-1:0]          w_gm_mwstrb;
wire                            w_gm_saccept;

ur_axi_conv #(
    .DATA_WIDTH      (DATA_WIDTH),
    .ADDR_WIDTH      (ADDR_WIDTH),
    .INTLV_STEP      (INTLV_STEP),
    .UR_ADDR_WIDTH   (UR_ADDR_WIDTH)
) u_ur_axi_conv(
    .clk                          (clk),
    .rst_n                        (rst_n),
    .o_mid                        (w_gm_mid),
    .o_maddr                      (w_gm_maddr),
    .o_mread                      (w_gm_mread),
    .o_mwrite                     (w_gm_mwrite),
    .o_mlen                       (w_gm_mlen),
    .o_msize                      (w_gm_msize),
    .o_mburst                     (w_gm_mburst),
    .o_mcache                     (w_gm_mcache),
    .o_mport                      (w_gm_mport),
    .o_mdata                      (w_gm_mdata),
    .o_mwstrb                     (w_gm_mwstrb),
    .i_saccept                    (w_gm_saccept),

    .o_ur_re                      (o_ur_re),
    .o_ur_addr                    (o_ur_addr),
    .i_ur_rdata                   (i_ur_rdata),

    .i_micro_inst_u_valid         (i_micro_inst_u_valid),
    .i_micro_inst_u_smc_strb      (i_micro_inst_u_smc_strb),
    .i_micro_inst_u_byte_strb     (i_micro_inst_u_byte_strb),
    .i_micro_inst_u_brst          (i_micro_inst_u_brst),
    .i_micro_inst_u_gr_base_addr  (i_micro_inst_u_gr_base_addr),
    .i_micro_inst_u_ur_id         (i_micro_inst_u_ur_id),
    .i_micro_inst_u_ur_addr       (i_micro_inst_u_ur_addr),
    .o_micro_inst_d_valid         (o_micro_inst_d_valid),
    .o_micro_inst_d_done          (o_micro_inst_d_done),
    .o_state                      (o_state)
);

reg [7:0] ready_random;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        ready_random     <= 8'd0;
    else
        ready_random     <= ready_random + 8'd1;
end

DW_axi_gm u_DW_axi_gm(
    .aclk                         (clk),
    .aresetn                      (rst_n),
    .gclken                       (1'b1),

    .mid                          (w_gm_mid),
    .maddr                        (w_gm_maddr),
    .mread                        (w_gm_mread),
    .mwrite                       (w_gm_mwrite),
    .mlen                         (w_gm_mlen),
    .msize                        (w_gm_msize),
    .mburst                       (w_gm_mburst),
    .mcache                       (w_gm_mcache),
    .mprot                        (w_gm_mport),
    .mdata                        (w_gm_mdata),
    .mwstrb                       (w_gm_mwstrb),
    .saccept                      (w_gm_saccept),

    .sid                          (),
    .svalid                       (),
    .slast                        (),
    .sdata                        (),
    .sresp                        (),
    .mready                       (ready_random[5]),     //GIF response accept,when manager is not ready to accept response, it drives mready low

    .awid                         (awid),
    .awvalid                      (awvalid),
    .awaddr                       (awaddr),
    .awlen                        (awlen),
    .awsize                       (awsize),
    .awburst                      (awburst),
    .awlock                       (awlock),
    .awcache                      (awcache),
    .awprot                       (awprot),
    .awready                      (awready),

    .wvalid                       (wvalid),
    .wlast                        (wlast),
    .wdata                        (wdata),
    .wstrb                        (wstrb),
    .wready                       (wready),
    
    .bid                          (bid),
    .bvalid                       (bvalid),
    .bresp                        (bresp),
    .bready                       (bready),

    .arid                         (arid),
    .arvalid                      (arvalid),
    .araddr                       (araddr),
    .arlen                        (arlen),
    .arsize                       (arsize),
    .arburst                      (arburst),
    .arlock                       (arlock),
    .arcache                      (arcache),
    .arprot                       (arprot),
    .arready                      (arready),

    .rid                          (rid),
    .rvalid                       (rvalid),
    .rlast                        (rlast),
    .rdata                        (rdata),
    .rresp                        (rresp),
    .rready                       (rready)
);
endmodule
