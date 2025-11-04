//---------------------------------------------------------------------
// Filename: ldb.v
// Author: cypher、hamid
// Date: 2025-11-4
// Version: 1.3
// Description: This is a module that supports burst data transfer initiation, selective byte masking, and interleaved address calculation for SMC.
//---------------------------------------------------------------------

`timescale 1ns/1ps

`default_nettype none

module ldb #(
    parameter param_ur_byte_cnt = 16,
    parameter param_gr_intlv_addr = 32,
    parameter param_smc_cnt = 64,
    parameter ur_addr_w = 11,
    parameter gr_addr_w = 64,
    parameter brst_w = 16
)(
    input wire clk,
    input wire rst_n,
    
    // 指令输入接口
    input wire [127:0] cru_ldb_i,
    input wire [1:0] crd_ldb_i,
    
    // AXI读取控制接口
    output reg axi_req_valid,
    input wire axi_req_ready,
    output reg [gr_addr_w-1:0] axi_req_addr,
    output reg [8:0] axi_req_len,
    input wire axi_req_done,
    input wire axi_req_err,
    
    // AXI数据输入接口
    input wire axi_data_valid,
    input wire [127:0] axi_data,
    input wire axi_data_last,
    
    // UR接口
    output reg ur_we,
    output reg [5:0] smc_index, // SMC索引输出
    output reg [ur_addr_w-1:0] ur_addr,
    output reg [param_ur_byte_cnt*8-1:0] ur_wdata,
    
    // 响应输出接口
    output wire [127:0] cru_ldb_o,
    output reg [1:0] crd_ldb_o
);

// 常量定义
localparam ur_data_width = param_ur_byte_cnt * 8;
localparam BYTE_PER_BEAT = 16;
localparam MAX_SMC_COUNT = 64;

// 状态定义
typedef enum logic [3:0] {
    IDLE,
    PARSE,
    PROCESS_SMC,
    WAIT_AXI,
    DATA,
    NEXT_SMC,
    DONE
} state_t;

// 寄存器声明
state_t state_q;
reg [brst_w-1:0] burst_cnt_q;
reg [gr_addr_w-1:0] byte_addr_q;
reg [ur_addr_w-1:0] ur_addr_q;
reg [3:0] byte_strb_q;
reg [5:0] smc_strb_q;
reg [7:0] ur_id_q;
reg is_last_beat;

// SMC处理相关寄存器
reg [5:0] current_smc_idx_q;
reg [5:0] num_smc_q; // 要使能的SMC数量
reg processing_smc_q;

// 新增：原始值寄存器
reg [brst_w-1:0] original_burst_cnt_q;
reg [ur_addr_w-1:0] original_ur_addr_q;

// 组合逻辑变量
state_t state_d;
reg [brst_w-1:0] burst_cnt_d;
reg [gr_addr_w-1:0] byte_addr_d;
reg [ur_addr_w-1:0] ur_addr_d;
reg [3:0] byte_strb_d;
reg [5:0] smc_strb_d;
reg [7:0] ur_id_d;
reg is_last_beat_d;
reg ur_we_d;
reg [ur_data_width-1:0] ur_wdata_d;
reg axi_req_valid_d;
reg [gr_addr_w-1:0] axi_req_addr_d;
reg [8:0] axi_req_len_d;
reg [1:0] crd_ldb_o_d;

// SMC处理相关组合逻辑变量
reg [5:0] current_smc_idx_d;
reg [5:0] num_smc_d;
reg processing_smc_d;

// 新增：原始值组合逻辑变量
reg [brst_w-1:0] original_burst_cnt_d;
reg [ur_addr_w-1:0] original_ur_addr_d;

// 字节使能掩码查找表
function [15:0] get_byte_mask;
    input [3:0] byte_strb;
    begin
        case (byte_strb)
            4'h0: get_byte_mask = 16'hFFFF;
            4'h1: get_byte_mask = 16'h0001;
            4'h2: get_byte_mask = 16'h0003;
            4'h3: get_byte_mask = 16'h0007;
            4'h4: get_byte_mask = 16'h000F;
            4'h5: get_byte_mask = 16'h001F;
            4'h6: get_byte_mask = 16'h003F;
            4'h7: get_byte_mask = 16'h007F;
            4'h8: get_byte_mask = 16'h00FF;
            4'h9: get_byte_mask = 16'h01FF;
            4'hA: get_byte_mask = 16'h03FF;
            4'hB: get_byte_mask = 16'h07FF;
            4'hC: get_byte_mask = 16'h0FFF;
            4'hD: get_byte_mask = 16'h1FFF;
            4'hE: get_byte_mask = 16'h3FFF;
            4'hF: get_byte_mask = 16'h7FFF;
            default: get_byte_mask = 16'hFFFF; 
        endcase
    end
endfunction

// 状态到字符串的转换函数
function string state2str(input state_t s);
    case (s)
        IDLE: state2str = "IDLE";
        PARSE: state2str = "PARSE";
        PROCESS_SMC: state2str = "PROCESS_SMC";
        WAIT_AXI: state2str = "WAIT_AXI";
        DATA: state2str = "DATA";
        NEXT_SMC: state2str = "NEXT_SMC";
        DONE: state2str = "DONE";
        default: state2str = "UNKNOWN";
    endcase
endfunction

// 组合逻辑
always @* begin
    // 默认值
    state_d = state_q;
    burst_cnt_d = burst_cnt_q;
    byte_addr_d = byte_addr_q;
    ur_addr_d = ur_addr_q;
    byte_strb_d = byte_strb_q;
    smc_strb_d = smc_strb_q;
    ur_id_d = ur_id_q;
    is_last_beat_d = is_last_beat;
    ur_we_d = 1'b0;
    ur_wdata_d = '0;
    axi_req_valid_d = 1'b0;
    axi_req_addr_d = byte_addr_q;
    axi_req_len_d = burst_cnt_q;
    crd_ldb_o_d = 2'b00;
    
    // SMC处理相关信号的默认值
    current_smc_idx_d = current_smc_idx_q;
    num_smc_d = num_smc_q;
    processing_smc_d = processing_smc_q;
    
    // 新增：原始值默认值
    original_burst_cnt_d = original_burst_cnt_q;
    original_ur_addr_d = original_ur_addr_q;
    
    case (state_q)
        IDLE: begin
            if (cru_ldb_i[127]) begin
                // 接收到指令包，转移到解析状态
                state_d = PARSE;
            end
        end
        
        PARSE: begin
            // 解析指令包
            original_burst_cnt_d = cru_ldb_i[116:101];  // 保存原始burst长度
            original_ur_addr_d = cru_ldb_i[28:18];      // 保存原始UR地址
            burst_cnt_d = cru_ldb_i[116:101];           // 当前burst长度
            byte_strb_d = cru_ldb_i[120:117];
            smc_strb_d = cru_ldb_i[126:121];
            ur_id_d = cru_ldb_i[36:29];
            ur_addr_d = cru_ldb_i[28:18];
            
            // 计算要使能的SMC数量: N = smc_strb + 1
            num_smc_d = smc_strb_d + 1;
            current_smc_idx_d = 0; // 从SMC0开始
            processing_smc_d = 1'b0;
            state_d = PROCESS_SMC;
        end
        
        PROCESS_SMC: begin
            // 重置burst计数和UR地址为原始值
            burst_cnt_d = original_burst_cnt_q;
            ur_addr_d = original_ur_addr_q;
            
            // 计算当前SMC的基地址
            byte_addr_d = {cru_ldb_i[100:37] + (current_smc_idx_q * param_gr_intlv_addr), 4'b0};
            
            $display("[LDB_SMC_ADDR] time=%0t: 处理SMC%d, 基地址=%h", 
                        $time, current_smc_idx_q, byte_addr_d);

            // 设置is_last_beat
            if (burst_cnt_d == 0) begin
                is_last_beat_d = 1'b1;
            end else begin
                is_last_beat_d = (burst_cnt_d == 1);
            end
            
            // 发起AXI读取请求
            axi_req_valid_d = 1'b1;
            axi_req_addr_d = byte_addr_d;
            axi_req_len_d = burst_cnt_d; // 使用原始burst长度
            state_d = WAIT_AXI;
        end
        
        WAIT_AXI: begin
            if (axi_req_ready) begin
                // AXI请求被接受，转移到数据处理状态
                state_d = DATA;
            end else begin
                // 继续等待
                axi_req_valid_d = 1'b1;
                state_d = WAIT_AXI;
            end
        end
        
        DATA: begin
            if (axi_data_valid) begin
                // 处理接收到的数据
                if (is_last_beat) begin
                    // 应用字节掩码
                    automatic logic [15:0] byte_mask = get_byte_mask(byte_strb_q);
                    for (int b = 0; b < 16; b = b + 1) begin
                        if (byte_mask[b]) begin
                            ur_wdata_d[b*8 +: 8] = axi_data[b*8 +: 8];
                        end
                    end
                end else begin
                    // 全字节写入
                    ur_wdata_d = axi_data;
                end

                // 生成写使能 - 针对当前SMC
                ur_we_d = 1'b1;

                // 更新计数和地址
                burst_cnt_d = burst_cnt_q - 1'b1;
                byte_addr_d = byte_addr_q + BYTE_PER_BEAT;
                ur_addr_d = ur_addr_q + 1;
                is_last_beat_d = (burst_cnt_d == 1);

                // 检查是否完成当前SMC的所有burst
                if (burst_cnt_d == 0) begin
                    state_d = NEXT_SMC; // 所有burst完成，处理下一个SMC
                end else begin
                    state_d = DATA; // 继续接收数据
                end
            end else begin
                // 没有数据时保持状态，等待有效数据
                state_d = DATA;
            end
        end
                
        NEXT_SMC: begin
            // 增加当前SMC索引
            current_smc_idx_d = current_smc_idx_q + 1;
            
            // 调试信息：在组合逻辑中打印当前值
            $display("[LDB_NEXT_SMC] time=%0t: current_smc_idx_d=%d, num_smc_q=%d", 
                $time, current_smc_idx_d, num_smc_q);
            
            // 检查是否还有更多SMC需要处理
            if (current_smc_idx_d < num_smc_q) begin
                // 处理下一个SMC
                state_d = PROCESS_SMC;
            end else begin
                // 所有SMC处理完成
                state_d = DONE;
            end
        end
        
        DONE: begin
            // 在DONE状态，输出完成信号 {vld=1, done=1}
            crd_ldb_o_d = 2'b11;
            
            // 等待一个周期，确保完成信号被检测到
            // 然后返回IDLE状态
            state_d = IDLE;
            
            // 清除内部状态
            burst_cnt_d = 0;
            axi_req_valid_d = 1'b0;
            processing_smc_d = 1'b0;
            
            // 如果AXI传输出错，打印错误信息
            if (axi_req_err) begin
                $display("[LDB_ERROR] time=%0t: AXI传输错误", $time);
            end
        end
        
        default: begin
            state_d = IDLE;
        end
    endcase
end

// 时序逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_q <= IDLE;
        burst_cnt_q <= '0;
        byte_addr_q <= '0;
        ur_addr_q <= '0;
        byte_strb_q <= '0;
        smc_strb_q <= '0;
        ur_id_q <= '0;
        is_last_beat <= 1'b0;
        ur_we <= '0;
        smc_index <= '0;
        ur_addr <= '0;
        ur_wdata <= '0;
        axi_req_valid <= 1'b0;
        axi_req_addr <= '0;
        axi_req_len <= '0;
        crd_ldb_o <= 2'b00;
        
        // SMC处理相关寄存器复位
        current_smc_idx_q <= '0;
        num_smc_q <= '0;
        processing_smc_q <= 1'b0;
        
        // 新增：原始值寄存器复位
        original_burst_cnt_q <= '0;
        original_ur_addr_q <= '0;
    end else begin
        state_q <= state_d;
        burst_cnt_q <= burst_cnt_d;
        byte_addr_q <= byte_addr_d;
        ur_addr_q <= ur_addr_d;
        byte_strb_q <= byte_strb_d;
        smc_strb_q <= smc_strb_d;
        ur_id_q <= ur_id_d;
        is_last_beat <= is_last_beat_d;
        ur_we <= ur_we_d;
        smc_index <= current_smc_idx_q; // 输出当前SMC索引
        ur_addr <= ur_addr_d;
        ur_wdata <= ur_wdata_d;
        axi_req_valid <= axi_req_valid_d;
        axi_req_addr <= axi_req_addr_d;
        axi_req_len <= axi_req_len_d;
        crd_ldb_o <= crd_ldb_o_d;
        
        // 更新SMC处理相关寄存器
        current_smc_idx_q <= current_smc_idx_d;
        num_smc_q <= num_smc_d;
        processing_smc_q <= processing_smc_d;
        
        // 新增：更新原始值寄存器
        original_burst_cnt_q <= original_burst_cnt_d;
        original_ur_addr_q <= original_ur_addr_d;
    end
end

// 直通输出
assign cru_ldb_o = cru_ldb_i;

// 调试信息
always @(posedge clk) begin
    // 监控指令包接收
    if (cru_ldb_i[127] && state_q == IDLE) begin
        $display("[LDB_DEBUG] time=%0t: 在IDLE状态接收到指令包", $time);
    end
    
    // 监控状态转换
    if (state_q != state_d) begin
        $display("[LDB_STATE_CHANGE] time=%0t: %s -> %s",
                 $time, state2str(state_q), state2str(state_d));
    end
    
    // 监控AXI请求
    if (axi_req_valid_d) begin
        $display("[LDB_AXI_REQ] time=%0t: 发起AXI请求: addr=%h, len=%d",
                 $time, axi_req_addr_d, axi_req_len_d);
    end
    
    // 监控AXI数据接收
    if (axi_data_valid) begin
        $display("[LDB_DATA_RCV] time=%0t: 接收到AXI数据: data=%h, last=%b",
                 $time, axi_data, axi_data_last);
    end
    
    // 监控UR写入
    if (ur_we_d) begin
        $display("[LDB_UR_WRITE] time=%0t: 写入SMC%d的UR: addr=%h, data=%h",
                 $time, current_smc_idx_q, ur_addr_d, ur_wdata_d);
    end
    
    // 监控burst计数
    if (burst_cnt_q != burst_cnt_d) begin
        $display("[LDB_BURST_CNT] time=%0t: burst_cnt %d -> %d",
                 $time, burst_cnt_q, burst_cnt_d);
    end
    
    // 监控SMC处理进度
    if (current_smc_idx_q != current_smc_idx_d) begin
        $display("[LDB_SMC_PROGRESS] time=%0t: 处理SMC%d -> SMC%d",
                 $time, current_smc_idx_q, current_smc_idx_d);
    end
    
    // 监控SMC数量
    if (num_smc_q != num_smc_d) begin
        $display("[LDB_SMC_COUNT] time=%0t: num_smc %d -> %d",
                 $time, num_smc_q, num_smc_d);
    end
    
    // 监控原始burst长度
    if (original_burst_cnt_q != original_burst_cnt_d) begin
        $display("[LDB_ORIG_BURST] time=%0t: orig_burst_cnt %d -> %d",
                 $time, original_burst_cnt_q, original_burst_cnt_d);
    end
end

endmodule