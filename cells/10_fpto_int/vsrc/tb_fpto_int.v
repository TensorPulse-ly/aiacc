`timescale 1ns/1ps
//------------------------------------------------------------------------------
// Filename: tb_fpto_int_array.v
// Author: [Sunny]
// Editor: [Oliver]
// Date: 2025-8-22
// Version: 1.1
// Description: testbench module for fpto_int.v, Modified the Input/Output port. 
//------------------------------------------------------------------------------
//==============================================================================
// 模块名称: tb_fpto_int 
// 测试覆盖: 基础功能、完整边界值、随机测试、DPI-C验证
//==============================================================================

module tb_fpto_int;

// DPI-C函数导入
import "DPI-C" function int dpi_f32_to_i32(input int fp_bits);
import "DPI-C" function shortint dpi_f32_to_i16(input int fp_bits);
import "DPI-C" function int dpi_f16_to_i32(input shortint fp16_bits);
import "DPI-C" function shortint dpi_f16_to_i16(input shortint fp16_bits);

// 接口信号
reg inst_vld, src_prec, dst_prec, src_pos, dst_pos;
reg [31:0] in_reg;
wire [31:0] out_reg;
wire result_vld;

// 测试统计
integer test_count = 0, pass_count = 0, fail_count = 0;

// 日志文件句柄
integer log_file;

// DUT实例化
fpto_int dut (
    .inst_vld(inst_vld), .src_prec(src_prec), .dst_prec(dst_prec),
    .src_pos(src_pos), .dst_pos(dst_pos), 
    .in_reg(in_reg), .out_reg(out_reg), .result_vld(result_vld)
);

//==============================================================================
// 测试数据结构和完整测试向量数组
//==============================================================================

// 测试向量结构: {数据, 控制位[4:0], 中文描述}
// 控制位格式: {src_prec, dst_prec, src_pos, dst_pos, vld}
typedef struct {
    reg [31:0] data;
    reg [4:0] ctrl;
    string desc;
} test_vector_t;

// 测试用例总数 - 合并基础和边界测试
parameter NUM_COMPREHENSIVE_TESTS = 50;
parameter NUM_RANDOM_TESTS = 2000;  // 添加随机测试数量参数

//==============================================================================
// 核心测试任务 
//==============================================================================

task run_single_test(input test_vector_t tv);
    reg [31:0] dpi_result;
    string status;
begin
    test_count++;
    
    // 解析控制信号并应用
    {src_prec, dst_prec, src_pos, dst_pos, inst_vld} = tv.ctrl;
    in_reg = tv.data;
    #1;
    
    // 计算DPI参考结果
    dpi_result = calculate_expected_result(tv.data, src_prec, dst_prec, src_pos, dst_pos);
    
    // 结果检查 - 仅输出到日志文件
    if (out_reg === dpi_result && result_vld === inst_vld) begin
        pass_count++;
        // 控制台输出已禁用
        $fdisplay(log_file, "测试 %3d 通过: %s", test_count, tv.desc);
        $fdisplay(log_file, "  输入: 0x%08h, 输出: 0x%08h, DPI参考: 0x%08h", tv.data, out_reg, dpi_result);
    end else begin
        fail_count++;
        // 控制台输出已禁用
        $fdisplay(log_file, "测试 %3d 失败: %s", test_count, tv.desc);
        $fdisplay(log_file, "  输入: 0x%08h, 控制: %05b", tv.data, tv.ctrl);
        $fdisplay(log_file, "  期望: 0x%08h, 实际: 0x%08h", dpi_result, out_reg);
        $fdisplay(log_file, "  result_vld: %b (期望: %b)", result_vld, inst_vld);
    end
    
    inst_vld = 0; #1;
end
endtask

// 计算预期结果的函数
function [31:0] calculate_expected_result(input [31:0] data, input src_prec, input dst_prec, input src_pos, input dst_pos);
    reg [15:0] fp16_data;
    reg [31:0] fp32_data;
    reg [15:0] int16_result;
    reg [31:0] int32_result;
    reg [15:0] low_fp16, high_fp16;
    reg [15:0] low_int16, high_int16;
begin
    if (src_prec) begin
        // FP32输入
        fp32_data = data;
        if (dst_prec) begin
            // FP32 -> INT32
            calculate_expected_result = dpi_f32_to_i32(fp32_data);
        end else begin
            // 普通FP32->INT16
            int16_result = dpi_f32_to_i16(fp32_data);
            if (dst_pos)
                calculate_expected_result = {int16_result, 16'h0000};
            else
                calculate_expected_result = {16'h0000, int16_result};
        end
    end else begin
        // FP16输入
        fp16_data = src_pos ? data[31:16] : data[15:0];
        low_fp16 = data[15:0];
        high_fp16 = data[31:16];
        if (dst_prec) begin
            // FP16 -> INT32
            calculate_expected_result = dpi_f16_to_i32(fp16_data);
        end else begin
            // FP16 -> INT16
            low_int16 = dpi_f16_to_i16(low_fp16);
            high_int16 = dpi_f16_to_i16(high_fp16);
            calculate_expected_result = {high_int16, low_int16};
        end
    end
end
endfunction

// 获取综合测试用例 (基础+边界)
function test_vector_t get_comprehensive_test(input integer idx);
begin
    case (idx)
        // ========== FP32转换测试 (0-19) ==========
        0: get_comprehensive_test = '{32'h3F800000, 5'b11001, "基础01: FP32(1.0) -> INT32"};
        1: get_comprehensive_test = '{32'hBF800000, 5'b11001, "基础02: FP32(-1.0) -> INT32"};
        2: get_comprehensive_test = '{32'h42F70000, 5'b11001, "基础03: FP32(123.5) -> INT32"};
        3: get_comprehensive_test = '{32'hC3E4CCCD, 5'b11001, "基础04: FP32(-456.8) -> INT32"};
        4: get_comprehensive_test = '{32'h00000000, 5'b11001, "基础05: FP32(0.0) -> INT32"};
        5: get_comprehensive_test = '{32'h7F800000, 5'b11001, "基础06: FP32(+INF) -> INT32"};
        6: get_comprehensive_test = '{32'hFF800000, 5'b11001, "基础07: FP32(-INF) -> INT32"};
        7: get_comprehensive_test = '{32'h7FC00000, 5'b11001, "基础08: FP32(NaN) -> INT32"};
        8: get_comprehensive_test = '{32'h3F800000, 5'b10001, "基础09: FP32(1.0) -> INT16"};
        9: get_comprehensive_test = '{32'h47000000, 5'b10001, "基础10: FP32(32768.0) -> INT16饱和"};
        10: get_comprehensive_test = '{32'hC7000080, 5'b10001, "基础11: FP32(-32769.0) -> INT16饱和"};
        11: get_comprehensive_test = '{32'h3F800000, 5'b10011, "基础12: FP32(1.0) -> INT16高位"};
        12: get_comprehensive_test = '{32'h41200000, 5'b10001, "基础13: FP32(10.0) -> INT16"};
        13: get_comprehensive_test = '{32'hC1200000, 5'b10001, "基础14: FP32(-10.0) -> INT16"};
        14: get_comprehensive_test = '{32'h461C4000, 5'b10001, "基础15: FP32(10000.0) -> INT16"};
        15: get_comprehensive_test = '{32'h4F000000, 5'b10001, "基础16: FP32(2147483648.0) -> INT16饱和"};
        16: get_comprehensive_test = '{32'hCF000000, 5'b10001, "基础17: FP32(-2147483648.0) -> INT16饱和"};
        17: get_comprehensive_test = '{32'h00800000, 5'b11001, "基础18: FP32最小正规格数 -> INT32"};
        18: get_comprehensive_test = '{32'h80800000, 5'b11001, "基础19: FP32最小负规格数 -> INT32"};
        19: get_comprehensive_test = '{32'h007FFFFF, 5'b11001, "基础20: FP32最大非规格数 -> INT32"};
        
        // ========== FP16转换测试 (20-34) ==========
        20: get_comprehensive_test = '{32'h00003C00, 5'b01001, "基础21: FP16(1.0)低位 -> INT32"};
        21: get_comprehensive_test = '{32'h3C000000, 5'b01101, "基础22: FP16(1.0)高位 -> INT32"};
        22: get_comprehensive_test = '{32'h0000C000, 5'b01001, "基础23: FP16(-2.0) -> INT32"};
        23: get_comprehensive_test = '{32'h00004200, 5'b00001, "基础24: FP16(3.0) -> INT16"};
        24: get_comprehensive_test = '{32'h0000C500, 5'b00001, "基础25: FP16(-5.0) -> INT16"};
        25: get_comprehensive_test = '{32'h3C000000, 5'b00011, "基础26: FP16(1.0)高位 -> INT16高位"};
        26: get_comprehensive_test = '{32'h00007C00, 5'b01001, "基础27: FP16(+INF) -> INT32"};
        27: get_comprehensive_test = '{32'h0000FC00, 5'b01001, "基础28: FP16(-INF) -> INT32"};
        28: get_comprehensive_test = '{32'h00007E00, 5'b01001, "基础29: FP16(NaN) -> INT32"};
        29: get_comprehensive_test = '{32'h00000000, 5'b01001, "基础30: FP16(0.0) -> INT32"};
        30: get_comprehensive_test = '{32'h00007BFF, 5'b01001, "基础31: FP16最大值 -> INT32"};
        31: get_comprehensive_test = '{32'h0000FBFF, 5'b01001, "基础32: FP16最小值 -> INT32"};
        32: get_comprehensive_test = '{32'h00000400, 5'b01001, "基础33: FP16最小正规格数 -> INT32"};
        33: get_comprehensive_test = '{32'h00008400, 5'b01001, "基础34: FP16最小负规格数 -> INT32"};
        34: get_comprehensive_test = '{32'h000003FF, 5'b01001, "基础35: FP16最大非规格数 -> INT32"};
        
        // ========== 子字并行测试 (35-44) ==========
        35: get_comprehensive_test = '{32'h40003C00, 5'b00001, "子字01: 并行FP16(2.0,1.0) -> INT16"};
        36: get_comprehensive_test = '{32'h44004200, 5'b00001, "子字02: 并行FP16(4.0,3.0) -> INT16"};
        37: get_comprehensive_test = '{32'hC600C500, 5'b00001, "子字03: 并行FP16(-6.0,-5.0) -> INT16"};
        38: get_comprehensive_test = '{32'h48004700, 5'b00001, "子字04: 并行FP16(8.0,7.0) -> INT16"};
        39: get_comprehensive_test = '{32'h7C003C00, 5'b00001, "子字05: 并行FP16(INF,1.0) -> INT16"};
        40: get_comprehensive_test = '{32'hFC00C000, 5'b00001, "子字06: 并行FP16(-INF,-2.0) -> INT16"};
        41: get_comprehensive_test = '{32'h7E007E00, 5'b00001, "子字07: 并行FP16(NaN,NaN) -> INT16"};
        42: get_comprehensive_test = '{32'h00000000, 5'b00001, "子字08: 并行FP16(0.0,0.0) -> INT16"};
        43: get_comprehensive_test = '{32'h7BFF3C00, 5'b00001, "子字09: 并行FP16(最大,1.0) -> INT16"};
        44: get_comprehensive_test = '{32'hFBFFC000, 5'b00001, "子字10: 并行FP16(最小,-2.0) -> INT16"};
        
        // ========== 边界值测试 (45-49) ==========
        45: get_comprehensive_test = '{32'h46FFFE00, 5'b11001, "边界01: FP32接近INT16上限 -> INT32"};
        46: get_comprehensive_test = '{32'hC7000000, 5'b11001, "边界02: FP32接近INT16下限 -> INT32"};
        47: get_comprehensive_test = '{32'h4EFFFFFF, 5'b11001, "边界03: FP32接近INT32上限 -> INT32"};
        48: get_comprehensive_test = '{32'hCF000000, 5'b11001, "边界04: FP32接近INT32下限 -> INT32"};
        49: get_comprehensive_test = '{32'h33800000, 5'b11001, "边界05: FP32很小的数 -> INT32"};
        
        default: get_comprehensive_test = '{32'h00000000, 5'b00000, "invld"};
    endcase
end
endfunction

// 运行综合测试 (基础+边界) - 仅日志输出
task run_comprehensive_tests();
    integer i;
    test_vector_t tv;
begin
    // 控制台输出已禁用
    $fdisplay(log_file, "\n========================================");
    $fdisplay(log_file, "         综合测试 - 基础功能+边界值测试");
    $fdisplay(log_file, "========================================");
    for (i = 0; i < NUM_COMPREHENSIVE_TESTS; i++) begin
        tv = get_comprehensive_test(i);
        run_single_test(tv);
    end
    // 控制台输出已禁用
    $fdisplay(log_file, "综合测试完成，共 %0d 个测试用例", NUM_COMPREHENSIVE_TESTS);
end
endtask

// 随机测试 - 仅日志输出
task run_random_tests(input integer num_tests);
    integer i;
    test_vector_t rand_tv;
begin
    // 控制台输出已禁用
    $fdisplay(log_file, "\n========================================");
    $fdisplay(log_file, "         随机测试 (%0d 个测试用例)", num_tests);
    $fdisplay(log_file, "========================================");
    
    for (i = 0; i < num_tests; i++) begin
        rand_tv.data = $random;
        rand_tv.ctrl = ($random & 5'b11110) | 5'b00001;  // 确保vld=1
        rand_tv.desc = $sformatf("随机测试%0d", i+1);
        run_single_test(rand_tv);
        
        // 每50个测试显示進度 - 仅日志输出
        if ((i+1) % 50 == 0) begin
            // 控制台输出已禁用
            $fdisplay(log_file, "随机测试进度: %0d/%0d", i+1, num_tests);
        end
    end
    // 控制台输出已禁用
    $fdisplay(log_file, "\n随机测试完成，共执行 %0d 个测试", num_tests);
end
endtask

// 指令无效测试 - 仅日志输出
task test_invld_instruction();
begin
    // 控制台输出已禁用
    $fdisplay(log_file, "\n========================================");
    $fdisplay(log_file, "         指令无效控制测试");
    $fdisplay(log_file, "========================================");
    
    // 先执行一个有效测试作为对比
    test_count++;
    {in_reg, src_prec, dst_prec, src_pos, dst_pos, inst_vld} 
        = {32'h3F800000, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1};
    #1;
    
    if (result_vld === 1'b1) begin
        pass_count++;
        // 控制台输出已禁用
        $fdisplay(log_file, "测试 %3d 通过: 有效指令测试", test_count);
    end else begin
        fail_count++;
        // 控制台输出已禁用
        $fdisplay(log_file, "测试 %3d 失败: 有效指令测试", test_count);
    end
    
    // 测试无效指令
    test_count++;
    {in_reg, src_prec, dst_prec, src_pos, dst_pos, inst_vld} 
        = {32'h3F800000, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
    #1;
    
    if (out_reg === 32'h0000_0000 && result_vld === 1'b0) begin
        pass_count++;
        // 控制台输出已禁用
        $fdisplay(log_file, "测试 %3d 通过: 指令无效时输出为0", test_count);
    end else begin
        fail_count++;
        // 控制台输出已禁用
        $fdisplay(log_file, "测试 %3d 失败: 指令无效时输出应为0", test_count);
        $fdisplay(log_file, "  当前输出: 0x%08h (期望: 0x00000000)", out_reg);
        $fdisplay(log_file, "  result_vld: %b (期望: 0)", result_vld);
    end
end
endtask

// 测试报告 - 仅日志输出
task print_test_summary();
    real pass_rate = (pass_count * 100.0) / test_count;
begin
    // 控制台输出已禁用 - 所有结果仅写入日志文件
    $fdisplay(log_file, "\n");
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "        测试完成统计报告");
    $fdisplay(log_file, "========================================");
    $fdisplay(log_file, "总测试数量: %0d", test_count);
    $fdisplay(log_file, "通过测试: %0d", pass_count);
    $fdisplay(log_file, "失败测试: %0d", fail_count);
    $fdisplay(log_file, "正确率: %.2f%%", pass_rate);
    $fdisplay(log_file, "");
    if (fail_count == 0) begin
        $fdisplay(log_file, "🎉 所有测试通过！设计验证成功！");
    end else begin
        $fdisplay(log_file, "⚠️  存在失败测试，请检查设计实现！");
    end
    $fdisplay(log_file, "详细覆盖率报告请查看VCS生成的coverage_report目录");
    $fdisplay(log_file, "========================================");
    
    // 关闭日志文件
    $fclose(log_file);
end
endtask

//==============================================================================
// 主测试流程 - 完整覆盖版本
//==============================================================================

initial begin
    // 初始化信号
    {in_reg, inst_vld, src_prec, dst_prec, src_pos, dst_pos} = 0;
    #10;
    
    // 打开日志文件
    log_file = $fopen("fpto_int_test.log", "w");
    if (log_file == 0) begin
        $display("错误: 无法创建日志文件 fpto_int_test.log");
        $finish;
    end
    
    $display("==== FPtoINT模块完整验证测试 ====");
    $display("设计: 数据驱动架构,保持完整测试覆盖,DPI-C验证");
    $display("包含: 综合测试(50个)、随机测试(2000个)、指令控制测试");
    $display("日志文件: fpto_int_test.log");
    $display("注意: 详细测试结果仅输出到日志文件");
    
    $fdisplay(log_file, "==== FPtoINT模块完整验证测试 ====");
    $fdisplay(log_file, "设计: 数据驱动架构,保持完整测试覆盖,DPI-C验证");
    $fdisplay(log_file, "包含: 综合测试(50个)、随机测试(2000个)、指令控制测试");
    $fdisplay(log_file, "测试时间: %t", $time);
    
    // 执行所有测试套件
    run_comprehensive_tests();
    run_random_tests(NUM_RANDOM_TESTS);  // 使用参数控制随机测试数量
    test_invld_instruction();
    
    #10;
    print_test_summary();
    $finish;
end

// 波形文件生成
initial begin
    $dumpfile("tb_fpto_int.vcd");
    $dumpvars(0, tb_fpto_int);
end

endmodule
