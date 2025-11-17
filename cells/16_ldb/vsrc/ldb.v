`timescale 1ns/1ps
`default_nettype none

`include "DW_axi_gm_cc_constants.vh"
`include "DW_axi_gm_constants.vh"

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
    
    // GIF接口（连接到DW_axi_gm）
    // GIF请求
    output reg [`GM_ID-1:0] mid,
    output reg [`GM_AW-1:0] maddr,
    output reg mread,
    output reg mwrite,
    output reg [`GM_BW-1:0] mlen,
    output reg [2:0] msize,
    output reg [1:0] mburst,
    output reg [3:0] mcache,
    output reg [2:0] mprot,
    output reg [`GM_DW-1:0] mdata,
    output reg [`GM_WW-1:0] mwstrb,
    input  wire saccept,
    
    // GIF响应
    input  wire [`GM_ID-1:0] sid,
    input  wire svalid,
    input  wire slast,
    input  wire [`GM_DW-1:0] sdata,
    input  wire [2:0] sresp,
    output reg mready,
    
    // UR接口
    output reg ur_we,
    output reg [5:0] smc_index,
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
        WAIT_GIF_ACCEPT,
        WAIT_DATA,
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
    reg [5:0] num_smc_q;
    reg processing_smc_q;

    // 原始值寄存器
    reg [brst_w-1:0] original_burst_cnt_q;
    reg [ur_addr_w-1:0] original_ur_addr_q;
    reg [gr_addr_w-1:0] gr_base_addr_q;  // 锁存的全局寄存器基地址

    // GIF请求控制寄存器
    reg gif_req_active_q;
    reg gif_data_receiving_q;

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
    reg [1:0] crd_ldb_o_d;

    // SMC处理相关组合逻辑变量
    reg [5:0] current_smc_idx_d;
    reg [5:0] num_smc_d;
    reg processing_smc_d;

    // 原始值组合逻辑变量
    reg [brst_w-1:0] original_burst_cnt_d;
    reg [ur_addr_w-1:0] original_ur_addr_d;
    reg [gr_addr_w-1:0] gr_base_addr_d;

    // GIF控制组合逻辑变量
    reg gif_req_active_d;
    reg gif_data_receiving_d;

    // GIF输出信号组合逻辑
    reg [`GM_ID-1:0] mid_d;
    reg [`GM_AW-1:0] maddr_d;
    reg mread_d;
    reg mwrite_d;
    reg [`GM_BW-1:0] mlen_d;
    reg [2:0] msize_d;
    reg [1:0] mburst_d;
    reg [3:0] mcache_d;
    reg [2:0] mprot_d;
    reg [`GM_DW-1:0] mdata_d;
    reg [`GM_WW-1:0] mwstrb_d;
    reg mready_d;

    // 字节使能掩码查找表（与测试文件保持一致）
    function [15:0] get_byte_mask;
        input [3:0] byte_strb;
        begin
            case (byte_strb)
                4'h0: get_byte_mask = 16'hFFFF;  // 全字节有效
                4'h1: get_byte_mask = 16'h0001;  // 仅字节0有效
                4'h2: get_byte_mask = 16'h0003;  // 字节0-1有效
                4'h3: get_byte_mask = 16'h0007;  // 字节0-2有效
                4'h4: get_byte_mask = 16'h000F;  // 字节0-3有效
                4'h5: get_byte_mask = 16'h001F;  // 字节0-4有效
                4'h6: get_byte_mask = 16'h003F;  // 字节0-5有效
                4'h7: get_byte_mask = 16'h007F;  // 字节0-6有效
                4'h8: get_byte_mask = 16'h00FF;  // 字节0-7有效
                4'h9: get_byte_mask = 16'h01FF;  // 字节0-8有效
                4'hA: get_byte_mask = 16'h03FF;  // 字节0-9有效
                4'hB: get_byte_mask = 16'h07FF;  // 字节0-10有效
                4'hC: get_byte_mask = 16'h0FFF;  // 字节0-11有效
                4'hD: get_byte_mask = 16'h1FFF;  // 字节0-12有效
                4'hE: get_byte_mask = 16'h3FFF;  // 字节0-13有效
                4'hF: get_byte_mask = 16'h7FFF;  // 字节0-14有效
                //default: get_byte_mask = 16'hFFFF;  // 所有字节有效
            endcase
        end
    endfunction

/*    // GIF响应解码函数
    function string gif_resp2str(input [2:0] resp);
        case (resp)
            3'b000: gif_resp2str = "OKAY";
            3'b001: gif_resp2str = "EXOKAY"; 
            3'b010: gif_resp2str = "SLVERR";
            3'b011: gif_resp2str = "DECERR";
            3'b100: gif_resp2str = "PROT_ERROR";
            3'b101: gif_resp2str = "RESERVED5";
            3'b110: gif_resp2str = "RESERVED6";
            3'b111: gif_resp2str = "RESERVED7";
            default: gif_resp2str = "UNKNOWN";
        endcase
    endfunction
*/
/*    // 状态到字符串的转换函数
    function string state2str(input state_t s);
        case (s)
            IDLE: state2str = "IDLE";
            PARSE: state2str = "PARSE";
            PROCESS_SMC: state2str = "PROCESS_SMC";
            WAIT_GIF_ACCEPT: state2str = "WAIT_GIF_ACCEPT";
            WAIT_DATA: state2str = "WAIT_DATA";
            DATA: state2str = "DATA";
            NEXT_SMC: state2str = "NEXT_SMC";
            DONE: state2str = "DONE";
            default: state2str = "UNKNOWN";
        endcase
    endfunction
*/
    task automatic handle_data_beat(input bit first_word);
        logic [brst_w-1:0] next_burst_cnt;
        logic [15:0] byte_mask;
        logic [ur_addr_w-1:0] current_beat_index;
        begin
            if (first_word) begin
                $display("[LDB] 开始接收GIF数据");
            end

            if (sresp != 3'b000) begin
                //$display("[DATA_ERROR] 响应错误: %s，跳过当前SMC", gif_resp2str(sresp));
                burst_cnt_d = '0;
                gif_data_receiving_d = 1'b0;
                state_d = NEXT_SMC;
                ur_we_d = 1'b0;
            end else begin
                // 计算下一个burst计数
                next_burst_cnt = (burst_cnt_q == 0) ? '0 : (burst_cnt_q - 1'b1);
                
                // 计算当前beat索引
                current_beat_index = original_burst_cnt_q - burst_cnt_q;
                
                // 对于单个beat的情况，始终应用字节掩码
                if (burst_cnt_q <= 1) begin
                    byte_mask = get_byte_mask(byte_strb_q);
                    ur_wdata_d = '0;
                    for (int b = 0; b < 16; b = b + 1) begin
                        if (byte_mask[b]) begin
                            ur_wdata_d[b*8 +: 8] = sdata[b*8 +: 8];
                        end else begin
                            ur_wdata_d[b*8 +: 8] = 8'h00;
                        end
                    end
                    $display("[LDB_DATA] 最后一个beat或单beat，应用字节掩码: mask=%h, data_before_mask=%h, data_after_mask=%h",
                        byte_mask, sdata, ur_wdata_d);
                end else begin
                    ur_wdata_d = sdata;
                    $display("[LDB_DATA] 非最后一个beat，全字节写入: data=%h", sdata);
                end

                ur_we_d = 1'b1;
                // 使用原始UR地址加上beat索引作为当前UR地址（先写入后递增）
                ur_addr_d = original_ur_addr_q + current_beat_index;
                
                $display("[LDB_DATA] 接收数据: SMC%d, UR地址=%h (原始=%h + beat索引=%h), burst剩余=%d, data=%h",
                    current_smc_idx_q, ur_addr_d, original_ur_addr_q, current_beat_index, burst_cnt_q, ur_wdata_d);

                burst_cnt_d = next_burst_cnt;

                $display("[DATA_UPDATE] burst_cnt %d -> %d, ur_addr %h -> %h", 
                    burst_cnt_q, burst_cnt_d, ur_addr_q, ur_addr_d);

                if (next_burst_cnt == 0) begin
                    $display("[DATA_COMPLETE] Burst完成，转移到NEXT_SMC");
                    gif_data_receiving_d = 1'b0;
                    state_d = NEXT_SMC;
                end else begin
                    $display("[DATA_CONTINUE] 继续等待下一个数据");
                    gif_data_receiving_d = 1'b1;
                    state_d = DATA;
                end
            end
        end
    endtask

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
        crd_ldb_o_d = 2'b00;

        // SMC处理相关信号的默认值
        current_smc_idx_d = current_smc_idx_q;
        num_smc_d = num_smc_q;
        processing_smc_d = processing_smc_q;

        // 原始值默认值
        original_burst_cnt_d = original_burst_cnt_q;
        original_ur_addr_d = original_ur_addr_q;
        gr_base_addr_d = gr_base_addr_q;

        // GIF控制默认值
        gif_req_active_d = gif_req_active_q;
        gif_data_receiving_d = gif_data_receiving_q;

        // GIF输出信号默认值
        mid_d = mid;
        maddr_d = maddr;
        mread_d = 1'b0;
        mwrite_d = 1'b0;
        mlen_d = mlen;
        msize_d = msize;
        mburst_d = mburst;
        mcache_d = mcache;
        mprot_d = mprot;
        mdata_d = mdata;
        mwstrb_d = mwstrb;
        mready_d = 1'b1;  // 默认准备好接收数据

        case (state_q)
            IDLE: begin
                if (cru_ldb_i[127]) begin
                    // 接收到指令包，转移到解析状态
                    state_d = PARSE;
                    $display("[LDB] 接收到新指令包，开始解析");
                end
            end

            PARSE: begin
                // 解析指令包
                original_burst_cnt_d = cru_ldb_i[116:101]; // 保存原始burst长度
                original_ur_addr_d = cru_ldb_i[28:18];     // 保存原始UR地址
                gr_base_addr_d = cru_ldb_i[100:37];        // 锁存全局寄存器基地址
                burst_cnt_d = cru_ldb_i[116:101];          // 当前burst长度
                byte_strb_d = cru_ldb_i[120:117];
                smc_strb_d = cru_ldb_i[126:121];
                ur_id_d = cru_ldb_i[36:29];
                ur_addr_d = cru_ldb_i[28:18];

                // 计算要使能的SMC数量: N = smc_strb + 1
                num_smc_d = smc_strb_d + 1;
                current_smc_idx_d = 0; // 从SMC0开始
                processing_smc_d = 1'b0;

                $display("[LDB_PARSE] 解析完成: brst=%d, byte_strb=%h, smc_strb=%b, ur_id=%d, num_smc=%d",
                    burst_cnt_d, byte_strb_d, smc_strb_d, ur_id_d, num_smc_d);

                state_d = PROCESS_SMC;
            end

            PROCESS_SMC: begin
                // 重置burst计数和UR地址为原始值
                burst_cnt_d = original_burst_cnt_q;
                ur_addr_d = original_ur_addr_q;  // 每个SMC都从原始UR地址开始

                // 计算地址（与测试文件保持一致）
                byte_addr_d = gr_base_addr_q + (current_smc_idx_q * 32) + (0 * 16);  // 初始beat索引为0
                // 确保地址对齐到16字节边界
                byte_addr_d = byte_addr_d & (~15);

                $display("[LDB_SMC_ADDR_DETAIL] 处理SMC%d:", current_smc_idx_q);
                $display("  gr_base_addr = %h", gr_base_addr_q);
                $display("  interlv_offset = %d * %d = %d",
                    current_smc_idx_q, param_gr_intlv_addr,
                    current_smc_idx_q * param_gr_intlv_addr);
                $display("  final_addr = %h", byte_addr_d);
                $display("  burst长度 = %d", burst_cnt_d);

                // 设置GIF请求信号
                mid_d = current_smc_idx_q[`GM_ID-1:0];  // 使用SMC索引作为ID
                maddr_d = byte_addr_d;
                mlen_d = original_burst_cnt_q - 1'b1;  // GIF的mlen是实际长度-1
                msize_d = 3'b100;          // 128位 = 16字节，2^4=16
                mburst_d = 2'b01;          // INCR模式
                mcache_d = 4'b0;           // 默认值
                mprot_d = 3'b0;            // 默认值
                mread_d = 1'b1;            // 读请求
                mwrite_d = 1'b0;           // 不写
                mdata_d = '0;              // 读操作，数据为0
                mwstrb_d = '0;             // 读操作，写选通为0

                // 设置is_last_beat
                is_last_beat_d = (burst_cnt_d == 1);

                gif_req_active_d = 1'b1;

                $display("[LDB_GIF_REQ] 发起GIF请求: SMC%d, addr=%h, len=%d",
                    current_smc_idx_q, maddr_d, mlen_d);

                state_d = WAIT_GIF_ACCEPT;
            end

            WAIT_GIF_ACCEPT: begin
                // 维持GIF请求
                mread_d = 1'b1;
                maddr_d = byte_addr_q;
                mlen_d = burst_cnt_q - 1;  // 确保burst_cnt_q为0时不会产生负数值

                if (saccept) begin
                    // GIF请求被接受，转移到等待数据状态
                    mread_d = 1'b0;  // 清除读请求
                    gif_req_active_d = 1'b0;
                    gif_data_receiving_d = 1'b1;
                    state_d = WAIT_DATA;
                    $display("[LDB] GIF请求被接受，等待数据传输");
                end
            end

            WAIT_DATA: begin
                // 准备接收数据
                mready_d = 1'b1;

                if (svalid) begin
                    handle_data_beat(1'b1);
                end else begin
                    state_d = WAIT_DATA;
                    $display("[LDB_WAIT_DATA] 等待数据，svalid=%b", svalid);
                end
            end

            DATA: begin
                // 准备接收数据
                mready_d = 1'b1;
                $display("[DATA_STATE_DEBUG] burst_cnt=%d, svalid=%b, sresp=%h",
                        burst_cnt_q, svalid, sresp);
                
                if (svalid) begin
                    // 计算当前UR地址：原始地址 + (总长度 - 剩余长度)
                    automatic logic [ur_addr_w-1:0] current_addr = 
                        original_ur_addr_q + (original_burst_cnt_q - burst_cnt_q);
                    
                    // 局部变量声明
                    reg [brst_w-1:0] next_burst_cnt;
                    reg [15:0] byte_mask;
                    
                    ur_addr_d = current_addr;
                    
                    next_burst_cnt = burst_cnt_q - 1'b1;
                        
                        // 对于单个beat的情况，始终应用字节掩码
                        if (burst_cnt_q <= 1) begin
                            byte_mask = get_byte_mask(byte_strb_q);
                            ur_wdata_d = '0;
                            for (int b = 0; b < 16; b = b + 1) begin
                                if (byte_mask[b]) begin
                                    ur_wdata_d[b*8 +: 8] = sdata[b*8 +: 8];
                                end else begin
                                    ur_wdata_d[b*8 +: 8] = 8'h00;
                                end
                            end
                            $display("[LDB_DATA] 最后一个beat或单beat，应用字节掩码: mask=%h, data_before_mask=%h, data_after_mask=%h",
                                    byte_mask, sdata, ur_wdata_d);
                        end else begin
                            ur_wdata_d = sdata;
                            $display("[LDB_DATA] 非最后一个beat，全字节写入: data=%h", sdata);
                        end
                        
                        ur_we_d = 1'b1;
                        
                        $display("[LDB_DATA] 接收数据: SMC%d, UR地址=%h (原始=%h + beat索引=%h), burst剩余=%d, data=%h",
                                current_smc_idx_q, current_addr, original_ur_addr_q, 
                                (original_burst_cnt_q - burst_cnt_q), burst_cnt_q, ur_wdata_d);
                        
                        burst_cnt_d = next_burst_cnt;
                        
                        $display("[DATA_UPDATE] burst_cnt %d -> %d, ur_addr %h -> %h",
                                burst_cnt_q, burst_cnt_d, ur_addr_q, ur_addr_d);
                        
                        if (next_burst_cnt == 0) begin
                            $display("[DATA_COMPLETE] Burst完成，转移到NEXT_SMC");
                            gif_data_receiving_d = 1'b0;
                            state_d = NEXT_SMC;
                        end else begin
                            $display("[DATA_CONTINUE] 继续等待下一个数据");
                            gif_data_receiving_d = 1'b1;
                            state_d = DATA;
                        end
                end
            end

            NEXT_SMC: begin
                // 增加当前SMC索引
                current_smc_idx_d = current_smc_idx_q + 1;
                $display("[LDB_NEXT_SMC] 处理下一个SMC: current_smc_idx=%d, num_smc=%d",
                    current_smc_idx_d, num_smc_q);

                // 检查是否还有更多SMC需要处理
                if (current_smc_idx_d < num_smc_q) begin
                    // 处理下一个SMC
                    state_d = PROCESS_SMC;
                    $display("[LDB_NEXT_SMC] 跳转到PROCESS_SMC处理下一个SMC");
                end else begin
                    // 所有SMC处理完成
                    state_d = DONE;
                    $display("[LDB] 所有SMC处理完成");
                end
            end

            DONE: begin
                // 输出完成信号 {vld=1, done=1}
                crd_ldb_o_d = 2'b11;
                $display("[LDB_DONE] 指令执行完成，输出响应信号");

                // 清除内部状态
                burst_cnt_d = 0;
                current_smc_idx_d = 0;  // 确保SMC索引被重置
                num_smc_d = 0;
                processing_smc_d = 1'b0;
                gif_req_active_d = 1'b0;
                gif_data_receiving_d = 1'b0;
                
                // 等待一个周期，确保完成信号被检测到
                // 然后返回IDLE状态
                state_d = IDLE;
                
                $display("[LDB_DONE] 返回IDLE状态，所有内部状态已清除");
            end

            default: begin
                state_d = IDLE;
                $display("[LDB_WARNING] 进入未知状态，返回IDLE");
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
            crd_ldb_o <= 2'b00;

            // SMC处理相关寄存器复位
            current_smc_idx_q <= '0;
            num_smc_q <= '0;
            processing_smc_q <= 1'b0;

            // 原始值寄存器复位
            original_burst_cnt_q <= '0;
            original_ur_addr_q <= '0;
            gr_base_addr_q <= '0;

            // GIF控制寄存器复位
            gif_req_active_q <= 1'b0;
            gif_data_receiving_q <= 1'b0;

            // GIF输出信号复位
            mid <= '0;
            maddr <= '0;
            mread <= 1'b0;
            mwrite <= 1'b0;
            mlen <= '0;
            msize <= '0;
            mburst <= '0;
            mcache <= '0;
            mprot <= '0;
            mdata <= '0;
            mwstrb <= '0;
            mready <= 1'b1;
            
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
            smc_index <= current_smc_idx_d;  // 使用更新后的SMC索引，确保与当前处理的SMC匹配
            ur_addr <= ur_addr_d;
            ur_wdata <= ur_wdata_d;
            crd_ldb_o <= crd_ldb_o_d;

            // 更新SMC处理相关寄存器
            current_smc_idx_q <= current_smc_idx_d;
            num_smc_q <= num_smc_d;
            processing_smc_q <= processing_smc_d;

            // 更新原始值寄存器
            original_burst_cnt_q <= original_burst_cnt_d;
            original_ur_addr_q <= original_ur_addr_d;
            gr_base_addr_q <= gr_base_addr_d;

            // 更新GIF控制寄存器
            gif_req_active_q <= gif_req_active_d;
            gif_data_receiving_q <= gif_data_receiving_d;

            // 更新GIF输出信号
            mid <= mid_d;
            maddr <= maddr_d;
            mread <= mread_d;
            mwrite <= mwrite_d;
            mlen <= mlen_d;
            msize <= msize_d;
            mburst <= mburst_d;
            mcache <= mcache_d;
            mprot <= mprot_d;
            mdata <= mdata_d;
            mwstrb <= mwstrb_d;
            mready <= mready_d;
        end
    end

    // 直通输出
    assign cru_ldb_o = cru_ldb_i;

    // 调试信息
    always @(posedge clk) begin
        // 监控指令包接收
        if (cru_ldb_i[127]) begin
            $display("[LDB_DEBUG] 在IDLE状态接收到指令包");
        end

        // 监控状态转换
 //       if (state_q != state_d) begin
 //           $display("[LDB_STATE_CHANGE] %s -> %s", state2str(state_q), state2str(state_d));
  //      end

        // 监控GIF请求
        if (mread_d) begin
            $display("[LDB_GIF_REQ] 发起GIF读请求: addr=%h, len=%d", maddr_d, mlen_d);
        end

        // 监控GIF数据接收
//        if (svalid) begin
//            $display("[LDB_DATA_RCV] 接收到GIF数据: data=%h, last=%b, resp=%s", 
 //               sdata, slast, gif_resp2str(sresp));
 //       end

        // 监控UR写入
        if (ur_we_d && !ur_we) begin
            $display("[LDB_UR_WRITE] 写入SMC%d的UR: addr=%h, data=%h",
                current_smc_idx_q, ur_addr_d, ur_wdata_d);
        end

        // 监控burst计数
        if (burst_cnt_q != burst_cnt_d) begin
            $display("[LDB_BURST_CNT] burst_cnt %d -> %d", burst_cnt_q, burst_cnt_d);
        end

        // 监控SMC处理进度
        if (current_smc_idx_q != current_smc_idx_d) begin
            $display("[LDB_SMC_PROGRESS] 处理SMC%d -> SMC%d", current_smc_idx_q, current_smc_idx_d);
        end

        // 监控GIF接受
        if (state_q == WAIT_GIF_ACCEPT) begin
            $display("[LDB_GIF_ACCEPT] GIF请求被接受");
        end

        // 监控错误响应
//        if (svalid && sresp != 3'b000) begin
//            $display("[LDB_ERROR] GIF响应错误: resp=%s (%h)", gif_resp2str(sresp), sresp);
  //      end
    end

endmodule