//---------------------------------------------------------------------
// Filename: logical.v
// Author: cypher
// Date: 2025-8-13
// Version: 1.2
// Description: This is a module that supports basic microinstructions.
//---------------------------------------------------------------------
`timescale 1ns/1ps

module logical_unit (
    input               clk,
    input               rst_n,
    input  [127:0]      dvr_logic_s0,
    input  [127:0]      dvr_logic_s1,
    input  [127:0]      dvr_logic_st,   // STATUS 128-bit 端口
    input  [5:0]        cru_logic,
    output reg [127:0]  dr_logic_d
);

parameter
    op_and              = 4'b0000,
    op_or               = 4'b0001,
    op_xor              = 4'b0010,
    op_not              = 4'b0011,
    op_copy             = 4'b0100,
    op_select_great     = 4'b0101,
    op_select_equal     = 4'b0110,
    op_select_less      = 4'b0111,
    op_logic_left_shift = 4'b1000,
    op_arith_left_shift = 4'b1001,
    op_rotate_left_shift= 4'b1010,
    op_logic_right_shift= 4'b1011,
    op_arith_right_shift= 4'b1100,
    op_rotate_right_shift=4'b1101,
    op_get_first_one    = 4'b1110,
    op_get_first_zero   = 4'b1111;

// 微指令字段
wire [3:0]  logical_op_i       = cru_logic[4:1];
wire        logical_vld_i      = cru_logic[5];
wire        logical_precision_i= cru_logic[0];  // 1=32-bit, 0=16-bit

// 32-bit 通道拆分
wire [31:0] src0_32 [0:3];
wire [31:0] src1_32 [0:3];
wire [ 2:0] st_32   [0:3];   // GT,EQ,LS
reg  [31:0] dst_32  [0:3];

// 16-bit 通道拆分
wire [15:0] src0_16 [0:7];
wire [15:0] src1_16 [0:7];
wire [ 2:0] st_16   [0:7];
reg  [15:0] dst_16  [0:7];

genvar i;
generate
    for (i = 0; i < 4; i = i + 1) begin : gen_32
        assign src0_32[i] = dvr_logic_s0[32*i +: 32];
        assign src1_32[i] = dvr_logic_s1[32*i +: 32];
        assign st_32  [i] = dvr_logic_st[32*i +: 3];   // 取低3位
    end
    for (i = 0; i < 8; i = i + 1) begin : gen_16
        assign src0_16[i] = dvr_logic_s0[16*i +: 16];
        assign src1_16[i] = dvr_logic_s1[16*i +: 16];
        assign st_16  [i] = dvr_logic_st[16*i +: 3];   // 取低3位
    end
endgenerate

// 并行运算
integer ch;
reg [4:0] shift32;
reg [3:0] shift16;

always @(*) begin
    if (logical_precision_i) begin // 32-bit × 4
        for (ch = 0; ch < 4; ch = ch + 1) begin
            shift32 = src1_32[ch][4:0];
            case (logical_op_i)
                op_and       : dst_32[ch] = src0_32[ch] & src1_32[ch];
                op_or        : dst_32[ch] = src0_32[ch] | src1_32[ch];
                op_xor       : dst_32[ch] = src0_32[ch] ^ src1_32[ch];
                op_not       : dst_32[ch] = ~src0_32[ch];
                op_copy      : dst_32[ch] = src0_32[ch];
                op_select_great : dst_32[ch] = st_32[ch][2] ? src0_32[ch] : src1_32[ch];
                op_select_equal : dst_32[ch] = st_32[ch][1] ? src0_32[ch] : src1_32[ch];
                op_select_less  : dst_32[ch] = st_32[ch][0] ? src0_32[ch] : src1_32[ch];
                op_logic_left_shift  : dst_32[ch] = src0_32[ch] << shift32;
                op_logic_right_shift : dst_32[ch] = src0_32[ch] >> shift32;
                op_arith_left_shift  : dst_32[ch] = $signed(src0_32[ch]) <<< shift32;
                op_arith_right_shift : dst_32[ch] = $signed(src0_32[ch]) >>> shift32;
                op_rotate_left_shift : begin
                    shift32 = src1_32[ch][4:0] % 32;
                    dst_32[ch] = (src0_32[ch] >> shift32) |
                                 (src0_32[ch] << (32 - shift32));
                end
                op_rotate_right_shift: begin
                    shift32 = src1_32[ch][4:0] % 32;
                    dst_32[ch] = (src0_32[ch] << shift32) |
                                 (src0_32[ch] >> (32 - shift32));
                end
                op_get_first_one   : dst_32[ch] = (src0_32[ch]) ?
                                                  {31'b0, $clog2(src0_32[ch])} : 32'b0;
                op_get_first_zero  : dst_32[ch] = ~src0_32[ch] ?
                                                  {31'b0, $clog2(~(src0_32[ch]))} : 32'b0;
                default: dst_32[ch] = 32'b0;
            endcase
        end
    end else begin // 16-bit × 8
        for (ch = 0; ch < 8; ch = ch + 1) begin
            shift16 = src1_16[ch][3:0];
            case (logical_op_i)
                op_and       : dst_16[ch] = src0_16[ch] & src1_16[ch];
                op_or        : dst_16[ch] = src0_16[ch] | src1_16[ch];
                op_xor       : dst_16[ch] = src0_16[ch] ^ src1_16[ch];
                op_not       : dst_16[ch] = ~src0_16[ch];
                op_copy      : dst_16[ch] = src0_16[ch];
                op_select_great : dst_16[ch] = st_16[ch][2] ? src0_16[ch] : src1_16[ch];
                op_select_equal : dst_16[ch] = st_16[ch][1] ? src0_16[ch] : src1_16[ch];
                op_select_less  : dst_16[ch] = st_16[ch][0] ? src0_16[ch] : src1_16[ch];
                op_logic_left_shift : dst_16[ch] = src0_16[ch] << shift16;
                op_logic_right_shift: dst_16[ch] = src0_16[ch] >> shift16;
                op_arith_left_shift : dst_16[ch] = $signed(src0_16[ch]) <<< shift16;
                op_arith_right_shift: dst_16[ch] = $signed(src0_16[ch]) >>> shift16;
                op_rotate_left_shift: begin
                    shift16 = src1_16[ch][3:0] % 16;
                    dst_16[ch] = (src0_16[ch] >> shift16) |
                                 (src0_16[ch] << (16 - shift16));
                end
                op_rotate_right_shift: begin
                    shift16 = src1_16[ch][3:0] % 16;
                    dst_16[ch] = (src0_16[ch] << shift16) |
                                 (src0_16[ch] >> (16 - shift16));
                end
                op_get_first_one   : dst_16[ch] = (src0_16[ch]) ?
                                                  {15'b0, $clog2(src0_16[ch])} : 16'b0;
                op_get_first_zero  : dst_16[ch] = (src0_16[ch]) ?
                                                  {15'b0, $clog2(~src0_16[ch])} : 16'b0;
                default: dst_16[ch] = 16'b0;
            endcase
        end
    end
end

// 结果拼接输出
integer k;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        dr_logic_d     <= 128'b0;
    end else if (logical_vld_i) begin
        if (logical_precision_i) begin // 32-bit
            for (k = 0; k < 4; k = k + 1)
                dr_logic_d[32*k +: 32] <= dst_32[k];
        end else begin // 16-bit
            for (k = 0; k < 8; k = k + 1)
                dr_logic_d[16*k +: 16] <= dst_16[k];
        end
    end
end

endmodule