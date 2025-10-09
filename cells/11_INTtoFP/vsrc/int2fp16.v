module int2fp16 (
    input  wire [15:0] in,
    input  wire        is_signed,
    output reg  [15:0] out
);

    reg        sign;
    reg [15:0] absv;
    reg [4:0]  lzc;
    reg [4:0]  exp;          // fp16: 5 位指数
    reg [9:0]  mant;         // fp16: 10 位尾数

    reg [15:0] tmp;
    reg [11:0] man_ext;      // 12 位扩展：10 位尾数 + Guard + Round 位
    reg        guard, sticky, round_up;
    integer    i;

    always @(*) begin
        sign = is_signed & in[15];
        absv = sign ? -in : in;

        if (absv == 16'd0) begin
            out = 16'd0;
        end else begin
            // 计算 lzc（16 位版）
            lzc = 5'd0;
            for (i = 15; i >= 0; i = i - 1)
                if (absv[i] == 1'b0) lzc = lzc + 5'd1; else break;

            exp = 5'd15 + 15 - lzc;   // fp16 偏移 15

            // 归一化后左移
            tmp = absv << lzc;

            // 尾数扩展：10 位 + 1 位 Guard + 1 位 Sticky 区域
            man_ext = {1'b0, tmp[15:5]};  // 12 位

            guard  = tmp[4];              // Guard 位
            sticky = |tmp[3:0];           // Sticky 位
            round_up = guard & (sticky | man_ext[0]);
            man_ext = man_ext + round_up;

            // 处理尾数进位
            if (man_ext[11]) begin
                mant = 10'd0;
                exp  = exp + 5'd1;
            end else begin
                mant = man_ext[9:0];
            end

            out = {sign, exp, mant};
        end
    end
endmodule
