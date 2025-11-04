`timescale 1ns/1ps
`default_nettype none

module axi_protocol_checker #(
    parameter AXI_ADDR_W = 64,
    parameter AXI_DATA_W = 128,
    parameter AXI_ID_W = 4,
    parameter TIMEOUT_CYCLES = 100
)(
    input wire clk,
    input wire rst_n,
    
    // AXI 读地址通道
    input wire arvalid,
    input wire arready,
    input wire [AXI_ADDR_W-1:0] araddr,
    input wire [7:0] arlen,
    input wire [2:0] arsize,
    input wire [1:0] arburst,
    input wire [AXI_ID_W-1:0] arid,
    
    // AXI 读数据通道
    input wire rvalid,
    input wire rready,
    input wire [AXI_DATA_W-1:0] rdata,
    input wire rlast,
    input wire [1:0] rresp,
    input wire [AXI_ID_W-1:0] rid,
    
    // 错误输出
    output reg [3:0] error_code,
    output reg [AXI_ID_W-1:0] error_id
);

    // 错误代码定义
    typedef enum logic [3:0] {
        NO_ERROR,
        ARVALID_STUCK,      // ARVALID持续有效未握手
        RVALID_STUCK,       // RVALID持续有效未握手
        RLAST_MISMATCH,     // RLAST与突发长度不匹配
        INVALID_RRESP,      // 无效的RRESP值
        ID_MISMATCH,        // ID不匹配
        ADDR_ALIGNMENT,     // 地址未对齐
        BURST_TYPE,         // 不支持的突发类型
        LENGTH_OVERRUN,     // 长度超过限制
        ADDR_OUT_OF_BOUND,  // 地址越界
        PROTOCOL_VIOLATION  // 协议违规
    } error_code_t;
    
    // 监控变量
    reg [31:0] arvalid_timeout = 0;
    reg [31:0] rvalid_timeout = 0;
    reg [7:0] expected_beats [0:15]; // 假设最多16个ID
    reg [7:0] beat_count [0:15];
    reg [AXI_ID_W-1:0] active_ids [0:15];
    reg [3:0] active_count = 0;
    integer id_found = 0;
    
    // 错误检测和报告
    function void report_error(error_code_t code, logic [AXI_ID_W-1:0] id = 0, logic [63:0] addr = 0);
        error_code = code;
        error_id = id;
        
        // 添加详细的错误信息输出
        case (code)
            ARVALID_STUCK:
                $display("协议错误 [时间 %0t]: ARVALID卡住, ID=%h", $time, id);
            RVALID_STUCK:
                $display("协议错误 [时间 %0t]: RVALID卡住, ID=%h", $time, id);
            RLAST_MISMATCH:
                $display("协议错误 [时间 %0t]: RLAST不匹配, ID=%h", $time, id);
            INVALID_RRESP:
                $display("协议错误 [时间 %0t]: 无效的RRESP值=%b, ID=%h", $time, rresp, id);
            ID_MISMATCH:
                $display("协议错误 [时间 %0t]: ID不匹配, 期望的ID未找到, 接收到的ID=%h", $time, id);
            ADDR_ALIGNMENT:
                $display("协议错误 [时间 %0t]: 地址未对齐, Addr=%h, Size=%d, ID=%h", $time, addr, arsize, id);
            BURST_TYPE:
                $display("协议错误 [时间 %0t]: 不支持的突发类型=%b, 只支持INCR(01), ID=%h", $time, arburst, id);
            LENGTH_OVERRUN:
                $display("协议错误 [时间 %0t]: 长度超过限制, Len=%0d, ID=%h", $time, arlen, id);
            ADDR_OUT_OF_BOUND:
                $display("协议错误 [时间 %0t]: 地址越界或从设备错误, Addr=%h, RRESP=%b, ID=%h", $time, addr, rresp, id);
            PROTOCOL_VIOLATION:
                $display("协议错误 [时间 %0t]: 协议违规, ID=%h", $time, id);
            default:
                $display("协议错误 [时间 %0t]: 未知错误, 代码=%h, ID=%h", $time, code, id);
        endcase
    endfunction
    
    integer found = 0;
    
    // 错误检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arvalid_timeout <= 0;
            rvalid_timeout <= 0;
            error_code <= NO_ERROR;
            error_id <= 0;
            
            for (int i = 0; i < 16; i++) begin
                expected_beats[i] <= 0;
                beat_count[i] <= 0;
                active_ids[i] <= 0;
            end
            active_count <= 0;
        end else begin
            // 默认无错误
            error_code <= NO_ERROR;
            
            // 检查ARVALID是否卡住
            if (arvalid && !arready) begin
                arvalid_timeout <= arvalid_timeout + 1;
                if (arvalid_timeout > TIMEOUT_CYCLES) begin
                    report_error(ARVALID_STUCK, arid);
                    arvalid_timeout <= 0;
                end
            end else begin
                arvalid_timeout <= 0;
            end
            
            // 检查RVALID是否卡住
            if (rvalid && !rready) begin
                rvalid_timeout <= rvalid_timeout + 1;
                if (rvalid_timeout > TIMEOUT_CYCLES) begin
                    report_error(RVALID_STUCK, rid);
                    rvalid_timeout <= 0;
                end
            end else begin
                rvalid_timeout <= 0;
            end
            
            // 检查地址对齐
            if (arvalid && arready) begin
                if (araddr % (1 << arsize) != 0) begin
                    report_error(ADDR_ALIGNMENT, arid, araddr);
                end
                
                // 检查突发类型
                if (arburst != 2'b01) begin // 只支持INCR模式
                    report_error(BURST_TYPE, arid);
                end
                
                // 检查突发长度
                if (arlen > 255) begin
                    report_error(LENGTH_OVERRUN, arid);
                end
                
                // 记录预期beat数 - 修复ID跟踪逻辑
                found = 0;
                for (int i = 0; i < active_count; i++) begin
                    if (active_ids[i] == arid) begin
                        expected_beats[i] <= arlen + 1;
                        beat_count[i] <= 0;
                        found = 1;
                        $display("[PROTOCOL_CHECKER] 更新ID: ID=%h, 预期beat数=%d", arid, arlen + 1);
                        break;
                    end
                end
                
                if (!found && active_count < 15) begin
                    active_ids[active_count] <= arid;
                    expected_beats[active_count] <= arlen + 1;
                    beat_count[active_count] <= 0;
                    active_count <= active_count + 1;
                    $display("[PROTOCOL_CHECKER] 新ID注册: ID=%h, 预期beat数=%d", arid, arlen + 1);
                end else if (!found) begin
                    $display("[PROTOCOL_CHECKER] 错误: 无法跟踪更多ID, 当前active_count=%d", active_count);
                end
            end
            
            // 数据通道握手
            if (rvalid && rready) begin
                // 查找当前rid对应的beat_count
                integer current_beat_count = 0;
                integer found_index = -1;
                id_found = 0;
                
                for (int i = 0; i < active_count; i++) begin
                    if (active_ids[i] == rid) begin
                        current_beat_count = beat_count[i];
                        found_index = i;
                        id_found = 1;
                        break;
                    end
                end
                
                if (found_index != -1) begin
                    // 修复RLAST检查逻辑
                    if ((beat_count[found_index] + 1 == expected_beats[found_index]) && !rlast) begin
                        report_error(RLAST_MISMATCH, rid);
                    end else if ((beat_count[found_index] + 1 < expected_beats[found_index]) && rlast) begin
                        report_error(RLAST_MISMATCH, rid);
                    end
                    
                    beat_count[found_index] <= beat_count[found_index] + 1;
                    
                    // 检查RRESP
                    if (rresp == 2'b10 || rresp == 2'b11) begin
                        // SLVERR或DECERR
                        report_error(ADDR_OUT_OF_BOUND, rid, araddr);
                    end else if (rresp != 2'b00 && rresp != 2'b01) begin
                        report_error(INVALID_RRESP, rid);
                    end
                    
                    // 如果这是最后一个beat，移除ID
                    if (rlast) begin
                        for (int j = found_index; j < active_count - 1; j++) begin
                            active_ids[j] <= active_ids[j + 1];
                            expected_beats[j] <= expected_beats[j + 1];
                            beat_count[j] <= beat_count[j + 1];
                        end
                        active_count <= active_count - 1;
                        $display("[PROTOCOL_CHECKER] ID完成: ID=%h", rid);
                    end
                end else begin
                    // 添加调试信息
                    $display("[PROTOCOL_CHECKER] 错误: 未找到ID=%h, active_count=%d", rid, active_count);
                    for (int i = 0; i < active_count; i++) begin
                        $display("[PROTOCOL_CHECKER] active_ids[%0d]=%h", i, active_ids[i]);
                    end
                    report_error(ID_MISMATCH, rid);
                end
            end
        end
    end
endmodule