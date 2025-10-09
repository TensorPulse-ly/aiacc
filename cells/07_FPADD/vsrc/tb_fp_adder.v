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

    // DPI-C
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

    // 日志
    integer log;
    integer pass = 0, fail = 0;

    // 常量
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

    // 动态计算最小可表示值(ULP)
    function real min_ulp16(input [15:0] v);
        if (v[14:10] == 5'b0) begin        // 非规格化数
            min_ulp16 = 2.0**-24;             // 2⁻²⁴ (FP16最小非规格化间隔)
        end else begin
            int exp_val = v[14:10] - 15;      // 实际指数值 (偏置15)
            min_ulp16 = 2.0**(exp_val - 10);  // 2^(E-10)
        end
    endfunction

    function real min_ulp32(input [31:0] v);
        if (v[30:23] == 8'b0) begin        // 非规格化数
            min_ulp32 = 2.0**-149;            // 2⁻¹⁴⁹ (FP32最小非规格化间隔)
        end else begin
            int exp_val = v[30:23] - 127;    // 实际指数值 (偏置127)
            min_ulp32 = 2.0**(exp_val - 23);  // 2^(E-23)
        end
    endfunction

    // 修改后的ULP计算函数
    function[31:0] ulp16;
        input[15:0] a,b;
        real fa = fp16_to_real(a), fb = fp16_to_real(b);
        real diff = (fa > fb) ? (fa - fb) : (fb - fa);
        real min_ulp = (min_ulp16(a) > min_ulp16(b))
                        ? min_ulp16(a) : min_ulp16(b);
        ulp16 = (min_ulp > 0) ? $rtoi(diff / min_ulp + 0.4999) : 0; // 四舍五入
    endfunction

    function[31:0] ulp32;
        input[31:0] a,b;
        real fa = fp32_to_real(a), fb = fp32_to_real(b);
        real diff = (fa > fb) ? (fa - fb) : (fb - fa);
        real min_ulp = (min_ulp32(a) > min_ulp32(b))
                        ? min_ulp32(a) : min_ulp32(b);
        ulp32 = (min_ulp > 0) ? $rtoi(diff / min_ulp + 0.4999) : 0; // 四舍五入
    endfunction

    function isnan16; input [15:0] v; isnan16 = (v[14:10]==5'h1F && (v[9:0]!=0)); endfunction
    function isnan32; input [31:0] v; isnan32 = (v[30:23]==8'hFF); endfunction

    // 执行测试
    task automatic execute_test;
        input string  desc;
        input         mode;
        input [127:0] a;
        input [127:0] b;
        reg   [127:0] exp;
        reg   [127:0] act;
        integer       ulp_vec[0:7];
        integer       i, j, ok;
        string        ulp_str;
        real val[0:7];
        integer ulp_error = 0;
        reg is_special_match = 1;
        reg has_special = 0;

        // 用 SoftFloat 计算预期值
        exp = 128'h0;
        if (mode == 0) begin
            for (i = 0; i < 8; i = i + 1)
                exp[16*i +:16] = fp16_add_softfloat(a[16*i +:16], b[16*i +:16]);
        end else begin
            for (i = 0; i < 4; i = i + 1)
                exp[32*i +:32] = fp32_add_softfloat(a[32*i +:32], b[32*i +:32]);
        end

        // 驱动 DUT
        dvr_fpadd_s0 = a;
        dvr_fpadd_s1 = b;
        cru_fpadd = {1'b1, mode, mode, 1'b1};
        @(posedge clk) #1;
        cru_fpadd = 4'b1000; // 清除微指令
        wait(uut.current_state == uut.STATE_IDLE); // 等待空闲状态
        @(posedge clk);
        act = dr_fpadd_d;

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

        // 打印并检查 dr_fpadd_st
        $write("状态:%h (", dr_fpadd_st);
        if (mode == 0) begin
            for (j = 7; j >= 0; j = j - 1)
                $write("%3b%s", dr_fpadd_st[16*j +: 3], j == 0 ? "" : ",");
        end else begin
            for (j = 3; j >= 0; j = j - 1)
                $write("%3b%s", dr_fpadd_st[32*j +: 3], j == 0 ? "" : ",");
        end
        $write(")\n");


        // 判断
        if (act === exp) begin
            $display("结果:通过(精确匹配)");
            pass = pass + 1;
            return;
        end

        if (mode == 0) begin // FP16模式
            for (i = 0; i < 8; i = i + 1) begin
                ulp_vec[i] = ulp16(exp[16*i+:16], act[16*i+:16]);
                if (ulp_vec[i] > 1) ulp_error = 1;
            end
            ulp_str = $sformatf("%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                             ulp_vec[0], ulp_vec[1], ulp_vec[2], ulp_vec[3],
                             ulp_vec[4], ulp_vec[5], ulp_vec[6], ulp_vec[7]);
        end else begin // FP32模式
            for (i = 0; i < 4; i = i + 1) begin
                ulp_vec[i] = ulp32(exp[32*i+:32], act[32*i+:32]);
                if (ulp_vec[i] > 1) ulp_error = 1;
            end
            ulp_str = $sformatf("%0d,%0d,%0d,%0d",
                                ulp_vec[0], ulp_vec[1], ulp_vec[2], ulp_vec[3]);
        end

        if (ulp_error) begin
            $display("结果:失败(容差向量=%s)", ulp_str);
            fail = fail + 1;
        end else begin
            $display("结果:通过(容差向量=%s)", ulp_str);
            pass = pass + 1;
        end
    endtask

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

    task run_tests;
        integer j;
        reg [127:0] a, b;
        test_fsm_abort;

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

        // 4×FP32
        execute_test("4×FP32 全1+全1", 1, {4{`FP32_ONE}}, {4{`FP32_ONE}});
        execute_test("4×FP32 全0+全0", 1, {4{`FP32_ZERO}}, {4{`FP32_ZERO}});
        execute_test("4×FP32 全-1+全1", 1, {4{`FP32_NEGONE}}, {4{`FP32_ONE}});
        execute_test("4×FP32 正+负", 1,
                     128'h40800000c080000040800000c0800000,
                     128'hc080000040800000c080000040800000);
        execute_test("4×FP32 Max+Max→Inf", 1, {4{`FP32_MAX}}, {4{`FP32_MAX}});
        execute_test("4×FP32 NaN+NaN", 1, {4{`FP32_NAN}}, {4{`FP32_NAN}});

        // FP16格式测试
        execute_test("8×FP16 双非规格化数(进位)", 0, 
                    128'h03FF03FF03FF03FF03FF03FF03FF03FF,  // 非规格化数 0x03FF
                    128'h03FF03FF03FF03FF03FF03FF03FF03FF);

        execute_test("8×FP16 双非规格化数(无进位)", 0,
                    128'h00010001000100010001000100010001,  // 非规格化数 0x0001
                    128'h00020002000200020002000200020002);

        execute_test("8×FP16 异号无穷大", 0,
                    {8{16'h7C00}},   // +inf
                    {8{16'hFC00}});  // -inf

        execute_test("8×FP16 规格化进位", 0,
                    128'h7BFF7BFF7BFF7BFF7BFF7BFF7BFF7BFF,  // 接近最大值
                    128'h7BFF7BFF7BFF7BFF7BFF7BFF7BFF7BFF);

        execute_test("8×FP16 低位前导1", 0,
                    128'h001F001F001F001F001F001F001F001F,  // 最小非规格化数
                    128'h001F001F001F001F001F001F001F001F);

        execute_test("8×FP16 严格零值", 0,
                    {8{16'h0000}},
                    {8{16'h0000}});

        execute_test("8×FP16 负零+负零", 0,
                    {8{16'h8000}},
                    {8{16'h8000}});

        // FP32格式测试
        execute_test("4×FP32 双非规格化数(进位)", 1,
                    128'h007FFFFF007FFFFF007FFFFF007FFFFF,  // 非规格化大数
                    128'h007FFFFF007FFFFF007FFFFF007FFFFF);

        execute_test("4×FP32 异号无穷大", 1,
                    {4{32'h7F800000}},   // +inf
                    {4{32'hFF800000}});  // -inf

        execute_test("4×FP32 规格化进位", 1,
                    {4{32'h7F7FFFFF}},   // MAX_FLOAT
                    {4{32'h7F7FFFFF}});

        execute_test("4×FP32 低位前导1", 1,
                    {4{32'h00000001}},   // 最小非规格化数
                    {4{32'h00000001}});

        execute_test("4×FP32 严格零值", 1,
                    {4{32'h00000000}},
                    {4{32'h00000000}});

        execute_test("4×FP32 负零+负零", 1,
                    {4{32'h80000000}},
                    {4{32'h80000000}});

        // 8×FP16 ─ 覆盖 denorm 相加、进位、zero、carry_out 等
        execute_test("8×FP16 denorm+denorm→denorm", 0,
                    128'h00010001000100010001000100010001,  // 8×0x0001 (denorm)
                    128'h00010001000100010001000100010001); // 8×0x0001  → 8×0x0002

        execute_test("8×FP16 denorm+denorm→规格化", 0,
                    128'h03ff03ff03ff03ff03ff03ff03ff03ff,  // 8×最大 denorm
                    128'h03ff03ff03ff03ff03ff03ff03ff03ff); // → 8×0x0400（规格化）

        execute_test("8×FP16 zero+zero→zero", 0,
                    128'h00000000000000000000000000000000,  // 8×0x0000
                    128'h00000000000000000000000000000000); // → 8×0x0000

        execute_test("8×FP16 inf+inf→inf", 0,
                    128'h7c007c007c007c007c007c007c007c00,  // 8×+inf
                    128'h7c007c007c007c007c007c007c007c00); // → 8×+inf

        execute_test("8×FP16 +inf+(-inf)→NaN", 0,
                    128'h7c007c007c007c007c007c007c007c00,  // 8×+inf
                    128'hfc00fc00fc00fc00fc00fc00fc00fc00); // → 8×NaN

        execute_test("8×FP16 carry_out=1", 0,
                    128'h3bff3bff3bff3bff3bff3bff3bff3bff,  // 8×尾数最大 + round_bit=1
                    128'h3c003c003c003c003c003c003c003c00); // → 8×进位后指数+1

        // 4×FP32 ─ 覆盖 denorm、carry_out、inf、zero
        execute_test("4×FP32 denorm+denorm→规格化", 1,
                    128'h007fffff007fffff007fffff007fffff,  // 4×最大 denorm
                    128'h007fffff007fffff007fffff007fffff); // → 4×0x00800000

        execute_test("4×FP32 carry_out=1", 1,
                    128'h437fffff437fffff437fffff437fffff,  // 4×尾数最大 + round_bit=1
                    128'h43800000438000004380000043800000); // → 4×指数+1

        execute_test("FP32 a_denorm=1, b_denorm=0", 1,
                    {4{32'h00000001}},  // a: 非规格化数（exp=0, frac≠0）
                    {4{32'h3F800000}}); // b: 规格化数（1.0）
                    
        execute_test("FP32 正无穷+正无穷", 1,
                    {4{32'h7F800000}},  // +inf
                    {4{32'h7F800000}}); // +inf

        // 使 sum_mant[1] = 1，其他高位为0，触发 leading_one=1
        execute_test("FP32 sum_mant[1]置位", 1,
                    {4{32'h00000001}},  // a: 极小非规格化数
                    {4{32'h00000001}}); // b: 极小非规格化数（和的mantissa[1]为1）
    
        execute_test("FP16 a_zero=1, b_zero=0", 0,
                {8{16'h0000}},  // a=0
                {8{16'h3C00}}); // b=1.0
        execute_test("8×FP16 混合非规格化数", 0,
                {16'h03FF, 16'h0001, 16'h3C00, 16'h0200, 16'h03FF, 16'h0001, 16'h3C00, 16'h0200},
                {16'h03FF, 16'h0002, 16'h0100, 16'h0300, 16'h03FF, 16'h0002, 16'h0100, 16'h0300});

        // 非规格化相加：0x0001 + 0x0001 = 0x0002
        execute_test("8×FP16 denorm相加(0x0001+0x0001)", 0,
                     {8{16'h0001}},
                     {8{16'h0001}});

        // 非规格化进位：0x03FF + 0x03FF = 0x0400
        execute_test("8×FP16 denorm进位(0x03FF+0x03FF)", 0,
                     {8{16'h03FF}},
                     {8{16'h03FF}});

        // NaN + 任意：0x7E00 + 0x3C00 = NaN
        execute_test("8×FP16 NaN传播(0x7E00+0x3C00)", 0,
                     {8{16'h7E00}},
                     {8{16'h3C00}});

        // 正零 + 负零：0x0000 + 0x8000 = 0x0000
        execute_test("8×FP16 零值合并(+0 + -0)", 0,
                     {8{16'h0000}},
                     {8{16'h8000}});

        // 最大数相加：0x7BFF + 0x7BFF = 0x7C00 (Inf)
        execute_test("8×FP16 最大值相加溢出(0x7BFF+0x7BFF)", 0,
                     {8{16'h7BFF}},
                     {8{16'h7BFF}});

        // 尾数舍入：0x3BFF + 0x3C00，检查 round_bit
        execute_test("8×FP16 尾数舍入(0x3BFF+0x3C00)", 0,
                     {8{16'h3BFF}},
                     {8{16'h3C00}});

        // 非规格化相加：0x00000001 + 0x00000001 = 0x00000002
        execute_test("4×FP32 denorm相加(0x00000001+0x00000001)", 1,
                     {4{32'h00000001}},
                     {4{32'h00000001}});

        // 非规格化进位：0x007FFFFF + 0x007FFFFF = 0x00800000
        execute_test("4×FP32 denorm进位(0x007FFFFF+0x007FFFFF)", 1,
                     {4{32'h007FFFFF}},
                     {4{32'h007FFFFF}});

        // NaN + 任意：0x7FC00000 + 0x3F800000 = NaN
        execute_test("4×FP32 NaN传播(0x7FC00000+0x3F800000)", 1,
                     {4{32'h7FC00000}},
                     {4{32'h3F800000}});

        // 正零 + 负零：0x00000000 + 0x80000000 = 0x00000000
        execute_test("4×FP32 零值合并(+0 + -0)", 1,
                     {4{32'h00000000}},
                     {4{32'h80000000}});

        // 最大数相加：0x7F7FFFFF + 0x7F7FFFFF = 0x7F800000 (Inf)
        execute_test("4×FP32 最大值相加溢出(0x7F7FFFFF+0x7F7FFFFF)", 1,
                     {4{32'h7F7FFFFF}},
                     {4{32'h7F7FFFFF}});

        // 尾数舍入：0x3F7FFFFF + 0x3F800000，检查 round_bit
        execute_test("4×FP32 尾数舍入(0x3F7FFFFF+0x3F800000)", 1,
                     {4{32'h3F7FFFFF}},
                     {4{32'h3F800000}});

        // 4×FP32：a=非零, b=零 → 触发 a_zero=0, b_zero=1
        execute_test("FP32 a非零+b为零", 1,
             {4{32'h3F800000}},  // 1.0
             {4{32'h00000000}}); // 0.0

        // 4×FP32：尾数最大 + 1 → 进位
        execute_test("FP32 尾数最大+1", 1,
             {4{32'h437FFFFF}}, // 255.99998
             {4{32'h3F800000}}); // 1.0

        // 4×FP32：非规格化数相加，触发低位分支
        execute_test("FP32 denorm+denorm→低位leading_one", 1,
             {4{32'h00000001}}, // 最小非规格化
             {4{32'h00000001}});

        // NaN + 任意
        execute_test("FP32 NaN+任意", 1,
                    {4{32'h7FC00000}},
                    {4{32'h3F800000}});

        // Inf + Inf
        execute_test("FP32 Inf+Inf", 1,
                    {4{32'h7F800000}},
                    {4{32'h7F800000}});

        // 最大数溢出
        execute_test("FP32 最大数溢出", 1,
                    {4{32'h7F7FFFFF}},
                    {4{32'h7F7FFFFF}});

        execute_test("FP32 尾数最大+round_bit=1触发carry_out", 1,
             {4{32'h437FFFFF}},  // 255.99998
             {4{32'h3F800000}}); // 1.0

        execute_test("FP32 denorm相加触发leading_one[20]", 1,
             {4{32'h00080000}},  // 非规格化数
             {4{32'h00080000}});

        execute_test("FP32 denorm相加触发leading_one[18]", 1,
             {4{32'h00040000}},  // 非规格化数
             {4{32'h00040000}});

        execute_test("FP32 精确舍入触发round_bit=1", 1,
             {4{32'h3F7FFFFF}},  // 1.9999998
             {4{32'h3F800000}}); // 1.0

        execute_test("FP32 零值 + 非零值", 1,
             {4{32'h00000000}},
             {4{32'h3F800000}});

        execute_test("FP32 两个最小非规格化数相加", 1,
             {4{32'h00000001}},
             {4{32'h00000001}});

        execute_test("FP32 非规格化数 + 规格化数", 1,
             {4{32'h00000001}}, 
             {4{32'h3F800000}});

        execute_test("FP32 无穷大 + 非无穷大", 1, 
             {4{32'h7F800000}}, 
             {4{32'h3F800000}});

        execute_test("FP32 NaN + 非NaN", 1, 
             {4{32'h7FC00000}}, 
             {4{32'h3F800000}});

        execute_test("FP32 最大值 + 最大值", 1, 
             {4{32'h7F7FFFFF}}, 
             {4{32'h7F7FFFFF}});

        execute_test("FP32 最小值 + 最小值", 1, 
             {4{32'h8F7FFFFF}}, 
             {4{32'h8F7FFFFF}});

        execute_test("FP32 正零 + 负零", 1, 
             {4{32'h00000000}}, 
             {4{32'h80000000}});

        execute_test("FP32 正无穷 + 负无穷", 1, 
             {4{32'h7F800000}}, 
             {4{32'hFF800000}});

        // FP32尾数[18:14]位域覆盖
        for (int i=14; i<=18; i++) begin
            execute_test($sformatf("FP32尾数位%d置位", i), 1,
                32'h00400000 << (i-14),
                32'h00400000 << (i-14)
            );
        end

        // FP16精确舍入场景
        execute_test("FP16舍入边界组合", 0,
            {16'h3BFF, 16'h3BFF, 16'h3BFF, 16'h3BFF, 16'h3BFF, 16'h3BFF, 16'h3BFF, 16'h3BFF},
            {16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00, 16'h3C00}
        );

        // 示例：两个 0x0180 相加（尾数和=768，满足 512≤sum<1024）
        execute_test("FP16 denorm 中值相加 (0x0180+0x0180)", 0,
            {8{16'h0180}},  // a = 非规格化数 0x0180
            {8{16'h0180}}   // b = 非规格化数 0x0180
        );
        execute_test("FP16 同号无穷相加 (+Inf++Inf)", 0,
            {8{16'h7C00}},  // +Inf
            {8{16'h7C00}}   // +Inf
        );
        // 示例：尾数=0x3BFF（二进制...0 1111111111），舍入位=1，norm_frac[0]=0
        execute_test("FP16 舍入边界 (0x3BFF+0x3C00)", 0,
            {8{16'h3BFF}}, 
            {8{16'h3C00}}
        );
        // 触发 carry_out=1
        execute_test("FP16 舍入进位 (0x3BFF+0x3C00)", 0,
            {8{16'h3BFF}},  // 尾数全1
            {8{16'h3C00}}   // 加1
        );
        execute_test("FP16 前导1在bit2 (0x0002+0x0002)", 0,
            {8{16'h0002}}, 
            {8{16'h0002}}
        );
        // 示例：为每个通道构造独立边界数据
        execute_test("FP16 全通道边界覆盖", 0,
            128'h03FF_0001_3BFF_0002_03FF_0001_3BFF_0002, // 通道0~7定制数据
            128'h03FF_0002_3C00_0002_03FF_0002_3C00_0002
        );
        // 触发 carry_out=1 的精确用例
        execute_test("FP16 舍入进位 (0x3BFF+0x3BFF)", 0,
            {8{16'h3BFF}},  // a = 尾数全1
            {8{16'h3BFF}}    // b = 尾数全1 (和=2046 → 进位)
        );        
        // 精确触发 bit10=1：输入值需满足 512 ≤ a+b < 1024 且 a+b[10]=1
        execute_test("FP16 denorm触发bit10=1 (0x0200+0x0200)", 0,
            {8{16'h0200}},  // 512 (0x200)
            {8{16'h0200}}   // 512 → 1024 (0x400) 但会触发第一个分支
        );

        // 正确用例：0x01FF + 0x0200 = 511+512=1023 (0x3FF)
        execute_test("FP16 denorm触发bit10=1 (0x01FF+0x0200)", 0,
            {8{16'h01FF}},  // 511
            {8{16'h0200}}   // 512 → 1023 (0x3FF) → bit10=1
        );
        // 触发 carry_out=1：尾数和 ≥ 2048
        // 0x43FF = 1.999 * 8 = 15.992 → 15.992+15.992=31.984 → 尾数和=4095>2048
        execute_test("FP16 尾数进位 (0x43FF+0x43FF)", 0,
            {8{16'h43FF}},  // 尾数0x3FF (1023)
            {8{16'h43FF}}   // 和=2046 → 需规格化进位
        );
        // 构造和=256~511 (bit8为最高位)
        // 规格化数 0x3800 (1.0) + 非规格化数 0x03FF (0.00006) = 1.00006
        execute_test("FP16 前导1在bit8 (0x3800+0x03FF)", 0,
            {8{16'h3800}},  // 1.0
            {8{16'h03FF}}   // 最大非规格化数 → 和=1.00006
        );
        // 构造尾数相等但符号不同
        execute_test("FP16 等尾数异号 (0x3C00+0xBC00)", 0,
            {8{16'h3C00}},  // +1.0
            {8{16'hBC00}}   // -1.0 → 尾数相同
        );

        execute_test("FP32特殊条件组合", 1, 
            {32'h7F800000, 32'hFF800000, 32'h7FC00000, 32'h3F800000}, // +inf,-inf,NaN,1.0
            {32'hFF800000, 32'h7F800000, 32'h3F800000, 32'h7FC00000});
    
        // 添加低位信号翻转测试
        execute_test("FP16低位翻转", 0,
            128'h0001_0002_0004_0008_0010_0020_0040_0080, // 低位设置
            128'h0001_0002_0004_0008_0010_0020_0040_0080);
                // 生成完整的 128-bit 随机值
        // FP16最小非规格化数
        execute_test("FP16 denorm_min", 0, 
            128'h0001_0001_0001_0001_0001_0001_0001_0001,  // 8×最小非规格化数
            128'h0001_0001_0001_0001_0001_0001_0001_0001);

        // FP32最小非规格化数
        execute_test("FP32 denorm_min", 1,
            {4{32'h00000001}},  // 4×最小非规格化数
            {4{32'h00000001}});
        // FP32进位测试 (尾数全1 + 1)
        execute_test("FP32 carry_out", 1,
            {4{32'h7F7FFFFF}},  // 最大规格化数
            {4{32'h7F7FFFFF}}); // 相加产生进位

        // FP16进位测试
        execute_test("FP16 carry_out", 0,
            {8{16'h7BFF}},      // 最大规格化数
            {8{16'h7BFF}});
        // 触发 sum_mant[1]=1
        execute_test("FP16 low_bit_set", 0,
            128'h0001_0001_0001_0001_0001_0001_0001_0001,  // 所有通道设置sum_mant[1]=1
            128'h0000);
        for (j = 0; j < 30; j = j + 1) begin
            a = {$urandom(), $urandom(), $urandom(), $urandom()}; // 128-bit
            b = {$urandom(), $urandom(), $urandom(), $urandom()};
            execute_test($sformatf("随机8FP16_%0d", j), 0, a, b);

            a = {$urandom(), $urandom(), $urandom(), $urandom()};
            b = {$urandom(), $urandom(), $urandom(), $urandom()};
            execute_test($sformatf("随机4FP32_%0d", j), 1, a, b);
        end
    endtask

    initial begin      
        set_softfloat_rounding_mode(0);
        log = $fopen("fpadd_sim.log","w");
        rst_n = 0; #20; rst_n = 1;
        repeat(2) @(posedge clk);
        run_tests();
        repeat(2) @(posedge clk);
        $display("\n=== 总结 ===");
        $display("总测试: %0d, 通过: %0d, 失败: %0d", pass+fail, pass, fail);
        $fdisplay(log, "\n=== 总结 ===");
        $fdisplay(log, "总测试: %0d, 通过: %0d, 失败: %0d", pass+fail, pass, fail);
        $fclose(log);
        $finish;
    end

endmodule