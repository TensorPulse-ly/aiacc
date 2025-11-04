`timescale 1ns/1ps

module tb_inttofp;
    reg         clk;
    reg         rst_n;
    reg [127:0] dvr_inttofp_s;
    reg [5:0]   cru_inttofp;
    wire [127:0] dr_inttofp_d;

    // -------------------------- 新增：适配inttofp的2个新端口 --------------------------
    reg [4:0]  smc_id;          // 驱动DUT的smc_id（5bit，AIACC文档5规范）
    wire [5:0] cru_inttofp_o;    // 监测DUT的cru_inttofp_o（6bit，与cru_inttofp位宽一致）

    // 原有DPI-C接口、err/pass_cnt/total_lane、log等信号保持不变...
    import "DPI-C" function longint unsigned int32_to_fp32(input int val, input int is_signed);
    import "DPI-C" function int unsigned        int16_to_fp16(input shortint val, input int is_signed);
    import "DPI-C" function real fp32_to_real(input longint unsigned val);
    import "DPI-C" function real fp16_to_real(input int unsigned val);
    integer err = 0;        
    integer pass_cnt = 0;   
    integer total_lane = 0; 
    integer log;

    /* DUT */
    inttofp dut (
        .clk(clk),                  // 原有
        .rst_n(rst_n),              // 原有
        .smc_id(smc_id),            // 新增：连接testbench的smc_id驱动
        .dvr_inttofp_s(dvr_inttofp_s),// 原有
        .cru_inttofp(cru_inttofp),  // 原有：输入微指令
        .dr_inttofp_d(dr_inttofp_d),// 原有
        .cru_inttofp_o(cru_inttofp_o)// 新增：连接testbench的监测信号
    );

    /* 时钟 */
    initial begin clk = 0; forever #5 clk = ~clk; end

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

        /* 32 → 32（4个lane） */
        if (ctrl[4] & ctrl[3]) begin
            total_lane = total_lane + 4; // 总lane数+4
            for (i = 0; i < 4; i = i + 1) begin
                rtl32[i]  = dr_inttofp_d[32*i +: 32];
                gold32[i] = int32_to_fp32(data[32*i +: 32], ctrl[2]);
                if (rtl32[i] != gold32[i]) begin
                    $display("  FAIL lane %0d RTL=%h Gold=%h", i, rtl32[i], gold32[i]);
                    err = err + 1; // FAIL计数+1
                end
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl32[i], gold32[i], fp32_to_real(gold32[i]));
                    pass_cnt = pass_cnt + 1; // PASS计数+1
                end
            end
        end
        /* 16 → 16（8个lane） */
        else if (!ctrl[4] & !ctrl[3]) begin
            total_lane = total_lane + 8; // 总lane数+8
            for (i = 0; i < 8; i = i + 1) begin
                rtl16[i]  = dr_inttofp_d[16*i +: 16];
                gold16[i] = int16_to_fp16(data[16*i +: 16], ctrl[2]);
                if (rtl16[i] != gold16[i]) begin
                    $display("  FAIL lane %0d RTL=%h Gold=%h", i, rtl16[i], gold16[i]);
                    err = err + 1; // FAIL计数+1
                end
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl16[i], gold16[i], fp16_to_real(gold16[i]));
                    pass_cnt = pass_cnt + 1; // PASS计数+1
                end
            end
        end
        /* 16 → 32（4个lane） */
        else if (!ctrl[4] & ctrl[3]) begin
            total_lane = total_lane + 4; // 总lane数+4
            for (i = 0; i < 4; i = i + 1) begin
                rtl32[i] = dr_inttofp_d[32*i +: 32];
                idx = ctrl[1] ? (2*i+1) : (2*i);
                tmp16 = data[16*idx +: 16];
                tmp32 = ctrl[2] ? {{16{tmp16[15]}}, tmp16} : {16'h0, tmp16};
                gold32[i] = int32_to_fp32(tmp32, ctrl[2]);
                if (rtl32[i] != gold32[i]) begin
                    $display("  FAIL lane %0d RTL=%h Gold=%h", i, rtl32[i], gold32[i]);
                    err = err + 1; // FAIL计数+1
                end 
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl32[i], gold32[i], fp32_to_real(gold32[i]));
                    pass_cnt = pass_cnt + 1; // PASS计数+1
                end
            end
        end
        /* 32 → 16（4个lane） */
        else begin
            total_lane = total_lane + 4; // 总lane数+4
            for (i = 0; i < 4; i = i + 1) begin
                tmp32 = data[32*i +: 32];
                gold16[i] = int16_to_fp16(
                                ctrl[0] ? tmp32[31:16] : tmp32[15:0],
                                ctrl[2]);
                rtl16[i] = dr_inttofp_d[16*i +: 16];
                if (rtl16[i] != gold16[i]) begin
                    $display("  FAIL lane %0d RTL=%h Gold=%h", i, rtl16[i], gold16[i]);
                    err = err + 1; // FAIL计数+1
                end
                else begin
                    $display("  PASS lane %0d: RTL=%h Golden=%h Real=%f", i, rtl16[i], gold16[i], fp16_to_real(gold16[i]));
                    pass_cnt = pass_cnt + 1; // PASS计数+1
                end 
            end
        end
    endtask

    // 方案1：用force命令强制信号为非法值（绕开赋值限制）
    task check_default_force;
        begin
            $display("\n=== 强制触发default分支（force命令）===");
            wait(rst_n == 1'b1);
            @(posedge clk);
            
            // 1. 先将valid设为1（确保进入case块）
            cru_inttofp[5] = 1'b1; // valid=1
            dvr_inttofp_s = 128'h0000_0000_0000_0000_0000_0000_0000_0001;
            
            // 2. 关键：用force命令强制{src_is_32b, dst_is_32b}为非法值（如2'b11之外的“伪值”）
            // （注：2位信号只有4种合法值，这里通过force绕开，工具会视为非法）
            force dut.src_is_32b = 1'bx; // 直接强制模块内部信号为x
            force dut.dst_is_32b = 1'bx;
            $display("[tb] 强制 dut.src_is_32b=x, dut.dst_is_32b=x");
            
            @(posedge clk); // 模块采样，进入default
            #1;
            $display("[tb] default分支触发，模块输出：%h", dr_inttofp_d);
            
            // 3. 释放force，避免影响后续测试
            release dut.src_is_32b;
            release dut.dst_is_32b;
            $display("=== default分支测试结束 ===\n");
        end
    endtask

// 在tb_inttofp.v中新增独立的valid切换测试（不依赖check任务，避免时序干扰）
task force_valid_toggle;
    reg [5:0] ctrl;
    begin
        $display("\n=== 强制触发valid Toggle测试 ===");
        // 确保模块处于复位释放状态
        wait(rst_n == 1'b1);
        @(posedge clk); // 对齐时钟
        
        // 步骤1：valid=1（持续2个周期，确保模块采样）
        ctrl = 6'b1_1_1_1_0_0; // valid=1，32→32场景（数据随意）
        dvr_inttofp_s = 128'h0000_0000_0000_0000_0000_0000_0000_0001;
        cru_inttofp = ctrl;
        @(posedge clk);
        $display("[tb] valid=1，第1个周期，ctrl=%b", ctrl);
        @(posedge clk);
        $display("[tb] valid=1，第2个周期，ctrl=%b", ctrl);
        
        // 步骤2：valid=0（持续2个周期，触发1→0切换）
        ctrl[5] = 1'b0; // 仅将valid设为0，其他位不变
        cru_inttofp = ctrl;
        @(posedge clk);
        $display("[tb] valid=0，第1个周期（1→0切换），ctrl=%b", ctrl);
        @(posedge clk);
        $display("[tb] valid=0，第2个周期，ctrl=%b", ctrl);
        
        // 步骤3：valid=1（持续2个周期，触发0→1切换）
        ctrl[5] = 1'b1; // 恢复valid=1
        cru_inttofp = ctrl;
        @(posedge clk);
        $display("[tb] valid=1，第3个周期（0→1切换），ctrl=%b", ctrl);
        @(posedge clk);
        $display("[tb] valid=1，第4个周期，ctrl=%b", ctrl);
        
        $display("=== valid Toggle测试结束 ===\n");
    end
endtask

    // 主测试序列（新增smc_id驱动）
    initial begin
        log = $fopen("int2fp.log","w");
        rst_n = 0;
        smc_id = 5'd0;  // 复位默认smc_id=0
        @(posedge clk);
        rst_n = 1;

        // 二次复位（原有）
        $display("\n[二次复位] 开始触发rst_n Toggle...");
        @(posedge clk);
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;
        $display("[二次复位] rst_n Toggle完成");
        @(posedge clk);

        // 切换smc_id（新增）
        smc_id = 5'd1;
        $display("[tb] smc_id切换为：%d", smc_id);
        @(posedge clk);

        // 原有测试流程...
        err = 0;
        pass_cnt = 0;
        total_lane = 0;
        force_valid_toggle;
        check_default_force;
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
        // -------------------------- 补充：16→32 定向测试（覆盖 0&1 条件） --------------------------
        check(128'h00000000000000000000000000000000, 6'b1_0_1_1_0_0, "16s→32f zero");
        check(128'h00000000000000000000000000000001, 6'b1_0_1_1_0_0, "16s→32f +1");
        check(128'h0000000000000000000000000000ffff, 6'b1_0_1_1_0_0, "16s→32f -1");
        check(128'h00000000000000000000000000007fff, 6'b1_0_1_1_0_0, "16s→32f maxpos（32767）");
        check(128'h00000000000000000000000000008000, 6'b1_0_1_1_0_0, "16s→32f minneg（-32768）");
        check(128'h00000000000000000000000000001234, 6'b1_0_1_0_0_0, "16u→32f 0x1234（无符号）");
        check(128'h0000000000000000000000000000ffff, 6'b1_0_1_0_0_0, "16u→32f maxu（65535）");
        // 测试 src_high=1（取16位高半部分）
        check(128'h000000000000000000007fff00000000, 6'b1_0_1_1_1_0, "16s→32f src_high=1（高16位32767）");
        // -------------------------- 补充：32→16 定向测试（覆盖 1&0 条件） --------------------------
        check(128'h00000000000000000000000000000000, 6'b1_1_0_1_0_0, "32s→16f zero (dst_high=0，低16位)");
        check(128'h00000000000000000000000000000001, 6'b1_1_0_1_0_0, "32s→16f +1 (dst_high=0)");
        check(128'h0000000000000000000000000000ffff, 6'b1_1_0_1_0_0, "32s→16f -1 (dst_high=0)");
        check(128'h0000000000000000000000007fff0000, 6'b1_1_0_1_1_0, "32s→16f maxpos (dst_high=1，高16位32767)");
        check(128'h00000000000000000000000080000000, 6'b1_1_0_1_1_0, "32s→16f minneg (dst_high=1，高16位-32768)");
        check(128'h00000000000000000000000012345678, 6'b1_1_0_0_0_0, "32u→16f low 0x5678 (dst_high=0，无符号)");
        check(128'h00000000000000000000000012345678, 6'b1_1_0_0_1_0, "32u→16f high 0x1234 (dst_high=1，无符号)");
        /* ---- 随机测试 ---- */
        begin
            integer k;
            reg [127:0] data;
            reg [5:0]   ctrl;
            integer loop = 40000; // 随机测试次数，可调整

            for (k = 0; k < loop; k = k + 1) begin
                data = { $random, $random, $random, $random };
                if (k % 1000 == 0) begin
                    smc_id = $random % 32;
                    $display("[tb] 随机测试第%d次，smc_id=%d", k, smc_id);
                end                
                case ($random & 3)
                    2'b00: ctrl = 6'b1_0_0_1_0_0;        // 16→16（8 lane）
                    2'b01: begin                         // 16→32（4 lane）
                             ctrl = 6'b1_0_1_1_0_0;
                             if ($random & 1) ctrl[1] = 1'b1;
                           end
                    2'b10: begin                         // 32→16（4 lane）
                             ctrl = 6'b1_1_0_0_0_0;
                             if ($random & 1) ctrl[0] = 1'b1;
                           end
                    default: ctrl = 6'b1_1_1_1_0_0;     // 32→32（4 lane）
                endcase
                ctrl[2] = $random & 1;
                check(data, ctrl, "");
            end
        end

        #100;
        // -------------------------- 关键修改3：输出PASS/FAIL统计结果 --------------------------
        $display("\n================== 测试结果汇总 ==================");
        $display("总测试lane数：%0d", total_lane);
        $display("PASS lane数：%0d", pass_cnt);
        $display("FAIL lane数：%0d", err);
        $display("通过率：%.2f%%", (pass_cnt * 100.0) / total_lane); // 新增通过率计算
        $display("================================================");
        if (err == 0)
            $display("=== 所有比对 PASS ===");
        else
            $display("=== FAIL 次数 = %0d ===", err);
        $fdisplay(log, "\n=== 总结 ===");
        $fdisplay(log, "总测试: %0d, 通过: %0d, 失败: %0d", total_lane, pass_cnt, err);
        $fdisplay(log, "通过率：%.2f%%", (pass_cnt * 100.0) / total_lane);
        $fclose(log);
        $finish;
    end
endmodule
