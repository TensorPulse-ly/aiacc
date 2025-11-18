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
// File Version     :        $Revision: #17 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gs/axi_dev_br/src/DW_axi_gs_sm.v#17 $ 
//
// -------------------------------------------------------------------------
//
// AUTHOR:    James Feagans      2/24/2005
//
// VERSION:   DW_axi_gs_sm Verilog Synthesis Model
//
//
//-----------------------------------------------------------------------------
//-----------------------------------------------------------------------------
//
// ABSTRACT:  AXI to Generic Interface (GIF) Slave Gasket State Machine
//
//
// This is the master state machine of the generic interface slave gasket.
// It controls the data path flow of the request and response modules.
//
// State machine (sm):
//                                |----|                           mread
// AXI Low-Power -----------------| sm |---------------------- GIF mwrite
//  Channel                       |____|                           mlast
//                                   |                             saccept
//                   <to/from req and resp data path>
//
//
// The state machine assigns just three control signals:
//   - start (starts a new read or write transaction)
//   - advance (advances a read or write transaction; also asserted upon start)
//   - next_state (next state of the state machine)
//
// The req and resp modules provide signals that inform the state machine of
// their present circumstances. The req module indicates its ability to deliver
// a new read or write transaction, and whether data is available to advance
// a write transaction. The resp module indicates its ability to accept
// additional transactions and additional responses, which depend on the level
// of its internal post transaction FIFOs (fifo_bid and fifo_rid) as well as
// the space available in its response FIFO (fifo_resp) in the case that the
// gasket is operating in GIF Lite mode.
//
// Based on these information signals from the data path modules, the state
// machine drives the start and advance control signals to direct the data flow
// of the req and resp modules.
//
// Since many of the transitions are shared among the various states, common
// Verilog tasks are utilized to consolidate logic and improve code readability.
//
// For performance reasons, a one-hot state machine is used. The GIF signals
// mread and mwrite are combinationally driven to minimize signal latency
// through the gasket, and therefore require as efficient logic as possible.
//
// Since the signals are for GIF, the state changes upon gclk.
//
//
//
//-----------------------------------------------------------------------------

`include "DW_axi_gs_all_includes.vh"

module DW_axi_gs_sm(/*AUTOARG*/
  // Outputs
                    mread, 
                    mwrite, 
                    start_wr, 
                    start_rd,
                    advance_wr, 
                    advance_rd, 
                    req_last_accepted, 
                    sm_high_pwr, 
                    // Inputs
                    aclk, 
                    aresetn, 
                    gclken, 
                    mlast, 
                    saccept, 
                    start_wr_valid, 
                    start_rd_valid, 
                    advance_wr_valid, 
                    start_wr_ready, 
                    start_rd_ready, 
                    advance_rd_ready
                    );


// ----------------------------------------------------------------------------
// PARAMETERS
// ----------------------------------------------------------------------------

// encoding of dual bit command signals "start" and "advance"
parameter CMD_IDLE = 2'b00,
          CMD_WR   = 2'b01,
          CMD_RD   = 2'b10;

// One-hot FSM
parameter SM_IDLE       = 0, // Idle, high-power mode
          SM_WR         = 1, // WR in progress, mwrite asserted
          SM_RD         = 2, // RD in progress, mread asserted
          SM_WR_MWAIT   = 3, // WR in progress, mwrite de-asserted
          SM_RD_MWAIT   = 4; // RD in progress, mread de-asserted

parameter NUM_STATES = 5 ;


// ----------------------------------------------------------------------------
// PORTS
// ----------------------------------------------------------------------------

// AXI INTERFACE
// Global
input  aclk;
input  aresetn;
// Low-power Channel

// GENERIC SLAVE INTERFACE
// Global
input  gclken;
// Request
output mread;
output mwrite;
input  mlast;
input  saccept;

// INTERNAL CONNECTIONS
// Inputs from req
input  start_wr_valid;
input  start_rd_valid;
input  advance_wr_valid;
//input  exfail;
// Inputs from resp
input  start_wr_ready;
input  start_rd_ready;
input  advance_rd_ready;
// Outputs
output start_wr;
output start_rd;
output advance_wr;
output advance_rd;
output req_last_accepted;
output sm_high_pwr;
  
// ----------------------------------------------------------------------------
// INTERNAL SIGNALS
// ----------------------------------------------------------------------------

// State machine
reg  [NUM_STATES-1:0] state, next_state;
wire  [NUM_STATES-1:0] state_c;

// Dual bit command signals
// This signal is not used when EXTD_GIF>0. It is not removed from the code in order to leave the tasks unchanged.
// This signal will be optimized during synthesis.
reg  [1:0] start;
reg  [1:0] advance;

// Indicates req and resp modules can perform a new write or read request
wire sysok_start_wr, sysok_start_rd;

reg  prev_req_last_accepted;
wire  prev_req_last_accepted_c;



// ----------------------------------------------------------------------------
// DESIGN
// ----------------------------------------------------------------------------

// GIF outputs combinationally driven in order to avoid second register stage
assign {mread, mwrite} = {next_state[SM_RD], next_state[SM_WR]};

// Control signals that initiate new write and read transactions
assign {start_rd, start_wr} = start;

// Control signals that advance the beat of current write and read transactions
assign {advance_rd, advance_wr} = advance;

// Instructs response module to automatically generate GIF response signals

// Indicates whether transaction or beat has completed
assign req_last_accepted = (|advance) & mlast;

// Low-power mode acknowledgement

// Indicates to req that arready and awready can be asserted
assign sm_high_pwr = 1'b1; 

// Determine whether the gasket is ready to issue a new GIF transaction
assign sysok_start_wr = start_wr_valid & start_wr_ready;
assign sysok_start_rd = start_rd_valid & start_rd_ready;

// State Machine. Since many states have the same transition condition/action pair, Verilog
// tasks are utilized to improve code readability. This is not an issue.

// we use configuration parameters in case expressions
// and 1-hot statemachines use non-constant case items.

always @(*)  
begin : MAIN_PROC

  next_state = {NUM_STATES{1'b0}};

// 1-hot statemachines can use a constant case-select expression. This is not an issue.
  case (1'b1)
    state[SM_IDLE]: begin
      // gen_idle task    
       start      = {sysok_start_rd, sysok_start_wr};
       if(saccept)
         advance = start;
       else
         advance = CMD_IDLE;
       case (start)
         CMD_WR: begin
           next_state[SM_WR] = 1'b1;
         end
         CMD_RD:   next_state[SM_RD] = 1'b1;
         default:  next_state[SM_IDLE] = 1'b1;
       endcase
    end 

    state[SM_WR]: begin
      if (prev_req_last_accepted) begin
        // current transaction request finished
        // gen_idle task    
        start      = {sysok_start_rd, sysok_start_wr};
        if(saccept)
          advance = start;
        else
          advance = CMD_IDLE;
        case (start)
          CMD_WR: begin
            next_state[SM_WR] = 1'b1;
          end
          CMD_RD:   next_state[SM_RD] = 1'b1;
          default:  next_state[SM_IDLE] = 1'b1;
        endcase
      end else begin
        // continue current transaction request
        // gen_wr task    
        start      = CMD_IDLE;
        next_state = {NUM_STATES{1'b0}};
        if (advance_wr_valid) begin // if gasket is ready, advance
          if(saccept)
            advance = CMD_WR;
          else
            advance = CMD_IDLE;
          next_state[SM_WR] = 1'b1;
        end
        else begin // wait for gasket to get wdata
          advance    = CMD_IDLE;
          next_state[SM_WR_MWAIT] = 1'b1;
        end
      end      
    end

    state[SM_WR_MWAIT]: begin
      // gen_wr task    
      start      = CMD_IDLE;
      next_state = {NUM_STATES{1'b0}};
      if (advance_wr_valid) begin // if gasket is ready, advance
        if(saccept)
          advance = CMD_WR;
        else
          advance = CMD_IDLE;
        next_state[SM_WR] = 1'b1;
      end
      else begin // wait for gasket to get wdata
        advance    = CMD_IDLE;
        next_state[SM_WR_MWAIT] = 1'b1;
      end
    end

    state[SM_RD]: begin
      if (prev_req_last_accepted) begin
        // current transaction request finished
        // gen_idle task    
        next_state = {NUM_STATES{1'b0}};
       start      = {sysok_start_rd, sysok_start_wr};
        if(saccept)
          advance = start;
        else
          advance = CMD_IDLE;
        case (start)
          CMD_WR: begin
            next_state[SM_WR] = 1'b1;
          end
          CMD_RD:   next_state[SM_RD] = 1'b1;
          default:  next_state[SM_IDLE] = 1'b1;
        endcase
      end else begin
        // continue current transaction request
        // gen_rd task    
        start      = CMD_IDLE;
        next_state = {NUM_STATES{1'b0}};
        if (advance_rd_ready) begin // if gasket is ready, advance
          if(saccept)
            advance = CMD_RD;
          else
            advance = CMD_IDLE;
          next_state[SM_RD] = 1'b1;
        end
        else begin // wait for gasket to become ready
          advance    = CMD_IDLE;
          next_state[SM_RD_MWAIT] = 1'b1;
        end
      end      
    end

    state[SM_RD_MWAIT]: begin
      // gen_rd task    
      start      = CMD_IDLE;
      next_state = {NUM_STATES{1'b0}};
      if (advance_rd_ready) begin // if gasket is ready, advance
        if(saccept)
          advance = CMD_RD;
        else
          advance = CMD_IDLE;
        next_state[SM_RD] = 1'b1;
      end
      else begin // wait for gasket to become ready
        advance    = CMD_IDLE;
        next_state[SM_RD_MWAIT] = 1'b1;
      end
    end
  

    default: begin
      start      = CMD_IDLE;
      advance    = CMD_IDLE;      
      next_state[SM_IDLE] = 1'b1;
    end
  endcase
end // MAIN


// ----------------------------------------------------------------------------
// Flip Flops
// ----------------------------------------------------------------------------

assign prev_req_last_accepted_c = prev_req_last_accepted;
assign state_c = state;
always @(posedge aclk or negedge aresetn)
begin : DFF_PROC
  if (!aresetn) begin
    state[NUM_STATES-1:1]  <= {(NUM_STATES-1){1'b0}};
    state[SM_IDLE]         <= 1'b1;
    prev_req_last_accepted <= 1'b0;
  end
  else begin
    if (gclken) begin
      state                  <= next_state;
      prev_req_last_accepted <= req_last_accepted;
    end
    else begin
      state                  <= state_c;
      prev_req_last_accepted <= prev_req_last_accepted_c;
    end
  end
end // DFF

endmodule
