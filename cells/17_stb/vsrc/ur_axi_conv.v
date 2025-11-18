//=========================================================================
// Project:     AIACC
// File:        ur_axi_conv.v
// Module:      ur_axi_conv
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2025-11-6
// Modified:    2025-11-6
// Version:     v0.1
//=========================================================================

// Description:
// Convert the user register interface to the AXI interface

// Parameters:
// - UR_BYTE_CNT  : Byte valid flag
// - DATA_WIDTH   : Data bus width in bits (default: 128)
// - ADDR_WIDTH   : Address bus width in bits (default: 32)
// - INTLV_STEP   : SMC interleave step

//=========================================================================
// Revision History:
// v0.1 - 2025-11-6  - Initial version
//
//=========================================================================

`timescale 1ns/1ps
module ur_axi_conv#( parameter DATA_WIDTH     = 128,
                     parameter ADDR_WIDTH     = 32,
                     parameter UR_BYTE_CNT    = DATA_WIDTH/8,
                     parameter INTLV_STEP     = 128,     //SMC  interleave step
                     parameter INTLV_STEP3    = INTLV_STEP * 3,
                     parameter INTLV_STEP5    = INTLV_STEP * 5,
                     parameter INTLV_STEP7    = INTLV_STEP * 7,
                     parameter INTLV_STEP9    = INTLV_STEP * 9,
                     parameter INTLV_STEP11   = INTLV_STEP * 11,
                     parameter INTLV_STEP13   = INTLV_STEP * 13,
                     parameter INTLV_STEP15   = INTLV_STEP * 15,
                     parameter INTLV_STEP17   = INTLV_STEP * 17,
                     parameter INTLV_STEP19   = INTLV_STEP * 19,
                     parameter INTLV_STEP21   = INTLV_STEP * 21,
                     parameter INTLV_STEP23   = INTLV_STEP * 23,
                     parameter INTLV_STEP25   = INTLV_STEP * 25,
                     parameter INTLV_STEP27   = INTLV_STEP * 27,
                     parameter INTLV_STEP29   = INTLV_STEP * 29,
                     parameter INTLV_STEP31   = INTLV_STEP * 31,
                     parameter UR_ADDR_WIDTH  = 11
    ) (
    input                           clk,
    input                           rst_n,

    //axi side signal
    output reg [3:0]                o_mid,
    output reg [ADDR_WIDTH-1:0]     o_maddr,
    output reg                      o_mread,
    output reg                      o_mwrite,
    output reg [3:0]                o_mlen,
    output reg [2:0]                o_msize,
    output reg [1:0]                o_mburst,
    output reg [3:0]                o_mcache,
    output reg [2:0]                o_mport,
    output reg [DATA_WIDTH-1:0]     o_mdata,
    output reg [UR_BYTE_CNT-1:0]    o_mwstrb,
    input                           i_saccept,

    //ur side signal
    output reg                      o_ur_re,        
    output reg [UR_ADDR_WIDTH-1:0]  o_ur_addr, 

    //micro instruction
    input                           i_micro_inst_u_valid,
    input      [5:0]                i_micro_inst_u_smc_strb,
    input      [3:0]                i_micro_inst_u_byte_strb,
    input      [1:0]                i_micro_inst_u_brst,           // （2bit：00=1，01=2，10=4，11=8）
    input      [ADDR_WIDTH-1:0]     i_micro_inst_u_gr_base_addr,   // outside sram addr
    input      [3:0]                i_micro_inst_u_ur_id,
    input      [UR_ADDR_WIDTH-1:0]  i_micro_inst_u_ur_addr,        //user addr
    input      [DATA_WIDTH-1:0]     i_ur_rdata,                    //random data input
    
    output reg                      o_micro_inst_d_valid,
    output reg                      o_micro_inst_d_done,
    output     [4:0]                o_state
);

localparam  IDLE                = 5'b0_0001;
localparam  INIT                = 5'b0_0010;
localparam  ACCEPT_DATA         = 5'b0_0100;
localparam  SMC_DET             = 5'b0_1000;
localparam  DONE                = 5'b1_0000;
      
wire [3:0]                      w_burst_len;
wire [UR_BYTE_CNT-1:0]          w_mwstrb;
      
reg  [3:0]                      r_burst_remain_len;
reg  [ADDR_WIDTH-1:0]           r_maddr;               //outside ram final address
reg  [ADDR_WIDTH-1:0]           r_smc_base_addr;       //outside ram base address
reg  [5:0]                      r_smc_cnt;
reg  [UR_ADDR_WIDTH-1:0]        r_ur_addr;
      
reg  [4:0]                      r_current_state;
reg  [4:0]                      r_next_current;

reg  [5:0]                      r_micro_inst_u_smc_strb;
reg  [3:0]                      r_micro_inst_u_byte_strb;
reg  [1:0]                      r_micro_inst_u_brst;           // （2bit：00=1，01=2，10=4，11=8）
reg  [ADDR_WIDTH-1:0]           r_micro_inst_u_gr_base_addr;   // outside sram addr
reg  [3:0]                      r_micro_inst_u_ur_id;
reg  [UR_ADDR_WIDTH-1:0]        r_micro_inst_u_ur_addr;        //user addr

assign o_state     = r_current_state;

//get burst length
assign w_burst_len = (i_micro_inst_u_brst == 2'b00) ? 4'd1 :
                     (i_micro_inst_u_brst == 2'b01) ? 4'd2 :
                     (i_micro_inst_u_brst == 2'b10) ? 4'd4 : 4'd8;


//get byte valid
assign w_mwstrb    = (r_micro_inst_u_byte_strb == 4'h0) ? 16'b1111_1111_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'h1) ? 16'b0000_0000_0000_0001 :
                     (r_micro_inst_u_byte_strb == 4'h2) ? 16'b0000_0000_0000_0011 :
                     (r_micro_inst_u_byte_strb == 4'h3) ? 16'b0000_0000_0000_0111 :
                     (r_micro_inst_u_byte_strb == 4'h4) ? 16'b0000_0000_0000_1111 :
                     (r_micro_inst_u_byte_strb == 4'h5) ? 16'b0000_0000_0001_1111 :
                     (r_micro_inst_u_byte_strb == 4'h6) ? 16'b0000_0000_0011_1111 :
                     (r_micro_inst_u_byte_strb == 4'h7) ? 16'b0000_0000_0111_1111 :
                     (r_micro_inst_u_byte_strb == 4'h8) ? 16'b0000_0000_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'h9) ? 16'b0000_0001_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'ha) ? 16'b0000_0011_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'hb) ? 16'b0000_0111_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'hc) ? 16'b0000_1111_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'hd) ? 16'b0001_1111_1111_1111 :
                     (r_micro_inst_u_byte_strb == 4'he) ? 16'b0011_1111_1111_1111 : 16'b0111_1111_1111_1111;

//base address of current SMC
always @(*) begin
    r_smc_base_addr = {ADDR_WIDTH{1'b0}};

    case (r_smc_cnt)
        6'd0:     r_smc_base_addr = r_micro_inst_u_gr_base_addr;
        6'd1:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP;
        6'd2:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP << 1);
        6'd3:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP3;
        6'd4:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP << 2);
        6'd5:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP5;
        6'd6:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP3 << 1);
        6'd7:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP7;
        6'd8:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP << 3);
        6'd9:     r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP9;
        6'd10:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP5 << 1);
        6'd11:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP11;
        6'd12:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP3 << 2);
        6'd13:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP13;
        6'd14:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP7 << 1);
        6'd15:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP15;
        6'd16:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP << 4);
        6'd17:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP17;
        6'd18:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP9 << 1);
        6'd19:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP19;
        6'd20:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP5 << 2);
        6'd21:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP21;
        6'd22:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP11 << 1);
        6'd23:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP23;
        6'd24:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP3 << 3);
        6'd25:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP25;
        6'd26:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP13 << 1);
        6'd27:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP27;
        6'd28:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP7 << 2);
        6'd29:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP29;
        6'd30:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + (INTLV_STEP15 << 1);
        6'd31:    r_smc_base_addr = r_micro_inst_u_gr_base_addr + INTLV_STEP31;
        default:  r_smc_base_addr = {ADDR_WIDTH{1'b0}};
    endcase
end

//get outside memory address
always @(*) begin
    r_maddr                    = 32'd0;

    if(o_mlen == 4'd0) begin
        r_maddr                = r_smc_base_addr;
    end else if(o_mlen == 4'd1) begin
        case (r_burst_remain_len)
            4'd1:   r_maddr    = r_smc_base_addr + 32'd16;
            4'd2:   r_maddr    = r_smc_base_addr;
            default:r_maddr    = 32'd0;
        endcase
    end else if(o_mlen == 4'd3) begin
        case (r_burst_remain_len)
            4'd1:   r_maddr    = r_smc_base_addr + 32'd48;
            4'd2:   r_maddr    = r_smc_base_addr + 32'd32;
            4'd3:   r_maddr    = r_smc_base_addr + 32'd16;
            4'd4:   r_maddr    = r_smc_base_addr;
            default:r_maddr    = 32'd0;
        endcase
    end else if(o_mlen == 4'd7) begin
        case (r_burst_remain_len)
            4'd1:   r_maddr    = r_smc_base_addr + 32'd112;
            4'd2:   r_maddr    = r_smc_base_addr + 32'd96;
            4'd3:   r_maddr    = r_smc_base_addr + 32'd80;
            4'd4:   r_maddr    = r_smc_base_addr + 32'd64;
            4'd5:   r_maddr    = r_smc_base_addr + 32'd48;
            4'd6:   r_maddr    = r_smc_base_addr + 32'd32;
            4'd7:   r_maddr    = r_smc_base_addr + 32'd16;
            4'd8:   r_maddr    = r_smc_base_addr;
            default:r_maddr    = 32'd0;
        endcase
    end else begin
        r_maddr                = 32'd0;
    end
end

//get user register address
always @(*) begin
    r_ur_addr                  = 11'd0;

    if(o_mlen == 4'd1) begin
            r_ur_addr    = r_micro_inst_u_ur_addr + 11'd16;
    end else if(o_mlen == 4'd3) begin
        case (r_burst_remain_len)
            4'd2: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd48;
            4'd3: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd32;
            4'd4: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd16;
            default: r_ur_addr = 11'd0;
        endcase
    end else if(o_mlen == 4'd7) begin
        case (r_burst_remain_len)
            4'd2: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd112;
            4'd3: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd96;
            4'd4: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd80;
            4'd5: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd64;
            4'd6: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd48;
            4'd7: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd32;
            4'd8: r_ur_addr    = r_micro_inst_u_ur_addr + 11'd16;
            default: r_ur_addr = 11'd0;
        endcase
    end else begin
        r_ur_addr              = 11'd0;
    end
end

//lock micro instruction
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_micro_inst_u_smc_strb            <= 6'd0;
        r_micro_inst_u_byte_strb           <= 4'd0;
        r_micro_inst_u_brst                <= 2'd0;
        r_micro_inst_u_gr_base_addr        <= {ADDR_WIDTH{1'b0}};
        r_micro_inst_u_ur_id               <= 4'd0;
        r_micro_inst_u_ur_addr             <= {UR_ADDR_WIDTH{1'b0}};
    end else if(i_micro_inst_u_valid) begin
        r_micro_inst_u_smc_strb            <= i_micro_inst_u_smc_strb;
        r_micro_inst_u_byte_strb           <= i_micro_inst_u_byte_strb;
        r_micro_inst_u_brst                <= i_micro_inst_u_brst;
        r_micro_inst_u_gr_base_addr        <= i_micro_inst_u_gr_base_addr;
        r_micro_inst_u_ur_id               <= i_micro_inst_u_ur_id;
        r_micro_inst_u_ur_addr             <= i_micro_inst_u_ur_addr;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_current_state <= IDLE;
    end else begin
        r_current_state <= r_next_current;
    end
end

always @(*) begin
    r_next_current                 = r_current_state;

    case(r_current_state)
        IDLE: begin
            if(i_micro_inst_u_valid) begin
                r_next_current     = INIT;
            end else begin
                r_next_current     = IDLE;
            end
        end

        INIT: begin
            r_next_current         = ACCEPT_DATA;
        end
        
        //when burst length = 1, IDLE state already read user register, so r_burst_remain_len == 4'd0
        //whwn burst length = 2/4/8, when r_burst_remain_len = 1, still have 1 data to be send, but no need to read user register
        ACCEPT_DATA: begin
            // if(o_mwrite && i_saccept && ((r_burst_remain_len == 4'd0) || (r_burst_remain_len == 4'd1))) begin
            if(i_saccept && ((r_burst_remain_len == 4'd0) || (r_burst_remain_len == 4'd1))) begin    //because of coverage
                r_next_current     = SMC_DET;
            end
        end

        //whwn burst length = 2/4/8, axi receive the last one data
        SMC_DET: begin
            // if((r_burst_remain_len == 4'd0) || ((r_burst_remain_len == 4'd1) && o_mwrite && i_saccept)) begin
            if((r_burst_remain_len == 4'd0) || ((r_burst_remain_len == 4'd1) && i_saccept)) begin    //because of coverage
                if(r_smc_cnt < r_micro_inst_u_smc_strb) begin
                    r_next_current     = INIT;
                end else begin
                    r_next_current     = DONE;
                end
            end
        end

        DONE: begin
            r_next_current         = IDLE;
        end

        default: begin
            r_next_current         = IDLE;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        o_mid                                 <= 4'd0;
        o_maddr                               <= {ADDR_WIDTH{1'b0}};
        o_mread                               <= 1'b0;
        o_mwrite                              <= 1'b0;
        o_mlen                                <= 4'd0;
        o_msize                               <= 3'd0;
        o_mburst                              <= 2'd0;
        o_mcache                              <= 4'd0;
        o_mport                               <= 3'd0;
        o_mdata                               <= {DATA_WIDTH{1'b0}};
        o_mwstrb                              <= {UR_BYTE_CNT{1'b0}};

        o_ur_re                               <= 1'b0;
        o_ur_addr                             <= {UR_ADDR_WIDTH{1'b0}};

        o_micro_inst_d_valid                  <= 1'b0;
        o_micro_inst_d_done                   <= 1'b0;

        r_smc_cnt                             <= 6'd0;
    end else begin     
        case(r_current_state)
            IDLE: begin
                o_mid                         <= 4'd0;
                o_maddr                       <= {ADDR_WIDTH{1'b0}};
                o_mread                       <= 1'b0;
                o_mwrite                      <= 1'b0;
                o_mlen                        <= 4'd0;
                o_msize                       <= 3'd0;
                o_mburst                      <= 2'd0;
                o_mcache                      <= 4'd0;
                o_mport                       <= 3'd0;
                o_mdata                       <= {DATA_WIDTH{1'b0}};
                o_mwstrb                      <= {UR_BYTE_CNT{1'b0}};

                o_micro_inst_d_valid          <= 1'b0;
                o_micro_inst_d_done           <= 1'b0;

                if(i_micro_inst_u_valid) begin
                    //get user register data to use
                    o_ur_re                   <= 1'b1;
                    o_ur_addr                 <= i_micro_inst_u_ur_addr;
                    o_mlen                    <= w_burst_len - 4'd1;
                    o_msize                   <= 3'b100;                  //16Byte
                    o_mburst                  <= 2'b01;                   //INCR
                    r_burst_remain_len        <= w_burst_len;             //when valid = 1, use w_burst_len
                end else begin
                    o_ur_re                   <= 1'b0;
                    o_ur_addr                 <= {UR_ADDR_WIDTH{1'b0}};
                end
            end

            INIT: begin
                //place the user register data on the user side of axi bus
                o_mwrite                      <= 1'b1;
                o_maddr                       <= r_smc_base_addr;
                o_mdata                       <= i_ur_rdata;
                o_mwstrb                      <= w_mwstrb;
                // r_burst_remain_len            <= w_burst_len;
                r_burst_remain_len            <= r_burst_remain_len - 4'd1;

                //when burst length = 1, IDLE state read user register, so INIT state reset o_ur_re
                //when burst length = 2/4/8, INIT state continue read user register
                if(o_mlen == 4'd0) begin
                    o_ur_re                   <= 1'b0;
                end else begin
                    o_ur_re                   <= 1'b1;
                    o_ur_addr                 <= r_ur_addr;
                end
            end

            ACCEPT_DATA: begin
                // if(o_mwrite && i_saccept) begin
                if(i_saccept) begin    //because of coverage
                    //when burst length = 1, the user side of the axi bus already receive user register data
                    if(r_burst_remain_len == 4'd0) begin
                        o_ur_re               <= 1'b0;
                        o_mwrite              <= 1'b0;
                    //when burst length = 2/4/8, burst length remain 1, dont read user register data
                    end else if((r_burst_remain_len == 4'd1)) begin
                        o_ur_re               <= 1'b0;
                        o_mdata               <= i_ur_rdata;
                        o_maddr               <= r_maddr;
                    end else begin
                        r_burst_remain_len    <= r_burst_remain_len - 4'd1;

                        o_mdata               <= i_ur_rdata;
                        o_maddr               <= r_maddr;
                        o_ur_re               <= 1'b1;
                        o_ur_addr             <= r_ur_addr;
                    end
                end else begin
                    o_ur_re                   <= 1'b0;
                end
            end

            SMC_DET: begin
                 //when burst length = 2/4/8, must wait axi already receive data, then jump DONE  state,read next SMC
                // if((r_burst_remain_len == 4'd0) || ((r_burst_remain_len == 4'd1) && o_mwrite && i_saccept)) begin
                if((r_burst_remain_len == 4'd0) || (i_saccept)) begin    //because of coverage
                    //jump to DONE
                    o_mwrite                      <= 1'b0;
    
                    if(r_smc_cnt < r_micro_inst_u_smc_strb) begin
                        r_smc_cnt                 <= r_smc_cnt + 6'd1;
    
                        o_ur_re                   <= 1'b1;
                        o_ur_addr                 <= r_micro_inst_u_ur_addr;
                        r_burst_remain_len        <= o_mlen + 4'd1;             //when valid = 0, use latch signal o_len
                    end else begin
                        r_smc_cnt                 <= 6'd0;
                    end
                end
            end

            DONE: begin
                o_micro_inst_d_valid          <= 1'b1;
                o_micro_inst_d_done           <= 1'b1;
            end
            
            default: begin
                o_micro_inst_d_valid          <= 1'b0;
                o_micro_inst_d_done           <= 1'b0;
                o_mread                       <= 1'b1;
                o_mwrite                      <= 1'b1;
                o_mdata                       <= {DATA_WIDTH{1'b1}};
                o_ur_re                       <= 1'b0;
                o_ur_addr                     <= {UR_ADDR_WIDTH{1'b1}};
            end
        endcase
    end
end


endmodule
