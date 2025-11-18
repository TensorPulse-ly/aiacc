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
// File Version     :        $Revision: #5 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gs/axi_dev_br/src/DW_axi_gs_fifo.v#5 $
//
//----------------------------------------------------------------------------- 
//
// AUTHOR:    James Feagans      2/10/2005
//
// VERSION:   DW_axi_gs_fifo Verilog Synthesis Model
//
//
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// ABSTRACT:  FIFO with valid/ready, DEPTH 0, signal feedthrough.
//
// Features:
//   1. Valid/ready signal interface
//   2. Configurable direct valid/data feedthrough:
//        e.g. if (DIRECT_VLD)
//               dst_data = (empty) ? src_data: memory;
//             else
//               dst_data = memory;
//   3. Configurable direct ready feedthrough:
//        e.g. if (DIRECT_RDY)
//               src_rdy = !full | dst_rdy;
//             else
//               src_rdy = !full;
//   4. Zero register stage configuration (DEPTH = 0) available if
//        (DIRECT_VLD & DIRECT_RDY)
//        
//-----------------------------------------------------------------------------

`include "DW_axi_gs_all_includes.vh"

module DW_axi_gs_fifo(

  // Global
  clk,        // Clock, positive edge
//  clk_en,     // Clock enable for quasi-synchronous clocking mode
  rst_n,      // Reset, active low

  // Source Interface
  src_data,   // Input data
  src_vld,    // Source indicates valid input data is available
  src_rdy,    // FIFO indicates ready to accept data

  // Destination Interface
  dst_data,   // Output data
  dst_vld,    // FIFO indicates valid output data is available
  dst_rdy     // Destination indicates ready to accept data

);

// ----------------------------------------------------------------------------
// PARAMETERS
// ----------------------------------------------------------------------------

// The width and DEPTH parameters are specified by the user upon component
// instantiation. They are set by default to the following values:
parameter WIDTH = 8;       // RANGE 1 to 255
parameter DEPTH = 4;       // RANGE 0 to 255

// if (DIRECT_VLD == 0) {
//   dst_vld = !empty;
//   data and valid arrive in minimum of one clock cycle
//   requirement: DEPTH >= 1
// }
// else {
//   dst_vld = !empty | src_vld;
//   data and valid arrive in same clock cycle when empty
//   requirement: DEPTH >= 0
// {
parameter DIRECT_VLD = 0; // RANGE 0 to 1

// if (DIRECT_RDY == 0) {
//   src_rdy = !full;
//   pushing when full not allowed
//   requirement: DEPTH >= 1 (DEPTH >= 2 for maximum throughput)
// }
// else {
//   src_rdy = !full | dst_rdy;
//   pushing when full allowed
//   requirement: DEPTH >= 0
// {
parameter DIRECT_RDY = 0;  // RANGE 0 to 1


// The ADDR_WIDTH parameter is automatically set based on the DEPTH parameter.
// It used to specify the select line bit width for the flip-flop memory
// bank multiplexer.
parameter ADDR_WIDTH = ((DEPTH>16)?((DEPTH>64)?((DEPTH>128)?8:7):
  ((DEPTH>32)?6:5)):((DEPTH>4)?((DEPTH>8)?4:3):((DEPTH>2)?2:1)));


// ----------------------------------------------------------------------------
// PORTS
// ----------------------------------------------------------------------------

// Global
input  clk;
//input  clk_en;
input  rst_n;

// Source Interface
input  [WIDTH-1:0] src_data;
input  src_vld;
output src_rdy;

// Destination Interface
output [WIDTH-1:0] dst_data;
output dst_vld;
input  dst_rdy;


// ----------------------------------------------------------------------------
// INTERNAL SIGNALS
// ----------------------------------------------------------------------------

wire empty, full;
wire [WIDTH-1:0] fifo_dst_data;
reg  dst_vld, push_req_n, pop_req_n;
reg  [WIDTH-1:0] dst_data;

wire push, pop;



// ----------------------------------------------------------------------------
// DESIGN
// ----------------------------------------------------------------------------

// Assign output port handshake signals based on internal state of the FIFO
// and input control signals:
assign src_rdy = (DIRECT_RDY ? (!full | dst_rdy): !full);

// if (valid & ready), initiate the FIFO operation
assign push = src_vld & src_rdy;
assign pop  = dst_vld & dst_rdy;

// jstokes, 3.6.11, VCS did not correctly simulate with the sensitivity
// list below, required change to always @(*). STAR 9000471292 filed.
//always @(src_vld or dst_rdy or empty or src_data or fifo_dst_data or empty or
//        push or pop)
always @(*)
begin:DST_CYC_PROC
  if ((DIRECT_VLD == 1) & src_vld & dst_rdy & empty) begin
    dst_data   = src_data;
    dst_vld    = src_vld;
    push_req_n = 1'b1;
    pop_req_n  = 1'b1;
  end
  else begin
    dst_data   = fifo_dst_data;
    dst_vld    = !empty;
    push_req_n = !push;
    pop_req_n  = !pop;
  end
end

//unused signals from the bcm65 module.
wire         almost_empty_unconn;
wire         almost_full_unconn;
wire         half_full_unconn;
wire         error_unconn;
  //spyglass disable_block W528
  //SMD: A signal or variable is set but never read
  //SJ : BCM components are configurable to use in various scenarios in this particular design we are not using certain ports. Hence although those signals are read we are not driving them. Therefore waiving this warning.
DW_axi_gs_bcm65
 #(WIDTH,DEPTH,0,0,0,0,ADDR_WIDTH)
    fifo(.clk(clk), 
         .rst_n(rst_n),
         .init_n(1'b1), 
         .diag_n(1'b1),
         .push_req_n(push_req_n), 
         .pop_req_n(pop_req_n),
         .data_in(src_data),
         .empty(empty), 
         .full(full),
         .data_out(fifo_dst_data),
         .almost_empty(almost_empty_unconn),
         .almost_full(almost_full_unconn),
         .half_full(half_full_unconn),
         .error(error_unconn)
         );
  //spyglass enable_block W528

endmodule
