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
// File Version     :        $Revision: #4 $ 
// Revision: $Id: //dwh/DW_ocb/DW_axi_gs/axi_dev_br/src/DW_axi_gs_constants.vh#4 $ 
//
// -------------------------------------------------------------------------

//==============================================================================
// Start Guard: prevent re-compilation of includes
//==============================================================================
`ifndef __GUARD__DW_AXI_GS_CONSTANTS__VH__
`define __GUARD__DW_AXI_GS_CONSTANTS__VH__

`define GS_RESP_W         2
`define GS_SRESP_OK_R     2'b00
`define GS_SRESP_OK_W     2'b01
`define GS_SRESP_SLVERR_R 2'b10
`define GS_SRESP_SLVERR_W 2'b11

`define GS_LOCK_NORM    2'b00
`define GS_LOCK_EX      2'b01
`define GS_LOCK_LOCK    2'b10

`define GS_BURST_W      2
`define GS_BURST_FIXED  2'b00
`define GS_BURST_INCR   2'b01
`define GS_BURST_WRAP   2'b10
`define GS_BURST_UINCR  2'b11

`define GS_AXI_FIXED 2'b00
`define GS_AXI_INCR  2'b01
`define GS_AXI_WRAP  2'b10
`define GS_AXI_RESVD 2'b11

`define GS_AXI_OKAY   2'b00
`define GS_AXI_EXOKAY 2'b01
`define GS_AXI_SLVERR 2'b10
`define GS_AXI_DECERR 2'b11

`define GS_SIZE_W   3
`define GS_SIZE_8   3'b0
`define GS_SIZE_16  3'b1
`define GS_SIZE_32  3'b10
`define GS_SIZE_64  3'b11
`define GS_SIZE_128 3'b100
`define GS_SIZE_256 3'b101
`define GS_SIZE_512 3'b110

`define AXI_LTW ((`GS_AXI_INTERFACE_TYPE == 0) ? 2: 1)

`define GS_W_QOS   4 
`define GS_W_REGION 4

//==============================================================================
// End Guard
//==============================================================================  
`endif
