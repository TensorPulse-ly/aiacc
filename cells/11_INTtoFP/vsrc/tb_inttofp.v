`timescale 1ns/1ps

module tb_inttofp;
    reg         clk;
    reg         rst_n;
    reg [127:0] dvr_inttofp_s;
    reg [5:0]   cru_inttofp;
    wire [127:0] dr_inttofp_d;

    /* DPI-C 接口 */
    import "DPI-C" function longint unsigned int32_to_fp32(input int val, input int is_signed);
    import "DPI-C" function int unsigned        int16_to_fp16(input shortint val, input int is_signed);
    import "DPI-C" function real fp32_to_real(input longint unsigned val);
    import "DPI-C" function real fp16_to_real(input int unsigned val);

    /* DUT */
    inttofp dut (
        .clk(clk),
        .rst_n(rst_n),
        .dvr_inttofp_s(dvr_inttofp_s),
        .cru_inttofp(cru_inttofp),
        .dr_inttofp_d(dr_inttofp_d)
    );

    /* 时钟 */
    initial begin clk = 0; forever #5 clk = ~clk; end

    integer err = 0;

    /* 比对任务 */
    task check (
        input [127:0] data,
        input [5:0]   ctrl,
        input [80*8:1] msg
    );
        reg [31:0] rtl32 [0:3];
        reg [15:0] rtl16 [0:7];
        reg [31:0] gold32 [0:3];
        reg [15:0] gold16 [0:7];
        integer i, j, idx;
        reg [15:0] tmp16;
        reg [31:0] tmp32;

        @(posedge clk);
        dvr_inttofp_s <= data;
        cru_inttofp   <= ctrl;
        @(posedge clk);
        #1;

        $display("[%0t] %0s: in=%h ctrl=%b out=%h", $time, msg, data, ctrl, dr_inttofp_d);

        /* 32 → 32 */
        if (ctrl[4] & ctrl[3]) begin
            for (i = 0; i < 4; i = i + 1) begin
                rtl32[i]  = dr_inttofp_d[32*i +: 32];
                gold32[i] = int32_to_fp32(data[32*i +: 32], ctrl[2]);
                if (rtl32[i] != gold32[i]) begin
                    $display("  Mismatch lane %0d RTL=%h Gold=%h", i, rtl32[i], gold32[i]);
                    err = err + 1;
                end
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl32[i], gold32[i], fp32_to_real(gold32[i]));
                end
            end
        end
        /* 16 → 16 */
        else if (!ctrl[4] & !ctrl[3]) begin
            for (i = 0; i < 8; i = i + 1) begin
                rtl16[i]  = dr_inttofp_d[16*i +: 16];
                gold16[i] = int16_to_fp16(data[16*i +: 16], ctrl[2]);
                if (rtl16[i] != gold16[i]) begin
                    $display("  Mismatch lane %0d RTL=%h Gold=%h", i, rtl16[i], gold16[i]);
                    err = err + 1;
                end
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl16[i], gold16[i], fp16_to_real(gold16[i]));
                end
            end
        end
        /* 仅在 task check 内部替换 16→32 与 32→16 两段即可 */
        /* 16 → 32 */
        else if (!ctrl[4] & ctrl[3]) begin
            for (i = 0; i < 4; i = i + 1) begin
                rtl32[i] = dr_inttofp_d[32*i +: 32];

                /* 与 RTL 对齐：src_high 时选高 16 位，否则低 16 位 */
                idx = ctrl[1] ? (2*i+1) : (2*i);
                tmp16 = data[16*idx +: 16];

                /* 与 RTL 对齐：符号扩展到 32 位 */
                tmp32 = ctrl[2] ? {{16{tmp16[15]}}, tmp16} : {16'h0, tmp16};
                gold32[i] = int32_to_fp32(tmp32, ctrl[2]);

                if (rtl32[i] != gold32[i]) begin
                    $display("  Mismatch lane %0d RTL=%h Gold=%h", i, rtl32[i], gold32[i]);
                    err = err + 1;
                end 
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl32[i], gold32[i], fp32_to_real(gold32[i]));
                end
            end
        end

        /* 32 → 16 */
                /* 32 → 16 */
        else begin
            for (i = 0; i < 4; i = i + 1) begin
                tmp32 = data[32*i +: 32];

                /* 计算 4 个参考值：dst_high 决定取高/低 16 位 */
                gold16[i] = int16_to_fp16(
                                ctrl[0] ? tmp32[31:16] : tmp32[15:0],
                                ctrl[2]);
            end

            /* 提取 RTL 输出低 64 位中的 4 个 16 位结果 */
            for (i = 0; i < 4; i = i + 1) begin
                rtl16[i] = dr_inttofp_d[16*i +: 16];
                if (rtl16[i] != gold16[i]) begin
                    $display("  Mismatch lane %0d RTL=%h Gold=%h", i, rtl16[i], gold16[i]);
                    err = err + 1;
                end
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl16[i], gold16[i], fp16_to_real(gold16[i]));
                end 
            end
        end


    endtask

    /* 主测试序列 */
    initial begin
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;

        /* ---- 定向测试 ---- */
        check(128'h0000_0000_0000_0000_0000_0000_0000_0000, 6'b1_1_1_1_0_0, "32s->32f zero");
        check(128'h0000_0000_0000_0000_0000_0000_0000_0001, 6'b1_1_1_1_0_0, "32s->32f +1");
        check(128'h0000_0000_0000_0000_0000_0000_FFFF_FFFF, 6'b1_1_1_1_0_0, "32s->32f -1");
        check(128'h0000_0000_0000_0000_0000_0000_7FFF_FFFF, 6'b1_1_1_1_0_0, "32s->32f maxpos");
        check(128'h0000_0000_0000_0000_0000_0000_8000_0000, 6'b1_1_1_1_0_0, "32s->32f minneg");
        check(128'h0000_0000_0000_0000_0000_0000_075B_CD15, 6'b1_1_1_1_0_0, "32s->32f +123456789");
        check(128'h0000_0000_0000_0000_0000_0000_C465_360F, 6'b1_1_1_1_0_0, "32s->32f -987654321");
        check(128'h0000_0000_0000_0000_0000_0000_7FFF_FFFF, 6'b1_1_1_1_0_0, "max 32-bit");
        check(128'h0000_0000_0000_0000_0000_0000_7FFF_FFFF, 6'b1_0_0_1_0_0, "16s->16f maxpos");
        check(128'h0000_0000_0000_0000_FFFF_FFFF_FFFF_FFFF, 6'b1_1_0_0_1_0, "32s->16f high");
        check(128'h00000000000000000000000000007fff, 6'b1_0_0_1_0_0, "16s->16f +32767");
        check(128'h00000000000000000000000000008000, 6'b1_0_0_1_0_0, "16s->16f -32768");
        check(128'h0000000000000000000000000000ffff, 6'b1_0_0_1_0_0, "16u->16f 65535");
        check(128'h0000000000000000000000007fffffff, 6'b1_1_0_0_0_0, "32s->16f high maxpos");
        check(128'h0000000000000000ffffffffffffffff, 6'b1_1_0_0_1_0, "32s->16f high -1");

        check(128'h00000000000000000000000080000000, 6'b1_1_1_1_0_0, "32s→32f minneg");
        check(128'h0000000000000000000000007fffffff, 6'b1_1_1_1_0_0, "32s→32f maxpos");
        check(128'h00000000000000000000000000000000, 6'b1_1_1_1_0_0, "32s→32f zero");
        check(128'h000000000000000000000000ffffffff, 6'b1_1_1_1_0_0, "32s→32f neg1");

        check(128'h00000000000000000000000000000000, 6'b1_1_1_0_0_0, "32u→32f zero");
        check(128'h000000000000000000000000ffffffff, 6'b1_1_1_0_0_0, "32u→32f maxu");

        check(128'h00000000000000000000000000008000, 6'b1_0_0_1_0_0, "16s→16f minneg");
        check(128'h00000000000000000000000000007fff, 6'b1_0_0_1_0_0, "16s→16f maxpos");
        check(128'h00000000000000000000000000000000, 6'b1_0_0_1_0_0, "16s→16f zero");
        check(128'h0000000000000000000000000000ffff, 6'b1_0_0_1_0_0, "16s→16f neg1");

        check(128'h00000000000000000000000000000000, 6'b1_0_0_0_0_0, "16u→16f zero");
        check(128'h0000000000000000000000000000ffff, 6'b1_0_0_0_0_0, "16u→16f maxu");

        check(128'h0000000000000000ffffffffffffffff, 6'b1_1_0_0_1_0, "32s→16f low  -1");
        check(128'h00000000000000007fff00007fff0000, 6'b1_1_0_0_1_0, "32s→16f low  maxpos");
        check(128'h00000000000000008000000080000000, 6'b1_1_0_0_1_0, "32s→16f low  minneg");

        check(128'hffffffff000000000000000000000000, 6'b1_1_0_0_1_1, "32s→16f high -1");
        check(128'h7fff0000000000000000000000000000, 6'b1_1_0_0_1_1, "32s→16f high maxpos");
        check(128'h80000000000000000000000000000000, 6'b1_1_0_0_1_1, "32s→16f high minneg");

        check(128'h000000000000ffff000000000000ffff, 6'b1_0_1_1_0_0, "16s→32f low  -1");
        check(128'h0000000000007fff0000000000007fff, 6'b1_0_1_1_0_0, "16s→32f low  maxpos");
        check(128'h00000000000080000000000000008000, 6'b1_0_1_1_0_0, "16s→32f low  minneg");

        check(128'hffff0000000000000000000000000000, 6'b1_0_1_1_1_0, "16s→32f high -1");
        check(128'h7fff0000000000000000000000000000, 6'b1_0_1_1_1_0, "16s→32f high maxpos");
        check(128'h80000000000000000000000000000000, 6'b1_0_1_1_1_0, "16s→32f high minneg");
                /* ---- 随机测试 ---- */
        begin
            integer k;
            reg [127:0] data;
            reg [5:0]   ctrl;
            integer loop = 100;

            for (k = 0; k < loop; k = k + 1) begin
                data = { $random, $random, $random, $random };   // 128 位随机

                /* 随机路由 */
                case ($random & 3)
                    2'b00: ctrl = 6'b1_0_0_1_0_0;        // 16→16
                    2'b01: begin                         // 16→32
                             ctrl = 6'b1_0_1_1_0_0;
                             if ($random & 1) ctrl[1] = 1'b1;
                           end
                    2'b10: begin                         // 32→16
                             ctrl = 6'b1_1_0_0_0_0;
                             if ($random & 1) ctrl[0] = 1'b1;
                           end
                    default: ctrl = 6'b1_1_1_1_0_0;     // 32→32
                endcase

                ctrl[2] = $random & 1;   // 随机符号
                check(data, ctrl, "");
            end
        end

        #100;
        $display("\n==================");
        if (err == 0)
            $display("=== 所有比对 PASS ===");
        else
            $display("=== FAIL 次数 = %0d ===", err);
        $finish;
    end
endmodule
