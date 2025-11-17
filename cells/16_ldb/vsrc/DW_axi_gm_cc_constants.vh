// ---------------------------------------------------------------------
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
// File Version     :        $Revision: #13 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gm/axi_dev_br/src/DW_axi_gm_cc_constants.vh#13 $
// -------------------------------------------------------------------------

//==============================================================================
// Start Guard: prevent re-compilation of includes
//==============================================================================
`ifndef __GUARD__DW_AXI_GM_CC_CONSTANTS__VH__
`define __GUARD__DW_AXI_GM_CC_CONSTANTS__VH__


// Name:         GM_AXI_INTERFACE_TYPE
// Default:      AXI3
// Values:       AXI3 (0), AXI4 (1)
// Enabled:      [<functionof> %item]
// 
// Select AXI Interface Type as AXI3 or AXI4
`define GM_AXI_INTERFACE_TYPE 1

// Creates a define for AXI4 interface support.

`define GM_AXI4_INTERFACE

// Lock Type Width Paramater.

`define GM_W_LTW 1




// Name:         GM_AW
// Default:      32
// Values:       32, ..., 64
// 
// Address width on AXI and GIF interfaces.
`define GM_AW 32


// Name:         GM_DW
// Default:      32
// Values:       8 16 32 64 128 256 512
// 
// Data width on AXI and GIF interfaces. No distinction is made between read and write channels.
`define GM_DW 128


// Name:         GM_ID
// Default:      4
// Values:       1 2 3 4 5 6 7 8 9 10 11 12
// 
// Width of transaction ID field of the AXI system (awid, arid, wid, rid, bid) and GIF manager (mid, sid) interfaces.
`define GM_ID 4


// Name:         GM_BW
// Default:      4
// Values:       4 5 6 7 8
// 
// Width of the burst length field of the AXI and GIF interfaces.
`define GM_BW 4


// Name:         GM_LOWPWR_HS_IF
// Default:      false
// Values:       false (0), true (1)
// 
// If true, the low-power handshaking interface (csysreq, csysack, and cactive signals) and associated control logic is 
// implemented. If false, no support for low-power handshaking interface is provided.
`define GM_LOWPWR_HS_IF 0



// Name:         GM_LOWPWR_NOPX_CNT
// Default:      0
// Values:       0, ..., 4294967295
// Enabled:      GM_LOWPWR_HS_IF==1
// 
// Number of AXI clock cycles to wait before cactive signal de-asserts, when there are no pending transactions. 
// Note that if csysreq de-asserts while waiting this number of cycles, cactive de-asserts immediately. If a new 
// transaction is initiated during the wait period, the counting will be halted, cactive will not de-assert, and the counting will be 
// initiated again when there are no pending transactions. This parameter is available only if GM_LOWPWR_HS_IF is true.
`define GM_LOWPWR_NOPX_CNT 33'd0

//Creates a define for enabling legacy low power interface

`define GM_LOWPWR_NOPX_CNT_W 1

// Legacy low power interface selection

`define GM_LOWPWR_LEGACY_IF 0

//Creates a define for enabling low power interface

// `define GM_HAS_LOWPWR_HS_IF

//Creates a define for enabling legacy low power interface

// `define GM_HAS_LOWPWR_LEGACY_IF

//Maximum number of outstanding read transactions; higher values allow more transactions to be active simultaneously, but also increase gate count slightly.

// Name:         GM_MAX_PENDTRANS_READ
// Default:      4
// Values:       1, ..., 32
// Enabled:      GM_LOWPWR_HS_IF==1
// 
// Maximum number of AXI read transactions that may be outstanding 
// at any time 
// Available only if GM_LOWPWR_HS_IF is true
`define GM_MAX_PENDTRANS_READ 4

//Maximum number of sutstanding write transactions; higher values allow more transactions to be active simultaneously, but also increase gate count slightly. 

// Name:         GM_MAX_PENDTRANS_WRITE
// Default:      4
// Values:       1, ..., 32
// Enabled:      GM_LOWPWR_HS_IF==1
// 
// Maximum number of AXI write transactions that may be outstanding 
// at any time 
// Available only if GM_LOWPWR_HS_IF is true
`define GM_MAX_PENDTRANS_WRITE 4

//Creates a define for calculating the width of the counter needed to 
//keep track of pending requests

`define GM_CNT_PENDTRANS_READ_W 3

//Creates a define for calculating the width of the counter needed to 
//keep track of pending requests

`define GM_CNT_PENDTRANS_WRITE_W 3


`define GM_WW (`GM_DW / 8 )


// Name:         GM_DIRECT_AXI_READY
// Default:      true
// Values:       false (0), true (1)
// 
// If true, AXI awready, wready, and rready inputs are combinationally connected to the GIF saccept output. If false, these 
// inputs are registered, inserting one cycle of latency.
`define GM_DIRECT_AXI_READY 1


// Name:         GM_REQ_BUFFER
// Default:      1
// Values:       1 2 3 4
// 
// Depth of GIF request buffer. Higher values allow GIF requests to be buffered, rather than stalled, if the AXI address 
// channel stalls DW_axi_gm transactions. Higher values also increase gate count. 
//  
// If both GM_BLOCK_READ and GM_BLOCK_WRITE are true, GM_REQ_BUFFER must be set to 1. If GM_DIRECT_GIF_READY is false, 
// then it is recommended to set to 2 or higher in order to avoid performance degradation.
`define GM_REQ_BUFFER 1

`define GM_REQ_BUFFER_AW (`GM_REQ_BUFFER/3)+1


// Name:         GM_WDATA_BUFFER
// Default:      1
// Values:       1 2 3 4
// 
// Depth of GIF write data buffer. Higher values allow GIF write data to be buffered, rather than stalled, if the AXI write 
// data channel stalls DW_axi_gm transactions. Higher values also increase gate count. 
//  
//  If GM_DIRECT_GIF_READY is false, it is recommended to set GM_WDATA_BUFFER to 2 or higher in order to avoid write 
//  performance degradation.
`define GM_WDATA_BUFFER 1

`define GM_WDATA_BUFFER_AW (`GM_WDATA_BUFFER/3)+1


// Name:         GM_DIRECT_GIF_READY
// Default:      true
// Values:       false (0), true (1)
// 
// If true, the mready input is combinationally connected to the rready/bready outputs. If false, the mready input is 
// registered, inserting one cycle of latency.
`define GM_DIRECT_GIF_READY 1


// Name:         GM_RESP_BUFFER
// Default:      1
// Values:       1 2 3 4
// 
// Depth of combined AXI read and write response buffer. Higher values allow AXI responses to be buffered, rather than 
// stalled, if the GIF response channel stalls DW_axi_gm transactions. Higher values also increase gate count. 
//  
// If GM_DIRECT_AXI_READY is false, recommended to be set to 2 or higher to avoid read and write response performance 
// degradation.
`define GM_RESP_BUFFER 1

`define GM_RESP_BUFFER_AW (`GM_RESP_BUFFER/3)+1


// Name:         GM_BLOCK_READ
// Default:      false
// Values:       false (0), true (1)
// 
// If true, current GIF read request must complete (all read data received from AXI read data channel) before the next GIF 
// request is accepted by DW_axi_gm. If false, GIF requests are allowed to be queued in the request buffer and transferred to 
// the AXI read address channel before outstanding read requests complete.
`define GM_BLOCK_READ 0



// Name:         GM_BLOCK_WRITE
// Default:      false
// Values:       false (0), true (1)
// 
// If true, current GIF write request must complete (write response received from AXI write response channel) before the 
// next GIF request is accepted by DW_axi_gm. If false, GIF requests are allowed to be queued in the request buffer and 
// transferred to the AXI write address channel before outstanding write requests complete.
`define GM_BLOCK_WRITE 0


// Name:         GM_AXI_HAS_QOS
// Default:      false
// Values:       false (0), true (1)
// Enabled:      GM_AXI_INTERFACE_TYPE != 0
// 
// If set to True, the QoS is enabled in DW_axi_gm.
`define GM_AXI_HAS_QOS 0

//Creates a define for whether we support QOS signals.

// `define GM_INC_QOS

// -------------------------------------
// simulation parameters available in cC
// -------------------------------------

// Verification use's below random variable if SIM_USE_CC_RAND_SEED
// is set. Use's get_systime value otherwise. Note the 
// seed wil be the same but the configurations 
// will be different between regression runs. 

`define SIM_RAND_SEED 1


`define SIM_USE_CC_RAND_SEED 1

//This is a testbench parameter. The design does not depend on this parameter. 
//This parameter specifies the clock period of the AXI interface.

`define SIM_ACLK_PERIOD 10

//This is a testbench parameter. The design does not depend on this parameter. 
//This parameter specifies the clock period of the generic interface GIF.

`define SIM_GCLK_PERIOD 10


// `define GM_ENCRYPT


//This is the maximum width of any sideband/user bus.

`define GM_MAX_SBW 256


// Name:         GM_HAS_ASB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then all AXI and GIF address channels have an associated sideband/user bus in AXI3/AXI4 mode, 
// respectively. The read/write address channel sideband/user bus is routed in the same way as the other read/write address channel 
// control signals.
`define GM_HAS_ASB 0


//Creates a define for whether we support sideband/user signals.

// `define GM_INC_ASB


// Name:         GM_A_SBW
// Default:      1
// Values:       1, ..., GM_MAX_SBW
// Enabled:      GM_HAS_ASB == 1
// 
// When the GM_HAS_ASB parameter is set to True, you can set the address channel sideband/user bus width.
`define GM_A_SBW 1

//Internal define

`define GM_A_SBW_INT 0


// Name:         GM_HAS_WSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then all AXI and GIF write data channels have an associated sideband/user bus in AXI3/AXI4 mode, 
// respectively. The write data channel sideband/user bus is routed in the same way as the other write data channel control signals.
`define GM_HAS_WSB 0

//Creates a define for whether we support sideband/user signals.

// `define GM_INC_WSB


// Name:         GM_W_SBW
// Default:      1
// Values:       1, ..., GM_MAX_SBW
// Enabled:      GM_HAS_WSB == 1
// 
// When the GM_HAS_WSB parameter is set to True, you can set the write address channel sideband/user bus width.
`define GM_W_SBW 1

//Internal define

`define GM_W_SBW_INT 0


// Name:         GM_HAS_RSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then all AXI and GIF read data and response channels have an associated sideband/user bus in AXI3/AXI4 
// mode, respectively. The read data channel and write response sideband/user bus is routed in the same way as the other read 
// data channel and write response control signals.
`define GM_HAS_RSB 0

//Creates a define for whether we support sideband/user signals.

// `define GM_INC_RSB

`define GM_BW_4






// Name:         GM_R_SBW
// Default:      1
// Values:       1, ..., GM_MAX_SBW
// Enabled:      GM_HAS_RSB == 1
// 
// When the GM_HAS_RSB parameter is set to True, you can set the response channel sideband/user bus width.
`define GM_R_SBW 1

//Internal define

`define GM_R_SBW_INT 0


//Used to insert internal tests

//==============================================================================
// End Guard
//==============================================================================  
`endif
