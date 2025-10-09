//---------------------------------------------------------------------
// Filename: inttofp.v
// Author: cypher
// Date: 2025-8-15
// Version: 1.0
// Description: This is a module that supports convert to floating point type.
//---------------------------------------------------------------------

module inttofp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [127:0] dvr_inttofp_s,
    input  wire [5:0]   cru_inttofp,
    output reg  [127:0] dr_inttofp_d
);

    // 微指令字段
    wire          valid      = cru_inttofp[5];
    wire          src_is_32b = cru_inttofp[4];
    wire          dst_is_32b = cru_inttofp[3];
    wire          src_signed = cru_inttofp[2];
    wire          src_high   = cru_inttofp[1];
    wire          dst_high   = cru_inttofp[0];

    // 数据分段
    wire [31:0] src32 [0:3];
    wire [15:0] src16 [0:7];
    assign src32[0] = dvr_inttofp_s[31:0];
    assign src32[1] = dvr_inttofp_s[63:32];
    assign src32[2] = dvr_inttofp_s[95:64];
    assign src32[3] = dvr_inttofp_s[127:96];
    assign src16[0] = dvr_inttofp_s[15:0];
    assign src16[1] = dvr_inttofp_s[31:16];
    assign src16[2] = dvr_inttofp_s[47:32];
    assign src16[3] = dvr_inttofp_s[63:48];
    assign src16[4] = dvr_inttofp_s[79:64];
    assign src16[5] = dvr_inttofp_s[95:80];
    assign src16[6] = dvr_inttofp_s[111:96];
    assign src16[7] = dvr_inttofp_s[127:112];

    // 转换结果
    wire [31:0] fp32 [0:3];     // 32→32
    wire [31:0] fp32_16 [0:3];  // 16→32
    wire [15:0] fp16 [0:7];     // 16→16
    wire [15:0] fp16_32 [0:7];  // 32→16

    // 32→32
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_fp32
            int2fp32 u_fp32 (
                .in       (src32[gi]),
                .is_signed(src_signed),
                .out      (fp32[gi])
            );
        end
    endgenerate

    // 16→16
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_fp16
            int2fp16 u_fp16 (
                .in       (src16[gi]),
                .is_signed(src_signed),
                .out      (fp16[gi])
            );
        end
    endgenerate

    // 16→32
    wire [31:0] ext32 [0:3];
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_ext32
            wire [15:0] lo = src16[gi*2];
            wire [15:0] hi = src16[gi*2+1];
            wire [15:0] sel = src_high ? hi : lo;
            assign ext32[gi] = src_high ?
                   {{16{src_signed ? hi[15] : 1'b0}}, hi} :
                   {{16{src_signed ? lo[15] : 1'b0}}, lo};

            int2fp32 u_ext (
                .in       (ext32[gi]),
                .is_signed(src_signed),
                .out      (fp32_16[gi])
            );
        end
    endgenerate

    // 32→16
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : g_split16
            int2fp16 u_lo (
                .in       (src32[gi][15:0]),
                .is_signed(src_signed),
                .out      (fp16_32[gi*2])
            );
            int2fp16 u_hi (
                .in       (src32[gi][31:16]),
                .is_signed(src_signed),
                .out      (fp16_32[gi*2+1])
            );
        end
    endgenerate

    // 输出映射
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dr_inttofp_d <= 128'd0;
        end else if (valid) begin
            if (src_is_32b && dst_is_32b) begin
                dr_inttofp_d <= {fp32[3], fp32[2], fp32[1], fp32[0]};
            end else if (!src_is_32b && !dst_is_32b) begin
                dr_inttofp_d <= {fp16[7], fp16[6], fp16[5], fp16[4],
                                 fp16[3], fp16[2], fp16[1], fp16[0]};
            end else if (!src_is_32b && dst_is_32b) begin
                dr_inttofp_d <= {fp32_16[3], fp32_16[2], fp32_16[1], fp32_16[0]};
            end else begin // 32→16
                if (dst_high) begin
                    dr_inttofp_d <= {fp16_32[7], fp16_32[5], fp16_32[3], fp16_32[1]};
                end else begin
                    dr_inttofp_d <= {fp16_32[6], fp16_32[4], fp16_32[2], fp16_32[0]};
                end
            end
        end
    end

endmodule
