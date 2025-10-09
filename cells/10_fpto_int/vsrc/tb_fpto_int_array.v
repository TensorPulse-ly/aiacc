`timescale 1ns/1ps
//------------------------------------------------------------------------------------
// Filename: tb_fpto_int_array.v
// Author: [Sunny]
// Editor: [Oliver]
// Date: 2025-8-21
// Version: 1.1
// Description: testbench module for fpto_int_array.v, Modified the Input/Output port.
//------------------------------------------------------------------------------------
module tb_fpto_int_array;

// 测试信号定义
reg         clk;
reg         rst_n;
reg [127:0] dvr_fptoint_s_in;
reg [4:0]   cru_fptoint_in;
wire [127:0] dr_fptoint_d_out;

// 日志文件句柄
integer log_file;

// 时钟生成
always #5 clk = ~clk;

// 实例化被测阵列模块
fpto_int_array uut (
    .clk(clk),
    .rst_n(rst_n),
    .dvr_fptoint_s_in(dvr_fptoint_s_in),
    .cru_fptoint_in(cru_fptoint_in),
    .dr_fptoint_d_out(dr_fptoint_d_out)
);

// 微指令信号解析
wire inst_vld = cru_fptoint_in[4];
wire src_prec = cru_fptoint_in[3];
wire dst_prec = cru_fptoint_in[2];
wire src_pos = cru_fptoint_in[1];
wire dst_pos = cru_fptoint_in[0];

// 输出数据拆分
wire [31:0] out_reg_0 = dr_fptoint_d_out[127:96];
wire [31:0] out_reg_1 = dr_fptoint_d_out[95:64];
wire [31:0] out_reg_2 = dr_fptoint_d_out[63:32];
wire [31:0] out_reg_3 = dr_fptoint_d_out[31:0];

// 测试任务
task test_array_conversion;
    input [31:0] test_input_0, test_input_1, test_input_2, test_input_3;
    input test_src_precision;
    input test_dst_precision;
    input test_src_pos;
    input test_dst_pos;
    input [255:0] test_name;
begin
    // 组合输入数据
    dvr_fptoint_s_in = {test_input_0, test_input_1, test_input_2, test_input_3};
    
    // 设置微指令
    cru_fptoint_in = {1'b1, test_src_precision, test_dst_precision, test_src_pos, test_dst_pos};
    
    // 等待时钟边沿
    @(posedge clk);
    #1; // 稍作延迟确保稳定
    
    $fdisplay(log_file, "阵列测试: %s", test_name);
    $fdisplay(log_file, "  源精度: %s, 目的精度: %s", 
             test_src_precision ? "32bit" : "16bit",
             test_dst_precision ? "32bit" : "16bit");
    $fdisplay(log_file, "  输入0: 0x%08X -> 输出0: 0x%08X", test_input_0, out_reg_0);
    $fdisplay(log_file, "  输入1: 0x%08X -> 输出1: 0x%08X", test_input_1, out_reg_1);
    $fdisplay(log_file, "  输入2: 0x%08X -> 输出2: 0x%08X", test_input_2, out_reg_2);
    $fdisplay(log_file, "  输入3: 0x%08X -> 输出3: 0x%08X", test_input_3, out_reg_3);
    $fdisplay(log_file, "");
end
endtask

// 主测试过程
initial begin
    // 打开日志文件
    log_file = $fopen("fpto_int_array_test.log", "w");
    if (!log_file) begin
        $display("错误: 无法创建日志文件");
        $finish;
    end
    
    // 初始化时钟和复位
    clk = 0;
    rst_n = 0;
    
    // 初始化输入
    dvr_fptoint_s_in = 128'h0;
    cru_fptoint_in = 5'h0;
    
    // 应用复位
    #20 rst_n = 1;
    
    // 开始测试信息 - 仅写入日志文件
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "FPtoINT 阵列模块测试开始");
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "日志文件: fpto_int_array_test.log");
    $fdisplay(log_file, "");
    
    // =================== FP32转INT32阵列测试 ===================
    $fdisplay(log_file, "=== FP32 -> INT32 4路并行转换测试 ===");
    
    // 测试1: 4个不同FP32数据并行转换
    test_array_conversion(
        32'h3F800000,  // 1.0
        32'hBF800000,  // -1.0
        32'h42F70000,  // 123.5
        32'hC3E4CCCD,  // -456.8
        1'b1, 1'b1, 1'b0, 1'b0,
        "4路FP32并行转INT32"
    );
    
    // =================== FP32转INT16阵列测试 ===================
    $fdisplay(log_file, "=== FP32 -> INT16 4路并行转换测试 ===");
    
    // 测试2: FP32转INT16，含饱和处理
    test_array_conversion(
        32'h3F800000,  // 1.0 -> 1
        32'h47000000,  // 32768.0 -> 32767 (饱和)
        32'hC7000080,  // -32769.0 -> -32768 (饱和)
        32'h41200000,  // 10.0 -> 10
        1'b1, 1'b0, 1'b0, 1'b0,
        "4路FP32转INT16含饱和"
    );
    
    // =================== FP16转INT32阵列测试 ===================
    $fdisplay(log_file, "=== FP16 -> INT32 4路并行转换测试 ===");
    
    // 测试3: FP16转INT32，低位输入
    test_array_conversion(
        32'h00003C00,  // FP16(1.0)
        32'h0000C000,  // FP16(-2.0)
        32'h00004200,  // FP16(3.0)
        32'h0000C500,  // FP16(-5.0)
        1'b0, 1'b1, 1'b0, 1'b0,
        "4路低位FP16转INT32"
    );
    
    // 测试4: FP16转INT32，高位输入
    test_array_conversion(
        32'h3C000000,  // FP16(1.0)在高位
        32'hC0000000,  // FP16(-2.0)在高位
        32'h42000000,  // FP16(3.0)在高位
        32'hC5000000,  // FP16(-5.0)在高位
        1'b0, 1'b1, 1'b1, 1'b0,
        "4路高位FP16转INT32"
    );
    
    // =================== FP16转INT16阵列测试 ===================
    $fdisplay(log_file, "=== FP16 -> INT16 4路并行转换测试 ===");
    
    // 测试5: FP16转INT16
    test_array_conversion(
        32'h00003C00,  // FP16(1.0)
        32'h00004000,  // FP16(2.0)
        32'h00004200,  // FP16(3.0)
        32'h00004400,  // FP16(4.0)
        1'b0, 1'b0, 1'b0, 1'b0,
        "4路FP16转INT16"
    );
    
    // =================== 子字并行阵列测试 ===================
    $fdisplay(log_file, "=== 子字并行 4路阵列转换测试 ===");
    
    // 测试6: 每个32位输入包含2个FP16数据
    test_array_conversion(
        32'h40003C00,  // 高位FP16(2.0)，低位FP16(1.0)
        32'h44004200,  // 高位FP16(4.0)，低位FP16(3.0)
        32'hC600C500,  // 高位FP16(-6.0)，低位FP16(-5.0)
        32'h48004700,  // 高位FP16(8.0)，低位FP16(7.0)
        1'b0, 1'b0, 1'b0, 1'b0,
        "4路子字并行FP16转INT16"//8路FP16转INT16
    );
    
    // =================== 边界条件阵列测试 ===================
    $fdisplay(log_file, "=== 边界条件 4路阵列测试 ===");
    
    // 测试7: 特殊值处理
    test_array_conversion(
        32'h00000000,  // 0.0
        32'h7F800000,  // +INF
        32'hFF800000,  // -INF
        32'h7FC00000,  // NaN
        1'b1, 1'b1, 1'b0, 1'b0,
        "4路特殊值处理"
    );
    
    // =================== 指令控制阵列测试 ===================
    $fdisplay(log_file, "=== 指令有效性控制阵列测试 ===");
    
    // 测试8: 指令无效测试
    cru_fptoint_in = 5'h0; // 指令无效
    dvr_fptoint_s_in = {32'h3F800000, 32'h40000000, 32'h40400000, 32'h40800000};
    @(posedge clk);
    #1;
    $fdisplay(log_file, "阵列测试: 指令无效");
    $fdisplay(log_file, "  指令无效时输出为0");
    $fdisplay(log_file, "  输出0: 0x%08X, 输出1: 0x%08X", out_reg_0, out_reg_1);
    $fdisplay(log_file, "  输出2: 0x%08X, 输出3: 0x%08X", out_reg_2, out_reg_3);
    $fdisplay(log_file, "");
    
    // 测试完成信息 - 仅写入日志文件
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "FPtoINT 阵列模块测试完成");  
    $fdisplay(log_file, "========================================");
    
    // 关闭日志文件
    $fclose(log_file);
    
    $finish;
end

// 监视输出
initial begin
    $monitor("Time: %t, Output: %h", $time, dr_fptoint_d_out);
end

endmodule