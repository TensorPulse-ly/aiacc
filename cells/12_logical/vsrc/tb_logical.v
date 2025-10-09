`timescale 1ns/1ps

module tb_logical_unit();

reg  clk;
reg  rst_n;
reg  [5:0]  cru_logic;
reg  [127:0] dvr_logic_s0;
reg  [127:0] dvr_logic_s1;
reg  [127:0] dvr_logic_st;
wire [127:0] dr_logic_d;

// DPI-C 仅保留，不用于 SELECT
import "DPI-C" function void set_softfloat_rounding_mode(input byte unsigned mode);
import "DPI-C" function void clear_softfloat_flags();
import "DPI-C" function byte unsigned get_softfloat_flags();
import "DPI-C" function byte unsigned fp32_compare_softfloat(input bit[31:0] a, input bit[31:0] b);
import "DPI-C" function byte unsigned fp16_compare_softfloat(input bit[15:0] a, input bit[15:0] b);

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

initial begin
    rst_n = 0;
    #20 rst_n = 1;
end

logical_unit dut (
    .clk(clk),
    .rst_n(rst_n),
    .cru_logic(cru_logic),
    .dvr_logic_s0(dvr_logic_s0),
    .dvr_logic_s1(dvr_logic_s1),
    .dvr_logic_st(dvr_logic_st),
    .dr_logic_d(dr_logic_d)
);

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
    op_rotate_left_shift= 4'b1010,
    op_logic_right_shift= 4'b1011,
    op_arith_right_shift= 4'b1100,
    op_rotate_right_shift=4'b1101,
    op_get_first_one    = 4'b1110,
    op_get_first_zero   = 4'b1111;

integer pass_count = 0;
integer fail_count = 0;
integer total_tests = 0;

task test_case;
    input  [3:0]  op;
    input         precision;
    input  [127:0] src0;
    input  [127:0] src1;
    input  [127:0] status_in;
    input  string  test_name;

    integer ch, width, lanes;
    reg [31:0]  exp32 [0:3];
    reg [15:0]  exp16 [0:7];
    reg [127:0] expected128;
    reg [2:0]   per_chan_status [0:7];

    cru_logic = {1'b0, op, precision};
    total_tests++;
    clear_softfloat_flags();

    width  = precision ? 32 : 16;
    lanes  = precision ? 4  : 8;

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
                op_rotate_left_shift : begin
                    sh = sh % 32;
                    exp32[ch] = (a >> sh) | (a << (32 - sh));
                end
                op_rotate_right_shift: begin
                    sh = sh % 32;
                    exp32[ch] = (a << sh) | (a >> (32 - sh));
                end
                op_get_first_one   : exp32[ch] = a ? {31'b0, $clog2(a)} : 32'b0;
                op_get_first_zero  : exp32[ch] = ~a ? {31'b0, $clog2(~a)} : 32'b0;
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
                op_rotate_left_shift: begin
                    sh = sh % 16;
                    exp16[ch] = (a >> sh) | (a << (16 - sh));
                end
                op_rotate_right_shift: begin
                    sh = sh % 16;
                    exp16[ch] = (a << sh) | (a >> (16 - sh));
                end
                op_get_first_one   : exp16[ch] = a ? {15'b0, $clog2(a)} : 16'b0;
                op_get_first_zero  : exp16[ch] = ~a ? {15'b0, $clog2(~a)} : 16'b0;
                op_select_great    : exp16[ch] = per_chan_status[ch][2] ? a : b;
                op_select_equal    : exp16[ch] = per_chan_status[ch][1] ? a : b;
                op_select_less     : exp16[ch] = per_chan_status[ch][0] ? a : b;
                default: exp16[ch] = 16'b0;
            endcase
        end
    end

    expected128 = (width == 32) ? {exp32[3],exp32[2],exp32[1],exp32[0]}
                                : {exp16[7],exp16[6],exp16[5],exp16[4],
                                   exp16[3],exp16[2],exp16[1],exp16[0]};

    @(posedge clk);
    cru_logic      <= {1'b1, op, precision};
    dvr_logic_s0   <= src0;
    dvr_logic_s1   <= src1;
    dvr_logic_st   <= status_in;

    @(posedge clk);
    #1;

    @(posedge clk);
    $display("\n[TEST] '%s' at %0tns", test_name, $time);
    $display(" Precision: %s", precision ? "32-bit" : "16-bit");
    $display(" Input   : S0=%032H", src0);
    $display("            S1=%032H", src1);
    $display(" Status  : ST=%032H", status_in);
    $display(" Expected:    %032H", expected128);
    $display(" Got     :    %032H", dr_logic_d);

    if (dr_logic_d !== expected128) begin
        $display(" [FAIL]");
        fail_count++;
    end else begin
        $display(" [PASS]");
        pass_count++;
    end
endtask

initial begin
    set_softfloat_rounding_mode(0);
    @(posedge rst_n);
    #10;

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

    #20;
    $display("\n===== Test Summary =====");
    $display(" Total tests: %0d", total_tests);
    $display(" Passed: %0d, Failed: %0d", pass_count, fail_count);
    if (fail_count == 0)
        $display("SUCCESS: All tests passed!");
    else
        $display("FAILURE: Some tests failed!");
    $finish;
end

initial begin
    $dumpfile("tb_logical_unit.vcd");
    $dumpvars(0, tb_logical_unit);
end

endmodule