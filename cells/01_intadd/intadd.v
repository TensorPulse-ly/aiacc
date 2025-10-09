`timescale 1ns / 1ps

module intadd (
    input         clk,
    input         rst_n,
    input  [127:0] src_reg0,
    input  [127:0] src_reg1,
    input  [127:0] src_reg2,
    input  [10:0]  cru_intadd, // 新增：微指令控制信号
    output [127:0] dst_reg0,
    output [127:0] dst_reg1,
    output [127:0] st          // 状态寄存器
);

    // 从 cru_intadd 解码各字段
    wire        inst_valid   = cru_intadd[10];
    wire [1:0]  precision_s0 = cru_intadd[9:8];
    wire [1:0]  precision_s1 = cru_intadd[7:6];
    wire [1:0]  precision_s2 = cru_intadd[5:4];
    wire        sign_s0      = cru_intadd[3];
    wire        sign_s1      = cru_intadd[2];
    wire        sign_s2      = cru_intadd[1];
    wire        update_st    = cru_intadd[0];

    wire [127:0] add8_dst0, add8_dst1, add8_st;
    wire [127:0] add32_dst, add32_st;

    add8 add8_unit (
        .clk(clk),
        .rst_n(rst_n),
        .src0(src_reg0),
        .src1(src_reg1),
        .src2(src_reg2),
        .sign_s0(sign_s0),
        .sign_s1(sign_s1),
        .sign_s2(sign_s2),
        .dst0(add8_dst0),
        .dst1(add8_dst1)
    );
    
    // add8模块没有st输出，设置为0
    assign add8_st = 128'd0;

    add32 add32_unit (
        .clk(clk),
        .rst_n(rst_n),
        .src0(src_reg0),
        .src1(src_reg1),
        .sign_s0(sign_s0),
        .sign_s1(sign_s1),
        .dst(add32_dst),
        .st(add32_st)
    );

    // 状态寄存器
    reg [127:0] st_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_reg <= 128'd0;
        end else if (inst_valid && update_st) begin
            if (precision_s0 == 2'b00 && precision_s1 == 2'b00 && precision_s2 == 2'b00) begin
                st_reg <= add8_st;  // 4+8bit模式
            end else if (precision_s0 == 2'b11 && precision_s1 == 2'b11) begin
                st_reg <= add32_st; // 32bit模式
            end else begin
                st_reg <= 128'd0;  // 其他模式
            end
        end
        // 当update_st为0或inst_valid为0时，保持st_reg的当前值
    end
    assign st = st_reg;

    // 数据输出选择
    assign dst_reg0 = (inst_valid && precision_s0 == 2'b00 && precision_s1 == 2'b00 && precision_s2 == 2'b00)
                      ? add8_dst0 :
                      (inst_valid && precision_s0 == 2'b11 && precision_s1 == 2'b11)
                      ? add32_dst : 128'd0;

    assign dst_reg1 = (inst_valid && precision_s0 == 2'b00 && precision_s1 == 2'b00 && precision_s2 == 2'b00)
                      ? add8_dst1 : 128'd0;

endmodule
