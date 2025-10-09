`timescale 1ns/1ps
module ur_model #(
    parameter DATA_WIDTH = 128,
    parameter LFSR_WIDTH = 32,
    parameter LFSR_POLY = 32'h8000000B, // X^32 + X^22 + X^2 + X^1 + 1 (修正多项式)
    parameter ADDR_WIDTH = 11,
    parameter MAX_ID = 16
)(
    input                   clk,
    input                   rst_n,
    
    // 读接口（连接burst_store）
    input                   ur_re,
    input [3:0]             ur_id,
    input [ADDR_WIDTH-1:0]  ur_addr,
    output reg [DATA_WIDTH-1:0] ur_rdata,
    
    // 写接口（可选）
    input                   ur_we,
    input [DATA_WIDTH-1:0]  ur_wdata,
    input [DATA_WIDTH/8-1:0] ur_wstrb,
    
    // 错误注入控制（可选）
    input                   err_inject,
    input [3:0]             err_type,
    input [ADDR_WIDTH-1:0]  err_addr_mask,
    
    // 统计输出（可选）
    output reg [31:0]       read_count,
    output reg [31:0]       write_count,
    output reg [31:0]       error_count
);
// 存储每个ID的LFSR状态
reg [LFSR_WIDTH-1:0] lfsr [0:MAX_ID-1];
// 实际存储阵列
reg [DATA_WIDTH-1:0] memory [0:(1<<ADDR_WIDTH)-1];
// 地址边界检查参数
localparam ADDR_MAX = (1 << ADDR_WIDTH) - 1;
// LFSR抽头位置计算
wire [LFSR_WIDTH-1:0] lfsr_taps;
assign lfsr_taps = LFSR_POLY;
// 错误注入标志
reg err_inject_active;
reg [3:0] active_err_type;
reg [ADDR_WIDTH-1:0] active_err_addr_mask;

// 用于测试用例3和5的数据记录变量（保持向后兼容）
reg [DATA_WIDTH-1:0] smc0_data;  // SMC0使用的随机数据
reg [DATA_WIDTH-1:0] smc1_data;  // SMC1使用的随机数据
reg [DATA_WIDTH-1:0] smc2_data;  // SMC2使用的随机数据
reg [DATA_WIDTH-1:0] smc3_data;  // SMC3使用的随机数据
reg [DATA_WIDTH-1:0] smc4_data;  // SMC4使用的随机数据
reg [DATA_WIDTH-1:0] smc5_data;  // SMC5使用的随机数据

// 初始化和更新LFSR
integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
            // 初始化每个ID的LFSR为不同的值
            for (i = 0; i < MAX_ID; i = i + 1) begin
                lfsr[i] <= {LFSR_WIDTH{1'b1}} ^ (i << 8) ^ (i << 16) ^ (i << 24);
            end
            // 初始化内存
            for (i = 0; i <= ADDR_MAX; i = i + 1) begin
                memory[i] <= {DATA_WIDTH{1'b0}};
            end
            // 初始化统计计数器
            read_count <= 0;
            write_count <= 0;
            error_count <= 0;
            // 初始化错误注入
            err_inject_active <= 0;
            active_err_type <= 0;
            active_err_addr_mask <= 0;
            // 初始化测试用例3和5的数据记录变量
            smc0_data <= {DATA_WIDTH{1'b0}};
            smc1_data <= {DATA_WIDTH{1'b0}};
            smc2_data <= {DATA_WIDTH{1'b0}};
            smc3_data <= {DATA_WIDTH{1'b0}};
            smc4_data <= {DATA_WIDTH{1'b0}};
            smc5_data <= {DATA_WIDTH{1'b0}};
    end else begin
        // 更新错误注入状态
        if (err_inject) begin
            err_inject_active <= 1;
            active_err_type <= err_type;
            active_err_addr_mask <= err_addr_mask;
        end
        // 处理读操作（响应burst_store的ur_re请求）
        if (ur_re && ur_addr <= ADDR_MAX) begin
            read_count <= read_count + 1;
            // 标准LFSR更新
            lfsr[ur_id] <= {lfsr[ur_id][LFSR_WIDTH-2:0], ^(lfsr[ur_id] & lfsr_taps)};
        end
        // 处理写操作（可选，未使用）
        if (ur_we && ur_addr <= ADDR_MAX) begin
            write_count <= write_count + 1;
            // 字节使能写入：直接写入到传入的地址
            for (i = 0; i < DATA_WIDTH/8; i = i + 1) begin
                if (ur_wstrb[i]) begin
                    memory[ur_addr][i*8 +: 8] <= ur_wdata[i*8 +: 8];
                end
            end
            
            // 特殊处理测试用例3和5的数据记录（保持向后兼容）
            if (ur_addr == 32) begin // 地址0x20
                if (smc0_data == {DATA_WIDTH{1'b0}}) begin
                    smc0_data <= ur_wdata; // 记录第一个写入的数据（SMC0使用）
                end else if (smc1_data == {DATA_WIDTH{1'b0}} && ur_wdata != smc0_data) begin
                    smc1_data <= ur_wdata; // 记录第二个写入的不同数据（SMC1使用）
                end else if (smc2_data == {DATA_WIDTH{1'b0}} && ur_wdata != smc0_data && ur_wdata != smc1_data) begin
                    smc2_data <= ur_wdata; // 记录第三个写入的不同数据（SMC2使用）
                end else if (smc3_data == {DATA_WIDTH{1'b0}} && ur_wdata != smc0_data && ur_wdata != smc1_data && ur_wdata != smc2_data) begin
                    smc3_data <= ur_wdata; // 记录第四个写入的不同数据（SMC3使用）
                end else if (smc4_data == {DATA_WIDTH{1'b0}} && ur_wdata != smc0_data && ur_wdata != smc1_data && ur_wdata != smc2_data && ur_wdata != smc3_data) begin
                    smc4_data <= ur_wdata; // 记录第五个写入的不同数据（SMC4使用）
                end else if (smc5_data == {DATA_WIDTH{1'b0}} && ur_wdata != smc0_data && ur_wdata != smc1_data && ur_wdata != smc2_data && ur_wdata != smc3_data && ur_wdata != smc4_data) begin
                    smc5_data <= ur_wdata; // 记录第六个写入的不同数据（SMC5使用）
                end
            end
        end
    end
end

// 生成输出数据（随机数据通过ur_rdata输出到burst_store）
always @(posedge clk) begin
    if (ur_re && ur_addr <= ADDR_MAX) begin
        // 基础数据：LFSR状态与地址混合
        reg [DATA_WIDTH-1:0] base_data;
        reg [LFSR_WIDTH-1:0] mixed_lfsr;
        
        // 增强的LFSR与地址混合逻辑
        mixed_lfsr = lfsr[ur_id] ^ ur_addr ^ (lfsr[ur_id] >> 8) ^ (lfsr[ur_id] << 8);
        // 生成128位基础数据（匹配DATA_WIDTH=128）
        base_data = {mixed_lfsr, mixed_lfsr ^ (ur_addr << 4) ^ (ur_addr >> 4), 
                    mixed_lfsr ^ lfsr[(ur_id+2)%MAX_ID], mixed_lfsr ^ lfsr[(ur_id+4)%MAX_ID]};
        
        // 应用错误注入（可选，默认关闭）
        if (err_inject_active && (ur_addr & active_err_addr_mask) == 0) begin
            case (active_err_type)
                4'h1: base_data = ~base_data; // 位翻转
                4'h2: base_data = {DATA_WIDTH{1'b0}}; // 全零
                4'h3: base_data = {DATA_WIDTH{1'b1}}; // 全一
                4'h4: base_data = base_data ^ {DATA_WIDTH{1'b1}}; // 按位取反
                4'h5: base_data = {base_data[DATA_WIDTH-2:0], base_data[DATA_WIDTH-1]}; // 循环移位
                4'h6: base_data = base_data + 1; // 加1错误
                4'h7: base_data = base_data - 1; // 减1错误
                4'h8: base_data = {DATA_WIDTH{1'b0}}; // 固定模式错误
                default: base_data = base_data; // 无错误
            endcase
            error_count <= error_count + 1;
        end
        
        // 关键：随机数据输出到burst_store的ur_rdata
        ur_rdata <= base_data;
        
        // 直接写入到传入的地址
        memory[ur_addr] <= base_data;
        
        // 特殊处理测试用例3和5的数据记录（保持向后兼容）
        if (ur_addr == 32) begin // 地址0x20
            if (smc0_data == {DATA_WIDTH{1'b0}}) begin
                smc0_data <= base_data; // 记录第一个写入的数据（SMC0使用）
            end else if (smc1_data == {DATA_WIDTH{1'b0}} && base_data != smc0_data) begin
                smc1_data <= base_data; // 记录第二个写入的不同数据（SMC1使用）
            end else if (smc2_data == {DATA_WIDTH{1'b0}} && base_data != smc0_data && base_data != smc1_data) begin
                smc2_data <= base_data; // 记录第三个写入的不同数据（SMC2使用）
            end else if (smc3_data == {DATA_WIDTH{1'b0}} && base_data != smc0_data && base_data != smc1_data && base_data != smc2_data) begin
                smc3_data <= base_data; // 记录第四个写入的不同数据（SMC3使用）
            end else if (smc4_data == {DATA_WIDTH{1'b0}} && base_data != smc0_data && base_data != smc1_data && base_data != smc2_data && base_data != smc3_data) begin
                smc4_data <= base_data; // 记录第五个写入的不同数据（SMC4使用）
            end else if (smc5_data == {DATA_WIDTH{1'b0}} && base_data != smc0_data && base_data != smc1_data && base_data != smc2_data && base_data != smc3_data && base_data != smc4_data) begin
                smc5_data <= base_data; // 记录第六个写入的不同数据（SMC5使用）
            end
        end
        
        // 调试信息保持不变
        $display("[UR_DEBUG] 时间%0t: 写入memory[0x%h] = 0x%h, ur_id=%d", $time, ur_addr, base_data, ur_id);
    end else if (ur_we && ur_addr <= ADDR_MAX) begin
        ur_rdata <= ur_wdata; // 写操作时返回写入数据
    end else begin
        ur_rdata <= ur_rdata; // 无操作时保持输出
    end
end

// 内存直接读取接口（供外部模块读取数据）
function [DATA_WIDTH-1:0] get_memory;
    input [ADDR_WIDTH-1:0] addr;
    begin
        if (addr <= ADDR_MAX) begin
            get_memory = memory[addr];
        end else begin
            get_memory = {DATA_WIDTH{1'b0}};
        end
    end
endfunction

// LFSR状态读取接口（供外部模块读取LFSR状态）
function [LFSR_WIDTH-1:0] get_lfsr;
    input [3:0] id;
    begin
        if (id < MAX_ID) begin
            get_lfsr = lfsr[id];
        end else begin
            get_lfsr = {LFSR_WIDTH{1'b0}};
        end
    end
endfunction

endmodule
    