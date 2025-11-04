//---------------------------------------------------------------------
// Filename: tb_logical_unit.v
// Author: cypher
// Date: 2025-8-8
// Version: 1.3  // 修复死循环+覆盖临时无效ID（SMC-ID=31）+解决数据错误
// Description: 仅测试指定3个文件，不修改SMC-ID位宽，符合AIACC文档v0.2.7
//---------------------------------------------------------------------
`timescale 1ns/1ps

module tb_logical_unit();

// 时钟/复位信号
reg  clk;
reg  rst_n;

// DUT输入信号（符合logical.v定义，SMC-ID保持5bit）
reg  [4:0]  smc_id_tb;         // 不修改位宽：5bit（对应DUT的smc_id）
reg  [5:0]  cru_logic;         // CRU输入（6bit）
reg  [127:0] dvr_logic_s0;     // 输入数据0（128bit）
reg  [127:0] dvr_logic_s1;     // 输入数据1（128bit）
reg  [127:0] dvr_logic_st;     // STATUS输入（128bit）

// DUT输出信号
wire [127:0] dr_logic_d;       // 运算结果输出（128bit）
wire [5:0]   cru_logic_o;      // CRU级联输出（6bit）

// DPI-C声明（保留原逻辑，符合测试需求）
import "DPI-C" function void set_softfloat_rounding_mode(input byte unsigned mode);
import "DPI-C" function void clear_softfloat_flags();
import "DPI-C" function byte unsigned get_softfloat_flags();
import "DPI-C" function byte unsigned fp32_compare_softfloat(input bit[31:0] a, input bit[31:0] b);
import "DPI-C" function byte unsigned fp16_compare_softfloat(input bit[15:0] a, input bit[15:0] b);

// 时钟生成（100MHz，周期10ns，符合AIACC文档v0.2.7 FPGA频率定义）
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// 复位生成（初始低电平，#20ns释放，符合数字电路标准）
initial begin
    rst_n = 0;
    #20 rst_n = 1;  // 仅一次复位，之后保持高电平
end

// DUT实例化（严格对应logical.v端口，不修改SMC-ID位宽）
logical_unit dut (
    .clk(clk),
    .rst_n(rst_n),
    .smc_id(smc_id_tb),    // 5bit测试信号驱动DUT
    .cru_logic(cru_logic),
    .dvr_logic_s0(dvr_logic_s0),
    .dvr_logic_s1(dvr_logic_s1),
    .dvr_logic_st(dvr_logic_st),
    .dr_logic_d(dr_logic_d),
    .cru_logic_o(cru_logic_o)
);

// 操作码定义（与DUT完全一致，符合AIACC文档v0.2.7）
parameter [3:0]
    op_and              = 4'b0000,
    op_or               = 4'b0001,
    op_xor              = 4'b0010,
    op_not              = 4'b0011,
    op_copy             = 4'b0100,
    op_select_great     = 4'b0101,
    op_select_equal     = 4'b0110,
    op_select_less      = 4'b0111,
    op_logic_left_shift = 4'b1000,
    op_arith_left_shift = 4'b1001,
    op_rotate_left_shift=4'b1010,
    op_logic_right_shift=4'b1011,
    op_arith_right_shift=4'b1100,
    op_rotate_right_shift=4'b1101,
    op_get_first_one    = 4'b1110,
    op_get_first_zero   = 4'b1111;

// 测试统计变量
integer pass_count = 0;
integer fail_count = 0;
integer total_tests = 0;
integer loop_cnt;  // 32bit循环计数器（解决死循环，不影响SMC-ID位宽）

// -------------------------- 复位测试任务（验证复位时CRU-O=0） --------------------------
task test_cru_reset;
    begin
        $display("\n[TEST] 复位测试（符合AIACC文档v0.2.7复位要求） at %0tns", $time);
        @(posedge clk);  
        #1;  // 避开时钟沿，稳定采样
        if (!rst_n) begin  // 仅在复位期间检查
            if (cru_logic_o !== 6'b0) begin
                $display(" [CRU-RESET FAIL] 复位时CRU-O应为0，实际为: %06b", cru_logic_o);
                fail_count++;
            end else begin
                $display(" [CRU-RESET PASS] 复位时CRU-O=0，符合预期");
                pass_count++;
            end
        end else begin
            $display(" [CRU-RESET ERROR] 未在复位期间执行测试！");
            fail_count++;
        end
        total_tests++;
    end
endtask

// -------------------------- 通用测试任务（验证运算结果+CRU-O） --------------------------
task test_case;
    input  [3:0]  op;          // 操作码
    input         precision;   // 数据精度（1=32bit，0=16bit）
    input  [127:0] src0;       // 输入数据0
    input  [127:0] src1;       // 输入数据1
    input  [127:0] status_in;  // STATUS输入
    input  string  test_name;  // 测试名称
    begin
        integer ch, width, lanes;
        reg [31:0]  exp32 [0:3];  // 32bit预期结果
        reg [15:0]  exp16 [0:7];  // 16bit预期结果
        reg [127:0] expected128;  // 拼接后的预期结果
        reg [2:0]   per_chan_status [0:7];  // 单通道STATUS
        reg [5:0]   expected_cru_o;  // CRU-O预期值

        // 配置CRU输入（指令有效+操作码+精度）
        cru_logic = {1'b0, op, precision};  // 先置指令无效，避免提前更新
        total_tests++;
        clear_softfloat_flags();

        // 计算通道数和数据宽度
        width  = precision ? 32 : 16;
        lanes  = precision ? 4  : 8;

        // 计算运算结果预期值（符合AIACC文档v0.2.7 5.3.12功能定义）
        for (ch = 0; ch < lanes; ch++) begin
            if (width == 32) begin
                automatic logic [31:0] a = src0[32*ch +: 32];
                automatic logic [31:0] b = src1[32*ch +: 32];
                automatic logic [4:0]  sh = b[4:0];
                per_chan_status[ch] = status_in[32*ch +: 3];
                case (op)
                    op_and       : exp32[ch] = a & b;
                    op_or        : exp32[ch] = a | b;
                    op_xor       : exp32[ch] = a ^ b;
                    op_not       : exp32[ch] = ~a;
                    op_copy      : exp32[ch] = a;
                    op_logic_left_shift  : exp32[ch] = a << sh;
                    op_logic_right_shift : exp32[ch] = a >> sh;
                    op_arith_left_shift  : exp32[ch] = $signed(a) <<< sh;
                    op_arith_right_shift : exp32[ch] = $signed(a) >>> sh;
                    op_rotate_left_shift : begin sh = sh % 32; exp32[ch] = (a << sh) | (a >> (32 - sh)); end
                    op_rotate_right_shift: begin sh = sh % 32; exp32[ch] = (a >> sh) | (a << (32 - sh)); end
                    op_get_first_one   : exp32[ch] = (a | b) ? {31'b0, $clog2(a | b)} : 32'b0;
                    op_get_first_zero  : exp32[ch] = (a & b) ? {31'b0, $clog2(~(a & b))} : 32'b0;
                    op_select_great    : exp32[ch] = per_chan_status[ch][2] ? a : b;
                    op_select_equal    : exp32[ch] = per_chan_status[ch][1] ? a : b;
                    op_select_less     : exp32[ch] = per_chan_status[ch][0] ? a : b;
                    default: exp32[ch] = 32'b0;
                endcase
            end else begin
                automatic logic [15:0] a = src0[16*ch +: 16];
                automatic logic [15:0] b = src1[16*ch +: 16];
                automatic logic [3:0]  sh = b[3:0];
                per_chan_status[ch] = status_in[16*ch +: 3];
                case (op)
                    op_and       : exp16[ch] = a & b;
                    op_or        : exp16[ch] = a | b;
                    op_xor       : exp16[ch] = a ^ b;
                    op_not       : exp16[ch] = ~a;
                    op_copy      : exp16[ch] = a;
                    op_logic_left_shift : exp16[ch] = a << sh;
                    op_logic_right_shift: exp16[ch] = a >> sh;
                    op_arith_left_shift : exp16[ch] = $signed(a) <<< sh;
                    op_arith_right_shift: exp16[ch] = $signed(a) >>> sh;
                    op_rotate_left_shift: begin sh = sh % 16; exp16[ch] = (a << sh) | (a >> (16 - sh)); end
                    op_rotate_right_shift: begin sh = sh % 16; exp16[ch] = (a >> sh) | (a << (16 - sh)); end
                    op_get_first_one   : exp16[ch] = (a | b) ? {15'b0, $clog2(a | b)} : 16'b0;
                    op_get_first_zero  : exp16[ch] = (a & b) ? {15'b0, $clog2(~(a & b))} : 16'b0;
                    op_select_great    : exp16[ch] = per_chan_status[ch][2] ? a : b;
                    op_select_equal    : exp16[ch] = per_chan_status[ch][1] ? a : b;
                    op_select_less     : exp16[ch] = per_chan_status[ch][0] ? a : b;
                    default: exp16[ch] = 16'b0;
                endcase
            end
        end

        // 拼接运算结果预期值
        expected128 = (width == 32) ? {exp32[3],exp32[2],exp32[1],exp32[0]}
                                    : {exp16[7],exp16[6],exp16[5],exp16[4],
                                       exp16[3],exp16[2],exp16[1],exp16[0]};

        // 驱动DUT并采样（确保指令有效，解决数据不更新问题）
        @(posedge clk);
        cru_logic      <= {1'b1, op, precision};  // 指令有效（logical_vld_i=1）
        dvr_logic_s0   <= src0;
        dvr_logic_s1   <= src1;
        dvr_logic_st   <= status_in;

        @(posedge clk);  // 等待寄存器更新（解决数据残留问题）
        #1;  // 稳定采样

        // 验证CRU-O（有效ID透传，临时无效ID置0）
        expected_cru_o = (smc_id_tb <= 5'd30) ? {1'b1, op, precision} : 6'b0;
        if (rst_n) begin
            if (cru_logic_o !== expected_cru_o) begin
                $display(" [CRU-O FAIL] %s: 预期=%06b，实际=%06b", test_name, expected_cru_o, cru_logic_o);
                fail_count++;
            end else begin
                $display(" [CRU-O PASS] %s: 预期=%06b，实际=%06b", test_name, expected_cru_o, cru_logic_o);
            end
        end

        // 验证运算结果
        $display("\n[TEST] %s at %0tns", test_name, $time);
        $display(" 精度: %s", precision ? "32-bit" : "16-bit");
        $display(" 输入: S0=%032H, S1=%032H, ST=%032H", src0, src1, status_in);
        $display(" 预期: %032H", expected128);
        $display(" 实际: %032H", dr_logic_d);
        if (dr_logic_d !== expected128) begin
            $display(" [DATA FAIL] %s", test_name);
            fail_count++;
        end else begin
            $display(" [DATA PASS] %s", test_name);
            pass_count++;
        end
    end
endtask

// -------------------------- 主测试流程（解决死循环+覆盖所有需求） --------------------------
initial begin
    // 初始化信号
    set_softfloat_rounding_mode(0);
    smc_id_tb = 5'd0;
    cru_logic = 6'b0;
    dvr_logic_s0 = 128'b0;
    dvr_logic_s1 = 128'b0;
    dvr_logic_st = 128'b0;
    loop_cnt = 0;

    // 步骤1：执行复位测试
    test_cru_reset();  

    // 步骤2：等待复位释放，开始有效ID（0~30）测试（解决死循环）
    @(posedge rst_n);
    #10;  // 稳定后测试
    $display("\n===== 测试1：有效ID覆盖（0~30，符合AIACC文档v0.2.7） =====");
    for (loop_cnt = 0; loop_cnt < 31; loop_cnt = loop_cnt + 1) begin  // 0~30共31次
        smc_id_tb = 5'(loop_cnt);  // 5bit有效ID
        $display("\n--- 当前测试：loop_cnt=%0d，SMC-ID=%0d（有效） ---", loop_cnt, smc_id_tb);

        // 测试1：32bit AND（覆盖32bit数据通路）
        test_case(
            op_and, 1'b1,
            128'hA5A5A5A5_DEADBEEF_12345678_87654321,
            128'h0F0F0F0F_CAFE1234_11111111_22222222,
            128'h0,
            $sformatf("32bit AND（SMC-ID=%0d）", smc_id_tb)
        );

        // 测试2：16bit OR（覆盖16bit数据通路）
        test_case(
            op_or, 1'b0,
            128'h0000FFFF_FFFF0000_1234AAAA_5555AAAA,
            128'h00000000_FFFF0000_0000AAAA_AAAA5555,
            128'h0,
            $sformatf("16bit OR（SMC-ID=%0d）", smc_id_tb)
        );
    end

    // 步骤3：测试临时无效ID（SMC-ID=31），覆盖logical.v 159-161行
    $display("\n===== 测试2：临时无效ID覆盖（SMC-ID=31，测试后需恢复原逻辑） =====");
    smc_id_tb = 5'd31;  // 临时无效ID（5bit可表示）
    $display("--- 当前测试：SMC-ID=%0d（临时无效） ---", smc_id_tb);

    // 测试：32bit AND（验证CRU-O置0+数据正确）
    test_case(
        op_and, 1'b1,
        128'hA5A5A5A5_DEADBEEF_12345678_87654321,
        128'h0F0F0F0F_CAFE1234_11111111_22222222,
        128'h0,
        "32bit AND（SMC-ID=31，临时无效）"
    );
    smc_id_tb = 5'd3;
    $display("\n===== 32-bit 4-channel Tests =====");
    test_case(op_and , 1, 128'hA5A5A5A5_DEADBEEF_12345678_87654321,
                      128'h0F0F0F0F_CAFE1234_11111111_22222222,
                      128'h0, "32-bit AND 4-channel");
    test_case(op_or  , 1, 128'hA5A5A5A5_DEADBEEF_12345678_87654321,
                      128'h0F0F0F0F_CAFE1234_11111111_22222222,
                      128'h0, "32-bit OR 4-channel");
    test_case(op_xor , 1, 128'hA5A5A5A5_DEADBEEF_12345678_87654321,
                      128'h0F0F0F0F_CAFE1234_11111111_22222222,
                      128'h0, "32-bit XOR 4-channel");
    test_case(op_not , 1, 128'hA5A5A5A5_DEADBEEF_12345678_87654321,
                      128'h0, 128'h0, "32-bit NOT 4-channel");
    test_case(op_copy, 1, 128'hDEADBEEF_CAFE1234_12345678_9ABCDEF0,
                      128'h0, 128'h0, "32-bit COPY 4-channel");

    $display("\n===== 16-bit 8-channel Tests =====");
    test_case(op_and , 0, 128'h0000FFFF_FFFF0000_1234AAAA_5555AAAA,
                      128'h00000000_FFFF0000_0000AAAA_AAAA5555,
                      128'h0, "16-bit AND 8-channel");
    test_case(op_or  , 0, 128'h0000FFFF_FFFF0000_1234AAAA_5555AAAA,
                      128'h00000000_FFFF0000_0000AAAA_AAAA5555,
                      128'h0, "16-bit OR 8-channel");
    test_case(op_xor , 0, 128'h0000FFFF_FFFF0000_1234AAAA_5555AAAA,
                      128'h00000000_FFFF0000_0000AAAA_AAAA5555,
                      128'h0, "16-bit XOR 8-channel");
    test_case(op_not , 0, 128'h0000FFFF_FFFF0000_1234AAAA_5555AAAA,
                      128'h0, 128'h0, "16-bit NOT 8-channel");
    test_case(op_copy, 0, 128'h1234AAAA_BBBBCCCC_DDDDEEEE_FFFF0123,
                      128'h0, 128'h0, "16-bit COPY 8-channel");

    $display("\n===== 32-bit Shift 4-channel =====");
    test_case(op_logic_left_shift , 1, 128'hF0F0F0F0_F0F0F0F0_F0F0F0F0_F0F0F0F0,
              128'h00000004_00000004_00000004_00000004, 128'h0, "32-bit Logic Left 4");
    test_case(op_logic_right_shift, 1, 128'hF0F0F0F0_F0F0F0F0_F0F0F0F0_F0F0F0F0,
              128'h00000004_00000004_00000004_00000004, 128'h0, "32-bit Logic Right 4");

    // 新增测试用例：覆盖dvr_logic_st[1]（EQ位）的Toggle
    test_case(op_select_equal, 1,
            128'h11111111_22222222_33333333_44444444,  // S0
            128'h55555555_66666666_77777777_88888888,  // S1
            128'h00000002_00000000_00000000_00000000,  // 第一次：EQ=1（dvr_logic_st[1]=1）
            "32-bit SELECT_EQ EQ=1");
    test_case(op_select_equal, 1,
            128'h11111111_22222222_33333333_44444444,  // 同一S0
            128'h55555555_66666666_77777777_88888888,  // 同一S1
            128'h00000000_00000000_00000000_00000000,  // 第二次：EQ=0（dvr_logic_st[1]=0）
            "32-bit SELECT_EQ EQ=0");

    $display("\n===== 16-bit Shift 8-channel =====");
    test_case(op_logic_left_shift , 0, 128'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0,
              128'h0004_0004_0004_0004_0004_0004_0004_0004, 128'h0, "16-bit Logic Left 4");
    test_case(op_logic_right_shift, 0, 128'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0,
              128'h0004_0004_0004_0004_0004_0004_0004_0004, 128'h0, "16-bit Logic Right 4");
    test_case(op_logic_left_shift, 0,
            128'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0,
            128'h0001_0002_0003_0004_0005_0006_0007_0008,
            128'h0,
            "16-bit Left Shift Different Per Channel");
            
    $display("\n===== SELECT_* Tests =====");
    test_case(op_select_great, 1,
              128'h11111111_33333333_55555555_77777777,
              128'h22222222_44444444_66666666_88888888,
              128'h00000004_00000002_00000001_00000004, "32-bit SELECT_GT full");
    test_case(op_select_equal, 1,
              128'h11111111_33333333_55555555_77777777,
              128'h22222222_44444444_66666666_88888888,
              128'h00000004_00000002_00000001_00000004, "32-bit SELECT_EQ full");
    test_case(op_select_less, 1,
              128'h11111111_33333333_55555555_77777777,
              128'h22222222_44444444_66666666_88888888,
              128'h00000004_00000002_00000001_00000004,"32-bit SELECT_LS full");

    test_case(op_select_less, 0,
              {16'h1111,16'h3333,16'h5555,16'h7777,16'h9999,16'h1111,16'h3333,16'h5555},
              {16'h2222,16'h4444,16'h6666,16'h8888,16'h0000,16'h2222,16'h4444,16'h6666},
              128'h0004_0001_0002_0004_0001_0002_0004_0001, "16-bit SELECT_LS full");

    test_case(op_select_great, 0,
              {16'h1111,16'h3333,16'h5555,16'h7777,16'h9999,16'h1111,16'h3333,16'h5555},
              {16'h2222,16'h4444,16'h6666,16'h8888,16'h0000,16'h2222,16'h4444,16'h6666},
              128'h0004_0001_0002_0004_0001_0002_0004_0001, "16-bit SELECT_GT full");

    test_case(op_select_equal, 0,
              {16'h1111,16'h3333,16'h5555,16'h7777,16'h9999,16'h1111,16'h3333,16'h5555},
              {16'h2222,16'h4444,16'h6666,16'h8888,16'h0000,16'h2222,16'h4444,16'h6666},
              128'h0004_0001_0002_0004_0001_0002_0004_0001,  "16-bit SELECT_EQ full");

    $display("\n===== First-One / First-Zero Tests =====");
    test_case(op_get_first_one, 1,
              128'h00000001_00000020_00000800_00400000,
              128'h0, 128'h0, "32-bit GET_FIRST_ONE");
    test_case(op_get_first_zero, 1,
              128'hFFFFFFFE_FFFFFFFD_FFFFF7FF_FF3FFFFF,
              128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF,
              128'h0, "32-bit GET_FIRST_ZERO");
    test_case(op_get_first_one, 0,
              128'h0001_0002_0004_0008_0010_0020_0040_8000,
              128'h0, 128'h0, "16-bit GET_FIRST_ONE");
    test_case(op_get_first_zero, 0,
              128'hFFFE_FFFD_FFFB_FFF7_FFEF_FFDF_FFBF_7FFF,
              128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF,
              128'h0, "16-bit GET_FIRST_ZERO");

    $display("\n===== Additional Coverage Tests =====");
    // 用例1：32bit通道0的EQ=1（dvr_logic_st[1] = 1）
    test_case(op_select_equal, 1,  // precision=1（32bit），op=SELECT_EQ
            128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD,  // s0：通道0=AAAAAAAA
            128'hAAAAAAAA_EEEEEEEE_FFFFFFFF_11111111,  // s1：通道0=AAAAAAAA（与s0相等）
            128'h00000002_00000000_00000000_00000000,  // status_in：32*0+1=bit1=1（EQ=1），其他通道EQ=0
            "32bit Ch0 EQ=1 (dvr_logic_st[1] = 1)");

    // 用例2：32bit通道0的EQ=0（dvr_logic_st[1] = 0）
    test_case(op_select_equal, 1,  // 同样32bit精度+SELECT_EQ
            128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD,  // s0：通道0=AAAAAAAA
            128'hBBBBBBBB_EEEEEEEE_FFFFFFFF_11111111,  // s1：通道0=BBBBBBBB（与s0不相等）
            128'h00000000_00000000_00000000_00000000,  // status_in：32*0+1=bit1=0（EQ=0）
            "32bit Ch0 EQ=0 (dvr_logic_st[1] = 0)");

    test_case(op_arith_right_shift, 1,
              128'hF0F0F0F0_F0F0F0F0_F0F0F0F0_F0F0F0F0,
              128'h00000004_00000004_00000004_00000004,
              128'h0, "32-bit Arith Right Shift 4");

    test_case(op_arith_left_shift, 1,
              128'h80000001_80000002_80000004_80000008,
              128'h00000001_00000002_00000003_00000004,
              128'h0, "32-bit Arith Left Shift");

    test_case(op_rotate_left_shift, 1,
              128'h12345678_87654321_DEADBEEF_CAFE1234,
              128'h00000003_00000005_00000007_00000009,
              128'h0, "32-bit Rotate Left");

    test_case(op_rotate_right_shift, 1,
              128'h12345678_87654321_DEADBEEF_CAFE1234,
              128'h00000003_00000005_00000007_00000009,
              128'h0, "32-bit Rotate Right");

    test_case(op_arith_right_shift, 0,
              128'hF0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0_F0F0,
              128'h0004_0004_0004_0004_0004_0004_0004_0004,
              128'h0, "16-bit Arith Right Shift 4");

    test_case(op_get_first_one, 1,
              128'h0, 128'h0, 128'h0, "32-bit GET_FIRST_ONE All Zero");

    test_case(op_get_first_zero, 1,
              128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF,
              128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF,
              128'h0, "32-bit GET_FIRST_ZERO All One");

    test_case(op_select_equal, 1,
              128'h12345678_12345678_12345678_12345678,
              128'h12345678_12345678_12345678_12345678,
              128'h00000004_00000004_00000004_00000004, "32-bit SELECT_EQ All EQ");

    test_case(op_logic_left_shift, 1,
              128'h12345678_12345678_12345678_12345678,
              128'h00000028_00000028_00000028_00000028,
              128'h0, "32-bit Left Shift Overflow");

    test_case(op_arith_left_shift, 0,
            128'h8001_8002_8003_8004_8005_8006_8007_8008,
            128'h0001_0002_0003_0004_0005_0006_0007_0008,
            128'h0, "16-bit Arith Left Shift");

    test_case(op_rotate_left_shift, 0,
            128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0,
            128'h0003_0005_0007_0009_000B_000D_000F_0011,
            128'h0, "16-bit Rotate Left");

    test_case(op_rotate_right_shift, 0,
            128'h1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0,
            128'h0003_0005_0007_0009_000B_000D_000F_0011,
            128'h0, "16-bit Rotate Right");

    // -------------------------- 修正：按官方定义驱动 status_in --------------------------
    $display("\n===== Test dvr_logic_st[1] (Ch0 EQ) Toggle =====");

    // 用例1：32bit 精度，通道0 EQ=1（dvr_logic_st[1] = 1）
    test_case(op_select_equal, 1,  // precision=1（32bit），op=SELECT_EQ
            128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD,  // s0：通道0=AAAAAAAA
            128'hAAAAAAAA_EEEEEEEE_FFFFFFFF_11111111,  // s1：通道0与s0相等（EQ=1）
            128'h00000002_00000000_00000000_00000000,  // status_in：Bit1=1（EQ=1），其他组为0
            "32bit Ch0 EQ=1 (dvr_logic_st[1] = 1)");

    // 用例2：32bit 精度，通道0 EQ=0（dvr_logic_st[1] = 0）
    test_case(op_select_equal, 1,  // 32bit 精度
            128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD,  // s0：通道0=AAAAAAAA
            128'hBBBBBBBB_EEEEEEEE_FFFFFFFF_11111111,  // s1：通道0与s0不相等（EQ=0）
            128'h00000000_00000000_00000000_00000000,  // status_in：Bit1=0（EQ=0）
            "32bit Ch0 EQ=0 (dvr_logic_st[1] = 0)");

    // 用例3：16bit 精度，通道0 EQ=1（dvr_logic_st[1] = 1）
    test_case(op_select_equal, 0,  // precision=0（16bit）
            128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_11111111_22222222,  // s0：通道0=AAAA
            128'hAAAAAAAA_EEEEEEEE_FFFFFFFF_11111111_22222222_33333333_44444444_55555555,  // s1：通道0与s0相等（EQ=1）
            128'h00000002_00000000_00000000_00000000_00000000_00000000_00000000_00000000,  // status_in：Bit1=1
            "16bit Ch0 EQ=1 (dvr_logic_st[1] = 1)");

    // 用例4：16bit 精度，通道0 EQ=0（dvr_logic_st[1] = 0）
    test_case(op_select_equal, 0,  // 16bit 精度
            128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_11111111_22222222,  // s0：通道0=AAAA
            128'hBBBBBBBB_EEEEEEEE_FFFFFFFF_11111111_22222222_33333333_44444444_55555555,  // s1：通道0与s0不相等（EQ=0）
            128'h00000000_00000000_00000000_00000000_00000000_00000000_00000000_00000000,  // status_in：Bit1=0
            "16bit Ch0 EQ=0 (dvr_logic_st[1] = 0)");

    $display("\n===== 32-bit GT/EQ/LS All Bits Toggle Tests =====");
    // 第0组（对应dvr_logic_st[2:0]：GT=2, EQ=1, LS=0）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000004_00000000_00000000_00000000, "32bit Grp0 GT=1"); // GT=1（bit2=1）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp0 GT=0"); // GT=0（bit2=0）- 翻转
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000002_00000000_00000000_00000000, "32bit Grp0 EQ=1"); // EQ=1（bit1=1）
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp0 EQ=0"); // EQ=0（bit1=0）- 翻转
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000001_00000000_00000000_00000000, "32bit Grp0 LS=1"); // LS=1（bit0=1）
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp0 LS=0"); // LS=0（bit0=0）- 翻转

    // 第1组（对应dvr_logic_st[34:32]：GT=34, EQ=33, LS=32）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000004_00000000_00000000, "32bit Grp1 GT=1"); // GT=1（bit34=1）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp1 GT=0"); // GT=0（bit34=0）- 翻转
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000002_00000000_00000000, "32bit Grp1 EQ=1"); // EQ=1（bit33=1）
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp1 EQ=0"); // EQ=0（bit33=0）- 翻转
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000001_00000000_00000000, "32bit Grp1 LS=1"); // LS=1（bit32=1）
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp1 LS=0"); // LS=0（bit32=0）- 翻转

    // 第2组（对应dvr_logic_st[66:64]：GT=66, EQ=65, LS=64）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000004_00000000, "32bit Grp2 GT=1"); // GT=1（bit66=1）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp2 GT=0"); // GT=0（bit66=0）- 翻转
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000002_00000000, "32bit Grp2 EQ=1"); // EQ=1（bit65=1）
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp2 EQ=0"); // EQ=0（bit65=0）- 翻转
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000001_00000000, "32bit Grp2 LS=1"); // LS=1（bit64=1）
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp2 LS=0"); // LS=0（bit64=0）- 翻转

    // 第3组（对应dvr_logic_st[98:96]：GT=98, EQ=97, LS=96）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000004, "32bit Grp3 GT=1"); // GT=1（bit98=1）
    test_case(op_select_great, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp3 GT=0"); // GT=0（bit98=0）- 翻转
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000002, "32bit Grp3 EQ=1"); // EQ=1（bit97=1）
    test_case(op_select_equal, 1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp3 EQ=0"); // EQ=0（bit97=0）- 翻转
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000001, "32bit Grp3 LS=1"); // LS=1（bit96=1）
    test_case(op_select_less,  1, 128'h00000000_00000000_00000000_00000000, 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF, 128'h00000000_00000000_00000000_00000000, "32bit Grp3 LS=0"); // LS=0（bit96=0）- 翻转

    $display("\n===== 16-bit GT/EQ/LS All Bits Toggle Tests =====");
    // 第0组（对应dvr_logic_st[2:0]：GT=2, EQ=1, LS=0）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0004_0000_0000_0000_0000_0000_0000_0000, "16bit Grp0 GT=1"); // GT=1（bit2=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp0 GT=0"); // GT=0（bit2=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0002_0000_0000_0000_0000_0000_0000_0000, "16bit Grp0 EQ=1"); // EQ=1（bit1=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp0 EQ=0"); // EQ=0（bit1=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0001_0000_0000_0000_0000_0000_0000_0000, "16bit Grp0 LS=1"); // LS=1（bit0=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp0 LS=0"); // LS=0（bit0=0）- 翻转

    // 第1组（对应dvr_logic_st[18:16]：GT=18, EQ=17, LS=16）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0004_0000_0000_0000_0000_0000_0000, "16bit Grp1 GT=1"); // GT=1（bit18=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp1 GT=0"); // GT=0（bit18=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0002_0000_0000_0000_0000_0000_0000, "16bit Grp1 EQ=1"); // EQ=1（bit17=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp1 EQ=0"); // EQ=0（bit17=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0001_0000_0000_0000_0000_0000_0000, "16bit Grp1 LS=1"); // LS=1（bit16=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp1 LS=0"); // LS=0（bit16=0）- 翻转

    // 第2组（对应dvr_logic_st[34:32]：GT=34, EQ=33, LS=32）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0004_0000_0000_0000_0000_0000, "16bit Grp2 GT=1"); // GT=1（bit34=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp2 GT=0"); // GT=0（bit34=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0002_0000_0000_0000_0000_0000, "16bit Grp2 EQ=1"); // EQ=1（bit33=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp2 EQ=0"); // EQ=0（bit33=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0001_0000_0000_0000_0000_0000, "16bit Grp2 LS=1"); // LS=1（bit32=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp2 LS=0"); // LS=0（bit32=0）- 翻转

    // 第3组（对应dvr_logic_st[50:48]：GT=50, EQ=49, LS=48）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0004_0000_0000_0000_0000, "16bit Grp3 GT=1"); // GT=1（bit50=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp3 GT=0"); // GT=0（bit50=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0002_0000_0000_0000_0000, "16bit Grp3 EQ=1"); // EQ=1（bit49=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp3 EQ=0"); // EQ=0（bit49=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0001_0000_0000_0000_0000, "16bit Grp3 LS=1"); // LS=1（bit48=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp3 LS=0"); // LS=0（bit48=0）- 翻转

    // 第4组（对应dvr_logic_st[66:64]：GT=66, EQ=65, LS=64）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0004_0000_0000_0000, "16bit Grp4 GT=1"); // GT=1（bit66=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp4 GT=0"); // GT=0（bit66=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0002_0000_0000_0000, "16bit Grp4 EQ=1"); // EQ=1（bit65=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp4 EQ=0"); // EQ=0（bit65=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0001_0000_0000_0000, "16bit Grp4 LS=1"); // LS=1（bit64=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp4 LS=0"); // LS=0（bit64=0）- 翻转

    // 第5组（对应dvr_logic_st[82:80]：GT=82, EQ=81, LS=80）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0004_0000_0000, "16bit Grp5 GT=1"); // GT=1（bit82=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp5 GT=0"); // GT=0（bit82=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0002_0000_0000, "16bit Grp5 EQ=1"); // EQ=1（bit81=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp5 EQ=0"); // EQ=0（bit81=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0001_0000_0000, "16bit Grp5 LS=1"); // LS=1（bit80=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp5 LS=0"); // LS=0（bit80=0）- 翻转

    // 第6组（对应dvr_logic_st[98:96]：GT=98, EQ=97, LS=96）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0004_0000, "16bit Grp6 GT=1"); // GT=1（bit98=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp6 GT=0"); // GT=0（bit98=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0002_0000, "16bit Grp6 EQ=1"); // EQ=1（bit97=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp6 EQ=0"); // EQ=0（bit97=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0001_0000, "16bit Grp6 LS=1"); // LS=1（bit96=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp6 LS=0"); // LS=0（bit96=0）- 翻转

    // 第7组（对应dvr_logic_st[114:112]：GT=114, EQ=113, LS=112）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0004, "16bit Grp7 GT=1"); // GT=1（bit114=1）
    test_case(op_select_great, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp7 GT=0"); // GT=0（bit114=0）- 翻转
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0002, "16bit Grp7 EQ=1"); // EQ=1（bit113=1）
    test_case(op_select_equal, 0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp7 EQ=0"); // EQ=0（bit113=0）- 翻转
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0001, "16bit Grp7 LS=1"); // LS=1（bit112=1）
    test_case(op_select_less,  0, 128'h00000000000000000000000000000000, 128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 128'h0000_0000_0000_0000_0000_0000_0000_0000, "16bit Grp7 LS=0"); // LS=0（bit112=0）- 翻转

    // 测试总结
        @(posedge clk);
        rst_n = 0; // 第二次切换：1→0（重新拉低复位）
        @(posedge clk); // 保持复位1个周期
        rst_n = 1; // 第三次切换：0→1（再次释放复位）
        $display("[二次复位] rst_n Toggle完成（1→0→1）");
        @(posedge clk);   

    // 步骤4：测试总结
    #20;
    $display("\n===== 测试总结（基于指定3个文件） =====");
    $display(" 总测试用例数：%0d", total_tests);
    $display(" Pass用例数：%0d，Fail用例数：%0d", pass_count, fail_count);
    if (fail_count == 0)
        $display(" 【SUCCESS】所有测试通过！测试后请恢复logical.v原逻辑（见代码备注）");
    else
        $display(" 【FAILURE】部分测试失败，请检查！");
    
    $finish;  // 强制结束仿真，避免卡住
end

// 波形dump（便于调试）
initial begin
    $dumpfile("tb_logical_unit.vcd");
    $dumpvars(0, tb_logical_unit);
end

endmodule