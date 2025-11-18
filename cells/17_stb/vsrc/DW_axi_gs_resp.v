// ---------------------------------------------------------------------
//
// ------------------------------------------------------------------------------
// 
// Copyright 2005 - 2022 Synopsys, INC.
// 
// This Synopsys IP and all associated documentation are proprietary to
// Synopsys, Inc. and may only be used pursuant to the terms and conditions of a
// written license agreement with Synopsys, Inc. All other use, reproduction,
// modification, or distribution of the Synopsys IP or the associated
// documentation is strictly prohibited.
// Inclusivity & Diversity - Visit SolvNetPlus to read the "Synopsys Statement on
//            Inclusivity and Diversity" (Refer to article 000036315 at
//                        https://solvnetplus.synopsys.com)
// 
// Component Name   : DW_axi_gs
// Component Version: 2.05a
// Release Type     : GA
// Build ID         : 19.15.20.7
// ------------------------------------------------------------------------------

// 
// Release version :  2.05a
// File Version     :        $Revision: #8 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gs/axi_dev_br/src/DW_axi_gs_resp.v#8 $ 
//
// -------------------------------------------------------------------------
//
// AUTHOR:    James Feagans      2/24/2005
//
// VERSION:   DW_axi_gs_resp Verilog Synthesis Model
//
//
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// ABSTRACT:  AXI to GIF Response Module
//
// This module handles the GIF to AXI transaction responses for RD and WR.
//
// Response datapath (resp):         <from req data path>
//                                        |          |
//                                   |--------| |--------|
//                                   |fifo_bid| |fifo_rid|
//                                   |--------| |--------|
//                                        |__________|
//                                             |                   mready
// AXI BRESP -\                    |---------| | /-----\           svalid
//  Channel    \___________________|fifo_resp|---|logic|------ GIF sdata
//             /                   |_________|   \-----/           sresp
// AXI RDATA -/
//  Channel
//
//
//-----------------------------------------------------------------------------

`include "DW_axi_gs_all_includes.vh"

module DW_axi_gs_resp(
  // AXI INTERFACE
  // Global
  aclk, 
                      aresetn,
                      // Write Response Channel
                      bid, 
                      bresp, 
                      bvalid, 
                      bready,
                      // Read Data Channel
                      rid, 
                      rdata, 
                      rresp, 
                      rlast, 
                      rvalid, 
                      rready,
                      // GENERIC SLAVE INTERFACE
                      // Global
                      gclken,
                      // Response Channel
                      svalid,
                      sdata,
                      sresp,
                      mready,
                      // INTERNAL CONNECTIONS
                      // Inputs from sm
                      start_wr, 
                      start_rd, 
                      // Inputs from req
                      id,
                      len,
                      exokay, 
                      exfail,
                      // Outputs to sm
                      advance_rd_ready, 
                      start_wr_ready, 
                      start_rd_ready
                      );
 
  
// ----------------------------------------------------------------------------
// PARAMETERS
// ----------------------------------------------------------------------------

parameter FBID_WIDTH  = `GS_ID+1+1;
parameter FRID_WIDTH  = `GS_ID+`GS_BW+1+1;
parameter FRESP_WIDTH =
        `GS_DW+`GS_ID+2+1+1+1;


// ----------------------------------------------------------------------------
// PORTS
// ----------------------------------------------------------------------------

// AXI INTERFACE
// Global
input  aclk;
input  aresetn;
// Write response channel
output [`GS_ID-1:0] bid;
output [1:0] bresp;
output bvalid;
input  bready;
// Read data channel
output [`GS_ID-1:0] rid;
output [`GS_DW-1:0] rdata;
output [1:0] rresp;
output rlast;
output rvalid;
input  rready;

// GENERIC SLAVE INTERFACE
// Global
input  gclken;
// Response Channel
input  svalid;
input  [`GS_DW-1:0] sdata;
input  [1:0] sresp;
output mready;


// INTERNAL CONNECTIONS
// Inputs from sm
input  start_wr;
input  start_rd;
// Inputs from req
input  [`GS_ID-1:0] id;
input  [`GS_BW-1:0] len;
input  exokay;
input  exfail;
// Outputs to sm
output start_wr_ready;
output start_rd_ready;
output advance_rd_ready;
// Outputs to low_pwr


// ----------------------------------------------------------------------------
// INTERNAL SIGNALS
// ----------------------------------------------------------------------------

wire fbexfail, fbexokay;
wire frexfail, frexokay;

// fifo_bid
wire fbid_src_rdy;
wire [FBID_WIDTH-1:0] fbid_src_data;
wire [FBID_WIDTH-1:0] fbid_dst_data;
wire [`GS_ID-1:0] fbid;

//In the configuration, ((@GS_LOWPWR_HS_IF==1) && (@GS_LOWPWR_LEGACY_IF == 0)), these signals are not used. 
// They are not removed because they come from different instances of the same module.
wire fbid_dst_vld;
wire frid_dst_vld;

wire [FRID_WIDTH-1:0] frid_dst_data;
// fifo_rid
wire frid_src_rdy;
wire [FRID_WIDTH-1:0] frid_src_data;
wire [`GS_BW-1:0] frlen;
wire [`GS_ID-1:0] frid;
wire [`GS_ID-1:0] muxed_id;
wire start_rd_gc;
wire start_wr_gc;
wire wr_resp_rdy;

// fifo_resp
wire [FRESP_WIDTH-1:0] fresp_src_data, fresp_dst_data;
wire fresp_src_rdy;
wire fresp_dst_rdy, fresp_dst_vld;

// indicates read response, write response, and last read response
wire rd_resp, wr_resp;
wire last_rd_resp;

// read response counter
reg  [`GS_BW-1:0] rd_resp_ctr;
wire  [`GS_BW-1:0] rd_resp_ctr_c;
wire [`GS_BW-1:0] next_rd_resp_ctr;


// internally or externally driven depending on `GS_GIF_SRESP
wire [1:0] sresp_int;
wire svalid_int;

// registers used for storing next automatic response

// multiplexed output of exfail and exokay signals of frid and fbid
wire dout_exfail, dout_exokay;

// AXI format of sresp_int for input into fifo_bresp or fifo_rdata
reg  [1:0] axi_sresp_int;

wire sresp_int_ok;



wire rw_resp;
 

// ----------------------------------------------------------------------------
// DESIGN
// ----------------------------------------------------------------------------

// In some configurations this signal is tied to logic0/1. This is not an issue
// as it takes a constant value based on configuration parameters.
assign advance_rd_ready = 1'b1;

// indicate to sm whether ready to begin a new write transaction
assign start_wr_ready = 
 fbid_src_rdy & 
advance_rd_ready;

// indicate to sm whether ready to begin a new read transaction
assign start_rd_ready = 
 frid_src_rdy & 
advance_rd_ready;

// indicate the clock is required

// If in GIF Lite mode, use internally driven sresp/svalid and drive mready = 1.
// Otherwise, use the port connections and fifo ready signal.
assign mready     = fresp_src_rdy;
assign sresp_int  = sresp;
assign svalid_int = svalid;
  
// Response type identification
// Controls rid, bid, rdata, and bresp FIFOs
assign rd_resp = gclken & svalid_int & (~sresp_int[0]);
assign wr_resp = gclken & svalid_int & sresp_int[0];
assign rw_resp = (mready & (rd_resp | wr_resp));
assign last_rd_resp = rd_resp & (rd_resp_ctr == frlen) & mready;


// ----------------------------------------------------------------------------
// FIFO instantiations
// ----------------------------------------------------------------------------
// fifo_bid
assign fbid_src_data = {id, exokay, exfail};
assign start_wr_gc =  start_wr & gclken;
assign wr_resp_rdy = wr_resp & mready;
  // Clock enable signal is not used in this design.
  // it will not cause any functional failure.
  // turn off check for unconnecte ports.
  //spyglass disable_block W528
  //SMD: A signal or variable is set but never read
  //SJ : In this configuration, ((@GS_LOWPWR_HS_IF==1) && (@GS_LOWPWR_LEGACY_IF == 0)), these signals are not used.  They are not removed because they come from different instances of the same module.
  DW_axi_gs_fifo
   #(FBID_WIDTH, `GS_BID_BUFFER, 0, 0)
  fifo_bid (.clk(aclk),
//            .clk_en(),
            .rst_n(aresetn),      
            .src_data(fbid_src_data),
            .src_vld(start_wr_gc), 
            .src_rdy(fbid_src_rdy),   
            .dst_data(fbid_dst_data),
            .dst_vld(fbid_dst_vld), 
            .dst_rdy(wr_resp_rdy)
            );
//spyglass enable_block W528
assign fbid     = fbid_dst_data[`GS_ID+1:2];
assign fbexokay = fbid_dst_data[1];
assign fbexfail = fbid_dst_data[0];

//wire [`GS_W_SBW_INT-1:0] rsideband ;
// fifo_rid
assign frid_src_data = {id, len, exokay, exfail};
assign start_rd_gc = start_rd & gclken;
  // Clock enable signal is not used in this design.
  // it will not cause any functional failure.
  //turn off check for unconnected port
  //spyglass disable_block W528
  //SMD: A signal or variable is set but never read
  //SJ : In this configuration, these signals are not used.  They are not removed because they come from different instances of the same module.
  DW_axi_gs_fifo
   #(FRID_WIDTH, `GS_RID_BUFFER, 0, 0)
  fifo_rid (.clk(aclk),
//            .clk_en(),
            .rst_n(aresetn),      
            .src_data(frid_src_data),
            .src_vld(start_rd_gc), 
            .src_rdy(frid_src_rdy),   
            .dst_data(frid_dst_data),
            .dst_vld(frid_dst_vld),
            .dst_rdy(last_rd_resp)
            );
//spyglass enable_block W528
assign frid     = frid_dst_data[`GS_ID+`GS_BW+1:`GS_BW+2];
assign frlen    = frid_dst_data[`GS_BW+1:2];
assign frexokay = frid_dst_data[1];
assign frexfail = frid_dst_data[0];

// fifo_resp
assign muxed_id = (rd_resp) ? frid: fbid;

assign fresp_src_data = {
sdata,
muxed_id, 
axi_sresp_int, 
last_rd_resp, 
rd_resp, wr_resp};

assign fresp_dst_rdy = (rvalid & rready) | (bvalid & bready);
  // Clock enable signal is not used in this design.
  // it will not cause any functional failure.
  //turn off check for unconnected port
  DW_axi_gs_fifo
   #(FRESP_WIDTH, `GS_RESP_BUFFER, 0, `GS_DIRECT_AXI_READY)
  fifo_resp (.clk(aclk),
//             .clk_en(),
             .rst_n(aresetn),      
             .src_data(fresp_src_data),
             .src_vld(rw_resp), 
             .src_rdy(fresp_src_rdy),   
             .dst_data(fresp_dst_data),
             .dst_vld(fresp_dst_vld), 
             .dst_rdy(fresp_dst_rdy)
             );
// Output assignments for AXI RDATA and BRESP channels
assign rdata  = fresp_dst_data[FRESP_WIDTH-1
 : 5+`GS_ID];
assign rid    = fresp_dst_data[4+`GS_ID:5];
assign rresp  = fresp_dst_data[4:3];
assign rlast  = fresp_dst_data[2];
assign rvalid = fresp_dst_vld & fresp_dst_data[1];
assign bvalid = fresp_dst_vld & fresp_dst_data[0];
assign bid    = rid;
assign bresp  = rresp;



// ----------------------------------------------------------------------------
// sresp_int to axi_sresp_int conversion
// ----------------------------------------------------------------------------

assign sresp_int_ok = (sresp_int == `GS_SRESP_OK_R) |
  (sresp_int == `GS_SRESP_OK_W);
/*
assign dout_exokay = 
`ifndef EXTD_GIF_MODE
(rd_resp) ? frexokay: fbexokay;
`else
1'b0;
`endif
assign dout_exfail = 
`ifndef EXTD_GIF_MODE
(rd_resp) ? frexfail: fbexfail;
`else
1'b0;
`endif
*/
assign dout_exokay = (rd_resp) ? frexokay: fbexokay;
assign dout_exfail = (rd_resp) ? frexfail: fbexfail;

always @(*)
begin : gen_axi_resp1_PROC
  case ({dout_exfail, dout_exokay})
    // exclusive access table check succeeded
    2'b01:
      begin
        if(sresp_int_ok)
          axi_sresp_int = `GS_AXI_EXOKAY;
        else
          axi_sresp_int = `GS_AXI_SLVERR;
      end
    // normal access
    default:
      begin
        if(sresp_int_ok)
          axi_sresp_int = `GS_AXI_OKAY;
        else
          axi_sresp_int = `GS_AXI_SLVERR;
      end
  endcase
end // gen_axi_resp

parameter [`GS_BW-1:0] TEMP_VAL_1 = 1;
assign next_rd_resp_ctr = (last_rd_resp) ? 0 : ((rd_resp & mready) ? rd_resp_ctr + TEMP_VAL_1 : rd_resp_ctr);  


// ----------------------------------------------------------------------------
// Flip flops
// ----------------------------------------------------------------------------

assign rd_resp_ctr_c = rd_resp_ctr;
always @(posedge aclk or negedge aresetn)
begin : dff_1_PROC
  if (!aresetn) begin
    rd_resp_ctr <= {`GS_BW{1'b0}};
  end
  else begin
    if (gclken) begin
      rd_resp_ctr <= next_rd_resp_ctr;
    end
    else begin
      rd_resp_ctr <= rd_resp_ctr_c;
    end
  end
end // dff


// ----------------------------------------------------------------------------
// Flip flops
// ----------------------------------------------------------------------------
endmodule
