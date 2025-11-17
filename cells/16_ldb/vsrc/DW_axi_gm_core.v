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
// Component Name   : DW_axi_gm
// Component Version: 2.05a
// Release Type     : GA
// Build ID         : 16.17.20.6
// ------------------------------------------------------------------------------

// 
// Release version :  2.05a
// File Version     :        $Revision: #11 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gm/axi_dev_br/src/DW_axi_gm_core.v#11 $ 
// 
// ----------------------------------------------------------------------------
// Author: Christian Graber
// ----------------------------------------------------------------------------

`include "DW_axi_gm_all_includes.vh"

module DW_axi_gm_core (/*AUTOARG*/
  // Outputs
  saccept, sid, svalid, slast, sdata, sresp, awvalid, awid, awaddr, 
  awlen, awsize, awburst, awlock, awcache,
  awprot, wvalid, wlast, 
  wid, wdata, wstrb, bready, arvalid, arid, araddr, arlen, arsize, 
  arburst, arlock, arcache, arprot, rready,
  // Inputs
  aclk, aresetn, gclken,
  mid, maddr, mread, mwrite, 
 mlen,
  msize, mburst, mcache, mprot, mdata, mwstrb, mready, awready, 
  wready, bvalid, bid, bresp, arready, rvalid, rid, rlast, rdata, 
  rresp
  );

  
  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------

  // Low Power FSM
  
  // --------------------------------------------------------------------------
  // Ports
  // --------------------------------------------------------------------------
  
  // Global signals  
  input                             aclk;
  input                             aresetn;
  input                             gclken;
  
  // GIF request
  input [`GM_ID-1:0]                mid;
  input [`GM_AW-1:0]                maddr;
  input                             mread;
  input                             mwrite;
  input [`GM_BW-1:0]                mlen;
  input [2:0]                       msize;
  input [1:0]                       mburst;
  input [3:0]                       mcache;
  input [2:0]                       mprot;
  input [`GM_DW-1:0]                mdata;
  input [`GM_WW-1:0]                mwstrb;
  output                            saccept;
  
  // GIF response
  output [`GM_ID-1:0]               sid;
  output                            svalid;
  output                            slast;
  output [`GM_DW-1:0]               sdata;
  output [2:0]                      sresp;
  input                             mready;
  
  // AXI write request
  output                            awvalid;
  output [`GM_ID-1:0]               awid;
  output [`GM_AW-1:0]               awaddr;
  output [`GM_BW-1:0]               awlen;
  output [2:0]                      awsize;
  output [1:0]                      awburst;
  output [`GM_W_LTW-1:0]            awlock;
  output [3:0]                      awcache;
  output [2:0]                      awprot;
  input                             awready;
  
  // AXI write data
  output                            wvalid;
  output                            wlast;
  output [`GM_ID-1:0]               wid;
  output [`GM_DW-1:0]               wdata;
  output [`GM_WW-1:0]               wstrb;
  input                             wready;
  
  // AXI write response
  input                             bvalid;
  input [`GM_ID-1:0]                bid;
  input [1:0]                       bresp;
  output                            bready;  
  
  // AXI read request
  output                            arvalid;
  output [`GM_ID-1:0]               arid;
  output [`GM_AW-1:0]               araddr;
  output [`GM_BW-1:0]               arlen;
  output [2:0]                      arsize;
  output [1:0]                      arburst;
  output [`GM_W_LTW-1:0]            arlock;
  output [3:0]                      arcache;
  output [2:0]                      arprot;
  input                             arready;
  
  // AXI read response & read data  
  input                             rvalid;
  input [`GM_ID-1:0]                rid;
  input                             rlast;
  input [`GM_DW-1:0]                rdata;
  input [1:0]                       rresp;
  output                            rready;
  
  
  // --------------------------------------------------------------------------
  // Internal Signals
  // --------------------------------------------------------------------------
  
  reg                                    saccept_r;  
  reg [`GM_BW-1:0]                       wburst_gif_count;
  wire[`GM_BW-1:0]                       wburst_gif_count_int;
  reg                                    saccept_reqb_block;
  reg                                    rready_gc;
  reg                                    bready_gc;
  reg [
 `GM_DW+`GM_ID+3:0]                      respb_data_in;
  reg                                    gvalid;
  reg                                    bselect;
  reg [`GM_BW-1:0]                       wburst_axi_count;
  wire[`GM_BW-1:0]                       wburst_axi_count_int;

  
  wire                                   saccept_reqb;
  wire                                   saccept_wb;
  wire                                   svalid;
  wire [2:0]                             sresp;
  wire                                   slast;
  wire                                   gready;  
  wire                                   respb_push_n;
  wire                                   respb_pop_n;
  wire                                   respb_push_gc_n;
  wire                                   respb_pop_gc_n;  
  wire                                   respb_empty;
  wire                                   respb_full;
  wire [
 `GM_DW+`GM_ID+3:0]                      respb_data_out;
  wire [
 `GM_AW+`GM_ID+`GM_BW+13:0]              reqb_data_in;
  wire [
 `GM_AW+`GM_ID+`GM_BW+13:0]              reqb_data_out;
  wire                                   reqb_push_gc_n;
  wire                                   reqb_pop_n;
  wire                                   reqb_push_n;
  wire                                   reqb_empty;
  wire                                   reqb_full;  
  wire [
 `GM_ID+`GM_DW+`GM_WW+`GM_BW-1:0]        wb_data_in;
  wire [
 `GM_ID+`GM_DW+`GM_WW+`GM_BW-1:0]        wb_data_out;
  wire                                   wb_push_gc_n;
  wire                                   wb_pop_n;
  wire                                   wb_push_n;
  wire                                   wb_empty;
  wire                                   wb_full;
  wire [`GM_BW-1:0]                      wlen;  
  wire                                   wburst_gif_active;     


//Unconnected wires to make module instantiations fully bounded.

  wire                                   unconnected_req_almost_empty;
  wire                                   unconnected_req_half_full;
  wire                                   unconnected_req_almost_full;
  wire                                   unconnected_req_error;
  wire                                   unconnected_wdata_almost_empty;
  wire                                   unconnected_wdata_half_full;
  wire                                   unconnected_wdata_almost_full;
  wire                                   unconnected_wdata_error;
  wire                                   unconnected_resp_almost_empty;
  wire                                   unconnected_resp_half_full;
  wire                                   unconnected_resp_almost_full;
  wire                                   unconnected_resp_error;


  
  // --------------------------------------------------------------------------
  // REQUEST PHASE
  // --------------------------------------------------------------------------
  
  // In this phase, request from the generic interface are pushed into
  // the request buffer and the write data buffer. Push & pop can only
  // be active once per gclk period. Signals with 'gc' identifier are
  // active during the entire gclk period.
  
  assign reqb_pop_n = ~((arvalid & arready) | (awvalid & awready));
  assign reqb_push_gc_n = ~((mread ^ mwrite) & (~wburst_gif_active) & saccept);

  assign reqb_push_n = (gclken==1'b1) ? reqb_push_gc_n : 1'b1;
  assign reqb_data_in = {
          mid,mprot,mcache,mread,mwrite,
          mburst,msize,mlen,maddr};

  // spyglass disable_block W528
  // SMD: A signal or variable is set but never read. 
  // SJ : BCM components are configurable to use in various scenarios in this particular design we are not using certain ports. Hence although those signals are read we are not driving them. Therefore waiving this warning.
  
  // REQUEST BUFFER
  DW_axi_gm_bcm65
   #(
  `GM_AW+`GM_ID+`GM_BW+14,
                              `GM_REQ_BUFFER,
                              1,
                              `GM_REQ_BUFFER-1,
                              0,
                              0,
                              `GM_REQ_BUFFER_AW)
  req_buffer(
             .clk(aclk),
             .rst_n(aresetn),
             .init_n(1'b1),
             .push_req_n(reqb_push_n),
             .pop_req_n(reqb_pop_n),
             .diag_n(1'b1),
             .data_in(reqb_data_in),
             .empty(reqb_empty),
             .almost_empty(unconnected_req_almost_empty),
             .half_full(unconnected_req_half_full),
             .almost_full(unconnected_req_almost_full),
             .full(reqb_full),
             .error(unconnected_req_error),
             .data_out(reqb_data_out)
             );
  // spyglass enable_block W528
  
  assign araddr = reqb_data_out[`GM_AW-1:0];
  assign arlen = reqb_data_out[`GM_AW+`GM_BW-1:`GM_AW];
  assign arsize = reqb_data_out[`GM_AW+`GM_BW+2:`GM_AW+`GM_BW];
  assign arburst = reqb_data_out[`GM_AW+`GM_BW+4:`GM_AW+`GM_BW+3];
  assign arlock = {1'b0};
  assign arcache = reqb_data_out[`GM_AW+`GM_BW+10:`GM_AW+`GM_BW+7];
  assign arprot = reqb_data_out[`GM_AW+`GM_BW+13:`GM_AW+`GM_BW+11];
  assign arid = reqb_data_out[`GM_AW+`GM_ID+`GM_BW+13:`GM_AW+`GM_BW+14];
  assign arvalid = ~reqb_empty & reqb_data_out[`GM_AW+`GM_BW+6];



  assign awaddr = reqb_data_out[`GM_AW-1:0];
  assign awlen = reqb_data_out[`GM_AW+`GM_BW-1:`GM_AW];
  assign awsize = reqb_data_out[`GM_AW+`GM_BW+2:`GM_AW+`GM_BW];
  assign awburst = reqb_data_out[`GM_AW+`GM_BW+4:`GM_AW+`GM_BW+3];
  assign awlock = {1'b0};
  assign awcache = reqb_data_out[`GM_AW+`GM_BW+10:`GM_AW+`GM_BW+7];
  assign awprot = reqb_data_out[`GM_AW+`GM_BW+13:`GM_AW+`GM_BW+11];
  assign awid = reqb_data_out[`GM_AW+`GM_ID+`GM_BW+13:`GM_AW+`GM_BW+14];                          

  assign awvalid = ~reqb_empty & reqb_data_out[`GM_AW+`GM_BW+5];
    
  // Enable direct feedthrough of arready and awready
  assign saccept_reqb = (~reqb_full | (reqb_full & arready & awready)) ;
  
  assign wb_push_gc_n = ~(mwrite & saccept);
  assign wb_push_n = (gclken==1'b1) ? wb_push_gc_n : 1'b1;
  assign wb_pop_n = ~(wvalid & wready);

  assign wb_data_in = {
          mid,mlen,mwstrb,mdata};

  // spyglass disable_block W528
  // SMD: A signal or variable is set but never read. 
  // SJ : BCM components are configurable to use in various scenarios in this particular design we are not using certain ports. Hence although those signals are read we are not driving them. Therefore waiving this warning.
  
  // WRITE DATA BUFFER
  DW_axi_gm_bcm65
   #(
  `GM_ID+`GM_DW+`GM_WW+`GM_BW,
                              `GM_WDATA_BUFFER,
                              1,
                              `GM_WDATA_BUFFER-1,
                              0,
                              0,
                              `GM_WDATA_BUFFER_AW)
    wdata_buffer(
              .clk(aclk),
              .rst_n(aresetn),
              .init_n(1'b1),
              .push_req_n(wb_push_n),
              .pop_req_n(wb_pop_n),
              .diag_n(1'b1),
              .data_in(wb_data_in),
              .empty(wb_empty),
              .almost_empty(unconnected_wdata_almost_empty),
              .half_full(unconnected_wdata_half_full),
              .almost_full(unconnected_wdata_almost_full),
              .full(wb_full),
              .error(unconnected_wdata_error),
              .data_out(wb_data_out)
              );
  // spyglass enable_block W528
  assign wdata = wb_data_out[`GM_DW-1:0];
  assign wstrb = wb_data_out[`GM_DW+`GM_WW-1:`GM_DW];
  assign wlen = wb_data_out[`GM_DW+`GM_WW+`GM_BW-1:`GM_DW+`GM_WW];
  assign wid = wb_data_out[`GM_ID+`GM_DW+`GM_WW+`GM_BW-1:`GM_DW+`GM_WW+`GM_BW];
  assign wvalid = ~wb_empty;  
  
  // Enable direct feedthrough of wready
  assign saccept_wb = (~wb_full | (wb_full & wready)) ;


  
  

  // Compose 'saccept'.
  always @ (*)
    /*AUTO_CONSTANT(`GM_BLOCK_READ)*/
    /*AUTO_CONSTANT(`GM_BLOCK_WRITE)*/
    begin : saccept_reqb_block_PROC
      // Enable read and/or write blocking.
          saccept_reqb_block = saccept_reqb;
    end // always@ (...
  //lede W456 on
  
  always@(/*AUTOSENSE*/saccept_reqb_block or saccept_wb
          or wburst_gif_active)
    begin : saccept_r_PROC
      if(wburst_gif_active)
        begin
          saccept_r = saccept_wb;
        end
      else
        begin
          // Acceptance of the 1st beat of read and write request requires
          // request and write data buffers to be ready. The advantage is
          // no loop from mread/mwrite back to saccept.
          saccept_r = saccept_reqb_block & saccept_wb;
        end
    end // always@ (...

  assign saccept = saccept_r;


  // Indicates write burst in progress on GIF side.

  assign wburst_gif_count_int = wburst_gif_count;

  always@(posedge aclk or negedge aresetn)
    begin : wburst_gif_count_PROC
      if(~aresetn)
        wburst_gif_count <= {(`GM_BW){1'b0}};
      else
        begin
          if(gclken)
            begin
              if((wburst_gif_count==mlen) && (mwrite & saccept))
                begin
                  wburst_gif_count <= {(`GM_BW){1'b0}};
                end
              else if(mwrite & saccept)
                begin
                  wburst_gif_count <= wburst_gif_count_int + {{(`GM_BW-1){1'b0}}, 1'b1} ;
                end
            end // if (gclken)
        end // else: !if(~aresetn)
    end // always@ (posedge aclk or negedge aresetn)

  assign wburst_gif_active = (wburst_gif_count != {(`GM_BW){1'b0}} );
  

  // Indicates write burst in progress on AXI side.

  assign wburst_axi_count_int = wburst_axi_count;

  always@(posedge aclk or negedge aresetn)
    begin : wburst_axi_count_PROC
      if(~aresetn)
        wburst_axi_count <= {(`GM_BW){1'b0}};
      else
        begin
          if((wburst_axi_count==wlen) && (wready & wvalid))
            begin
              wburst_axi_count <= {(`GM_BW){1'b0}};
            end
          else if(wready & wvalid)
            begin
              wburst_axi_count <= wburst_axi_count_int + {{(`GM_BW-1){1'b0}}, 1'b1};
            end
        end // else: !if(~aresetn)
    end // always@ (posedge aclk or negedge aresetn)

  assign wlast = (wburst_axi_count==wlen);   


  
  // -------------------------------------------------------------------
  // RESPONSE PHASE
  // -------------------------------------------------------------------
  
  // In this phase, responses from AXI are pushed into the response 
  // buffer. Push & pop can only be active once per gclk period. 
  // Signals with 'gc' identifier are active during the entire gclk 
  // period.

  
  // Determine which response to service first.
  // Toggle selection if read and write responses are available.
  always@(posedge aclk or negedge aresetn)
    begin : bselect_PROC
      if(~aresetn)
        bselect <= 1'b0;
      else
        if(rvalid & bvalid)
          begin
            if(bselect)
              bselect <= 1'b0;
            else
              bselect <= 1'b1;
          end
        else if(bvalid)
          bselect <= 1'b1;
        else
          bselect <= 1'b0;
    end // always@ (posedge aclk or negedge aresetn)


  // Select read/write reponse channel. Write responses can go
  // in between read bursts.
  always@(/*AUTOSENSE*/
bid or bresp or bselect or bvalid or gready
          or rdata or rid or rlast or rresp or rvalid)
    begin : read_resp_PROC
      if(bselect)
        begin
          respb_data_in =  {
          bid,1'b1,bresp,1'b1,rdata};
          gvalid = bvalid;
          rready_gc = 1'b0;
          bready_gc = gready;
        end
      else
        begin
          respb_data_in =  {
          rid,rlast,rresp,1'b0,rdata};
          gvalid = rvalid;
          rready_gc = gready;
          bready_gc = 1'b0;
        end // else: !if(bselect)
    end

  assign respb_push_gc_n = ~(gvalid & gready);
  assign respb_pop_gc_n = ~(svalid & mready);

  assign respb_push_n = (gclken==1'b1) ? respb_push_gc_n : 1'b1;
  assign respb_pop_n = (gclken==1'b1) ? respb_pop_gc_n : 1'b1;  

  // spyglass disable_block W528
  // SMD: A signal or variable is set but never read. 
  // SJ : BCM components are configurable to use in various scenarios in this particular design we are not using certain ports. Hence although those signals are read we are not driving them. Therefore waiving this warning.

  // RESPONSE BUFFER
  DW_axi_gm_bcm65
   #(
  `GM_DW+`GM_ID+4,
                              `GM_RESP_BUFFER,
                              1,
                              `GM_RESP_BUFFER-1,
                              0,
                              0,
                              `GM_RESP_BUFFER_AW)
      resp_buffer(
              .clk(aclk),
              .rst_n(aresetn),
              .init_n(1'b1),
              .push_req_n(respb_push_n),
              .pop_req_n(respb_pop_n),
              .diag_n(1'b1),
              .data_in(respb_data_in),
              .empty(respb_empty),
              .almost_empty(unconnected_resp_almost_empty),
              .half_full(unconnected_resp_half_full),
              .almost_full(unconnected_resp_almost_full),
              .full(respb_full),
              .error(unconnected_resp_error),
              .data_out(respb_data_out)
              );
  // spyglass enable_block W528
  // Leda W287 on
  
  
  // Enable direct feedthrough of mready.
  assign gready = (~respb_full | (respb_full & mready)) ;
  
  assign rready = (gclken==1'b1) ? rready_gc : 1'b0;
  assign bready = (gclken==1'b1) ? bready_gc : 1'b0;  

  assign svalid = ~respb_empty;
  assign sid = respb_data_out[`GM_DW+`GM_ID+3:`GM_DW+4];
  assign slast = respb_data_out[`GM_DW+3];
  assign sresp = {respb_data_out[`GM_DW+2:`GM_DW]};
  assign sdata = respb_data_out[`GM_DW-1:0];

  

  


      
endmodule 






