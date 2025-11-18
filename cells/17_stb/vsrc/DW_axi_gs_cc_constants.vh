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
// File Version     :        $Revision: #14 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gs/axi_dev_br/src/DW_axi_gs_cc_constants.vh#14 $ 
//
// -------------------------------------------------------------------------

//==============================================================================
// Start Guard: prevent re-compilation of includes
//==============================================================================
`ifndef __GUARD__DW_AXI_GS_CC_CONSTANTS__VH__
`define __GUARD__DW_AXI_GS_CC_CONSTANTS__VH__


// Name:         GS_AXI_INTERFACE_TYPE
// Default:      AXI3
// Values:       AXI3 (0), AXI4 (1)
// Enabled:      [<functionof> %item]
// 
// Select AXI Interface Type as AXI3 or AXI4. By default, DW_axi_gs supports the AXI3 interface.
`define GS_AXI_INTERFACE_TYPE 1

`define GS_HAS_AXI4 


// Name:         GS_AXI_HAS_QOS
// Default:      false
// Values:       false (0), true (1)
// Enabled:      GS_AXI_INTERFACE_TYPE > 0
// 
// If set to True, the QoS is enabled in DW_axi_gs, and the write address and read address channels on the GIF and the AXI 
// Interfaces have QoS signals on I/Os.
`define GS_AXI_HAS_QOS 0

//Creates a define for whether we support QOS signals.

// `define GS_INC_QOS



// Name:         GS_AXI_HAS_REGION
// Default:      false
// Values:       false (0), true (1)
// Enabled:      GS_AXI_INTERFACE_TYPE > 0
// 
// If set to True, write address channel and read address channels on GIF and AXI Interface have region signals on the 
// I/Os.
`define GS_AXI_HAS_REGION 0

//Creates a define for whether we support REGION signals.

// `define GS_INC_REGION


// Name:         GS_AW
// Default:      32
// Values:       32, ..., 64
// 
// Address width on AXI and GIF interfaces.
`define GS_AW 32


// Name:         GS_DW
// Default:      32
// Values:       8 16 32 64 128 256 512
// 
// Data width on AXI and GIF interfaces. No distinction is made between read and write channels.
`define GS_DW 128

`define GS_WW (`GS_DW / 8 )


// Name:         GS_ID
// Default:      12
// Values:       1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
// 
// Width of transaction ID field on the AXI (awid, arid, wid, rid, bid) and GIF (mid, sid) interfaces.
`define GS_ID 4


// Name:         GS_BW
// Default:      4
// Values:       4 5 6 7 8
// 
// Width of burst length field on the AXI and GIF interfaces.
`define GS_BW 4


// Name:         GS_LOWPWR_HS_IF
// Default:      false
// Values:       false (0), true (1)
// 
// If true, the low-power handshaking interface (csysreq, csysack, and cactive signals) and associated control logic is 
// implemented. If false, no support for low-power handshaking interface is provided.
`define GS_LOWPWR_HS_IF 0


// Name:         GS_LOWPWR_NOPX_CNT
// Default:      0
// Values:       0, ..., 4294967295
// Enabled:      GS_LOWPWR_HS_IF==1
// 
// Number of AXI clock cycles to wait before cactive signal de-asserts, when there are no pending transactions. 
// Note that if csysreq de-asserts while waiting this number of cycles, cactive will immediately de-assert.  If a new 
// transaction is initiated during the wait period, the counting will be halted, cactive will not deassert, and the counting will 
// be re-initiated when there are no pending transactions. This parameter is available only if GS_LOWPWR_HS_IF is true.
`define GS_LOWPWR_NOPX_CNT 33'd0

//Creates a define for enabling legacy low power interface

`define GS_LOWPWR_NOPX_CNT_W 1


// Name:         EXTD_GIF
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// Support for Extended GIF Mode. It enables the mid, sid, and slast signals on the GIF Interface.
`define EXTD_GIF 0

// Legacy low power interface selection

`define GS_LOWPWR_LEGACY_IF 0

//Creates a define for enabling low power interface

// `define GS_HAS_LOWPWR_HS_IF

//Creates a define for enabling legacy low power interface

// `define GS_HAS_LOWPWR_LEGACY_IF


// Name:         GS_AXI_EX_ACCESS
// Default:      1 ((EXTD_GIF == 0) ? 1 : 0)
// Values:       0, ..., 16
// Enabled:      EXTD_GIF == 0
// 
// Maximum number of exclusive accesses supported in parallel. A value of 0 means exclusive accesses are not supported.
`define GS_AXI_EX_ACCESS 1


// Name:         GS_GIF_LITE
// Default:      false
// Values:       false (0), true (1)
// Enabled:      EXTD_GIF == 0
// 
// Lite version of GIF. Supports devices with one-cycle data response and no flow control.
`define GS_GIF_LITE 0


// Name:         GS_BID_BUFFER
// Default:      1
// Values:       1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
// Enabled:      EXTD_GIF == 0
// 
// Depth of BID buffer for outstanding GIF write requests. If set to 1, equivalent to blocking GIF write; current GIF write 
// requests must complete (write response received from GIF Response Channel) before next AXI write request is accepted by 
// DW_axi_gs. If greater than 1, AXI write IDs are allowed to be queued in BID buffer, while write request is transferred to 
// GIF Request Channel before previous GIF writes responses are completed (up to the configured limit).
`define GS_BID_BUFFER 1


// Name:         GS_RID_BUFFER
// Default:      1
// Values:       1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
// Enabled:      EXTD_GIF == 0
// 
// Depth of RID buffer for outstanding RID requests. If set to 1 (which is equivalent to blocking GIF read) current GIF 
// read requests must complete (read response received from GIF response channel) before next AXI read request is accepted by 
// DW_axi_gs. If greater than 1, AXI read IDs are allowed to be queued in RID buffer, while read request is transferred to GIF 
// Request Channel before previous GIF read responses are completed (up to the configured limit).
`define GS_RID_BUFFER 1


// Name:         GS_DIRECT_GIF_READY
// Default:      true
// Values:       false (0), true (1)
// Enabled:      EXTD_GIF == 0
// 
// If true, GIF saccept input is combinationally connected to AXI awready, wready, and arready outputs. If false, GIF 
// saccept input is registered, inserting one cycle of latency.
`define GS_DIRECT_GIF_READY 1


// Name:         GS_REQ_BUFFER
// Default:      1
// Values:       1 2 3 4
// 
// Depth of combined read and write AXI request buffer. Higher values allow AXI requests to be buffered, rather than 
// stalled, if GIF request channel stalls DW_axi_gs transactions.
`define GS_REQ_BUFFER 1

//Creates a define for calculating the maximum number of pending requests

`define GS_LOWPWR_PENDTRANS_MAX 2

//Creates a define for calculating the width of the counter needed to 
//keep track of pending requests

`define GS_LOWPWR_PENDTRANS_CNT_W 2


// Name:         GS_WDATA_BUFFER
// Default:      1
// Values:       1 2 3 4
// 
// Depth of AXI write data buffer. Higher values allow AXI write data to be buffered, rather than being stalled, if GIF 
// request channel stalls DW_axi_gs transactions data.
`define GS_WDATA_BUFFER 1

// See databook for side effect of DIRECT_AXI_READY
// and GIF_LITE both enabled with a slow GCLK.


// Name:         GS_DIRECT_AXI_READY
// Default:      true
// Values:       false (0), true (1)
// Enabled:      EXTD_GIF == 0
// 
// If true, AXI rready and bready inputs are combinationally connected to GIF mready outputs. If false, AXI rready and 
// bready inputs are registered, inserting one cycle of latency.
`define GS_DIRECT_AXI_READY 1


// Name:         GS_RESP_BUFFER
// Default:      1
// Values:       1 2 3 4
// 
// Depth of GIF response buffer. Higher values allow GIF responses to be buffered, rather than being stalled, if AXI read 
// data or write response channel stall DW_axi_gs responses.
`define GS_RESP_BUFFER 1

//Calculate the maximum possible length

`define GS_MAX_LEN 16

//Calculate the maximum possible size

`define GS_MAX_SIZE 4

//Bits required to store axi size, for max possible t/x size

`define GS_MAX_SIZE_W 3

//Calculate the number of bits required to store the t/x size in bytes

`define GS_TX_SIZE_BYTES_W 9

//Number of bits required to store a maximum t/x size of 1K bytes. Follows
//GS_TX_SIZE_BYTES_W, but maxes out at 11. Used for wrap transfers where
//length cannot exceed 16.
//NOTE : need to store the actual value 1024

`define GS_TX_SIZE_BYTES_1KMAX_W 9


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


// `define GS_ENCRYPT

//Include SVA assertions

//This is the maximum width of any sideband/user bus.

`define GS_MAX_SBW 256


// Name:         GS_HAS_AWSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then all AXI write address and GIF address channels have an associated sideband/user bus in AXI3/AXI4 
// mode, respectively. The write address channel sideband/user bus is routed in the same way as the other write address channel 
// control signals.
`define GS_HAS_AWSB 0

//Creates a define for whether we support sideband/user signals.

// `define GS_INC_AWSB


// Name:         GS_HAS_ARSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then both AXI read address and GIF address channels have an associated sideband/user bus in AXI3/AXI4 
// mode, respectively. The read address channel sideband/user bus is routed in the same way as the other read address channel 
// control signals.
`define GS_HAS_ARSB 0

//Creates a define for whether we support sideband/user signals.

// `define GS_INC_ARSB


// Name:         GS_A_SBW
// Default:      1
// Values:       1, ..., GS_MAX_SBW
// Enabled:      GS_HAS_AWSB == 1 || GS_HAS_ARSB == 1
// 
// When the GS_HAS_AWSB or GS_HAS_ARSB parameter is set to True, you can set the address channel sideband/user bus width.
`define GS_A_SBW 1

//Internal define

`define GS_A_SBW_INT 0


// Name:         GS_HAS_WSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then both AXI and GIF write data channels have an associated sideband/user bus in AXI3/AXI4 mode, 
// respectively. The write data channel sideband/user bus is routed in the same way as the other write data channel control 
// signals.
`define GS_HAS_WSB 0

//Creates a define for whether we support sideband/user signals.

// `define GS_INC_WSB


// Name:         GS_W_SBW
// Default:      1
// Values:       1, ..., GS_MAX_SBW
// Enabled:      GS_HAS_WSB == 1
// 
// When the GS_HAS_WSB parameter is set to True, you can set the write data channel sideband/user bus width.
`define GS_W_SBW 1

//Internal define

`define GS_W_SBW_INT 0


// Name:         GS_HAS_BSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then both AXI write response and GIF response channels have an associated sideband/user bus in AXI3/AXI4 
// mode, respectively. The write response channel sideband/user bus is routed in the same way as the other write response 
// channel control signals.
`define GS_HAS_BSB 0

//Creates a define for whether we support sideband/user signals.

// `define GS_INC_BSB


// Name:         GS_HAS_RSB
// Default:      false
// Values:       false (0), true (1)
// Enabled:      [<functionof> %item]
// 
// If set to True, then both AXI read data and GIF response channels have an associated sideband/user bus in AXI3/AXI4 
// mode, respectively. The read data channel sideband/user bus is routed in the same way as the other read data channel control 
// signals.
`define GS_HAS_RSB 0

//Creates a define for whether we support sideband/user signals.

// `define GS_INC_RSB



// Name:         GS_R_SBW
// Default:      1
// Values:       1, ..., GS_MAX_SBW
// Enabled:      GS_HAS_BSB == 1 || GS_HAS_RSB == 1
// 
// When the GS_HAS_RSB or GS_HAS_BSB parameter is set to True, you can set the read-data/write-response channel 
// sideband/user bus width.
`define GS_R_SBW 1


//Internal define

`define GS_R_SBW_INT 0


//Creates a define for whether we support sideband/user signals.

// `define GS_INC_ASB

//Creates a define for whether we support sideband/user signals.

// `define GS_INC_GSB

//Creates a define for the bit width of the "size" signal in DW_axi_gs_exclusive module.

`define GS_SIZE_BW 3

//Creates a define if the data bus width is greater than 8 bits.  Used in the test environment.
`define GS_DB_GT8

//Creates a define if the data bus width is greater than 16 bits.  Used in the test environment.
`define GS_DB_GT16

//Creates a define if the data bus width is greater than 32 bits.  Used in the test environment.
`define GS_DB_GT32

//Creates a define if the data bus width is greater than 64 bits.  Used in the test environment.
`define GS_DB_GT64

//Creates a define if the data bus width is greater than 128 bits.  Used in the test environment.

//Creates a define if the data bus width is greater than 256 bits.  Used in the test environment.

//Creates a define if the burst length width is 4.  Used in the test environment.
`define GS_BW_FOUR 

//Creates a define if the burst length width is 5.  Used in the test environment.

//Creates a define if the burst length width is 6.  Used in the test environment.

//Creates a define if the burst length width is 7.  Used in the test environment.

//Creates a define if the burst length width is 8.  Used in the test environment.

//Creates a define if GIF Lite mode is enabled.  Used in the test environment.

//Creates a define for the NUM_ENTRIES parameter in DW_axi_gs_exclusive module.

`define NUM_ENTRIES_INT 1


//Used to insert internal tests

//==============================================================================
// End Guard
//==============================================================================  
`endif
