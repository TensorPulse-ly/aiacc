`timescale 1ns/1ps

module tb_fpadd;

    // 时钟复位
    reg        clk = 0;
    always #5 clk = ~clk;
    reg        rst_n = 0;

    // 128-bit 接口
    reg  [127:0] dvr_fpadd_s0;
    reg  [127:0] dvr_fpadd_s1;
    reg  [3:0]   cru_fpadd; // 微指令
    wire [127:0] dr_fpadd_d;
    wire [127:0] dr_fpadd_st;   // 状态寄存器

    // DPI-C（保留原软浮点接口，用于计算预期值）
    import "DPI-C" function void  set_softfloat_rounding_mode(input int mode);
    import "DPI-C" function shortint fp16_add_softfloat(input shortint a,b);
    import "DPI-C" function int     fp32_add_softfloat(input int a,b);
    import "DPI-C" function real    fp16_to_real(input shortint a);
    import "DPI-C" function real    fp32_to_real(input int a);

    // DUT 实例（端口宽度匹配）
    fpadd uut (
        .clk(clk), .rst_n(rst_n),
        .dvr_fpadd_s0(dvr_fpadd_s0), .dvr_fpadd_s1(dvr_fpadd_s1),
        .dr_fpadd_d(dr_fpadd_d),
        .dr_fpadd_st(dr_fpadd_st),   
        .cru_fpadd(cru_fpadd)
    );

    // 日志与计数器（新增mediume统计1ulp误差）
    integer log;
    integer pass = 0, fail = 0, mediume = 0;

    // 常量（保留原定义）
    `define FP16_ZERO   16'h0000
    `define FP16_ONE    16'h3C00
    `define FP16_NEGONE 16'hBC00
    `define FP16_INF    16'h7C00
    `define FP16_NAN    16'h7E00
    `define FP16_MAX    16'h7BFF

    `define FP32_ZERO   32'h00000000
    `define FP32_ONE    32'h3F800000
    `define FP32_NEGONE 32'hBF800000
    `define FP32_INF    32'h7F800000
    `define FP32_NAN    32'h7FC00000
    `define FP32_MAX    32'h7F7FFFFF

    `define FP16_TWO    16'h4000  
    `define FP32_TWO    32'h40000000  

    // --------------------------
    // 新增：ULP计算核心函数（将浮点数转为线性整数，相邻浮点数对应相邻整数）
    // --------------------------
    // FP16转线性整数（用于计算ULP差）
    function int fp16_to_linear(input [15:0] v);
        reg sign;
        reg [4:0] exp;
        reg [9:0] frac;
        reg [15:0] abs_v;
        reg [15:0] neg_abs_linear;
    begin
        sign = v[15];
        exp = v[14:10];
        frac = v[9:0];
        abs_v = {1'b0, exp, frac}; // 提取绝对值的指数+尾数（符号位清0）

        // 负数处理：补码转负整数，确保数值越小（越负）线性值越小
        if (sign) begin
            neg_abs_linear = ~abs_v + 1'b1; // 绝对值的补码（对应负数数值）
            fp16_to_linear = - ( {1'b0, neg_abs_linear} ); // 转为负线性值
        end else begin
            fp16_to_linear = {1'b0, abs_v}; // 正数直接用绝对值线性值
        end
    end
    endfunction

    // 计算两个FP16的ULP差
    function int fp16_ulp_diff(input [15:0] a, input [15:0] b);
    begin
        fp16_ulp_diff = $abs(fp16_to_linear(a) - fp16_to_linear(b));
    end
    endfunction

    // FP32转线性整数（用于计算ULP差）
    function int fp32_to_linear(input [31:0] v);
        reg sign;
        reg [7:0] exp;
        reg [22:0] frac;
        reg [31:0] abs_v;
        reg [31:0] neg_abs_linear;
    begin
        sign = v[31];
        exp = v[30:23];
        frac = v[22:0];
        abs_v = {1'b0, exp, frac}; // 提取绝对值的指数+尾数（符号位清0）

        // 负数处理：补码转负整数，确保数值越小（越负）线性值越小
        if (sign) begin
            neg_abs_linear = ~abs_v + 1'b1; // 绝对值的补码（对应负数数值）
            fp32_to_linear = - ( {1'b0, neg_abs_linear} ); // 转为负线性值
        end else begin
            fp32_to_linear = {1'b0, abs_v}; // 正数直接用绝对值线性值
        end
    end
    endfunction

    // 计算两个FP32的ULP差
    function int fp32_ulp_diff(input [31:0] a, input [31:0] b);
    begin
        fp32_ulp_diff = $abs(fp32_to_linear(a) - fp32_to_linear(b));
    end
    endfunction

    // 特殊值判断函数（保留原逻辑）
    function isnan16; input [15:0] v; isnan16 = (v[14:10]==5'h1F && (v[9:0]!=0)); endfunction
    function isnan32; input [31:0] v; isnan32 = (v[30:23]==8'hFF && (v[22:0]!=0)); endfunction
    function isinf16; input [15:0] v; isinf16 = (v[14:10]==5'h1F && (v[9:0]==0)); endfunction
    function isinf32; input [31:0] v; isinf32 = (v[30:23]==8'hFF && (v[22:0]==0)); endfunction
    function iszero16; input [15:0] v; iszero16 = (v[14:0]==15'h0000); endfunction
    function iszero32; input [31:0] v; iszero32 = (v[30:0]==31'h00000000); endfunction

    // --------------------------
    // 核心修改：execute_test任务（支持1ulp误差判断）
    // --------------------------
    task automatic execute_test;
        input string  desc;
        input         mode; // 0=8×FP16，1=4×FP32
        input [127:0] a;    // 输入A
        input [127:0] b;    // 输入B
        reg   [127:0] exp;  // 预期结果（软浮点计算）
        reg   [127:0] act;  // 实际结果（DUT输出）
        integer       i, j;
        // 新增：结果分类标志（替代原is_match）
        reg has_pass;    // 所有子字完全匹配
        reg has_mediume;  // 存在1ulp误差，无>1ulp误差
        reg has_big_error; // 存在>1ulp误差或特殊值不匹配
        real          val[0:7];  // 用于打印数值
    begin
        // 初始化结果标志
        has_pass = 1'b1;
        has_mediume = 1'b0;
        has_big_error = 1'b0;

        // 第一步：用SoftFloat计算预期值（逻辑不变）
        exp = 128'h0;
        if (mode == 0) begin // 8×FP16
            for (i = 0; i < 8; i = i + 1)
                exp[16*i +:16] = fp16_add_softfloat(a[16*i +:16], b[16*i +:16]);
        end else begin // 4×FP32
            for (i = 0; i < 4; i = i + 1)
                exp[32*i +:32] = fp32_add_softfloat(a[32*i +:32], b[32*i +:32]);
        end

        // 第二步：驱动DUT（逻辑不变）
        dvr_fpadd_s0 = a;
        dvr_fpadd_s1 = b;
        cru_fpadd = {1'b1, mode, mode, 1'b1}; // 微指令：有效+源目精度一致+更新状态
        @(posedge clk) #1;
        cru_fpadd = 4'b1000; // 清除微指令
        wait(uut.current_state == uut.STATE_IDLE); // 等待DUT回到空闲
        @(posedge clk);
        act = dr_fpadd_d;

        // 第三步：打印测试信息（格式不变）
        $display("\n测试: %s", desc);

        $write("A=%h (", a);
        if (mode == 0) begin
            for (j = 7; j >= 0; j = j - 1) begin
                val[j] = fp16_to_real(a[16*j +:16]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end else begin
            for (j = 3; j >= 0; j = j - 1) begin
                val[j] = fp32_to_real(a[32*j +:32]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end
        $write(")\n");

        $write("B=%h (", b);
        if (mode == 0) begin
            for (j = 7; j >= 0; j = j - 1) begin
                val[j] = fp16_to_real(b[16*j +:16]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end else begin
            for (j = 3; j >= 0; j = j - 1) begin
                val[j] = fp32_to_real(b[32*j +:32]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end
        $write(")\n");

        $write("预期:%h (", exp);
        if (mode == 0) begin
            for (j = 7; j >= 0; j = j - 1) begin
                val[j] = fp16_to_real(exp[16*j +:16]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end else begin
            for (j = 3; j >= 0; j = j - 1) begin
                val[j] = fp32_to_real(exp[32*j +:32]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end
        $write(")\n");

        $write("实际:%h (", act);
        if (mode == 0) begin
            for (j = 7; j >= 0; j = j - 1) begin
                val[j] = fp16_to_real(act[16*j +:16]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end else begin
            for (j = 3; j >= 0; j = j - 1) begin
                val[j] = fp32_to_real(act[32*j +:32]);
                $write("%0.8f%s", val[j], j == 0 ? "" : ", ");
            end
        end
        $write(")\n");

        $write("状态:%h (", dr_fpadd_st);
        if (mode == 0) begin
            for (j = 7; j >= 0; j = j - 1)
                $write("%3b%s", dr_fpadd_st[16*j +: 3], j == 0 ? "" : ",");
        end else begin
            for (j = 3; j >= 0; j = j - 1)
                $write("%3b%s", dr_fpadd_st[32*j +: 3], j == 0 ? "" : ",");
        end
        $write(")\n");

        // --------------------------
        // 核心修改：子字匹配判断（分3类结果）
        // --------------------------
        if (mode == 0) begin // 8×FP16：逐子字判断
            for (i = 0; i < 8; i = i + 1) begin
                reg [15:0] exp_sub = exp[16*i +:16];
                reg [15:0] act_sub = act[16*i +:16];
                reg sub_match;

                if (isnan16(exp_sub)) begin
                    // 特殊值1：预期NaN → 实际必须是NaN（否则>1ulp误差）
                    sub_match = isnan16(act_sub);
                    if (!sub_match) begin
                        has_big_error = 1'b1;
                        $display("  子字[%0d]不匹配（预期NaN，实际非NaN）：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end
                end else if (isinf16(exp_sub)) begin
                    // 特殊值2：预期Inf → 实际必须是同符号Inf（否则>1ulp误差）
                    sub_match = (isinf16(act_sub) && (exp_sub[15] == act_sub[15]));
                    if (!sub_match) begin
                        has_big_error = 1'b1;
                        $display("  子字[%0d]不匹配（预期Inf，实际非Inf或符号不同）：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end
                end else if (iszero16(exp_sub)) begin
                    // 特殊值3：预期零 → 实际必须是零（否则>1ulp误差）
                    sub_match = iszero16(act_sub);
                    if (!sub_match) begin
                        has_big_error = 1'b1;
                        $display("  子字[%0d]不匹配（预期零，实际非零）：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end
                end else begin
                    // 普通值：计算ULP差，分3类
                    int ulp_diff = fp16_ulp_diff(exp_sub, act_sub);
                    if (ulp_diff == 0) begin
                        sub_match = 1'b1; // 完全匹配
                    end else if (ulp_diff == 1) begin
                        sub_match = 1'b0;
                        has_mediume = 1'b1; // 1ulp误差
                        $display("  子字[%0d]1ulp误差：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end else begin
                        sub_match = 1'b0;
                        has_big_error = 1'b1; // >1ulp误差
                        $display("  子字[%0d]误差>1ulp：预期=0x%h，实际=0x%h，ULP差=%0d", i, exp_sub, act_sub, ulp_diff);
                    end
                end

                // 只要有一个子字不匹配，整体就不是完全pass
                if (!sub_match) begin
                    has_pass = 1'b0;
                end
            end
        end else begin // 4×FP32：逐子字判断
            for (i = 0; i < 4; i = i + 1) begin
                reg [31:0] exp_sub = exp[32*i +:32];
                reg [31:0] act_sub = act[32*i +:32];
                reg sub_match;

                if (isnan32(exp_sub)) begin
                    sub_match = isnan32(act_sub);
                    if (!sub_match) begin
                        has_big_error = 1'b1;
                        $display("  子字[%0d]不匹配（预期NaN，实际非NaN）：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end
                end else if (isinf32(exp_sub)) begin
                    sub_match = (isinf32(act_sub) && (exp_sub[31] == act_sub[31]));
                    if (!sub_match) begin
                        has_big_error = 1'b1;
                        $display("  子字[%0d]不匹配（预期Inf，实际非Inf或符号不同）：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end
                end else if (iszero32(exp_sub)) begin
                    sub_match = iszero32(act_sub);
                    if (!sub_match) begin
                        has_big_error = 1'b1;
                        $display("  子字[%0d]不匹配（预期零，实际非零）：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end
                end else begin
                    int ulp_diff = fp32_ulp_diff(exp_sub, act_sub);
                    if (ulp_diff == 0) begin
                        sub_match = 1'b1;
                    end else if (ulp_diff == 1) begin
                        sub_match = 1'b0;
                        has_mediume = 1'b1;
                        $display("  子字[%0d]1ulp误差：预期=0x%h，实际=0x%h", i, exp_sub, act_sub);
                    end else begin
                        sub_match = 1'b0;
                        has_big_error = 1'b1;
                        $display("  子字[%0d]误差>1ulp：预期=0x%h，实际=0x%h，ULP差=%0d", i, exp_sub, act_sub, ulp_diff);
                    end
                end

                if (!sub_match) begin
                    has_pass = 1'b0;
                end
            end
        end

        // --------------------------
        // 最终结果分类计数
        // --------------------------
        if (has_big_error) begin
            $display("结果:失败(存在>1ulp误差)");
            fail = fail + 1;
        end else if (has_mediume) begin
            $display("结果:中等(仅1ulp误差)");
            mediume = mediume + 1;
        end else begin
            $display("结果:通过(值完全匹配)");
            pass = pass + 1;
        end
    end
    endtask

    // tb_fp_adder.v 修复后：用 force 驱动 wire 类型的 mode_flag
    task test_default_with_z_x;
            reg [127:0] test_src0, test_src1;  
            reg [1:0] test_mode_type[0:1];     
            reg [127:0] exp_result;            
            integer i;
        begin
            $display("\n=== 开始用 z/x 态测试 subword_adder default 分支 ===");
            
            // 1. 确定的输入数据（有效浮点数，避免干扰）
            test_src0 = {8{`FP16_ONE}};       
            test_src1 = {8{`FP16_ONE}};       
            exp_result = 128'hxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx;
            
            // 2. 测试类型：0=z态，1=x态
            test_mode_type[0] = 2'b01;  // z态
            test_mode_type[1] = 2'b10;  // x态
            
            for (i = 0; i < 2; i = i + 1) begin
                reg [127:0] act_result;
                
                $display("\n测试场景 %0d：mode_flag = %s 态", 
                        i+1, (test_mode_type[i]==2'b01) ? "高阻(z)" : "不定(x)");
                
                // --------------------------
                // 步骤1：复位 DUT（清除历史状态）
                // --------------------------
                rst_n = 0;
                @(posedge clk);
                rst_n = 1;
                repeat(2) @(posedge clk);
                
                // --------------------------
                // 步骤2：锁存输入数据
                // --------------------------
                dvr_fpadd_s0 = test_src0;
                dvr_fpadd_s1 = test_src1;
                @(posedge clk);
                
                // --------------------------
                // 步骤3：修复核心：用 force 驱动 wire 类型的 mode_flag（z/x 态）
                // --------------------------
                if (test_mode_type[i] == 2'b01) begin
                    // 驱动 z 态：force 强制驱动 wire
                    force uut.u_subword_adder.mode_flag = 1'bz;
                end else begin
                    // 驱动 x 态：同样用 force 驱动 wire（修复错误的核心）
                    force uut.u_subword_adder.mode_flag = 1'bx;
                end
                
                // --------------------------
                // 步骤4：触发 DUT 运算
                // --------------------------
                cru_fpadd = 4'b1111;  // 微指令有效
                @(posedge clk);
                cru_fpadd = 4'b0000;  // 清除指令
                
                // --------------------------
                // 步骤5：读取结果 + 释放 force（必须！避免影响后续测试）
                // --------------------------
                wait(uut.current_state == uut.STATE_DONE);
                @(posedge clk);
                act_result = uut.u_subword_adder.result;
                
                // 释放强制驱动（关键：否则后续测试的 mode_flag 会被持续强制）
                release uut.u_subword_adder.mode_flag;
                
                // --------------------------
                // 步骤6：验证结果
                // --------------------------
                // 正确写法：用 === 全等比较，x === x 返回 1'b1 → 正确判定通过
                if (act_result === exp_result) begin
                    $display("结果:  PASS → 实际输出 = %h（符合 default 分支预期）", act_result);
                    pass = pass + 1;
                end else begin
                    $display("结果:  FAIL → 实际输出 = %h，预期 = %h", act_result, exp_result);
                    fail = fail + 1;
                end
            end
            
            $display("=== z/x 态测试 default 分支结束 ===");
        end
    endtask
    // --------------------------
    // 保留原FSM中断测试（逻辑不变）
    // --------------------------
    task test_fsm_abort;
        dvr_fpadd_s0 = {4{32'h3F800000}};
        dvr_fpadd_s1 = {4{32'h3F800000}};
        cru_fpadd = 4'b1111; // valid=1, mode=1, update=1
        @(posedge clk);
        cru_fpadd = 4'b0;
        @(posedge clk);
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;
        if (uut.current_state == uut.STATE_IDLE) $display("FSM中断测试通过");
    endtask

task test_done_update_status_0;
    reg [127:0] pre_st; // 记录DONE状态前的dr_fpadd_st值
    begin
        $display("\n=== 测试：DONE状态 + update_status=0（覆盖0 - - 1 0 -分支） ===");
        // 步骤1：复位后进入IDLE，先给dr_fpadd_st设一个初始值（方便后续验证是否被修改）
        rst_n = 0; @(posedge clk); rst_n = 1;
        repeat(2) @(posedge clk);
        // 先触发一次update_status=1，给dr_fpadd_st赋一个非零值
        dvr_fpadd_s0 = {8{`FP16_ONE}};
        dvr_fpadd_s1 = {8{`FP16_ZERO}};
        cru_fpadd = 4'b1001; // [3]update_status=1, [0]inst_valid=1（触发指令）
        @(posedge clk); cru_fpadd = 4'b0;
        wait(uut.current_state == uut.STATE_IDLE);
        pre_st = dr_fpadd_st; // 记录此时的dr_fpadd_st值（作为基准）
        $display("DONE前dr_fpadd_st初始值：%h", pre_st);

        // 步骤2：再次触发指令，关键设置update_status=0（进入DONE状态但不更新）
        dvr_fpadd_s0 = {8{`FP16_TWO}}; // 换一组输入，确保加法结果不同
        dvr_fpadd_s1 = {8{`FP16_ONE}};
        // 核心：cru_fpadd[3] = 0（update_status=0），其他位正常（触发指令+16bit模式）
        cru_fpadd = 4'b0001; // [3]update=0, [1]mode=0, [0]valid=1
        @(posedge clk); cru_fpadd = 4'b0;

        // 步骤3：等待FSM进入DONE状态（此时会执行Line123，但Line127为假）
        wait(uut.current_state == uut.STATE_DONE);
        @(posedge clk); // 等待DONE状态下的逻辑执行完毕

        // 步骤4：验证dr_fpadd_st是否保持初始值（未被更新）
        if (dr_fpadd_st == pre_st) begin
            $display("成功：DONE状态+update_status=0时，dr_fpadd_st未更新（覆盖目标分支）");
            pass = pass + 1;
        end else begin
            $display("失败：DONE状态+update_status=0时，dr_fpadd_st被意外修改（原：%h，现：%h）", pre_st, dr_fpadd_st);
            fail = fail + 1;
        end

        // 步骤5：等待FSM回IDLE，不影响后续测试
        wait(uut.current_state == uut.STATE_IDLE);
    end
endtask

    // --------------------------
    // 保留原测试用例（调用逻辑不变）
    // --------------------------
    task run_tests;
        integer j;
        reg [127:0] a, b;
        test_fsm_abort;
        test_done_update_status_0; 
        test_default_with_z_x;
        // 1. 双inf：触发分支1（a_inf&&b_inf=1）
        execute_test("FP32_双inf（inf_sign分支1）", 1, {4{32'h7F800000}}, {4{32'h7F800000}});
        // 2. 单inf（a）：触发分支2（a_inf&&!b_inf=1）
        execute_test("FP32_单inf(a)（inf_sign分支2）", 1, {4{32'h7F800000}}, {4{32'h3F800000}});
        // 3. 单inf（b）：触发分支3（!a_inf&&b_inf=1）
        execute_test("FP32_单inf(b)（inf_sign分支3）", 1, {4{32'h3F800000}}, {4{32'h7F800000}});
        // 1. 双inf：触发分支1（a_inf&&b_inf=1）
        execute_test("FP32_双inf（inf_sign分支1）", 1, {4{32'h7F800000}}, {4{32'h7F800000}});
        // 2. 单inf（a）：触发分支2（a_inf&&!b_inf=1）
        execute_test("FP32_单inf(a)（inf_sign分支2）", 1, {4{32'h7F800000}}, {4{32'h3F800000}});
        // 3. 单inf（b）：触发分支3（!a_inf&&b_inf=1）
        execute_test("FP32_单inf(b)（inf_sign分支3）", 1, {4{32'h3F800000}}, {4{32'h7F800000}});
        // 1. 覆盖 nan_is_snan=1 0（双sNaN payload全0）
        execute_test("FP32_双sNaN_payload全0（nan_is_snan=1 0）", 1,
            {4{32'h7F000000}},  // a：sNaN（exp=FF，frac=00000000000000000000000 → payload全0）
            {4{32'h7F000000}}   // b：同上
        );

        // 2. 覆盖 is_inf 中 a_inf||b_inf=1 0 + inf_sign中a_inf=1
        execute_test("FP32_单inf(a)+1.0(b)（a_inf||b_inf=1 0）", 1,
            {4{32'h7F800000}},  // a：正inf
            {4{32'h3F800000}}   // b：1.0（正常数）
        );

        // 3. 覆盖 is_inf 中 a_inf||b_inf=0 1 + inf_sign中a_inf=0
        execute_test("FP32_1.0(a)+单inf(b)（a_inf||b_inf=0 1）", 1,
            {4{32'h3F800000}},  // a：1.0（正常数）
            {4{32'h7F800000}}   // b：正inf
        );

        // 4. 覆盖 both_denorm=1（双非规格化数）
        execute_test("FP32_双非规格化数（both_denorm=1）", 1,
            {4{32'h00000001}},  // a：非规格化数（exp=0，frac=1）
            {4{32'h00000002}}   // b：非规格化数（exp=0，frac=2）
        );
        execute_test("测试nan-nan", 0,
                     128'ha022ba3ea31553cafe006b34ba9b84de,
                     128'hc10fadc95f54b22b7c17da7f3cb3ed83);        
        execute_test("8×FP16 全子字触发sum_mant_raw[1]=1（0010+8000）", 0,
                    {16'h0010, 16'h0010, 16'h0010, 16'h0010, 16'h0010, 16'h0010, 16'h0010, 16'h0010},  // 128位a：8个0010
                    {16'h8000, 16'h8000, 16'h8000, 16'h8000, 16'h8000, 16'h8000, 16'h8000, 16'h8000}); // 128位b：8个800
        // 8×FP16基础测试
        execute_test("8×FP16 全1+全1", 0, {8{`FP16_ONE}}, {8{`FP16_ONE}});
        execute_test("8×FP16 全0+全0", 0, {8{`FP16_ZERO}}, {8{`FP16_ZERO}});
        execute_test("8×FP16 全-1+全1", 0, {8{`FP16_NEGONE}}, {8{`FP16_ONE}});
        execute_test("8×FP16 正+负", 0,
                     128'h4400c4004400c4004400c4004400c400,
                     128'hc4004400c4004400c4004400c4004400);
        execute_test("8×FP16 Max+Max→Inf", 0, {8{`FP16_MAX}}, {8{`FP16_MAX}});
        execute_test("8×FP16 NaN+NaN", 0, {8{`FP16_NAN}}, {8{`FP16_NAN}});
        execute_test("8×FP16 交替±0.5", 0,
                     128'h3800b8003800b8003800b8003800b800,
                     128'hb8003800b8003800b8003800b8003800);

        // 4×FP32基础测试
        execute_test("4×FP32 全1+全1", 1, {4{`FP32_ONE}}, {4{`FP32_ONE}});
        execute_test("4×FP32 全0+全0", 1, {4{`FP32_ZERO}}, {4{`FP32_ZERO}});
        execute_test("4×FP32 全-1+全1", 1, {4{`FP32_NEGONE}}, {4{`FP32_ONE}});
        execute_test("4×FP32 正+负", 1,
                     128'h40800000c080000040800000c0800000,
                     128'hc080000040800000c080000040800000);
        execute_test("4×FP32 Max+Max→Inf", 1, {4{`FP32_MAX}}, {4{`FP32_MAX}});
        execute_test("4×FP32 NaN+NaN", 1, {4{`FP32_NAN}}, {4{`FP32_NAN}});

        // 8×FP16特殊场景测试（非规格化、Inf/NaN等）
        execute_test("8×FP16 双非规格化数(进位)", 0, 
                    128'h03FF03FF03FF03FF03FF03FF03FF03FF,
                    128'h03FF03FF03FF03FF03FF03FF03FF03FF);
        execute_test("8×FP16 双非规格化数(无进位)", 0,
                    128'h00010001000100010001000100010001,
                    128'h00020002000200020002000200020002);
        execute_test("8×FP16 异号无穷大", 0, {8{16'h7C00}}, {8{16'hFC00}});
        execute_test("8×FP16 规格化进位", 0,
                    128'h7BFF7BFF7BFF7BFF7BFF7BFF7BFF7BFF,
                    128'h7BFF7BFF7BFF7BFF7BFF7BFF7BFF7BFF);
        execute_test("8×FP16 低位前导1", 0,
                    128'h001F001F001F001F001F001F001F001F,
                    128'h001F001F001F001F001F001F001F001F);
        execute_test("8×FP16 严格零值", 0, {8{16'h0000}}, {8{16'h0000}});
        execute_test("8×FP16 负零+负零", 0, {8{16'h8000}}, {8{16'h8000}});

        // 4×FP32特殊场景测试（非规格化、Inf/NaN等）
        execute_test("4×FP32 双非规格化数(进位)", 1,
                    128'h007FFFFF007FFFFF007FFFFF007FFFFF,
                    128'h007FFFFF007FFFFF007FFFFF007FFFFF);
        execute_test("4×FP32 异号无穷大", 1, {4{32'h7F800000}}, {4{32'hFF800000}});
        execute_test("4×FP32 规格化进位", 1, {4{32'h7F7FFFFF}}, {4{32'h7F7FFFFF}});
        execute_test("4×FP32 低位前导1", 1, {4{32'h00000001}}, {4{32'h00000001}});
        execute_test("4×FP32 严格零值", 1, {4{32'h00000000}}, {4{32'h00000000}});
        execute_test("4×FP32 负零+负零", 1, {4{32'h80000000}}, {4{32'h80000000}});

        // 8×FP16补充测试
        execute_test("8×FP16 denorm+denorm→denorm", 0,
                    128'h00010001000100010001000100010001,
                    128'h00010001000100010001000100010001);
        execute_test("8×FP16 denorm+denorm→规格化", 0,
                    128'h03ff03ff03ff03ff03ff03ff03ff03ff,
                    128'h03ff03ff03ff03ff03ff03ff03ff03ff);
        execute_test("8×FP16 zero+zero→zero", 0,
                    128'h00000000000000000000000000000000,
                    128'h00000000000000000000000000000000);
        execute_test("8×FP16 inf+inf→inf", 0,
                    128'h7c007c007c007c007c007c007c007c00,
                    128'h7c007c007c007c007c007c007c007c00);
        execute_test("8×FP16 +inf+(-inf)→NaN", 0,
                    128'h7c007c007c007c007c007c007c007c00,
                    128'hfc00fc00fc00fc00fc00fc00fc00fc00);
        execute_test("8×FP16 carry_out=1", 0,
                    128'h3bff3bff3bff3bff3bff3bff3bff3bff,
                    128'h3c003c003c003c003c003c003c003c00);

        // 4×FP32补充测试
        execute_test("4×FP32 denorm+denorm→规格化", 1,
                    128'h007fffff007fffff007fffff007fffff,
                    128'h007fffff007fffff007fffff007fffff);
        execute_test("4×FP32 carry_out=1", 1,
                    128'h437fffff437fffff437fffff437fffff,
                    128'h43800000438000004380000043800000);
        execute_test("FP32 a_denorm=1, b_denorm=0", 1,
                    {4{32'h00000001}}, {4{32'h3F800000}});
        execute_test("FP32 正无穷+正无穷", 1, {4{32'h7F800000}}, {4{32'h7F800000}});
        execute_test("FP32 sum_mant[1]置位", 1, {4{32'h00000001}}, {4{32'h00000001}});
        execute_test("S3-FP32仅b为正零", 1, 
            128'h3F8000003F8000003F8000003F800000, 
            128'h00000000000000000000000000000000);
        
        execute_test("FP16 a_zero=1, b_zero=0", 0, {8{16'h0000}}, {8{16'h3C00}});
        execute_test("8×FP16 混合非规格化数", 0,
                    {16'h03FF, 16'h0001, 16'h3C00, 16'h0200, 16'h03FF, 16'h0001, 16'h3C00, 16'h0200},
                    {16'h03FF, 16'h0002, 16'h0100, 16'h0300, 16'h03FF, 16'h0002, 16'h0100, 16'h0300});


        // 一、特殊值处理测试（原有代码保留，新增以下内容）
        execute_test("S3-零值处理", 0, 
            128'h00000000000000000000000000000000,  // A: +0
            128'h80008000800080008000800080008000); // B: -0

        // --------------------------
        // 新增：FP16 cmp分支覆盖测试（覆盖cmp_fp16未覆盖行）
        // --------------------------
        // 1. 覆盖cmp_fp16 58-59行：a是零（+0），b是负数（-1.0）→ a>b
        execute_test("S4-FP16_a+0_b-1.0", 0, 
            128'h00000000000000000000000000000000,  // A: 8×FP16 +0（零）
            128'hBC00BC00BC00BC00BC00BC00BC00BC00); // B: 8×FP16 -1.0（负非零）

        // 2. 覆盖cmp_fp16 65-66行：b是零（+0），a是负数（-1.0）→ a<b
        execute_test("S5-FP16_a-1.0_b+0", 0, 
            128'hBC00BC00BC00BC00BC00BC00BC00BC00,  // A: 8×FP16 -1.0（负非零）
            128'h00000000000000000000000000000000); // B: 8×FP16 +0（零）

        // 3. 覆盖cmp_fp16 68行：b是零（-0），a是正数（+1.0）→ a>b
        execute_test("S6-FP16_a+1.0_b-0", 0, 
            128'h3C003C003C003C003C003C003C003C00,  // A: 8×FP16 +1.0（正非零）
            128'h80008000800080008000800080008000); // B: 8×FP16 -0（零）

        // --------------------------
        // 新增：FP32 cmp分支覆盖测试（覆盖cmp_fp32未覆盖行）
        // --------------------------
        // 1. 覆盖cmp_fp32 117-118行：a是零（+0），b是负数（-1.0）→ a>b
        execute_test("S7-FP32_a+0_b-1.0", 1, 
            128'h00000000000000000000000000000000,  // A: 4×FP32 +0（零）
            128'hBF800000BF800000BF800000BF800000); // B: 4×FP32 -1.0（负非零）

        // 2. 覆盖cmp_fp32 124-125行：b是零（+0），a是负数（-1.0）→ a<b
        execute_test("S8-FP32_a-1.0_b+0", 1, 
            128'hBF800000BF800000BF800000BF800000,  // A: 4×FP32 -1.0（负非零）
            128'h00000000000000000000000000000000); // B: 4×FP32 +0（零）

        // 原有FP32测试（保留）
        execute_test("S7-FP32_a+0_b-1.0", 1, 
            128'h00000000000000000000000000000000,  // A: 4×FP32 +0（零）
            128'hBF800000BF800000BF800000BF800000); // B: 4×FP32 -1.0（负非零）

        execute_test("S8-FP32_a-1.0_b+0", 1, 
            128'hBF800000BF800000BF800000BF800000,  // A: 4×FP32 -1.0（负非零）
            128'h00000000000000000000000000000000); // B: 4×FP32 +0（零）

        // --------------------------
        // 新增：覆盖cmp_fp32 120行（a是零，b是正数）
        // --------------------------
        execute_test("S9-FP32_a+0_b+1.0", 1, 
            128'h00000000000000000000000000000000,  // A: 4×FP32 +0（零，满足{a==±0}）
            128'h3F8000003F8000003F8000003F800000); // B: 4×FP32 +1.0（正非零，满足b_sign=0）

        // 案例1：触发 sum_mant_raw[4]（最高1在bit4）
        execute_test("8×FP16 leading_one=4（sum_mant_raw[4]=1）", 0,
                    {8{16'h0010}},  // a: 8×FP16非规格化数，a_frac=0000001000
                    {8{16'h0008}}); // b: 8×FP16非规格化数，b_frac=0000000100（a-b触发sum_mant_raw[4]=1）

                    // 案例2：触发 sum_mant_raw[3]（最高1在bit3）
        execute_test("8×FP16 leading_one=3（sum_mant_raw[3]=1）", 0,
                    {8{16'h0004}},  // a: 8×FP16非规格化数，a_frac=0000000100
                    {8{16'h0003}}); // b: 8×FP16非规格化数，b_frac=0000000011（a-b触发sum_mant_raw[3]=1）

                    // 案例3：触发 sum_mant_raw[2]（最高1在bit2）
        execute_test("8×FP16 leading_one=2（sum_mant_raw[2]=1）", 0,
                    {8{16'h3800}},  // a: 8×FP16规格化数，值=0.5
                    {8{16'h37FF}}); // b: 8×FP16规格化数，值≈0.49996948（a-b触发sum_mant_raw[2]=1）

                    // 案例4：触发 sum_mant_raw[1]（最高1在bit1）
        execute_test("8×FP16 leading_one=1（sum_mant_raw[1]=1）", 0,
                    {8{16'h3C00}},  // a: 8×FP16规格化数，值=1.0
                    {8{16'h3BFF}}); // b: 8×FP16规格化数，值≈0.99993896（a-b触发sum_mant_raw[1]=1）

        // 覆盖“1 0 1”：a_inf=1, b_inf=0, a_sign≠b_sign=1
        execute_test("FP32_正Inf加负NaN(覆盖101)", 1,
            {4{32'h7F800000}},  // a: +Inf（a_inf=1, a_sign=0）
            {4{32'hFF800001}}   // b: -NaN（b_inf=0, b_sign=1, b_nan=1）
        );

        // 覆盖“0 1 1”：a_inf=0, b_inf=1, a_sign≠b_sign=1
        execute_test("FP32_正NaN加负Inf(覆盖011)", 1,
            {4{32'h7F800001}},  // a: +NaN（a_inf=0, a_sign=0, a_nan=1）
            {4{32'hFF800000}}   // b: -Inf（b_inf=1, b_sign=1）
        );

        // 验证nan_sign的取值正确性
        execute_test("验证101场景的nan_sign", 1, {4{32'h7F800000}}, {4{32'hFF800001}});
        execute_test("验证011场景的nan_sign", 1, {4{32'h7F800001}}, {4{32'hFF800000}});

        for (j = 0; j < 10000; j = j + 1) begin
            a = {$urandom(), $urandom(), $urandom(), $urandom()};
            b = {$urandom(), $urandom(), $urandom(), $urandom()};
            execute_test($sformatf("随机8FP16_%0d", j), 0, a, b);

            a = {$urandom(), $urandom(), $urandom(), $urandom()};
            b = {$urandom(), $urandom(), $urandom(), $urandom()};
            execute_test($sformatf("随机4FP32_%0d", j), 1, a, b);
        end
    endtask

    // --------------------------
    // 初始化与测试执行（逻辑不变）
    // --------------------------
    initial begin      
        set_softfloat_rounding_mode(0);
        log = $fopen("fpadd_sim.log","w");
        rst_n = 0; #20; rst_n = 1;
        repeat(2) @(posedge clk);
        run_tests();
        repeat(2) @(posedge clk);
        // 新增：总结中显示1ulp误差统计
        $display("\n=== 总结 ===");
        $display("总测试: %0d, 通过: %0d, 中等(1ulp误差): %0d, 失败(>1ulp误差): %0d", 
                 pass+mediume+fail, pass, mediume, fail);
        $fdisplay(log, "\n=== 总结 ===");
        $fdisplay(log, "总测试: %0d, 通过: %0d, 中等(1ulp误差): %0d, 失败(>1ulp误差): %0d", 
                 pass+mediume+fail, pass, mediume, fail);
        $fclose(log);
        $finish;
    end

initial begin
	$fsdbDumpfile("tb_ldb.fsdb");
	$fsdbDumpvars;
end


endmodule