module int2fp32 (
    input  wire [31:0] in,
    input  wire        is_signed,
    output reg  [31:0] out
);
    reg        sign;
    reg [31:0] absv;
    reg [4:0]  lzc;
    reg [7:0]  exp;
    reg [22:0] mant;

    reg [31:0] tmp;
    reg [23:0] man_ext;
    reg        guard, sticky, round_up;
    integer    i;

    always @(*) begin
        sign = is_signed & in[31];
        absv = sign ? -in : in;

        if (absv == 32'd0) begin
            out = 32'd0;
        end else begin
            // 计算 lzc
            lzc = 5'd0;
            for (i = 31; i >= 0; i = i - 1)
                if (absv[i] == 1'b0) lzc = lzc + 5'd1; else break;

            exp = 8'd127 + 31 - lzc;

            // 尾数：右移 9 位 → 23 位
            tmp = absv << lzc;
            man_ext = {1'b0, tmp[30:8]}; // 24 位

            guard  = tmp[7];          // 第 8 位
            sticky = |tmp[6:0];       // 低 8 位
            round_up = guard & (sticky | man_ext[0]);
            man_ext = man_ext + round_up;

            if (man_ext[23]) begin
                mant = 23'd0;
                exp  = exp + 8'd1;
            end else begin
                mant = man_ext[22:0];
            end

            out = {sign, exp, mant};
        end
    end
endmodule
