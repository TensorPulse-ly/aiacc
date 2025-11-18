`timescale 1ns/1ps
module stb_shell_tb #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter SMC_COUNT = 6
)(
    // input                                clk,
    // input                                rst_n,
    
    // output reg                           i_micro_inst_u_valid,
    // output reg [5:0]                     i_micro_inst_u_smc_strb,
    // output reg [3:0]                     i_micro_inst_u_byte_strb,
    // output reg [1:0]                     i_micro_inst_u_brst,           // （2bit：00=1，01=2，10=4，11=8）
    // output reg [ADDR_WIDTH-1:0]          i_micro_inst_u_gr_base_addr,   // outside sram addr
    // output reg [3:0]                     i_micro_inst_u_ur_id,
    // output reg [10:0]                    i_micro_inst_u_ur_addr,        //user addr
    // input                                o_micro_inst_d_valid,
    // input                                o_micro_inst_d_done,

    // output reg  [DATA_WIDTH-1:0]         i_src_random_data,
    // input       [4:0]                    o_state
);

localparam   TEST_IDLE          = 4'b0001;
localparam   TEST_START         = 4'b0010;
localparam   TEST_WAIT          = 4'b0100;
localparam   TEST_NEXT          = 4'b1000;

localparam   RANDOM_TEST_TIMES  = 16'd1000;

reg [3:0]                     test_state;
reg [15:0]                    r_random_cnt;

wire                          clk;
wire                          rst_n;

reg                           i_micro_inst_u_valid;
reg [5:0]                     i_micro_inst_u_smc_strb;
reg [3:0]                     i_micro_inst_u_byte_strb;
reg [1:0]                     i_micro_inst_u_brst;           // （2bit：00=1，01=2，10=4，11=8）
reg [ADDR_WIDTH-1:0]          i_micro_inst_u_gr_base_addr;   // outside sram addr
reg [3:0]                     i_micro_inst_u_ur_id;
reg [10:0]                    i_micro_inst_u_ur_addr;        //user addr
wire                          o_micro_inst_d_valid;
wire                          o_micro_inst_d_done;
reg  [DATA_WIDTH-1:0]         i_src_random_data;
wire [4:0]                    o_state;

// 时钟与复位生成（自动驱动）
reg clk_gen;
reg rst_n_gen;
// reg tb_en_gen;

reg [3:0]                     r_test_case;
reg [4:0]                     r_state_prev;

integer i;

initial begin
    clk_gen   = 1'b0;
    rst_n_gen = 1'b0;
    // tb_en_gen = 1'b0;
    
    // 复位序列（100ns低电平）
    #100
    rst_n_gen = 1'b1;
    $display("[TB] 时间%0t: 复位释放，准备启动测试", $time);
    
    // 启动测试（延迟100ns确保模块稳定）
    // #100
    // tb_en_gen = 1'b1;
    // $display("[TB] 时间%0t: tb_en置1，开始执行测试用例", $time);
    
    // 仿真超时保护（10ms未完成则强制结束）
    #10000000
    $display("[TB] 时间%0t: 仿真超时（1ms），强制结束", $time);
    $finish;
end

// 50MHz时钟（周期20ns）
always #10 clk_gen = ~clk_gen;

// 信号连接：测试平台→axi_top
assign clk = clk_gen;
assign rst_n = rst_n_gen;
// assign tb_en = tb_en_gen;

`ifndef FSDB_GENERAL
    initial begin
        $fsdbDumpfile("stb.fsdb");
        $fsdbDumpvars(0, u_stb_shell);
    end
`endif

stb_shell #(
    .UR_ADDR_WIDTH      (11),
    .ADDR_WIDTH         (32),
    .ATA_WIDTH          (128),
    .INTLV_STEP         (128)     //SMC  interleave step
) u_stb_shell(
    .clk                                 (clk),
    .rst_n                               (rst_n),
    .i_micro_inst_u_valid                (i_micro_inst_u_valid),
    .i_micro_inst_u_smc_strb             (i_micro_inst_u_smc_strb),
    .i_micro_inst_u_byte_strb            (i_micro_inst_u_byte_strb),
    .i_micro_inst_u_brst                 (i_micro_inst_u_brst),
    .i_micro_inst_u_gr_base_addr         (i_micro_inst_u_gr_base_addr),
    .i_micro_inst_u_ur_id                (i_micro_inst_u_ur_id),
    .i_micro_inst_u_ur_addr              (i_micro_inst_u_ur_addr),
    .o_micro_inst_d_valid                (o_micro_inst_d_valid),
    .o_micro_inst_d_done                 (o_micro_inst_d_done),
    .i_src_random_data                   (i_src_random_data),
    .o_state                             (o_state)
);

always @(posedge clk) begin
    r_state_prev    <= o_state;
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        i_micro_inst_u_valid             <= 1'b0;
        i_micro_inst_u_smc_strb          <= 6'd0;
        i_micro_inst_u_byte_strb         <= 4'd0;
        i_micro_inst_u_brst              <= 2'd0;
        i_micro_inst_u_gr_base_addr      <= 32'd0;
        i_micro_inst_u_ur_id             <= 4'd0;
        i_micro_inst_u_ur_addr           <= 11'd0;
        i_src_random_data                <= 128'd0;
        r_test_case                       <= 4'd0;
        test_state                       <= 4'b0001;
        r_random_cnt                     <= 16'd0;
    end else begin
        case (test_state)
            TEST_IDLE: begin
                case(r_test_case)
                    4'd0: begin
                        $display("\n==================================================");
                        $display("[TB] 时间%0t: 测试初始化完成，准备执行测试用例1（随机数据写入）", $time);
                        $display("==================================================\n");

                        r_test_case              <= 4'd1;
                    end

                    // 测试用例1：单次burst（1拍），SMC0使能，写入地址0x1000
                    4'd1: begin
                        $display("[TB] 时间%0t: 测试用例1启动", $time);
                        config_test_case(6'b000000, 4'h0, 2'b00, 32'h0000_1000, 4'd0, 11'h000);

                        test_state              <= TEST_START;
                    end

                    // 测试用例2：单次burst（1拍），SMC0-SMC1使能，写入地址0x2000
                    4'd2: begin
                        $display("[TB] 时间%0t: 测试用例2启动", $time);
                        config_test_case(6'b000001, 4'h0, 2'b00, 32'h0000_2000, 4'd0, 11'h010);

                        test_state              <= TEST_START;
                    end

                    // 测试用例3：单次burst（1拍），SMC0-SMC31使能，写入地址0x3000
                    4'd3: begin
                        $display("[TB] 时间%0t: 测试用例3启动", $time);
                        config_test_case(6'b011111, 4'h0, 2'b00, 32'h0000_3000, 4'd0, 11'h020);

                        test_state              <= TEST_START;
                    end

                    // 测试用例4：burst（8拍），SMC0使能，写入地址0x4000
                    4'd4: begin
                        $display("[TB] 时间%0t: 测试用例4启动", $time);
                        config_test_case(6'b000000, 4'h0, 2'b11, 32'h0000_4000, 4'd0, 11'h030);

                        test_state              <= TEST_START;
                    end

                    // 测试用例5：burst（8拍），SMC0-SMC1使能，写入地址0x5000
                    4'd5: begin
                        $display("[TB] 时间%0t: 测试用例5启动", $time);
                        config_test_case(6'b000001, 4'h0, 2'b11, 32'h0000_5000, 4'd0, 11'h040);

                        test_state              <= TEST_START;
                    end

                    // 测试用例6：burst（8拍），SMC0-SMC31使能，写入地址0x6000
                    4'd6: begin
                        $display("[TB] 时间%0t: 测试用例6启动", $time);
                        config_test_case(6'b011111, 4'h0, 2'b11, 32'h0000_6000, 4'd0, 11'h050);

                        test_state              <= TEST_START;
                    end

                    // 测试用例7：burst（1拍），SMC0使能，写入地址0x7000，部分字节有效
                    4'd7: begin
                        $display("[TB] 时间%0t: 测试用例7启动", $time);
                        config_test_case(6'b000000, 4'hb, 2'b00, 32'h0000_7000, 4'd0, 11'h060);

                        test_state              <= TEST_START;
                    end

                    // 测试用例8：burst（8拍），SMC0使能，写入地址0x8000，部分字节有效
                    4'd8: begin
                        $display("[TB] 时间%0t: 测试用例8启动", $time);
                        config_test_case(6'b000000, 4'hc, 2'b11, 32'h0000_8000, 4'd0, 11'h070);

                        test_state              <= TEST_START;
                    end

                    //随机
                    4'd9: begin
                        if(r_random_cnt < RANDOM_TEST_TIMES) begin
                            $display("[TB] 时间%0t: 测试用例%d启动", $time, r_random_cnt+9);

                            r_random_cnt        <= r_random_cnt + 16'd1;

                            config_test_case({1'b0, {{$random} & 32'h3f}[4:0]}, 
                                             {{$random} & 32'h0f}[3:0], 
                                             {{$random} & 32'h03}[1:0], 
                                             {$random} & 32'hffff_fff0, 
                                             4'd0, 
                                             {{$random}[10:0]} & 11'h7f0);

                            test_state          <= TEST_START;
                        end else begin
                            r_random_cnt        <= RANDOM_TEST_TIMES;

                        end
                    end

                    4'd10: begin
                        $display("\n==================================================");
                        $display("[TB] 所有测试用例执行完成");
                        $display("==================================================\n");
                        #100
                        $finish; // 结束仿真
                    end
                endcase
            end

            TEST_START: begin
                i_micro_inst_u_valid            <= 1'b1;
                // i_src_random_data               <= {$random, $random, $random, $random};

                test_state                      <= TEST_WAIT;
            end

            TEST_WAIT: begin
                i_micro_inst_u_valid            <= 1'b0;
                i_src_random_data               <= {$random, $random, $random, $random};

                if (r_state_prev == 5'b1_0000 && o_state == 5'b0_0001) begin
                    test_state                  <= TEST_NEXT;
                end
            end

            TEST_NEXT: begin
                if (r_test_case < 4'd9) begin
                    r_test_case                  <= r_test_case + 1;
                end else if((r_random_cnt < RANDOM_TEST_TIMES) && (r_test_case == 4'd9)) begin
                    r_test_case                  <= 4'd9;
                end else begin
                    r_test_case                  <= 4'd10;
                end

                test_state                      <= TEST_IDLE;
            end
        endcase
    end
end

task automatic config_test_case(
    input  [5:0]          smc_strb,
    input  [3:0]          byte_strb,
    input  [1:0]          brst,
    input  [31:0]         gr_base_addr,
    input  [3:0]          ur_id,
    input  [10:0]         ur_addr
);
    begin
        i_micro_inst_u_smc_strb       <= smc_strb;
        i_micro_inst_u_byte_strb      <= byte_strb;
        i_micro_inst_u_brst           <= brst;
        i_micro_inst_u_gr_base_addr   <= gr_base_addr;
        i_micro_inst_u_ur_id          <= ur_id;
        i_micro_inst_u_ur_addr        <= ur_addr;

        $display("[TB]   SMC使能   : 6'b%b", smc_strb);
        $display("[TB]   字节使能  : 4'b%b", byte_strb);
        $display("[TB]   Burst长度 : %0d拍", get_burst_length(brst));
        $display("[TB]   基地址    : 0x%h", gr_base_addr);
        $display("[TB]   UR地址    : 0x%h", ur_addr);
    end
endtask

function integer get_burst_length;
    input  [1:0] burst;
    begin
        case(burst)
            2'b00: get_burst_length    = 1;
            2'b01: get_burst_length    = 2;
            2'b10: get_burst_length    = 4;
            2'b11: get_burst_length    = 8;
        endcase
    end
endfunction

endmodule
