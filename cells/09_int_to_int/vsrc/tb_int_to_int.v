`timescale 1ns/1ps
//------------------------------------------------------------------------------
// Filename: tb_int_to_int.v
// Author: [Oliver]
// Date: 2025-8-29
// Version: 1.0
// Description: Testbench for int_to_int.v module
//------------------------------------------------------------------------------
//==============================================================================
// 模块名称: tb_int_to_int
// 测试覆盖: 基础功能、边界值、随机测试、指令控制
//==============================================================================

module tb_int_to_int;

// DPI-C函数导入
import "DPI-C" function int dpi_int_to_int_convert(
    input int in_data, input byte src_prec, input byte dst_prec, 
    input byte src_signed, input byte dst_signed, input byte src_pos, input byte dst_pos
);

// 接口信号
reg instr_vld, src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos;
reg [31:0] in_reg;
wire [31:0] out_reg;
wire result_vld;

// 测试统计
integer test_count = 0, pass_count = 0, fail_count = 0;

// 日志文件句柄
integer log_file;

// DUT实例化
int_to_int dut (
    .instr_vld(instr_vld),
    .src_prec(src_prec),
    .dst_prec(dst_prec),
    .src_signed(src_signed),
    .dst_signed(dst_signed),
    .src_pos(src_pos),
    .dst_pos(dst_pos),
    .in_reg(in_reg),
    .out_reg(out_reg),
    .result_vld(result_vld)
);

//==============================================================================
// 测试数据结构和完整测试向量数组
//==============================================================================

// 测试向量结构: {数据, 控制位[6:0], 中文描述}
// 控制位格式: {src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos, vld}
typedef struct {
    reg [31:0] data;
    reg [6:0] ctrl;
    string desc;
} test_vector_t;

// 测试用例总数
parameter NUM_COMPREHENSIVE_TESTS = 40;
parameter NUM_RANDOM_TESTS = 1000;

//==============================================================================
// 核心测试任务 
//==============================================================================

task run_single_test(input test_vector_t tv);
    reg [31:0] dpi_result;
    string status;
begin
    test_count++;
    
    // 解析控制信号并应用
    {src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos, instr_vld} = tv.ctrl;
    in_reg = tv.data;
    #1;
    
    // DPI参考结果
    dpi_result = dpi_int_to_int_convert(tv.data, src_prec, dst_prec, 
                                      src_signed, dst_signed, src_pos, dst_pos);
    
    // 结果检查
    if (out_reg === dpi_result && result_vld === instr_vld) begin
        pass_count++;
        $fdisplay(log_file, "测试 %3d 通过: %s", test_count, tv.desc);
        $fdisplay(log_file, "  输入: 0x%08h, 输出: 0x%08h, DPI参考: 0x%08h", tv.data, out_reg, dpi_result);
    end else begin
        fail_count++;
        $fdisplay(log_file, "测试 %3d 失败: %s", test_count, tv.desc);
        $fdisplay(log_file, "  输入: 0x%08h, 控制: %07b", tv.data, tv.ctrl);
        $fdisplay(log_file, "  期望: 0x%08h, 实际: 0x%08h", dpi_result, out_reg);
        $fdisplay(log_file, "  result_vld: %b (期望: %b)", result_vld, instr_vld);
    end
    
    instr_vld = 0; #1;
end
endtask

// 获取综合测试用例
function test_vector_t get_comprehensive_test(input integer idx);
begin
    case (idx)
        // ========== 32位到32位转换测试 (0-9) ==========
        // 选择依据: 测试有符号/无符号转换的各种边界情况
        0: get_comprehensive_test = '{32'h0000007F, 7'b1111111, "基础01: s32(127) -> s32"};
        1: get_comprehensive_test = '{32'hFFFFFF80, 7'b1111111, "基础02: s32(-128) -> s32"};
        2: get_comprehensive_test = '{32'h0000007F, 7'b1111011, "基础03: s32(127) -> u32"};
        3: get_comprehensive_test = '{32'hFFFFFF80, 7'b1111011, "基础04: s32(-128) -> u32(0)"};
        4: get_comprehensive_test = '{32'h000000FF, 7'b1101111, "基础05: u32(255) -> s32(255)"};
        5: get_comprehensive_test = '{32'h80000000, 7'b1101111, "基础06: u32(2147483648) -> s32(饱和)"};
        6: get_comprehensive_test = '{32'h000000FF, 7'b1100011, "基础07: u32(255) -> u32(255)"};
        7: get_comprehensive_test = '{32'h7FFFFFFF, 7'b1111111, "边界01: s32(2147483647) -> s32"};
        8: get_comprehensive_test = '{32'h80000000, 7'b1111111, "边界02: s32(-2147483648) -> s32"};
        9: get_comprehensive_test = '{32'hFFFFFFFF, 7'b1111011, "边界03: s32(-1) -> u32(0)"};
        
        // ========== 32位到16位转换测试 (10-19) ==========
        // 选择依据: 测试各种溢出和边界情况
        10: get_comprehensive_test = '{32'h00007FFF, 7'b1011111, "基础08: s32(32767) -> s16(32767)"};
        11: get_comprehensive_test = '{32'h00008000, 7'b1011111, "基础09: s32(32768) -> s16(饱和)"};
        12: get_comprehensive_test = '{32'hFFFF8000, 7'b1011111, "基础10: s32(-32768) -> s16(-32768)"};
        13: get_comprehensive_test = '{32'hFFFF7FFF, 7'b1011111, "基础11: s32(-32769) -> s16(饱和)"};
        14: get_comprehensive_test = '{32'h0000FFFF, 7'b1010011, "基础12: s32(65535) -> u16(饱和)"};
        15: get_comprehensive_test = '{32'h0000FFFF, 7'b1001111, "基础13: u32(65535) -> s16(饱和)"};
        16: get_comprehensive_test = '{32'h0000FFFF, 7'b1000011, "基础14: u32(65535) -> u16(65535)"};
        17: get_comprehensive_test = '{32'h00010000, 7'b1000011, "基础15: u32(65536) -> u16(饱和)"};
        18: get_comprehensive_test = '{32'h00007FFF, 7'b1010011, "基础16: s32(32767) -> u16高位"};
        19: get_comprehensive_test = '{32'h00007FFF, 7'b1010001, "基础17: s32(32767) -> u16低位"};
        
        // ========== 16位到32位转换测试 (20-29) ==========
        // 选择依据: 测试符号扩展和零扩展
        20: get_comprehensive_test = '{32'h00007FFF, 7'b0111001, "基础18: s16(32767) -> s32"};
        21: get_comprehensive_test = '{32'h00008000, 7'b0111001, "基础19: s16(-32768) -> s32"};
        22: get_comprehensive_test = '{32'h00007FFF, 7'b0110001, "基础20: s16(32767) -> u32"};
        23: get_comprehensive_test = '{32'h00008000, 7'b0110001, "基础21: s16(-32768) -> u32(0)"};
        24: get_comprehensive_test = '{32'h0000FFFF, 7'b0101001, "基础22: u16(65535) -> s32(饱和)"};
        25: get_comprehensive_test = '{32'h0000FFFF, 7'b0100001, "基础23: u16(65535) -> u32"};
        26: get_comprehensive_test = '{32'h12345678, 7'b0101111, "基础24: 高位u16(4660) -> s32"};
        27: get_comprehensive_test = '{32'h12345678, 7'b0101111, "基础25: 低位u16(22136) -> s32"};
        28: get_comprehensive_test = '{32'h0000FFFE, 7'b0111001, "边界04: s16(-2) -> s32"};
        29: get_comprehensive_test = '{32'h0000007F, 7'b0110001, "边界05: s16(127) -> u32"};
        
        // ========== 16位到16位转换测试 (30-39) ==========
        // 选择依据: 测试子字并行处理
        30: get_comprehensive_test = '{32'h7FFF8000, 7'b0011111, "基础26: s16(32767,-32768) -> s16"};
        31: get_comprehensive_test = '{32'h7FFF8000, 7'b0010011, "基础27: s16(32767,-32768) -> u16"};
        32: get_comprehensive_test = '{32'hFFFF0001, 7'b0001111, "基础28: u16(65535,1) -> s16"};
        33: get_comprehensive_test = '{32'hFFFF0001, 7'b0000011, "基础29: u16(65535,1) -> u16"};
        34: get_comprehensive_test = '{32'h7FFF8000, 7'b0001111, "基础30: u16(32767,32768) -> s16"};
        35: get_comprehensive_test = '{32'h7FFF8000, 7'b0000011, "基础31: u16(32767,32768) -> u16"};
        36: get_comprehensive_test = '{32'h00FF7F80, 7'b0011111, "边界06: s16(255,32640) -> s16"};
        37: get_comprehensive_test = '{32'h0080FF7F, 7'b0010011, "边界07: s16(128,65407) -> u16"};
        38: get_comprehensive_test = '{32'h7FFF7FFF, 7'b0011111, "边界08: s16(32767,32767) -> s16"};
        39: get_comprehensive_test = '{32'h80008000, 7'b0011111, "边界09: s16(-32768,-32768) -> s16"};
        
        default: get_comprehensive_test = '{32'h00000000, 7'b0000000, "invld"};
    endcase
end
endfunction

// 运行综合测试
task run_comprehensive_tests();
    integer i;
    test_vector_t tv;
begin
    $fdisplay(log_file, "\n========================================");
    $fdisplay(log_file, "         综合测试 - 基础功能+边界值测试");
    $fdisplay(log_file, "========================================");
    for (i = 0; i < NUM_COMPREHENSIVE_TESTS; i++) begin
        tv = get_comprehensive_test(i);
        run_single_test(tv);
    end
    $fdisplay(log_file, "综合测试完成，共 %0d 个测试用例", NUM_COMPREHENSIVE_TESTS);
end
endtask

// 随机测试 - 改进的随机数生成
task run_random_tests(input integer num_tests);
    integer i;
    test_vector_t rand_tv;
    reg [31:0] rand_seed = 32'h12345678;
begin
    $fdisplay(log_file, "\n========================================");
    $fdisplay(log_file, "         随机测试 (%0d 个测试用例)", num_tests);
    $fdisplay(log_file, "========================================");
    
    for (i = 0; i < num_tests; i++) begin
        // 使用更好的随机数生成方法
        rand_tv.data = $random(rand_seed);
        
        // 确保控制信号的有效性，避免无效组合
        rand_tv.ctrl[6] = $random & 1'b1; // src_prec
        rand_tv.ctrl[5] = $random & 1'b1; // dst_prec
        rand_tv.ctrl[4] = $random & 1'b1; // src_signed
        rand_tv.ctrl[3] = $random & 1'b1; // dst_signed
        rand_tv.ctrl[2] = $random & 1'b1; // src_pos
        rand_tv.ctrl[1] = $random & 1'b1; // dst_pos
        rand_tv.ctrl[0] = 1'b1;           // vld (总是有效)
        
        rand_tv.desc = $sformatf("随机测试%0d", i+1);
        run_single_test(rand_tv);
        
        // 每50个测试显示进度
        if ((i+1) % 50 == 0) begin
            $fdisplay(log_file, "随机测试进度: %0d/%0d", i+1, num_tests);
        end
    end
    $fdisplay(log_file, "\n随机测试完成，共执行 %0d 个测试", num_tests);
end
endtask

// 指令无效测试
task test_invld_instruction();
begin
    $fdisplay(log_file, "\n========================================");
    $fdisplay(log_file, "         指令无效控制测试");
    $fdisplay(log_file, "========================================");
    
    // 先执行一个有效测试作为对比
    test_count++;
    {in_reg, src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos, instr_vld} 
        = {32'h00007FFF, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1};
    #1;
    
    if (result_vld === 1'b1) begin
        pass_count++;
        $fdisplay(log_file, "测试 %3d 通过: 有效指令测试", test_count);
    end else begin
        fail_count++;
        $fdisplay(log_file, "测试 %3d 失败: 有效指令测试", test_count);
    end
    
    // 测试无效指令
    test_count++;
    {in_reg, src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos, instr_vld} 
        = {32'h00007FFF, 1'b1, 1'b1, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
    #1;
    
    if (out_reg === 32'h00000000 && result_vld === 1'b0) begin
        pass_count++;
        $fdisplay(log_file, "测试 %3d 通过: 指令无效时输出为0", test_count);
    end else begin
        fail_count++;
        $fdisplay(log_file, "测试 %3d 失败: 指令无效时输出应为0", test_count);
        $fdisplay(log_file, "  当前输出: 0x%08h (期望: 0x00007FFF)", out_reg);
        $fdisplay(log_file, "  result_vld: %b (期望: 0)", result_vld);
    end
end
endtask

// 测试报告
task print_test_summary();
    real pass_rate = (pass_count * 100.0) / test_count;
begin
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
    $fdisplay(log_file, "========================================");
    
    // 关闭日志文件
    $fclose(log_file);
end
endtask

//==============================================================================
// 主测试流程
//==============================================================================

initial begin
    // 初始化信号
    {in_reg, instr_vld, src_prec, dst_prec, src_signed, dst_signed, src_pos, dst_pos} = 0;
    #10;
    
    // 打开日志文件
    log_file = $fopen("int_to_int_test.log", "w");
    if (log_file == 0) begin
        $display("错误: 无法创建日志文件 int_to_int_test.log");
        $finish;
    end
    
    $display("==== INTtoINT模块完整验证测试 ====");
    $display("设计: 整数到整数转换模块");
    $display("包含: 综合测试(40个)、随机测试(1000个)、指令控制测试");
    $display("日志文件: int_to_int_test.log");
    
    $fdisplay(log_file, "==== INTtoINT模块完整验证测试 ====");
    $fdisplay(log_file, "设计: 整数到整数转换模块");
    $fdisplay(log_file, "包含: 综合测试(40个)、随机测试(1000个)、指令控制测试");
    $fdisplay(log_file, "测试时间: %t", $time);
    
    // 执行所有测试套件
    run_comprehensive_tests();
    run_random_tests(NUM_RANDOM_TESTS);
    test_invld_instruction();
    
    #10;
    print_test_summary();
    $finish;
end

// 波形文件生成
initial begin
    $dumpfile("tb_int_to_int.vcd");
    $dumpvars(0, tb_int_to_int);
end

endmodule