//=========================================================================
// Project:     AIACC
// File:        memory_model.v
// Module:      memory_model
// Author:      zhuzhenglong
// Email:       zhuzhenglong@inchitech.com
// Created:     2025-11-6
// Modified:    2025-11-6
// Version:     v0.1
//=========================================================================

// Description:
// write memory

// Parameters:
// - BYTE_STRB     : Byte valid flag
// - DATA_WIDTH    : Data bus width in bits (default: 128)
// - ADDR_WIDTH    : Address bus width in bits (default: 1024 * 512)
// - MEM_SIZE      : Memory size (default: 32)

//=========================================================================
// Revision History:
// v0.1 - 2025-11-6  - Initial version
//
//=========================================================================
`timescale 1ns/1ps
module memory_model #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 128,
    parameter BYTE_STRB     = DATA_WIDTH/8,
    parameter MEM_SIZE      = 1024 * 512    // memory size（512KB，0~0x80000）
)(
    input                           clk,
    input                           rst_n,
    
    input      [ADDR_WIDTH-1:0]     i_maddr,
    input                           i_mread,
    input                           i_mwrite,
    input      [2:0]                i_msize,
    input      [1:0]                i_mburst,
    input      [3:0]                i_mlen,
    input                           i_mlast,
    input      [DATA_WIDTH-1:0]     i_mdata,
    input      [BYTE_STRB-1:0]      i_mwstrb,
    output reg                      o_saccept,
    output reg                      o_svalid,
    output reg [1:0]                o_sresp,
    input                           i_mready
);

// 内存数组（存储数据，512KB大小）
reg [DATA_WIDTH-1:0] r_memory [0:MEM_SIZE-1];
reg [DATA_WIDTH-1:0] r_memory_data;

always @(*) begin
    if(!i_mlast) begin
        r_memory_data                                 = i_mdata;
    end else begin
        case (i_mwstrb)
            16'b0000_0000_0000_0001: r_memory_data    = {120'd0, i_mdata[7:0]};
            16'b0000_0000_0000_0011: r_memory_data    = {112'd0, i_mdata[15:0]};
            16'b0000_0000_0000_0111: r_memory_data    = {104'd0, i_mdata[23:0]};
            16'b0000_0000_0000_1111: r_memory_data    = {96'd0,  i_mdata[31:0]};
            16'b0000_0000_0001_1111: r_memory_data    = {88'd0,  i_mdata[39:0]};
            16'b0000_0000_0011_1111: r_memory_data    = {80'd0,  i_mdata[47:0]};
            16'b0000_0000_0111_1111: r_memory_data    = {72'd0,  i_mdata[55:0]};
            16'b0000_0000_1111_1111: r_memory_data    = {64'd0,  i_mdata[63:0]};
            16'b0000_0001_1111_1111: r_memory_data    = {56'd0,  i_mdata[71:0]};
            16'b0000_0011_1111_1111: r_memory_data    = {48'd0,  i_mdata[79:0]};
            16'b0000_0111_1111_1111: r_memory_data    = {40'd0,  i_mdata[87:0]};
            16'b0000_1111_1111_1111: r_memory_data    = {32'd0,  i_mdata[95:0]};
            16'b0001_1111_1111_1111: r_memory_data    = {24'd0,  i_mdata[103:0]};
            16'b0011_1111_1111_1111: r_memory_data    = {16'd0,  i_mdata[111:0]};
            16'b0111_1111_1111_1111: r_memory_data    = {8'd0,   i_mdata[119:0]};
            16'b1111_1111_1111_1111: r_memory_data    = i_mdata[127:0];
            default:                 r_memory_data    = {DATA_WIDTH{1'b0}};
        endcase
    end
end

reg   [2:0]               r_current_state;
reg   [2:0]               r_next_state;

localparam   IDLE           = 3'b001;
localparam   ACCEPT_DATA    = 3'b010;
localparam   RESP           = 3'b100;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        r_current_state              <= IDLE;
    end else begin
        r_current_state              <= r_next_state;
    end
end

always @(*) begin
    case (r_current_state)
        IDLE: begin
            r_next_state          = IDLE;

            if(!i_mread && i_mwrite && !i_mlast) begin
                r_next_state      = ACCEPT_DATA;
            end else if(!i_mread && i_mwrite && i_mlast) begin
                r_next_state      = RESP;
            end
        end

        ACCEPT_DATA: begin
            r_next_state          = ACCEPT_DATA;

            if(!i_mread && i_mwrite && i_mlast) begin    //COND: when i_mwrite = 0, i_mlast must be 0
                r_next_state      = RESP;
            end
        end

        RESP: begin
            r_next_state          = RESP;

            if(i_mready) begin
                r_next_state      = IDLE;
            end
        end
        
        default: begin
            r_next_state          = IDLE;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    case (r_current_state)
        IDLE: begin
            o_svalid                               <= 1'b0;

            if(!i_mread && i_mwrite) begin
                r_memory[i_maddr]                  <= r_memory_data;
            end
        end

        ACCEPT_DATA: begin
            if(!i_mread && i_mwrite) begin
                r_memory[i_maddr]                  <= r_memory_data;
            end
        end

        RESP: begin
            if(i_mready) begin
                o_svalid                           <= 1'b1;
                o_sresp                            <= 2'b01;
            end else begin
                o_svalid                           <= 1'b0;
            end
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        o_saccept                          <= 1'b0;
    end else begin
        o_saccept                          <= 1'b1;
    end
end

integer fh;
always @(posedge clk) begin
    if(o_saccept && i_mwrite & (!i_mread)) begin
        fh = $fopen("dst.txt", "a");

        if(i_mlast) begin
            $fdisplay(fh, "[DEST] time=%0t, mlast = %h, strb=%h, memory_addr = %h, r_memory_data = [%h]" ,$time, i_mlast, i_mwstrb, i_maddr, r_memory_data);
                // $fdisplay(fh, "[FAIL][4+8bit] RTL_dst0=%h C_dst0=%h RTL_dst1=%h C_dst1=%h RTL_st=%h C_st=%h",
                //           rtl_dst0, c_dst0, rtl_dst1, c_dst1, rtl_st, c_st_reg);
        end else begin
            $fdisplay(fh, "[DEST] time=%0t, memory_addr = %h, r_memory_data = [%h]" ,$time, i_maddr, r_memory_data);
        end
        $fclose(fh);

    end
end

endmodule
    