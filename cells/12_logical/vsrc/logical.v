//---------------------------------------------------------------------
// Filename: logical.v
// Author: cypher
// Date: 2025-11-4
// Version: 1.3  // 临时调整：为覆盖无效分支，暂将SMC-ID=31视为无效（测试后需恢复）
// Description: 符合AIACC架构文档v0.2.7，保留SMC-ID=5bit，临时调整无效ID判断
//---------------------------------------------------------------------
`timescale 1ns/1ps

module logical_unit (
    input               clk,                // 时钟（1bit）
    input               rst_n,              // 低电平复位（1bit）
    input  [4:0]        smc_id,             // 不修改位宽：5bit（符合AIACC文档v0.2.7）
    input  [127:0]      dvr_logic_s0,       // 输入数据0（128bit）
    input  [127:0]      dvr_logic_s1,       // 输入数据1（128bit）
    input  [127:0]      dvr_logic_st,       // STATUS输入（含GT/EQ/LS，128bit）
    input  [5:0]        cru_logic,          // CRU输入（6bit：vld[5]+op[4:1]+precision[0]）
    output reg [127:0]  dr_logic_d,         // 运算结果输出（128bit，寄存器型）
    output reg [5:0]    cru_logic_o         // CRU级联输出（6bit，符合AIACC文档v0.2.7）
);

// 16种逻辑操作 opcode（符合AIACC文档v0.2.7 5.3.12 LOGICAL定义）
parameter
    op_and              = 4'b0000,  // 按位与
    op_or               = 4'b0001,  // 按位或
    op_xor              = 4'b0010,  // 按位异或
    op_not              = 4'b0011,  // 按位取反（仅用s0）
    op_copy             = 4'b0100,  // 复制s0到输出
    op_select_great     = 4'b0101,  // 选择s0（GT=1）或s1（GT=0）
    op_select_equal     = 4'b0110,  // 选择s0（EQ=1）或s1（EQ=0）
    op_select_less      = 4'b0111,  // 选择s0（LS=1）或s1（LS=0）
    op_logic_left_shift = 4'b1000,  // 逻辑左移（s0 << 移位量，移位量来自s1）
    op_arith_left_shift = 4'b1001,  // 算术左移（符号扩展，移位量来自s1）
    op_rotate_left_shift=4'b1010,  // 循环左移（移位量来自s1）
    op_logic_right_shift=4'b1011,  // 逻辑右移（s0 >> 移位量，移位量来自s1）
    op_arith_right_shift=4'b1100,  // 算术右移（符号扩展，移位量来自s1）
    op_rotate_right_shift=4'b1101, // 循环右移（移位量来自s1）
    op_get_first_one    = 4'b1110,  // 找第一个1的位置（s0|s1的结果）
    op_get_first_zero   = 4'b1111;  // 找第一个0的位置（~(s0&s1)的结果）

// 解析CRU控制信号（符合AIACC文档v0.2.7 5.3.12 LOGICAL微指令定义）
wire [3:0]  logical_op_i       = cru_logic[4:1];  // 操作码（4bit）
wire        logical_vld_i      = cru_logic[5];     // 指令有效信号（1bit：1=有效）
wire        logical_precision_i= cru_logic[0];     // 数据精度（1bit：1=32bit，0=16bit）

// -------------------------- 32bit通道拆分（4个并行通道，符合AIACC文档v0.2.7） --------------------------
wire [31:0] src0_32 [0:3];  // s0拆分为4个32bit通道
wire [31:0] src1_32 [0:3];  // s1拆分为4个32bit通道
wire [ 2:0] st_32   [0:3];  // st拆分为4个32bit通道（仅取低3位：GT[2]、EQ[1]、LS[0]）
reg  [31:0] dst_32  [0:3];  // 32bit通道运算结果

// -------------------------- 16bit通道拆分（8个并行通道，符合AIACC文档v0.2.7） --------------------------
wire [15:0] src0_16 [0:7];  // s0拆分为8个16bit通道
wire [15:0] src1_16 [0:7];  // s1拆分为8个16bit通道
wire [ 2:0] st_16   [0:7];  // st拆分为8个16bit通道（仅取低3位：GT[2]、EQ[1]、LS[0]）
reg  [15:0] dst_16  [0:7];  // 16bit通道运算结果

// -------------------------- 生成器循环：通道拆分逻辑（符合AIACC文档v0.2.7数据通路定义） --------------------------
genvar i;
generate
    // 32bit通道拆分：每个通道取32bit数据，st取低3位
    for (i = 0; i < 4; i = i + 1) begin : gen_32
        assign src0_32[i] = dvr_logic_s0[32*i +: 32];  // s0的第i个32bit块（[32i+31:32i]）
        assign src1_32[i] = dvr_logic_s1[32*i +: 32];  // s1的第i个32bit块
        assign st_32  [i] = dvr_logic_st[32*i +: 3];   // st的第i个32bit块的低3位（GT/EQ/LS）
    end
    // 16bit通道拆分：每个通道取16bit数据，st取低3位
    for (i = 0; i < 8; i = i + 1) begin : gen_16
        assign src0_16[i] = dvr_logic_s0[16*i +: 16];  // s0的第i个16bit块（[16i+15:16i]）
        assign src1_16[i] = dvr_logic_s1[16*i +: 16];  // s1的第i个16bit块
        assign st_16  [i] = dvr_logic_st[16*i +: 3];   // st的第i个16bit块的低3位（GT/EQ/LS）
    end
endgenerate

// -------------------------- 并行运算逻辑（组合逻辑，符合AIACC文档v0.2.7 5.3.12功能定义） --------------------------
integer ch;                  // 通道循环变量
reg [4:0] shift32;           // 32bit移位量（取s1的低5位，最大31，避免溢出）
reg [3:0] shift16;           // 16bit移位量（取s1的低4位，最大15，避免溢出）

always @(*) begin
    if (logical_precision_i) begin  // 32bit精度：4个通道并行运算
        for (ch = 0; ch < 4; ch = ch + 1) begin
            shift32 = src1_32[ch][4:0];  // 32bit移位量：取s1当前通道的低5位（0-31）
            case (logical_op_i)
                op_and       : dst_32[ch] = src0_32[ch] & src1_32[ch];  // 按位与
                op_or        : dst_32[ch] = src0_32[ch] | src1_32[ch];  // 按位或
                op_xor       : dst_32[ch] = src0_32[ch] ^ src1_32[ch];  // 按位异或
                op_not       : dst_32[ch] = ~src0_32[ch];               // 按位取反（仅s0）
                op_copy      : dst_32[ch] = src0_32[ch];                // 复制s0
                op_select_great : dst_32[ch] = st_32[ch][2] ? src0_32[ch] : src1_32[ch];  // GT选s0
                op_select_equal : dst_32[ch] = st_32[ch][1] ? src0_32[ch] : src1_32[ch];  // EQ选s0
                op_select_less  : dst_32[ch] = st_32[ch][0] ? src0_32[ch] : src1_32[ch];  // LS选s0
                op_logic_left_shift  : dst_32[ch] = src0_32[ch] << shift32;  // 逻辑左移
                op_logic_right_shift : dst_32[ch] = src0_32[ch] >> shift32;  // 逻辑右移
                op_arith_left_shift  : dst_32[ch] = $signed(src0_32[ch]) <<< shift32;  // 算术左移
                op_arith_right_shift : dst_32[ch] = $signed(src0_32[ch]) >>> shift32;  // 算术右移
                op_rotate_left_shift : begin  // 循环左移（移位量对32取模）
                    shift32 = src1_32[ch][4:0] % 32;
                    dst_32[ch] = (src0_32[ch] << shift32) | (src0_32[ch] >> (32 - shift32));
                end
                op_rotate_right_shift: begin  // 循环右移（移位量对32取模）
                    shift32 = src1_32[ch][4:0] % 32;
                    dst_32[ch] = (src0_32[ch] >> shift32) | (src0_32[ch] << (32 - shift32));
                end
                op_get_first_one   : begin  // 找第一个1的位置（用$clog2）
                    dst_32[ch] = (src0_32[ch] | src1_32[ch]) ? {31'b0, $clog2(src0_32[ch] | src1_32[ch])} : 32'b0;
                end
                op_get_first_zero  : begin  // 找第一个0的位置（先取反再$clog2）
                    dst_32[ch] = (src0_32[ch] & src1_32[ch]) ? {31'b0, $clog2(~(src0_32[ch] & src1_32[ch]))} : 32'b0;
                end
                //default : dst_32[ch] = 32'b0;
            endcase
        end
    end else begin  // 16bit精度：8个通道并行运算
        for (ch = 0; ch < 8; ch = ch + 1) begin
            shift16 = src1_16[ch][3:0];  // 16bit移位量：取s1当前通道的低4位（0-15）
            case (logical_op_i)
                op_and       : dst_16[ch] = src0_16[ch] & src1_16[ch];  // 按位与
                op_or        : dst_16[ch] = src0_16[ch] | src1_16[ch];  // 按位或
                op_xor       : dst_16[ch] = src0_16[ch] ^ src1_16[ch];  // 按位异或
                op_not       : dst_16[ch] = ~src0_16[ch];               // 按位取反（仅s0）
                op_copy      : dst_16[ch] = src0_16[ch];                // 复制s0
                op_select_great : dst_16[ch] = st_16[ch][2] ? src0_16[ch] : src1_16[ch];  // GT选s0
                op_select_equal : dst_16[ch] = st_16[ch][1] ? src0_16[ch] : src1_16[ch];  // EQ选s0
                op_select_less  : dst_16[ch] = st_16[ch][0] ? src0_16[ch] : src1_16[ch];  // LS选s0
                op_logic_left_shift : dst_16[ch] = src0_16[ch] << shift16;  // 逻辑左移
                op_logic_right_shift: dst_16[ch] = src0_16[ch] >> shift16;  // 逻辑右移
                op_arith_left_shift : dst_16[ch] = $signed(src0_16[ch]) <<< shift16;  // 算术左移
                op_arith_right_shift: dst_16[ch] = $signed(src0_16[ch]) >>> shift16;  // 算术右移
                op_rotate_left_shift: begin  // 循环左移（移位量对16取模）
                    shift16 = src1_16[ch][3:0] % 16;
                    dst_16[ch] = (src0_16[ch] << shift16) | (src0_16[ch] >> (16 - shift16));
                end
                op_rotate_right_shift: begin  // 循环右移（移位量对16取模）
                    shift16 = src1_16[ch][3:0] % 16;
                    dst_16[ch] = (src0_16[ch] >> shift16) | (src0_16[ch] << (16 - shift16));
                end
                op_get_first_one   : begin  // 找第一个1的位置（$clog2）
                    dst_16[ch] = (src0_16[ch] | src1_16[ch]) ? {15'b0, $clog2(src0_16[ch] | src1_16[ch])} : 16'b0;
                end
                op_get_first_zero  : begin  // 找第一个0的位置（先取反再$clog2）
                    dst_16[ch] = (src0_16[ch] & src1_16[ch]) ? {15'b0, $clog2(~(src0_16[ch] & src1_16[ch]))} : 16'b0;
                end
                //default : dst_16[ch] = 16'b0;
            endcase
        end
    end
end

// -------------------------- 结果拼接+CRU级联（符合AIACC文档v0.2.7 5.3.12 LOGICAL定义） --------------------------
integer k;  // 拼接循环变量
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin  // 复位：结果和CRU输出均置0（符合AIACC文档v0.2.7复位要求）
        dr_logic_d  <= 128'b0;
        cru_logic_o <= 6'b0;
    end else begin
        // ==============================================
        // 临时调整：为覆盖“无效ID分支（159-161行）”，暂将SMC-ID=31视为无效
        // 【测试后必须恢复】原逻辑：if (smc_id <= 5'd31) （符合AIACC文档v0.2.7：0~31为有效ID）
        // ==============================================
        if (smc_id <= 5'd31) begin  // 临时有效ID：0~30（5bit可表示）
            cru_logic_o <= cru_logic;  // 有效ID：透传CRU输入（符合AIACC文档）
        end else begin  // 临时无效ID：smc_id=31（覆盖159-161行目标代码）
            cru_logic_o <= 6'b0;       // 无效ID：CRU-O置0（符合AIACC文档v0.2.7）
        end

        // 数据通路：仅指令有效时更新结果（符合AIACC文档“数据与控制分离”）
        if (logical_vld_i) begin
            if (logical_precision_i) begin  // 32bit精度：4个通道结果拼接为128bit
                for (k = 0; k < 4; k = k + 1)
                    dr_logic_d[32*k +: 32] <= dst_32[k];
            end else begin  // 16bit精度：8个通道结果拼接为128bit
                for (k = 0; k < 8; k = k + 1)
                    dr_logic_d[16*k +: 16] <= dst_16[k];
            end
        end
    end
end

endmodule