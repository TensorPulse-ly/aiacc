`timescale 1ns/1ps
// STB (Burst Store) 模块 - 核心功能：解析STB指令，透传UR随机数据到axi_stb
module burst_store #(
    parameter ADDR_WIDTH = 32,          // 地址宽度
    parameter DATA_WIDTH = 128,         // 数据宽度（匹配UR和AXI）
    parameter SMC_COUNT = 6,            // SMC数量（固定6个）
    parameter UR_BYTE_CNT = 16,         // 字节使能宽度（128bit/8=16）
    parameter INTLV_STEP = 64           // SMC地址交错步长（64字节）
)(
    // 时钟与复位
    input                   clk,
    input                   rst_n,
    
    // CRU-STB-I 输入信号（测试平台/上层指令）
    input                   stb_u_valid,    // 指令有效信号
    input [SMC_COUNT-1:0]   stb_u_smc_strb, // SMC使能编码（6bit，每bit对应一个SMC）
    input [3:0]             stb_u_byte_strb,// 字节使能编码（4bit，对应16字节掩码）
    input [1:0]             stb_u_brst,     // burst长度编码（2bit：00=1拍，01=2拍，10=4拍，11=8拍）
    input [ADDR_WIDTH-1:0]  stb_u_gr_base_addr, // 外部内存基地址
    input [3:0]             stb_u_ur_id,    // 目标UR ID（0~15）
    input [10:0]            stb_u_ur_addr,  // 目标UR地址（0~2047）
    input [DATA_WIDTH-1:0]  ur_rdata,       // 输入：ur_model生成的随机数据
    
    // CRD-STB-O 输出信号（反馈给上层）
    output reg              stb_d_valid,    // 指令有效反馈
    output reg              stb_d_done,     // 指令完成反馈
    input                   stb_d_ready,    // 上层就绪信号（握手确认）
    output reg [2:0]        state  ,         // 状态输出（供调试）
    
    // UR接口（连接ur_model，发起读请求）
    output reg              ur_re,          // UR读使能（向ur_model请求随机数据）
    output reg [10:0]       ur_addr,        // UR读地址（传递给ur_model）
    
    // 事务参数输出（连接axi_stb，传递随机数据+指令参数）
    output reg              stb2stb_valid,  // 事务包就绪标志（通知axi_stb处理）
    output reg [ADDR_WIDTH-1:0] stb2stb_addr,  // 最终写入地址（基地址+SMC偏移）
    output reg [DATA_WIDTH-1:0] stb2stb_data,  // 透传UR随机数据（核心）
    output reg [7:0]        stb2stb_burst_len,  // burst长度（0=1拍，1=2拍，3=4拍，7=8拍）
    output reg [UR_BYTE_CNT-1:0] stb2stb_wstrb,  // 字节使能掩码（16bit）
    input                   stb2stb_done     // 输入：axi_stb事务完成反馈
);

// 状态定义（简化为5个核心状态）
localparam IDLE      = 3'd0;  // 空闲状态（等待STB指令）
localparam INIT      = 3'd1;  // 初始化状态（解析指令参数，选择SMC）
localparam AW_HANDSHAKE = 3'd2; // 读取UR数据+生成事务包
localparam WAIT_RESP  = 3'd3; // 等待axi_stb事务完成
localparam DONE      = 3'd4;  // 指令完成（反馈给上层）

// 内部寄存器（锁存指令参数）
reg [SMC_COUNT-1:0]     smc_strb_reg;    // 锁存SMC使能信息
reg [SMC_COUNT-1:0]     next_smc;        // 下一个要处理的SMC（临时变量）
reg [3:0]               byte_strb_reg;   // 锁存字节使能编码
reg [1:0]               brst_reg;        // 锁存burst长度编码
reg [ADDR_WIDTH-1:0]    gr_base_addr_reg;// 锁存外部内存基地址
reg [3:0]               ur_id_reg;       // 锁存UR ID
reg [10:0]              ur_addr_reg;     // 锁存UR地址
reg [SMC_COUNT-1:0]     current_smc;     // 当前处理的SMC（位掩码）
reg [6:0]               wait_resp_cnt;   // 超时计数器（防止死锁）



// 字节掩码解码（根据stb_u_byte_strb生成16bit使能）
wire [UR_BYTE_CNT-1:0] byte_mask;
assign byte_mask = 
    (byte_strb_reg == 4'h0) ? 16'b1111_1111_1111_1111 : // 全16字节有效
    (byte_strb_reg == 4'h1) ? 16'b0000_0000_0000_0001 : // 低1字节
    (byte_strb_reg == 4'h2) ? 16'b0000_0000_0000_0011 : // 低2字节
    (byte_strb_reg == 4'h3) ? 16'b0000_0000_0000_0111 : // 低3字节
    (byte_strb_reg == 4'h4) ? 16'b0000_0000_0000_1111 : // 低4字节
    (byte_strb_reg == 4'h5) ? 16'b0000_0000_0001_1111 : // 低5字节
    (byte_strb_reg == 4'h6) ? 16'b0000_0000_0011_1111 : // 低6字节
    (byte_strb_reg == 4'h7) ? 16'b0000_0000_0111_1111 : // 低7字节
    (byte_strb_reg == 4'h8) ? 16'b0000_0000_1111_1111 : // 低8字节
    (byte_strb_reg == 4'h9) ? 16'b0000_0001_1111_1111 : // 低9字节
    (byte_strb_reg == 4'ha) ? 16'b0000_0011_1111_1111 : // 低10字节
    (byte_strb_reg == 4'hb) ? 16'b0000_0111_1111_1111 : // 低11字节
    (byte_strb_reg == 4'hc) ? 16'b0000_1111_1111_1111 : // 低12字节
    (byte_strb_reg == 4'hd) ? 16'b0001_1111_1111_1111 : // 低13字节
    (byte_strb_reg == 4'he) ? 16'b0011_1111_1111_1111 : // 低14字节
    (byte_strb_reg == 4'hf) ? 16'b0111_1111_1111_1111 : // 低15字节
    16'b1111_1111_1111_1111; // 默认全字节

// 状态机逻辑（核心：解析指令→读UR数据→透传参数到axi_stb）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位初始化
        state <= IDLE;
        stb_d_valid <= 1'b0;
        stb_d_done <= 1'b0;
        ur_re <= 1'b0;
        ur_addr <= 11'd0;
        stb2stb_valid <= 1'b0;
        stb2stb_addr <= 32'd0;
        stb2stb_data <= {DATA_WIDTH{1'b0}};
        stb2stb_burst_len <= 8'd0;
        stb2stb_wstrb <= {UR_BYTE_CNT{1'b0}};
        smc_strb_reg <= {SMC_COUNT{1'b0}};
        byte_strb_reg <= 4'd0;
        brst_reg <= 2'd0;
        gr_base_addr_reg <= 32'd0;
        ur_id_reg <= 4'd0;
        ur_addr_reg <= 11'd0;
        current_smc <= 1'b1; // 从SMC0开始处理
        wait_resp_cnt <= 7'd0;
    end else begin
        case (state)
            IDLE:
                begin
                    // 复位控制信号
                    stb_d_valid <= 1'b0;
                    stb_d_done <= 1'b0;
                    ur_re <= 1'b0;
                    stb2stb_valid <= 1'b0;
                    wait_resp_cnt <= 7'd0;
                    
                    // 接收STB指令（stb_u_valid有效）
                    if (stb_u_valid) begin
                        $display("[BURST_STORE] 时间%0t: 接收STB指令，开始解析参数", $time);
                        // 锁存指令参数
                        smc_strb_reg <= stb_u_smc_strb;
                        byte_strb_reg <= stb_u_byte_strb;
                        brst_reg <= stb_u_brst;
                        gr_base_addr_reg <= stb_u_gr_base_addr;
                        ur_id_reg <= stb_u_ur_id;
                        ur_addr_reg <= stb_u_ur_addr;
                        current_smc <= 1'b1; // 初始化SMC0
                        state <= INIT;
                    end
                end
            
            INIT:
                begin
                    // 查找当前使能的SMC（从SMC0到SMC5）
                    if (smc_strb_reg & current_smc) begin
                        $display("[BURST_STORE] 时间%0t: 选中SMC%0d，发起UR读请求", $time, $clog2(current_smc));
                        // 向ur_model发起读请求（获取随机数据）
                        ur_re <= 1'b1;
                        ur_addr <= ur_addr_reg;
                        // 计算burst长度（根据brst_reg编码）
                        case (brst_reg)
                            2'b00: stb2stb_burst_len <= 8'd0;  // 1拍
                            2'b01: stb2stb_burst_len <= 8'd1;  // 2拍
                            2'b10: stb2stb_burst_len <= 8'd3;  // 4拍
                            2'b11: stb2stb_burst_len <= 8'd7;  // 8拍
                        endcase
                        // 计算最终写入地址（基地址 + SMC偏移：SMCn偏移 = n * INTLV_STEP）
                        // 使用case语句根据current_smc的值直接确定SMC索引
                        case (current_smc)
                            6'b000001: stb2stb_addr <= gr_base_addr_reg + 0 * INTLV_STEP; // SMC0
                            6'b000010: stb2stb_addr <= gr_base_addr_reg + 1 * INTLV_STEP; // SMC1
                            6'b000100: stb2stb_addr <= gr_base_addr_reg + 2 * INTLV_STEP; // SMC2
                            6'b001000: stb2stb_addr <= gr_base_addr_reg + 3 * INTLV_STEP; // SMC3
                            6'b010000: stb2stb_addr <= gr_base_addr_reg + 4 * INTLV_STEP; // SMC4
                            6'b100000: stb2stb_addr <= gr_base_addr_reg + 5 * INTLV_STEP; // SMC5
                            default: stb2stb_addr <= gr_base_addr_reg; // 默认地址
                        endcase
                        // 生成字节使能掩码
                        stb2stb_wstrb <= byte_mask;
                        state <= AW_HANDSHAKE;
                    end else if (current_smc < (1 << SMC_COUNT)) begin
                        // 切换到下一个SMC
                        current_smc <= current_smc << 1;
                    end else begin
                        // 所有SMC均未使能，直接完成
                        $display("[BURST_STORE] 时间%0t: 无SMC使能，指令直接完成", $time);
                        state <= DONE;
                    end
                end
            
            AW_HANDSHAKE:
                begin
                    ur_re <= 1'b0; // 停止UR读请求（已获取随机数据）
                    // 关键：透传UR随机数据到stb2stb_data（无任何修改）
                    stb2stb_data <= ur_rdata;
                    // 置位事务包就绪标志，通知axi_stb处理
                    stb2stb_valid <= 1'b1;
                    $display("[BURST_STORE] 时间%0t: 事务包就绪，地址=0x%h，随机数据=0x%h，burst长度=%0d", 
                             $time, stb2stb_addr, stb2stb_data, stb2stb_burst_len + 1);
                    
                    // 等待axi_stb的事务完成反馈（stb2stb_done）
                    if (stb2stb_done) begin
                        stb2stb_valid <= 1'b0; // 清除就绪标志
                        // 检查是否有其他SMC需要处理
                        next_smc = current_smc << 1;
                        if (next_smc < (1 << SMC_COUNT) && (smc_strb_reg & next_smc)) begin
                            current_smc <= next_smc;
                            state <= INIT; // 处理下一个SMC
                        end else begin
                            state <= WAIT_RESP; // 所有SMC处理完成，等待最终反馈
                        end
                    end else begin
                        // 超时保护（增加超时时间以适应多SMC配置和较长的burst长度）
                        // 增加到127个时钟周期（7位计数器的最大值2^7-1），确保多SMC写入场景下有足够时间完成
                        // 注意：在多SMC场景下，即使超时也应该尝试处理下一个SMC，而不是直接进入DONE状态
                        wait_resp_cnt <= wait_resp_cnt + 1;
                        if (wait_resp_cnt >= 7'd127) begin
                            $display("[BURST_STORE] 时间%0t: 等待axi_stb超时，准备处理下一个SMC", $time);
                            stb2stb_valid <= 1'b0;
                            // 检查是否有其他SMC需要处理
                            next_smc = current_smc << 1;
                            if (next_smc < (1 << SMC_COUNT) && (smc_strb_reg & next_smc)) begin
                                current_smc <= next_smc;
                                state <= INIT; // 处理下一个SMC
                                wait_resp_cnt <= 7'd0;
                            end else begin
                                state <= DONE; // 所有SMC处理完成或超时
                            end
                        end
                    end
                end
            
            WAIT_RESP:
                begin
                    // 实际等待所有AXI事务完成
                    if (stb2stb_done) begin
                        $display("[BURST_STORE] 时间%0t: 所有SMC事务完成，准备反馈上层", $time);
                        state <= DONE;
                    end else begin
                        // 继续等待事务完成
                        wait_resp_cnt <= wait_resp_cnt + 1;
                        if (wait_resp_cnt >= 7'd255) begin
                            $display("[BURST_STORE] 时间%0t: 所有SMC事务超时完成，准备反馈上层", $time);
                            state <= DONE;
                        end
                    end
                end
            
            DONE:
                begin
                    // 反馈给上层：指令完成
                    stb_d_valid <= 1'b1;
                    stb_d_done <= 1'b1;
                    $display("[BURST_STORE] 时间%0t: STB指令完全完成，等待上层确认（stb_d_done=1保持）", $time);
                    
                    // 等待上层确认（stb_d_ready为1）
                    if (stb_d_ready) begin
                        stb_d_valid <= 1'b0;
                        stb_d_done <= 1'b0;
                        $display("[BURST_STORE] 时间%0t: 上层确认收到完成信号", $time);
                        state <= IDLE; // 回到空闲状态，等待下一条指令
                    end else begin
                        // 保持stb_d_done=1，直到收到上层确认
                        stb_d_valid <= 1'b1;
                        stb_d_done <= 1'b1;
                    end
                end
        endcase
    end
end
endmodule
    