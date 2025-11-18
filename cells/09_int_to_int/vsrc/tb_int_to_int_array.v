`timescale 1ns/1ps
//------------------------------------------------------------------------------
// Filename: tb_int_to_int_array.v
// Author: [Oliver]
// Date: 2025-8-28
// Version: 1.0
// Description: Testbench for int_to_int_array.v module
//------------------------------------------------------------------------------

module tb_int_to_int_array;

// DPI-C函数导入
import "DPI-C" function int dpi_int_to_int_convert(
    input int in_data, input byte src_prec, input byte dst_prec, 
    input byte src_signed, input byte dst_signed, input byte src_pos, input byte dst_pos
);

// 测试信号定义
reg          clk;
reg          rst_n;
reg [127:0]  dvr_inttoint_s_in;
reg [6:0]    cru_inttoint_in;
wire [127:0] dr_inttoint_d_out;
wire [6:0]   cru_inttoint_out;
reg  [4:0]   smc_id_in;

reg [31:0]   conv_data_3;
reg [31:0]   conv_data_2;
reg [31:0]   conv_data_1;
reg [31:0]   conv_data_0;

reg         instr_vld  ;
reg         src_prec   ;
reg         dst_prec   ;
reg         src_signed ;
reg         dst_signed ;
reg         src_pos    ;
reg         dst_pos    ;

wire [31:0] out_reg_0  ;
wire [31:0] out_reg_1  ;
wire [31:0] out_reg_2  ;
wire [31:0] out_reg_3  ;
wire [31:0] in_reg_0   ;
wire [31:0] in_reg_1   ;
wire [31:0] in_reg_2   ;
wire [31:0] in_reg_3   ;

// 日志文件句柄
integer log_file;
integer pass_cnt, total_cnt;

// 时钟生成
always #5 clk = ~clk;

// 实例化被测阵列模块
int_to_int_array uut (
    .clk(clk),
    .rst_n(rst_n),
    .dvr_inttoint_s_in(dvr_inttoint_s_in),
    .cru_inttoint_in(cru_inttoint_in),
    .dr_inttoint_d_out(dr_inttoint_d_out),
    .cru_inttoint_out(cru_inttoint_out),
    .smc_id_in(smc_id_in)
);



// 输出数据拆分
assign out_reg_0 = dr_inttoint_d_out[127:96];
assign out_reg_1 = dr_inttoint_d_out[95:64];
assign out_reg_2 = dr_inttoint_d_out[63:32];
assign out_reg_3 = dr_inttoint_d_out[31:0];

// 输入数据拆分
assign in_reg_0 = dvr_inttoint_s_in[127:96];
assign in_reg_1 = dvr_inttoint_s_in[95:64];
assign in_reg_2 = dvr_inttoint_s_in[63:32];
assign in_reg_3 = dvr_inttoint_s_in[31:0];

// 测试任务
task test_array_conversion;
    input [31:0] test_input_0, test_input_1, test_input_2, test_input_3;
    input test_src_precision;
    input test_dst_precision;
    input test_src_signed;
    input test_dst_signed;
    input test_src_pos;
    input test_dst_pos;
    input [255:0] test_name;

    reg [31:0] dpi_result0;
    reg [31:0] dpi_result1;
    reg [31:0] dpi_result2;
    reg [31:0] dpi_result3;
begin
    
    // 设置微指令
    cru_inttoint_in = {1'b1, test_src_precision, test_dst_precision, 
                      test_src_signed, test_dst_signed, test_src_pos, test_dst_pos};
    
    // 组合输入数据
    dvr_inttoint_s_in = {test_input_0, test_input_1, test_input_2, test_input_3};
    
    // 等待时钟边沿
    @(posedge clk);
    #1; // 稍作延迟确保稳定

    dpi_result0 = dpi_int_to_int_convert(test_input_0, test_src_precision, test_dst_precision, 
                                      test_src_signed, test_dst_signed, test_src_pos, test_dst_pos);
    dpi_result1 = dpi_int_to_int_convert(test_input_1, test_src_precision, test_dst_precision, 
                                      test_src_signed, test_dst_signed, test_src_pos, test_dst_pos);
    dpi_result2 = dpi_int_to_int_convert(test_input_2, test_src_precision, test_dst_precision, 
                                      test_src_signed, test_dst_signed, test_src_pos, test_dst_pos);
    dpi_result3 = dpi_int_to_int_convert(test_input_3, test_src_precision, test_dst_precision, 
                                      test_src_signed, test_dst_signed, test_src_pos, test_dst_pos);
    
    $fdisplay(log_file, "阵列测试: %s", test_name);
    $fdisplay(log_file, "  源精度: %s, 目的精度: %s", 
             test_src_precision ? "32bit" : "16bit",
             test_dst_precision ? "32bit" : "16bit");
    $fdisplay(log_file, "  源符号: %s, 目的符号: %s", 
             test_src_signed ? "有符号" : "无符号",
             test_dst_signed ? "有符号" : "无符号");
    $fdisplay(log_file, "  输入0: 0x%08X -> 输出0: 0x%08X -> C输出0: 0x%08X", test_input_0, out_reg_0, dpi_result0);
    $fdisplay(log_file, "  输入1: 0x%08X -> 输出1: 0x%08X -> C输出1: 0x%08X", test_input_1, out_reg_1, dpi_result1);
    $fdisplay(log_file, "  输入2: 0x%08X -> 输出2: 0x%08X -> C输出2: 0x%08X", test_input_2, out_reg_2, dpi_result2);
    $fdisplay(log_file, "  输入3: 0x%08X -> 输出3: 0x%08X -> C输出3: 0x%08X", test_input_3, out_reg_3, dpi_result3);
    if((out_reg_0 == dpi_result0) && (out_reg_1 == dpi_result1) && (out_reg_2 == dpi_result2) && (out_reg_3 == dpi_result3))
        $fdisplay(log_file, "  PASS");
    else
        $fdisplay(log_file, "  FAIL");

    $fdisplay(log_file, "");

    if(out_reg_0 == dpi_result0)
        pass_cnt++;
    total_cnt++;
end
endtask

// 主测试过程
integer i;
initial begin
    // 打开日志文件
    log_file = $fopen("int_to_int_array_test.log", "w");
    if (!log_file) begin
        $display("错误: 无法创建日志文件");
        $finish;
    end

    // 微指令信号解析
    instr_vld  = cru_inttoint_in[6];
    src_prec   = cru_inttoint_in[5];
    dst_prec   = cru_inttoint_in[4];
    src_signed = cru_inttoint_in[3];
    dst_signed = cru_inttoint_in[2];
    src_pos    = cru_inttoint_in[1];
    dst_pos    = cru_inttoint_in[0];

    // 初始化时钟和复位
    clk = 1'b0;
    rst_n = 1'b0;
    pass_cnt = 0;
    total_cnt = 0;
    // 初始化输入
    dvr_inttoint_s_in = 128'h0;
    cru_inttoint_in = 7'h0;
    
    // 应用复位
    #20 rst_n = 1;
    
    // 开始测试信息
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "INTtoINT 阵列模块测试开始");
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "日志文件: int_to_int_array_test.log");
    $fdisplay(log_file, "");
    
    // =================== 测试1: s32 -> s32 ===================
    test_array_conversion(
        32'h0000007F,  // 127
        32'hFFFFFF80,  // -128
        32'h7FFFFFFF,  // 2147483647
        32'h80000000,  // -2147483648
        1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0,
        "s32 -> s32 转换"
    );

    // =================== 测试2: s32 -> u32 ===================
    test_array_conversion(
        32'h0000007F,  // 127 -> 127
        32'hFFFFFF80,  // -128 -> 0
        32'h00000000,  // 0 -> 0
        32'hFFFFFFFF,  // -1 -> 0
        1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0,
        "s32 -> u32 转换"
    );
    

    
    // =================== 测试3: u32 -> s32 ===================
    test_array_conversion(
        32'h0000007F,  // 127 -> 127
        32'h7FFFFFFF,  // 2147483647 -> 2147483647
        32'h80000000,  // 2147483648 -> 2147483647 (饱和)
        32'hFFFFFFFF,  // 4294967295 -> 2147483647 (饱和)
        1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0,
        "u32 -> s32 转换"
    );
    
    // =================== 测试4: u32 -> u32 ===================
    test_array_conversion(
        32'h0000007F,  // 127 -> 127
        32'h7FFFFFFF,  // 2147483647 -> 2147483647
        32'h80000000,  // 2147483648 -> 2147483648
        32'hFFFFFFFF,  // 4294967295 -> 4294967295
        1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
        "u32 -> u32 转换"
    );
    
    // =================== 测试5: s32 -> s16 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32767 (饱和)
        32'hFFFF8000,  // -32768 -> -32768
        32'hFFFF7FFF,  // -32769 -> -32768 (饱和)
        1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0,
        "s32 -> s16(low) 转换"
    );
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32767 (饱和)
        32'hFFFF8000,  // -32768 -> -32768
        32'hFFFF7FFF,  // -32769 -> -32768 (饱和)
        1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1,
        "s32 -> s16(high) 转换"
    );
    
    // =================== 测试6: s32 -> u16 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32768
        32'hFFFF8000,  // -32768 -> 0
        32'hFFFF7FFF,  // -32769 -> 0
        1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
        "s32 -> u16(low) 转换"
    );
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32768
        32'hFFFF8000,  // -32768 -> 0
        32'hFFFF7FFF,  // -32769 -> 0
        1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1,
        "s32 -> u16(high) 转换"
    );
    
    // =================== 测试7: u32 -> s16 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32767 (饱和)
        32'h0000FFFF,  // 65535 -> 32767 (饱和)
        32'h0000007F,  // 127 -> 127
        1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
        "u32 -> s16(low) 转换"
    );
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32767 (饱和)
        32'h0000FFFF,  // 65535 -> 32767 (饱和)
        32'h0000007F,  // 127 -> 127
        1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1,
        "u32 -> s16(high) 转换"
    );
    
    // =================== 测试8: u32 -> u16 ===================
    test_array_conversion(
        32'h0000FFFF,  // 65535 -> 65535
        32'h00010000,  // 65536 -> 65535 (饱和)
        32'h00000000,  // 0 -> 0
        32'h00007FFF,  // 32767 -> 32767
        1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        "u32 -> u16(low) 转换"
    );
    test_array_conversion(
        32'h0000FFFF,  // 65535 -> 65535
        32'h00010000,  // 65536 -> 65535 (饱和)
        32'h00000000,  // 0 -> 0
        32'h00007FFF,  // 32767 -> 32767
        1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1,
        "u32 -> u16(high) 转换"
    );
    
    // =================== 测试9: s16 -> s32 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // -32768 -> -32768
        32'h0000007F,  // 127 -> 127
        32'h0000FFFE,  // -2 -> -2
        1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0,
        "s16(low) -> s32 转换"
    );
    test_array_conversion(
        32'h7FFF0000,  // 32767 -> 32767
        32'h80000000,  // -32768 -> -32768
        32'h007F0000,  // 127 -> 127
        32'hFFFE0000,  // -2 -> -2
        1'b0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0,
        "s16(high) -> s32 转换"
    );
    
    // =================== 测试10: s16 -> u32 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // -32768 -> 0
        32'h0000007F,  // 127 -> 127
        32'h0000FFFE,  // -2 -> 0
        1'b0, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0,
        "s16(low) -> u32 转换"
    );
    test_array_conversion(
        32'h7FFF0000,  // 32767 -> 32767
        32'h80000000,  // -32768 -> 0
        32'h007F0000,  // 127 -> 127
        32'hFFFE0000,  // -2 -> 0
        1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0,
        "s16(high) -> u32 转换"
    );
    
    // =================== 测试11: u16 -> s32 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32768
        32'h0000FFFF,  // 65535 -> 65535
        32'h0000007F,  // 127 -> 127
        1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0,
        "u16(low) -> s32 转换"
    );
    test_array_conversion(
        32'h7FFF0000,  // 32767 -> 32767
        32'h80000000,  // 32768 -> 32768
        32'hFFFF0000,  // 65535 -> 65535
        32'h007F0000,  // 127 -> 127
        1'b0, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0,
        "u16(high) -> s32 转换"
    );
    
    // =================== 测试12: u16 -> u32 ===================
    test_array_conversion(
        32'h00007FFF,  // 32767 -> 32767
        32'h00008000,  // 32768 -> 32768
        32'h0000FFFF,  // 65535 -> 65535
        32'h0000007F,  // 127 -> 127
        1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
        "u16(low) -> u32 转换"
    );
    test_array_conversion(
        32'h7FFF0000,  // 32767 -> 32767
        32'h80000000,  // 32768 -> 32768
        32'hFFFF0000,  // 65535 -> 65535
        32'h007F0000,  // 127 -> 127
        1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0,
        "u16(high) -> u32 转换"
    );
    
    // =================== 测试13: s16 -> s16 ===================
    test_array_conversion(
        32'h7FFF8000,  // 32767,-32768 -> 32767,-32768
        32'h0000FFFF,  // 0,-1 -> 0,-1
        32'h7F807F80,  // 32640,32640 -> 32640,32640
        32'h00800080,  // 128,128 -> 128,128
        1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0,
        "s16 -> s16 转换"
    );
    
    // =================== 测试14: s16 -> u16 ===================
    test_array_conversion(
        32'h7FFF8000,  // 32767,-32768 -> 32767,0
        32'h0000FFFF,  // 0,-1 -> 0,0
        32'h7F807F80,  // 32640,32640 -> 32640,32640
        32'h00800080,  // 128,128 -> 128,128
        1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0,
        "s16 -> u16 转换"
    );
    
    // =================== 测试15: u16 -> s16 ===================
    test_array_conversion(
        32'h7FFF8000,  // 32767,32768 -> 32767,32767 (饱和)
        32'hFFFF0001,  // 65535,1 -> 32767,1
        32'h0080007F,  // 128,127 -> 128,127
        32'h7F807F80,  // 32640,32640 -> 32640,32640
        1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0,
        "u16 -> s16 转换"
    );
    
    // =================== 测试16: u16 -> u16 ===================
    test_array_conversion(
        32'h7FFF8000,  // 32767,32768 -> 32767,32768
        32'hFFFF0001,  // 65535,1 -> 65535,1
        32'h0080007F,  // 128,127 -> 128,127
        32'h7F807F80,  // 32640,32640 -> 32640,32640
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
        "u16 -> u16 转换"
    );
    
    // =================== 测试17: 指令无效测试 ===================
    $fdisplay(log_file, "=== 指令无效测试 ===");
    cru_inttoint_in = 7'h0; // 指令无效
    dvr_inttoint_s_in = {32'h00007FFF, 32'hFFFFFF80, 32'h7FFFFFFF, 32'h80000000};
    @(posedge clk);
    #1
    $fdisplay(log_file, "阵列测试: 指令无效");
    $fdisplay(log_file, "  指令无效时输出为0");
    $fdisplay(log_file, "  输出0: 0x%08X, 输出1: 0x%08X", out_reg_0, out_reg_1);
    $fdisplay(log_file, "  输出2: 0x%08X, 输出3: 0x%08X", out_reg_2, out_reg_3);
    $fdisplay(log_file, "");

    // =================== 测试18: 随机测试 ===================
    for (i = 0; i < 10000; i++) begin
        conv_data_0 = $random;
        conv_data_1 = $random;
        conv_data_2 = $random;
        conv_data_3 = $random;
        src_prec    = $random & 1'b1;
        dst_prec    = $random & 1'b1;
        src_signed  = $random & 1'b1;
        dst_signed  = $random & 1'b1;
        src_pos     = $random & 1'b1;
        dst_pos     = $random & 1'b1;

        test_array_conversion(
          conv_data_3[31:0], conv_data_2[31:0], conv_data_1[31:0], conv_data_0[31:0], 
          src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos,
          "随机测试  转换"
        );
    end

    #20 rst_n = 0;
    #20 rst_n = 1;
    // =================== 测试19: 随机测试 ===================
    for (i = 0; i < 10000; i++) begin
        conv_data_0 = $random;
        conv_data_1 = $random;
        conv_data_2 = $random;
        conv_data_3 = $random;
        src_prec    = $random & 1'b1;
        dst_prec    = $random & 1'b1;
        src_signed  = $random & 1'b1;
        dst_signed  = $random & 1'b1;
        src_pos     = $random & 1'b1;
        dst_pos     = $random & 1'b1;

        test_array_conversion(
          conv_data_3[31:0], conv_data_2[31:0], conv_data_1[31:0], conv_data_0[31:0], 
          src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos,
          "随机测试 转换"
        );
    end


    $fdisplay(log_file, "==== SUMMARY ====");
    $fdisplay(log_file, "PASS: %0d / TOTAL: %0d", pass_cnt, total_cnt);
    
    // 测试完成信息
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "INTtoINT 阵列模块测试完成");  
    $fdisplay(log_file, "========================================");
    
    // 关闭日志文件
    $fclose(log_file);
    
    $finish;
end

// 监视输出
initial begin
    $monitor("Time: %t, Output: %h", $time, dr_inttoint_d_out);
end

endmodule