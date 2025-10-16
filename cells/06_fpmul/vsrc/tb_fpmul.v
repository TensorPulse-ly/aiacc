`timescale 1ns / 1ps

module tb_fpmul;

  //------------------------------------------------------------------
  // 参数定义
  //------------------------------------------------------------------
  parameter CLK_PERIOD = 10;
  parameter TEST_VECTORS_32B = 100000;  // 测试向量数量
  parameter TEST_VECTORS_16B = 100000;  // 测试向量数量
  parameter TEST_SPECIAL_CASES = 20000; // 特殊值测试数量

  //------------------------------------------------------------------
  // 测试平台信号
  //------------------------------------------------------------------
  reg clk;
  reg rst_n;
  reg [127:0] dvr_fpmul_s0;
  reg [127:0] dvr_fpmul_s1;
  reg [2:0]   cru_fpmul;
  wire [127:0] dr_fpmul_d;

  integer pass_count;
  integer fail_count;
  integer total_tests;

  import "DPI-C" function int unsigned dpi_f32_mul(input int unsigned a, input int unsigned b);
  import "DPI-C" function shortint unsigned dpi_f16_mul(input shortint unsigned a, input shortint unsigned b);
    
  // 舍入模式和异常标志相关DPI函数
  import "DPI-C" function void dpi_set_rounding_mode(input int unsigned mode);
  import "DPI-C" function int unsigned dpi_get_rounding_mode();
  import "DPI-C" function void dpi_clear_exception_flags();
  import "DPI-C" function int unsigned dpi_get_exception_flags();


  initial begin
    $fsdbDumpfile("fpmul.fsdb");
    $fsdbDumpvars(0, dut);
  end
  //------------------------------------------------------------------
  // NaN检测函数
  //------------------------------------------------------------------
  function is_f32_nan;
    input [31:0] f32_val;
    begin
      is_f32_nan = (f32_val[30:23] == 8'hFF) && (f32_val[22:0] != 23'h0);
    end
  endfunction

  function is_f16_nan;
    input [15:0] f16_val;
    begin
      is_f16_nan = (f16_val[14:10] == 5'h1F) && (f16_val[9:0] != 10'h0);
    end
  endfunction

  //------------------------------------------------------------------
  // 特殊浮点数值生成函数
  //------------------------------------------------------------------
  function [31:0] gen_special_f32;
    input [3:0] type_sel;  
    begin
      case (type_sel)
        4'b0000: gen_special_f32 = 32'h00000000; // +0.0 (正零)
        4'b0001: gen_special_f32 = 32'h80000000; // -0.0 (负零)
        4'b0010: gen_special_f32 = 32'h7F800000; // +Inf (正无穷)
        4'b0011: gen_special_f32 = 32'hFF800000; // -Inf (负无穷)
        4'b0100: gen_special_f32 = 32'h7FC00000; // qNaN (静默NaN)
        4'b0101: gen_special_f32 = 32'h7F800001; // sNaN (信号NaN)
        4'b0110: gen_special_f32 = 32'h00800000; // 最小正规格化数 (2^-126)
        4'b0111: gen_special_f32 = 32'h7F7FFFFF; // 最大正规格化数
        4'b1000: gen_special_f32 = 32'h00000001; // 最小非规格化数
        4'b1001: gen_special_f32 = 32'h007FFFFF; // 最大非规格化数
        4'b1010: gen_special_f32 = 32'h80000001; // 最小负非规格化数
        4'b1011: gen_special_f32 = 32'h807FFFFF; // 最大负非规格化数
        4'b1100: gen_special_f32 = 32'h3F800000; // 1.0
        4'b1101: gen_special_f32 = 32'hBF800000; // -1.0
        4'b1110: gen_special_f32 = 32'h40000000; // 2.0
        4'b1111: gen_special_f32 = 32'hC0000000; // -2.0
      endcase
    end
  endfunction

  function [15:0] gen_special_f16;
    input [3:0] type_sel;  
    begin
      case (type_sel)
        4'b0000: gen_special_f16 = 16'h0000; // +0.0 (正零)
        4'b0001: gen_special_f16 = 16'h8000; // -0.0 (负零)
        4'b0010: gen_special_f16 = 16'h7C00; // +Inf (正无穷)
        4'b0011: gen_special_f16 = 16'hFC00; // -Inf (负无穷)
        4'b0100: gen_special_f16 = 16'h7E00; // qNaN (静默NaN)
        4'b0101: gen_special_f16 = 16'h7C01; // sNaN (信号NaN)
        4'b0110: gen_special_f16 = 16'h0400; // 最小正规格化数 (2^-14)
        4'b0111: gen_special_f16 = 16'h7BFF; // 最大正规格化数
        4'b1000: gen_special_f16 = 16'h0001; // 最小非规格化数
        4'b1001: gen_special_f16 = 16'h03FF; // 最大非规格化数
        4'b1010: gen_special_f16 = 16'h8001; // 最小负非规格化数
        4'b1011: gen_special_f16 = 16'h83FF; // 最大负非规格化数
        4'b1100: gen_special_f16 = 16'h3C00; // 1.0
        4'b1101: gen_special_f16 = 16'hBC00; // -1.0
        4'b1110: gen_special_f16 = 16'h4000; // 2.0
        4'b1111: gen_special_f16 = 16'hC000; // -2.0
      endcase
    end
  endfunction

  //------------------------------------------------------------------
  // 实例化被测设计(DUT)
  //------------------------------------------------------------------
  fpmul dut (
    .clk(clk),
    .rst_n(rst_n),
    .dvr_fpmul_s0(dvr_fpmul_s0),
    .dvr_fpmul_s1(dvr_fpmul_s1),
    .cru_fpmul(cru_fpmul),
    .dr_fpmul_d(dr_fpmul_d)
  );

  //------------------------------------------------------------------
  // 时钟和复位生成
  //------------------------------------------------------------------
  initial begin
    clk = 0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  task apply_reset;
    begin
      rst_n = 1'b0;
      @(posedge clk);
      rst_n = 1'b1;
      $display("信息: 系统复位已应用。");
    end
  endtask

  task reset_toggle;
    begin
      rst_n = 1'b0;
      @(posedge clk);
      rst_n = 1'b1;
      $display("信息: 系统复位已切换。");
    end
  endtask

  // 任务: 测试4路并行32位乘法
  task test_mode_32bit;
    reg [127:0] expected_result;
    reg [127:0] s0_stim, s1_stim;
    reg [31:0] exp32, act32;
    reg lane_ok;
    integer i, lane;
    begin
      $display("\n信息: 开始32位模式测试 (%0d个向量)...", TEST_VECTORS_32B);
            
      // 设置微指令为32位模式
      cru_fpmul = 3'b111; // inst_valid=1, src_prec=32b, dst_prec=32b

      for (i = 0; i < TEST_VECTORS_32B; i = i + 1) begin
        // 生成随机输入并存储
        s0_stim = {$random, $random, $random, $random};
        s1_stim = {$random, $random, $random, $random};

        // 应用输入到DUT
        dvr_fpmul_s0 = s0_stim;
        dvr_fpmul_s1 = s1_stim;
                
        // 使用DPI-C计算每个通道的预期结果
        expected_result[31:0]   = dpi_f32_mul(s0_stim[31:0],   s1_stim[31:0]);
        expected_result[63:32]  = dpi_f32_mul(s0_stim[63:32],  s1_stim[63:32]);
        expected_result[95:64]  = dpi_f32_mul(s0_stim[95:64],  s1_stim[95:64]);
        expected_result[127:96] = dpi_f32_mul(s0_stim[127:96], s1_stim[127:96]);
                
        // 等待一个时钟周期让DUT注册结果
        @(posedge clk);
        #1; 
                
        lane_ok = 1'b1;
                
        // 逐个通道检查并显示详细结果
        for (lane = 0; lane < 4; lane = lane + 1) begin
          exp32 = expected_result[lane*32 +: 32];
          act32 = dr_fpmul_d[lane*32 +: 32];
                    
          // 检查预期和实际是否都是NaN
          if (is_f32_nan(exp32) && is_f32_nan(act32)) begin
            // 两者都是NaN，通过
            $display("FP32测试 %0d 通道 %0d: A=%h, B=%h, 预期=%h(NaN), 实际=%h(NaN) 通过(均为NaN)", 
              i, lane, 
              s0_stim[lane*32 +: 32], 
              s1_stim[lane*32 +: 32], 
              exp32, act32);
          end else begin
            // 精确比较
            // 显示单个通道结果
            $display("FP32测试 %0d 通道 %0d: A=%h, B=%h, 预期=%h, 实际=%h %s", 
              i, lane, 
              s0_stim[lane*32 +: 32], 
              s1_stim[lane*32 +: 32], 
              exp32, act32,
              (exp32 === act32) ? "通过" : "失败");
                        
            if (exp32 !== act32) lane_ok = 1'b0;
          end
        end

        total_tests = total_tests + 1;
        if (lane_ok) begin
          pass_count = pass_count + 1;
        end else begin
          fail_count = fail_count + 1;
          $display("错误: 失败 [32位测试 %0d]: 一个或多个通道失败!", i);
        end
      end
      $display("信息: 32位模式测试完成。");
    end
  endtask

  // 任务: 测试8路并行16位乘法
  task test_mode_16bit;
    reg [127:0] expected_result;
    reg [127:0] s0_stim, s1_stim;
    reg [15:0] exp16, act16;
    reg lane_ok;
    integer i, j;
    begin
      $display("\n信息: 开始16位模式测试 (%0d个向量)...", TEST_VECTORS_16B);
            
      // 设置微指令为16位模式
      cru_fpmul = 3'b100; // inst_valid=1, src_prec=16b, dst_prec=16b
            
      for (i = 0; i < TEST_VECTORS_16B; i = i + 1) begin
        // 生成随机输入并存储
        for (j = 0; j < 8; j = j + 1) begin
          s0_stim[j*16 +: 16] = $random;
          s1_stim[j*16 +: 16] = $random;
        end

        // 应用输入到DUT
        dvr_fpmul_s0 = s0_stim;
        dvr_fpmul_s1 = s1_stim;

        // 使用DPI-C计算8个子字的预期结果
        for (j = 0; j < 8; j = j + 1) begin
          expected_result[j*16 +: 16] = dpi_f16_mul(s0_stim[j*16 +: 16], s1_stim[j*16 +: 16]);
        end

        // 等待一个时钟周期让DUT注册结果
        @(posedge clk);
        #1; // 添加小延迟以避免竞争条件
                
        lane_ok = 1'b1;
        for (j = 0; j < 8; j = j + 1) begin
          exp16 = expected_result[j*16 +: 16];
          act16 = dr_fpmul_d[j*16 +: 16];
                    
          // 检查预期和实际是否都是NaN
          if (is_f16_nan(exp16) && is_f16_nan(act16)) begin
            // 两者都是NaN，通过
            $display("FP16测试 %0d 通道 %0d: A=%h, B=%h, 预期=%h(NaN), 实际=%h(NaN) 通过(均为NaN)", 
              i, j, 
              s0_stim[j*16 +: 16], 
              s1_stim[j*16 +: 16], 
              exp16, act16);
          end else begin
            // 精确比较
            $display("FP16测试 %0d 通道 %0d: A=%h, B=%h, 预期=%h, 实际=%h %s", 
              i, j, 
              s0_stim[j*16 +: 16], 
              s1_stim[j*16 +: 16], 
              exp16, act16,
              (exp16 === act16) ? "通过" : "失败");
                        
            if (exp16 !== act16) lane_ok = 1'b0;
          end
        end

        total_tests = total_tests + 1;
        if (lane_ok) begin
          pass_count = pass_count + 1;
        end else begin
          fail_count = fail_count + 1;
          $display("错误: 失败 [16位测试 %0d]: 一个或多个通道失败!", i);
        end
      end
      $display("信息: 16位模式测试完成。");
    end
  endtask

  // 任务: 测试特殊值情况
  task test_special_cases;
    reg [127:0] expected_result;
    reg [127:0] s0_stim, s1_stim;
    reg [31:0] exp32, act32;
    reg [15:0] exp16, act16;
    reg lane_ok;
    integer i, j;
    reg [3:0] type_sel0, type_sel1;  
    begin
      $display("\n信息: 开始特殊值测试 (%0d个向量)...", TEST_SPECIAL_CASES);
            
      // 测试32位特殊值
      $display("信息: 测试32位特殊值...");
      cru_fpmul = 3'b111; // 32位模式
            
      for (i = 0; i < TEST_SPECIAL_CASES; i = i + 1) begin
        // 生成特殊值输入
        for (j = 0; j < 4; j = j + 1) begin
          type_sel0 = $random % 16;  
          type_sel1 = $random % 16;
          s0_stim[j*32 +: 32] = gen_special_f32(type_sel0);
          s1_stim[j*32 +: 32] = gen_special_f32(type_sel1);
        end

        // 应用输入到DUT
        dvr_fpmul_s0 = s0_stim;
        dvr_fpmul_s1 = s1_stim;
                
        // 使用DPI-C计算预期结果
        expected_result[31:0]   = dpi_f32_mul(s0_stim[31:0],   s1_stim[31:0]);
        expected_result[63:32]  = dpi_f32_mul(s0_stim[63:32],  s1_stim[63:32]);
        expected_result[95:64]  = dpi_f32_mul(s0_stim[95:64],  s1_stim[95:64]);
        expected_result[127:96] = dpi_f32_mul(s0_stim[127:96], s1_stim[127:96]);
                
        // 等待一个时钟周期
        @(posedge clk);
        #1;

        // 比较结果
        lane_ok = 1'b1;
        for (j = 0; j < 4; j = j + 1) begin
          exp32 = expected_result[j*32 +: 32];
          act32 = dr_fpmul_d[j*32 +: 32];
                    
          if (is_f32_nan(exp32) && is_f32_nan(act32)) begin
            // 两者都是NaN，通过
            $display("FP32特殊测试 %0d 通道 %0d: A=%h, B=%h, 预期=NaN, 实际=NaN 通过", 
              i, j, 
              s0_stim[j*32 +: 32], 
              s1_stim[j*32 +: 32]);
          end else begin
            $display("FP32特殊测试 %0d 通道 %0d: A=%h, B=%h, 预期=%h, 实际=%h %s", 
              i, j, 
              s0_stim[j*32 +: 32], 
              s1_stim[j*32 +: 32], 
              exp32, act32,
              (exp32 === act32) ? "通过" : "失败");
                        
            if (exp32 !== act32) lane_ok = 1'b0;
          end
        end

        total_tests = total_tests + 1;
        if (lane_ok) begin
          pass_count = pass_count + 1;
        end else begin
          fail_count = fail_count + 1;
          $display("错误: 失败 [32位特殊测试 %0d]: 一个或多个通道失败!", i);
        end
      end

      // 测试16位特殊值
      $display("信息: 测试16位特殊值...");
      cru_fpmul = 3'b100; // 16位模式
            
      for (i = 0; i < TEST_SPECIAL_CASES; i = i + 1) begin
        // 生成特殊值输入
        for (j = 0; j < 8; j = j + 1) begin
          type_sel0 = $random % 4;
          type_sel1 = $random % 4;
          s0_stim[j*16 +: 16] = gen_special_f16(type_sel0);
          s1_stim[j*16 +: 16] = gen_special_f16(type_sel1);
        end

        // 应用输入到DUT
        dvr_fpmul_s0 = s0_stim;
        dvr_fpmul_s1 = s1_stim;
                
        // 使用DPI-C计算预期结果
        for (j = 0; j < 8; j = j + 1) begin
          expected_result[j*16 +: 16] = dpi_f16_mul(s0_stim[j*16 +: 16], s1_stim[j*16 +: 16]);
        end
                
        @(posedge clk);
        #1;

        // 比较结果
        lane_ok = 1'b1;
        for (j = 0; j < 8; j = j + 1) begin
          exp16 = expected_result[j*16 +: 16];
          act16 = dr_fpmul_d[j*16 +: 16];
                    
          if (is_f16_nan(exp16) && is_f16_nan(act16)) begin
            // 两者都是NaN，通过
            $display("FP16特殊测试 %0d 通道 %0d: A=%h, B=%h, 预期=NaN, 实际=NaN 通过", 
              i, j, 
              s0_stim[j*16 +: 16], 
              s1_stim[j*16 +: 16]);
          end else begin
            $display("FP16特殊测试 %0d 通道 %0d: A=%h, B=%h, 预期=%h, 实际=%h %s", 
              i, j, 
              s0_stim[j*16 +: 16], 
              s1_stim[j*16 +: 16], 
              exp16, act16,
              (exp16 === act16) ? "通过" : "失败");
                        
            if (exp16 !== act16) lane_ok = 1'b0;
          end
        end

        total_tests = total_tests + 1;
        if (lane_ok) begin
          pass_count = pass_count + 1;
        end else begin
          fail_count = fail_count + 1;
          $display("错误: 失败 [16位特殊测试 %0d]: 一个或多个通道失败!", i);
        end
      end
      $display("信息: 特殊值测试完成。");
    end
  endtask

// 任务: 指令测试
task test_invalid_instruction;
  reg [127:0] value_valid_before; 
  reg [127:0] value_valid_after;  
  begin
    $display("\n信息: 开始无效指令测试 + cru_fpmul[2]翻转覆盖...");
        

    cru_fpmul = 3'b111; 
    dvr_fpmul_s0 = 128'h3f800000_40000000_40400000_40800000; // [1.0, 2.0, 3.0, 4.0]
    dvr_fpmul_s1 = 128'h3f800000_40000000_40400000_40800000;
    @(posedge clk); 
    #1;
    value_valid_before = dr_fpmul_d;
    $display("阶段0: 有效指令基准值 = 0x%h", value_valid_before);

    cru_fpmul = 3'b011; 
    dvr_fpmul_s0 = 128'hDEADBEEF_CAFEBABE_12345678_87654321; 
    dvr_fpmul_s1 = 128'hFFFFFFFF_EEEEEEEE_DDDDDDDD_CCCCCCCC;
    @(posedge clk); 
    #1;

    total_tests = total_tests + 1;
    if (dr_fpmul_d === value_valid_before) begin
      pass_count = pass_count + 1;
      $display("阶段1: 通过 - 无效指令时输出保持基准值 0x%h", dr_fpmul_d);
    end else begin
      fail_count = fail_count + 1;
      $display("阶段1: 失败 - 无效指令时输出意外改变！实际=0x%h, 预期=0x%h", dr_fpmul_d, value_valid_before);
    end

    $display("信息: 翻转 cru_fpmul[2] 从 0 -> 1(无效→有效)...");
    cru_fpmul = 3'b111; 
    dvr_fpmul_s0 = 128'h3f800000_40800000_40400000_40800000; // 新的有效输入 [1.0,4.0,3.0,4.0]
    dvr_fpmul_s1 = 128'h3f800000_40800000_40400000_40800000;
    @(posedge clk); 
    #1;
    value_valid_after = dr_fpmul_d; 

    total_tests = total_tests + 1;
    if (value_valid_after !== value_valid_before) begin
      pass_count = pass_count + 1;
      $display("阶段2: 通过 - cru_fpmul[2]翻转后，有效指令输出更新为 0x%h", value_valid_after);
    end else begin
      fail_count = fail_count + 1;
      $display("阶段2: 失败 - cru_fpmul[2]翻转后，有效指令输出未更新！仍为 0x%h", value_valid_after);
    end

    $display("信息: 无效指令测试 + cru_fpmul[2]翻转覆盖完成。");
  end
endtask



  initial begin
    $display("========================================");
    $display(" FPMUL测试平台启动 ");
    $display("========================================");

    // 设置SoftFloat舍入模式为向最近偶数舍入
    dpi_set_rounding_mode(32'h0);  // softfloat_round_near_even = 0
    dpi_clear_exception_flags();
    $display("信息: 当前舍入模式码: %0d", dpi_get_rounding_mode());

    pass_count = 0;
    fail_count = 0;
    total_tests = 0;

    apply_reset();
        
    // 运行测试序列
    test_mode_32bit();
    test_mode_16bit();
    test_special_cases();
    test_invalid_instruction();
    reset_toggle();

    // 打印最终摘要
    $display("========================================");
    $display(" 测试摘要:");
    $display("   总测试数: %0d", total_tests);
    $display("   通过测试: %0d", pass_count);
    $display("   失败测试: %0d", fail_count);
    if (fail_count == 0) begin
      $display("   结果: 所有测试通过");
    end else begin
      $display("   结果: 有测试失败");
    end
    $display("========================================");

    $finish;
  end

endmodule

