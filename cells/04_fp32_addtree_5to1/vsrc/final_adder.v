module final_adder #(
    parameter WIDTH = 32
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH:0] sum  // 包含最终进位的完整输出
);

    wire [WIDTH:0] carry;
    wire [WIDTH-1:0] p; // 进位传递信号
    wire [WIDTH-1:0] g; // 进位生成信号
    
    assign carry[0] = 1'b0;
    
    genvar i;
    generate
        for (i=0; i<WIDTH; i=i+1) begin : adder
            assign p[i] = a[i] ^ b[i];      // 进位传递信号
            assign g[i] = a[i] & b[i];      // 进位生成信号
            assign sum[i] = p[i] ^ carry[i];
            assign carry[i+1] = g[i] | (p[i] & carry[i]);
        end
    endgenerate
    
    // 输出最终进位
    assign sum[WIDTH] = carry[WIDTH];
endmodule