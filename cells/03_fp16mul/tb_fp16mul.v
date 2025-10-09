`timescale 1ns/1ps

// 规则:
// 1) S0123 写: cru_fp16mul_s0123[1] 为 valid, [0] 为 bank 选择
// 2) S4567 写: cru_fp16mul_s4567[3] 为 valid, [2] 为 bank, [1:0] 为 S4..S7 编号
// 3) 计算: cru_fp16mul[2] 为 valid, [1] 选择 S0..S3 的 bank, [0] 选择 S4..S7 的 bank

module tb_fp16_to_fp32_multiplier;
    // ---------------------------------------------------------------------------
    // 参数
    // ---------------------------------------------------------------------------
    localparam NUM_GROUPS      = 32;   // 并行 group 数
    localparam NUM_S0123_REGS  = 2;    // S0-S3 bank 数
    localparam NUM_S4567_REGS  = 2;    // S4-S7 bank 数

    // SoftFloat 
    localparam SOFTFLOAT_ROUND_NEAR_EVEN = 0;

    // ---------------------------------------------------------------------------
    // DUT 接口信号
    // ---------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [127:0] dvr_fp16mul_s0, dvr_fp16mul_s1, dvr_fp16mul_s2, dvr_fp16mul_s3;
    reg  [127:0] dvr_fp16mul_s4567;
    reg  [1:0]   cru_fp16mul_s0123;   // {valid, bank}
    reg  [3:0]   cru_fp16mul_s4567;   // {valid, bank, which[1:0]}
    reg  [2:0]   cru_fp16mul;         // {valid, bank_a, bank_b}
    wire [127:0] dr_fp16mul_d0, dr_fp16mul_d1, dr_fp16mul_d2, dr_fp16mul_d3;
    wire [127:0] dr_fp16mul_d4, dr_fp16mul_d5, dr_fp16mul_d6, dr_fp16mul_d7;

    // DPI-C SoftFloat
    import "DPI-C" function int unsigned fp16_inputs_mul_to_fp32_softfloat(input shortint unsigned a, input shortint unsigned b);
    import "DPI-C" function void set_softfloat_rounding_mode(input int unsigned mode);
    import "DPI-C" function void clear_softfloat_flags();
    //import "DPI-C" function int unsigned get_softfloat_flags();

    // 统计
    integer test_count  = 0;
    integer pass_count  = 0;
    integer fail_count  = 0;

    // ---------------------------------------------------------------------------
    // DUT 实例
    // ---------------------------------------------------------------------------
    fp16mul dut (
        .clk(clk),
        .rst_n(rst_n),
        .dvr_fp16mul_s0(dvr_fp16mul_s0),
        .dvr_fp16mul_s1(dvr_fp16mul_s1),
        .dvr_fp16mul_s2(dvr_fp16mul_s2),
        .dvr_fp16mul_s3(dvr_fp16mul_s3),
        .dvr_fp16mul_s4567(dvr_fp16mul_s4567),
        .cru_fp16mul_s0123(cru_fp16mul_s0123),
        .cru_fp16mul_s4567(cru_fp16mul_s4567),
        .cru_fp16mul(cru_fp16mul),
        .dr_fp16mul_d0(dr_fp16mul_d0),
        .dr_fp16mul_d1(dr_fp16mul_d1),
        .dr_fp16mul_d2(dr_fp16mul_d2),
        .dr_fp16mul_d3(dr_fp16mul_d3),
        .dr_fp16mul_d4(dr_fp16mul_d4),
        .dr_fp16mul_d5(dr_fp16mul_d5),
        .dr_fp16mul_d6(dr_fp16mul_d6),
        .dr_fp16mul_d7(dr_fp16mul_d7)
    );

    // 时钟
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // 波形
    initial begin
        $fsdbDumpfile("fp16_to_fp32_multiplier.fsdb");
        $fsdbDumpvars(0, tb_fp16_to_fp32_multiplier);
    end

    // 复位
    task reset_system;
        begin
            rst_n = 0;
            @(posedge clk);
            rst_n = 1;
            @(posedge clk);
            rst_n = 0;
            @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------------------
    // 工具: 重构单 group 输出为 32-bit
    // ---------------------------------------------------------------------------
    function automatic [31:0] reconstruct_result;
        input integer gid;
        begin
            reconstruct_result = {
                dr_fp16mul_d7[gid*4 +:4], dr_fp16mul_d6[gid*4 +:4],
                dr_fp16mul_d5[gid*4 +:4], dr_fp16mul_d4[gid*4 +:4],
                dr_fp16mul_d3[gid*4 +:4], dr_fp16mul_d2[gid*4 +:4],
                dr_fp16mul_d1[gid*4 +:4], dr_fp16mul_d0[gid*4 +:4]
            };
        end
    endfunction

    // 结果比较 (支持 NaN 相等)
    function automatic bit verify_result;
        input [15:0] a, b;
        input [31:0] act, exp;
        input integer id;
        input string tag;
        bit is_nan_exp = (exp[30:23] == 8'hff) && (exp[22:0] != 0);
        bit is_nan_act = (act[30:23] == 8'hff) && (act[22:0] != 0);
        begin
            test_count++;
            if (act == exp || (is_nan_exp && is_nan_act)) begin
                $display("[%s] PASS id=%0d a=%h b=%h exp=%h act=%h", tag, id, a, b, exp, act);
                verify_result = 1;
                pass_count++;
            end else begin
                $display("[%s] FAIL id=%0d a=%h b=%h exp=%h act=%h", tag, id, a, b, exp, act);
                verify_result = 0;
                fail_count++;
            end
        end
    endfunction

    // ---------------------------------------------------------------------------
    // Scoreboard 模型存储 (镜像 DUT bank 内容)
    // ---------------------------------------------------------------------------
    reg [127:0] model_s0 [0:NUM_S0123_REGS-1];
    reg [127:0] model_s1 [0:NUM_S0123_REGS-1];
    reg [127:0] model_s2 [0:NUM_S0123_REGS-1];
    reg [127:0] model_s3 [0:NUM_S0123_REGS-1];
    reg [127:0] model_s4 [0:NUM_S4567_REGS-1];
    reg [127:0] model_s5 [0:NUM_S4567_REGS-1];
    reg [127:0] model_s6 [0:NUM_S4567_REGS-1];
    reg [127:0] model_s7 [0:NUM_S4567_REGS-1];

    task init_scoreboard_model;
        integer b;
        begin
            for (b = 0; b < NUM_S0123_REGS; b++) begin
                model_s0[b] = 0;
                model_s1[b] = 0;
                model_s2[b] = 0;
                model_s3[b] = 0;
            end
            for (b = 0; b < NUM_S4567_REGS; b++) begin
                model_s4[b] = 0;
                model_s5[b] = 0;
                model_s6[b] = 0;
                model_s7[b] = 0;
            end
        end
    endtask

    // 写一整 bank 的 A (S0..S3)
    task scoreboard_write_s0123_bank;
        input integer bank;
        input [15:0] vals_a [0:31];
        integer i;
        reg [127:0] s0v, s1v, s2v, s3v;
        begin
            s0v = 0;
            s1v = 0;
            s2v = 0;
            s3v = 0;
            for (i = 0; i < 32; i++) begin
                s0v[i*4 +:4] = vals_a[i][3:0];
                s1v[i*4 +:4] = vals_a[i][7:4];
                s2v[i*4 +:4] = vals_a[i][11:8];
                s3v[i*4 +:4] = vals_a[i][15:12];
            end
            dvr_fp16mul_s0 = s0v;
            dvr_fp16mul_s1 = s1v;
            dvr_fp16mul_s2 = s2v;
            dvr_fp16mul_s3 = s3v;
            cru_fp16mul_s0123 = {1'b1, bank[0]};
            @(posedge clk);
            cru_fp16mul_s0123 = 2'b00;
            @(posedge clk);
            model_s0[bank] = s0v;
            model_s1[bank] = s1v;
            model_s2[bank] = s2v;
            model_s3[bank] = s3v;
        end
    endtask

    // 写 B (S4..S7) 中单个 which 段
    task scoreboard_write_single_s4567;
        input integer bank;
        input [1:0] which;
        input [15:0] vals_b [0:31];
        integer i;
        reg [127:0] tmp;
        begin
            tmp = 0;
            for (i = 0; i < 32; i++) begin
                case(which)
                    2'd0: tmp[i*4 +:4] = vals_b[i][3:0];
                    2'd1: tmp[i*4 +:4] = vals_b[i][7:4];
                    2'd2: tmp[i*4 +:4] = vals_b[i][11:8];
                    2'd3: tmp[i*4 +:4] = vals_b[i][15:12];
                endcase
            end
            dvr_fp16mul_s4567 = tmp;
            cru_fp16mul_s4567 = {1'b1, bank[0], which};
            @(posedge clk);
            cru_fp16mul_s4567 = 4'b0000;
            @(posedge clk);
            case(which)
                2'd0: model_s4[bank] = tmp;
                2'd1: model_s5[bank] = tmp;
                2'd2: model_s6[bank] = tmp;
                2'd3: model_s7[bank] = tmp;
            endcase
        end
    endtask

    task scoreboard_write_full_s4567_bank;
        input integer bank;
        input [15:0] vals_b [0:31];
        begin
            scoreboard_write_single_s4567(bank, 2'd0, vals_b);
            scoreboard_write_single_s4567(bank, 2'd1, vals_b);
            scoreboard_write_single_s4567(bank, 2'd2, vals_b);
            scoreboard_write_single_s4567(bank, 2'd3, vals_b);
        end
    endtask

    function automatic [15:0] model_get_a;
        input integer bank;
        input integer gid;
        begin
            model_get_a = {
                model_s3[bank][gid*4 +:4], model_s2[bank][gid*4 +:4],
                model_s1[bank][gid*4 +:4], model_s0[bank][gid*4 +:4]
            };
        end
    endfunction

    function automatic [15:0] model_get_b;
        input integer bank;
        input integer gid;
        begin
            model_get_b = {
                model_s7[bank][gid*4 +:4], model_s6[bank][gid*4 +:4],
                model_s5[bank][gid*4 +:4], model_s4[bank][gid*4 +:4]
            };
        end
    endfunction

    // 发起计算并比对
    task scoreboard_compute_and_check;
        input integer bank_a;
        input integer bank_b;
        integer gid;
        reg [15:0] a_val, b_val;
        reg [31:0] exp32, act32;
        begin
            cru_fp16mul = {1'b1, bank_a[0], bank_b[0]};
            @(posedge clk);
            cru_fp16mul = 3'b000;
            @(posedge clk);
            @(posedge clk);
            for (gid = 0; gid < 32; gid++) begin
                a_val = model_get_a(bank_a, gid);
                b_val = model_get_b(bank_b, gid);
                clear_softfloat_flags();
                exp32 = fp16_inputs_mul_to_fp32_softfloat(a_val, b_val);
                act32 = reconstruct_result(gid);
                void'(verify_result(a_val, b_val, act32, exp32, gid, "计算"));
            end
        end
    endtask

    // 测试A bank0 + B bank0 → 计算 → 再写 A bank1 + B bank1 → 计算 → 再算一次 bank0 确认未被破坏。 
    //覆盖点：
    // a. S0123 写一次覆盖整 bank（四段 nibble 分别落入 s0..s3） 
    // b. S4567 一次性全写（4 段）后结果正确 
    // c. bank 间独立性（写 bank1 不影响 bank0）
    task test_s0123_update_logic;
        reg [15:0] a0[0:31];
        reg [15:0] a1[0:31];
        reg [15:0] b0[0:31];
        reg [15:0] b1[0:31];
        integer i;
        begin
            $display("[TEST] S0123 更新逻辑");
            for (i = 0; i < 32; i++) begin
                a0[i] = $urandom();
                a1[i] = $urandom();
                b0[i] = $urandom();
                b1[i] = $urandom();
            end
            scoreboard_write_s0123_bank(0, a0);
            scoreboard_write_full_s4567_bank(0, b0);
            scoreboard_compute_and_check(0, 0);
            scoreboard_write_s0123_bank(1, a1);
            scoreboard_write_full_s4567_bank(1, b1);
            scoreboard_compute_and_check(1, 1);
            scoreboard_compute_and_check(0, 0); // 再次确认 bank0 未被破坏
        end
    endtask

    // test_s4567测试--A 先写好，B 逐段 which=0/1/2/3 逐步写入，每写一段都发起一次计算。 
    // 覆盖点： 
    // a. S4567 分段增量更新不破坏已写 nibble; 
    // b. 每次部分更新后使用最新组合计算; 
    // c. 乘法阵列在 B 侧逐段“渐进可见”行为
    task test_s4567_update_logic;
        reg [15:0] a0[0:31];
        reg [15:0] b_prog[0:31];
        integer i;
        integer active_list[0:31];
        begin
            $display("[TEST] S4567 分步更新逻辑");
            for (i = 0; i < 32; i++) begin
                a0[i] = $urandom();
                b_prog[i] = 16'h0000;
                active_list[i] = i;
            end
            scoreboard_write_s0123_bank(0, a0);
            for (i = 0; i < 32; i++) b_prog[i][3:0] = $urandom();
            scoreboard_write_single_s4567(0, 2'd0, b_prog);
            scoreboard_compute_and_check(0, 0);
            for (i = 0; i < 32; i++) b_prog[i][7:4] = $urandom();
            scoreboard_write_single_s4567(0, 2'd1, b_prog);
            scoreboard_compute_and_check(0, 0);
            for (i = 0; i < 32; i++) b_prog[i][11:8] = $urandom();
            scoreboard_write_single_s4567(0, 2'd2, b_prog);
            scoreboard_compute_and_check(0, 0);
            for (i = 0; i < 32; i++) b_prog[i][15:12] = $urandom();
            scoreboard_write_single_s4567(0, 2'd3, b_prog);
            scoreboard_compute_and_check(0, 0);
        end
    endtask

    // 随机测试--每次迭代随机写两个 A bank、两个 B bank，做四种 (A_bank, B_bank) 组合。 
    // 覆盖点 ：
    // a. bank 选择矩阵 2×2 全覆盖 
    // b. 大量不同 FP16 输入对 corner（NaN/Inf/Subnormal）触发概率更高 
    // c. 验证流水线在交错发起时仍正确
    task test_cross_bank_compute_random;
        input integer iterations;
        reg [15:0] a0[0:31];
        reg [15:0] a1[0:31];
        reg [15:0] b0[0:31];
        reg [15:0] b1[0:31];
        integer it, i;
        begin
            $display("[TEST] 交叉 bank 随机组合 iterations=%0d", iterations);
            for (it = 0; it < iterations; it++) begin
                for (i = 0; i < 32; i++) begin
                    a0[i] = $urandom();
                    a1[i] = $urandom();
                    b0[i] = $urandom();
                    b1[i] = $urandom();
                end
                scoreboard_write_s0123_bank(0, a0);
                scoreboard_write_full_s4567_bank(0, b0);
                scoreboard_write_s0123_bank(1, a1);
                scoreboard_write_full_s4567_bank(1, b1);
                scoreboard_compute_and_check(0, 0);
                scoreboard_compute_and_check(0, 1);
                scoreboard_compute_and_check(1, 0);
                scoreboard_compute_and_check(1, 1);
            end
        end
    endtask

    // 特殊值处理测试：覆盖 +Inf/-Inf/NaN/+0/-0/Denorm/最大最小正规数 等组合
    // 说明:
    //  - 使用 bank0 写入 32 组数据中的前若干条为特殊值用例，剩余位置填充 0 或随机（不影响验证目标）
    //  - 结果期望由 SoftFloat DPI 模型给出，verify_result 已对 NaN == NaN 做等价判断
    task test_special_values;
        reg [15:0] a_vals[0:31];
        reg [15:0] b_vals[0:31];
        integer i;
        // FP16 常量编码
        localparam [15:0] FP16_POS_ZERO   = 16'h0000;
        localparam [15:0] FP16_NEG_ZERO   = 16'h8000;
        localparam [15:0] FP16_ONE        = 16'h3C00; // 1.0
        localparam [15:0] FP16_TWO        = 16'h4000; // 2.0
        localparam [15:0] FP16_INF_POS    = 16'h7C00;
        localparam [15:0] FP16_INF_NEG    = 16'hFC00;
        localparam [15:0] FP16_QNAN       = 16'h7E00; // 简单取最高 mantissa bit 置 1
        localparam [15:0] FP16_MIN_DENORM = 16'h0001; // 最小非规格化
        localparam [15:0] FP16_MAX_DENORM = 16'h03FF; // 最大非规格化
        localparam [15:0] FP16_MIN_NORM   = 16'h0400; // 最小正规数 (exp=1, frac=0)
        localparam [15:0] FP16_MAX_NORM   = 16'h7BFF; // 最大正规数 (exp=0x1E, frac=all1)
        begin
            $display("[TEST] 特殊值处理");
            // 默认清零
            for (i = 0; i < 32; i++) begin
                a_vals[i] = FP16_POS_ZERO;
                b_vals[i] = FP16_POS_ZERO;
            end
            // 列出典型用例（索引注释）
            a_vals[0]  = FP16_INF_POS;    b_vals[0]  = FP16_ONE;        // +Inf * 1.0 -> +Inf
            a_vals[1]  = FP16_INF_POS;    b_vals[1]  = FP16_INF_POS;    // +Inf * +Inf -> +Inf
            a_vals[2]  = FP16_INF_NEG;    b_vals[2]  = FP16_INF_POS;    // -Inf * +Inf -> -Inf
            a_vals[3]  = FP16_INF_POS;    b_vals[3]  = FP16_POS_ZERO;   // +Inf * +0 -> NaN (无效)
            a_vals[4]  = FP16_QNAN;       b_vals[4]  = FP16_ONE;        // NaN * 1.0 -> NaN
            a_vals[5]  = FP16_ONE;        b_vals[5]  = FP16_QNAN;       // 1.0 * NaN -> NaN
            a_vals[6]  = FP16_QNAN;       b_vals[6]  = FP16_INF_POS;    // NaN * Inf -> NaN
            a_vals[7]  = FP16_POS_ZERO;   b_vals[7]  = FP16_ONE;        // +0 * 1.0 -> +0
            a_vals[8]  = FP16_POS_ZERO;   b_vals[8]  = FP16_NEG_ZERO;   // +0 * -0 -> -0 (SoftFloat 决定符号)
            a_vals[9]  = FP16_MIN_DENORM; b_vals[9]  = FP16_ONE;        // 最小非规 * 1.0
            a_vals[10] = FP16_MAX_DENORM; b_vals[10] = FP16_ONE;        // 最大非规 * 1.0
            a_vals[11] = FP16_MIN_DENORM; b_vals[11] = FP16_MIN_DENORM; // 非规 * 非规 -> 可能下溢/0
            a_vals[12] = FP16_INF_NEG;    b_vals[12] = FP16_INF_NEG;    // -Inf * -Inf -> +Inf
            a_vals[13] = FP16_MAX_NORM;   b_vals[13] = FP16_MAX_NORM;   // 最大正规 * 最大正规 -> +Inf (上溢)
            a_vals[14] = FP16_MAX_NORM;   b_vals[14] = FP16_ONE;        // 最大正规 * 1.0 -> 保持
            a_vals[15] = FP16_MIN_NORM;   b_vals[15] = FP16_MIN_NORM;   // 最小正规 * 最小正规 -> 非规/0
            // 其余索引保持 0 * 0

            // 写入 bank0
            scoreboard_write_s0123_bank(0, a_vals);
            scoreboard_write_full_s4567_bank(0, b_vals);
            // 计算并比对
            scoreboard_compute_and_check(0, 0);
        end
    endtask



    // Initial
    initial begin
        set_softfloat_rounding_mode(SOFTFLOAT_ROUND_NEAR_EVEN);
        dvr_fp16mul_s0 = 0;
        dvr_fp16mul_s1 = 0;
        dvr_fp16mul_s2 = 0;
        dvr_fp16mul_s3 = 0;
        dvr_fp16mul_s4567 = 0;
        cru_fp16mul_s0123 = 0;
        cru_fp16mul_s4567 = 0;
        cru_fp16mul = 0;


        reset_system();
        init_scoreboard_model();

        test_s0123_update_logic();
        test_s4567_update_logic();
        test_special_values();
        test_cross_bank_compute_random(30000); 
        
        repeat(5) @(posedge clk);
        $display("=== 测试完成 ===");
        $display("总测试: %0d 通过: %0d 失败: %0d 通过率: %0.1f%%", test_count, pass_count, fail_count,
                 (test_count > 0) ? (pass_count * 100.0) / test_count : 0.0);
        if (fail_count == 0) $display(" ======= ALL PASS ========");
        else $display("FAILURES PRESENT !!!!");
        $finish;
    end

endmodule