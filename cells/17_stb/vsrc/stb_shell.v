//=========================================================================
// Project:     AIACC
// File:        stb_shell.v
// Module:      stb_shell
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2025-11-6
// Modified:    2025-11-6
// Version:     v0.1
//=========================================================================

// Description:
// sbt shell for test

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
//user_reg_model-->ur_axi_conv-->DW_axi_gm-->DW_axi_gs-->memory_model
module stb_shell #(
    parameter UR_ADDR_WIDTH     = 11,
    parameter ADDR_WIDTH        = 32,
    parameter DATA_WIDTH        = 128,
    parameter BYTE_STRB         = DATA_WIDTH/8,
    parameter INTLV_STEP        = 128     //SMC  interleave step
) (
    input                           clk,
    input                           rst_n,

    //micro instruction
    input                       i_micro_inst_u_valid,
    input [5:0]                 i_micro_inst_u_smc_strb,
    input [3:0]                 i_micro_inst_u_byte_strb,
    input [1:0]                 i_micro_inst_u_brst,           // （2bit：00=1，01=2，10=4，11=8）
    input [ADDR_WIDTH-1:0]      i_micro_inst_u_gr_base_addr,   // outside sram addr
    input [3:0]                 i_micro_inst_u_ur_id,
    input [UR_ADDR_WIDTH-1:0]   i_micro_inst_u_ur_addr,        //user addr
    output                      o_micro_inst_d_valid,
    output                      o_micro_inst_d_done,

    input  [DATA_WIDTH-1:0]     i_src_random_data,
    output [4:0]                o_state
);

wire                            w_ur_re;
wire   [UR_ADDR_WIDTH-1:0]      w_ur_addr;
wire   [DATA_WIDTH-1:0]         w_ur_rdata;

wire   [ADDR_WIDTH-1:0]         w_gs_maddr;
wire                            w_gs_mread;
wire                            w_gs_mwrite;
wire   [2:0]                    w_gs_msize;
wire   [1:0]                    w_gs_mburst;
wire   [3:0]                    w_gs_mlen;
wire                            w_gs_mlast;
wire   [DATA_WIDTH-1:0]         w_gs_mdata;
wire   [BYTE_STRB-1:0]          w_gs_mwstrb;
wire                            w_gs_saccept;

wire [3:0]                      w_awid;
wire                            w_awvalid;
wire [ADDR_WIDTH-1:0]           w_awaddr;
wire [3:0]                      w_awlen;
wire [2:0]                      w_awsize;
wire [1:0]                      w_awburst;
wire [0:0]                      w_awlock;
wire [3:0]                      w_awcache;
wire [2:0]                      w_awprot;
wire                            w_awready;
wire                            w_wvalid;
wire                            w_wlast;
wire [DATA_WIDTH-1:0]           w_wdata;
wire [BYTE_STRB-1:0]            w_wstrb;
wire                            w_wready;
wire [3:0]                      w_bid;
wire                            w_bvalid;
wire [1:0]                      w_bresp;
wire                            w_bready;  
wire [3:0]                      w_arid;
wire                            w_arvalid;
wire [ADDR_WIDTH-1:0]           w_araddr;
wire [3:0]                      w_arlen;
wire [2:0]                      w_arsize;
wire [1:0]                      w_arburst;
wire [0:0]                      w_arlock;
wire [3:0]                      w_arcache;
wire [2:0]                      w_arprot; 
wire                            w_arready;
wire [3:0]                      w_rid;
wire                            w_rvalid;
wire                            w_rlast;
wire [DATA_WIDTH-1:0]           w_rdata;
wire [1:0]                      w_rresp;
wire                            w_rready;

wire                            w_svalid;
wire [1:0]                      w_sresp;

user_reg_model #(
    .DATA_WIDTH       (DATA_WIDTH),
    .UR_ADDR_WIDTH    (UR_ADDR_WIDTH)
) u_user_reg_model(
    .clk                   (clk),
    .rst_n                 (rst_n),
    .ur_re                 (w_ur_re),
    .ur_addr               (w_ur_addr),
    .ur_rdata              (w_ur_rdata),
    .i_src_random_data     (i_src_random_data)
);

stb_top  #(
    .DATA_WIDTH      (DATA_WIDTH),
    .ADDR_WIDTH      (ADDR_WIDTH),
    .INTLV_STEP      (INTLV_STEP),
    .UR_ADDR_WIDTH   (UR_ADDR_WIDTH)
) u_stb_top(
    .clk                          (clk),
    .rst_n                        (rst_n),

    .i_micro_inst_u_valid         (i_micro_inst_u_valid),
    .i_micro_inst_u_smc_strb      (i_micro_inst_u_smc_strb),
    .i_micro_inst_u_byte_strb     (i_micro_inst_u_byte_strb),
    .i_micro_inst_u_brst          (i_micro_inst_u_brst),
    .i_micro_inst_u_gr_base_addr  (i_micro_inst_u_gr_base_addr),
    .i_micro_inst_u_ur_id         (i_micro_inst_u_ur_id),
    .i_micro_inst_u_ur_addr       (i_micro_inst_u_ur_addr),
    .o_micro_inst_d_valid         (o_micro_inst_d_valid),
    .o_micro_inst_d_done          (o_micro_inst_d_done),
    .o_state                      (o_state),

    .o_ur_re                      (w_ur_re),
    .o_ur_addr                    (w_ur_addr),
    .i_ur_rdata                   (w_ur_rdata),
    .i_smc_id                     (5'd0),

    .awid                         (w_awid),
    .awvalid                      (w_awvalid),
    .awaddr                       (w_awaddr),
    .awlen                        (w_awlen),
    .awsize                       (w_awsize),
    .awburst                      (w_awburst),
    .awlock                       (w_awlock),
    .awcache                      (w_awcache),
    .awprot                       (w_awprot),
    .awready                      (w_awready),

    .wvalid                       (w_wvalid),
    .wlast                        (w_wlast),
    .wdata                        (w_wdata),
    .wstrb                        (w_wstrb),
    .wready                       (w_wready),
    
    .bid                          (w_bid),
    .bvalid                       (w_bvalid),
    .bresp                        (w_bresp),
    .bready                       (w_bready),

    .arid                         (w_arid),
    .arvalid                      (w_arvalid),
    .araddr                       (w_araddr),
    .arlen                        (w_arlen),
    .arsize                       (w_arsize),
    .arburst                      (w_arburst),
    .arlock                       (w_arlock),
    .arcache                      (w_arcache),
    .arprot                       (w_arprot),
    .arready                      (w_arready),

    .rid                          (w_rid),
    .rvalid                       (w_rvalid),
    .rlast                        (w_rlast),
    .rdata                        (w_rdata),
    .rresp                        (w_rresp),
    .rready                       (w_rready)
);

DW_axi_gs U_DW_axi_gs(
    .aclk                         (clk),
    .aresetn                      (rst_n),
    .gclken                       (1'b1),

    .awid                         (w_awid),
    .awaddr                       (w_awaddr),
    .awlen                        (w_awlen),
    .awsize                       (w_awsize),
    .awburst                      (w_awburst),
    .awlock                       (w_awlock),
    .awcache                      (w_awcache),
    .awprot                       (w_awprot),
    .awvalid                      (w_awvalid),
    .awready                      (w_awready),

    .wlast                        (w_wlast),
    .wdata                        (w_wdata),
    .wstrb                        (w_wstrb),
    .wvalid                       (w_wvalid),
    .wready                       (w_wready),

    .bid                          (w_bid),
    .bresp                        (w_bresp),
    .bvalid                       (w_bvalid),
    .bready                       (w_bready),

    .arid                         (w_arid),
    .araddr                       (w_araddr),
    .arlen                        (w_arlen),
    .arsize                       (w_arsize),
    .arburst                      (w_arburst),
    .arlock                       (w_arlock),
    .arcache                      (w_arcache),
    .arprot                       (w_arprot),
    .arvalid                      (w_arvalid),
    .arready                      (w_arready),

    .rid                          (w_rid),
    .rdata                        (w_rdata),
    .rresp                        (w_rresp),
    .rlast                        (w_rlast),
    .rvalid                       (w_rvalid),
    .rready                       (w_rready),

    .maddr                        (w_gs_maddr),
    .mread                        (w_gs_mread),
    .mwrite                       (w_gs_mwrite),
    .msize                        (w_gs_msize),
    .mburst                       (w_gs_mburst),
    .mlen                         (w_gs_mlen),
    .mlast                        (w_gs_mlast),
    .mdata                        (w_gs_mdata),
    .mwstrb                       (w_gs_mwstrb),
    .saccept                      (w_gs_saccept),

    .svalid                       (w_svalid),
    .sresp                        (w_sresp),
    .sdata                        ({DATA_WIDTH{1'b0}}),
    .mready                       (w_mready)
);

memory_model #(
    .ADDR_WIDTH      (ADDR_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH),
    .BYTE_STRB       (BYTE_STRB)
) u_memory_model (
    .clk                          (clk),
    .rst_n                        (rst_n),
    .i_maddr                      (w_gs_maddr),
    .i_mread                      (w_gs_mread),
    .i_mwrite                     (w_gs_mwrite),
    .i_msize                      (w_gs_msize),
    .i_mburst                     (w_gs_mburst),
    .i_mlen                       (w_gs_mlen),
    .i_mlast                      (w_gs_mlast),
    .i_mdata                      (w_gs_mdata),
    .i_mwstrb                     (w_gs_mwstrb),
    .o_saccept                    (w_gs_saccept),
    .o_svalid                     (w_svalid),
    .o_sresp                      (w_sresp),
    .i_mready                     (w_mready)
);

endmodule
