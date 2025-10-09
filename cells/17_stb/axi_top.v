`timescale 1ns/1ps
// 顶层模块 - 核心功能：连接所有子模块，实现“ur_model→burst_store→axi_stb→axi_stb_s→axi_mem_model”链路
module axi_top #(
    parameter ADDR_WIDTH = 32,          // 地址宽度
    parameter DATA_WIDTH = 128,         // 数据宽度
    parameter SMC_COUNT = 6,            // SMC数量
    parameter UR_BYTE_CNT = 16,         // 字节使能宽度（128bit/8=16）
    parameter INTLV_STEP = 64,          // SMC地址交错步长
    parameter MEM_SIZE = 1024 * 512    // 内存大小（512KB）
)(
    // 时钟与复位
    input                   clk,
    input                   rst_n,
    
    // 测试平台接口（连接burst_store_tb）
    input                   tb_en,         // 测试使能
    output                  tb_done,       // 测试完成
    
    // STB接口（连接测试平台，接收STB指令）
    input                   stb_u_valid,    // 指令有效
    input [SMC_COUNT-1:0]   stb_u_smc_strb, // SMC使能编码
    input [3:0]             stb_u_byte_strb,// 字节使能编码
    input [1:0]             stb_u_brst,     // burst长度编码
    input [ADDR_WIDTH-1:0]  stb_u_gr_base_addr, // 外部内存基地址
    input [3:0]             stb_u_ur_id,    // 目标UR ID
    input [10:0]            stb_u_ur_addr,  // 目标UR地址
    output                  stb_d_valid,    // 指令有效反馈
    output                  stb_d_done,     // 指令完成反馈
    input                   stb_d_ready,    // 上层就绪信号（握手确认）
    
    // 错误注入控制（连接测试平台）
    input                   ur_err_inject,  // 错误注入使能
    input [3:0]             ur_err_type,    // 错误类型
    input [10:0]            ur_err_addr_mask, // 错误地址掩码
    
    // 协议检查器输出（连接测试平台，监控AXI错误）
    output                  protocol_error, // AXI协议错误标志
    output [3:0]            error_code,     // 错误代码
    
    // 调试信号（连接测试平台，监控burst_store状态）
    output [2:0]            burst_store_state
);

// 内部信号定义（模块间连接桥梁）
// 1. ur_model ↔ burst_store 连接信号
wire                    ur_re;          // burst_store→ur_model：读使能
wire [10:0]             ur_addr;        // burst_store→ur_model：读地址
wire [DATA_WIDTH-1:0]   ur_rdata;       // ur_model→burst_store：随机数据

// 2. burst_store ↔ axi_stb 连接信号（事务包）
wire                    stb2stb_valid;  // burst_store→axi_stb：事务包就绪
wire [ADDR_WIDTH-1:0]   stb2stb_addr;  // burst_store→axi_stb：写入地址
wire [DATA_WIDTH-1:0]   stb2stb_data;  // burst_store→axi_stb：随机数据
wire [7:0]              stb2stb_burst_len;  // burst_store→axi_stb：burst长度
wire [UR_BYTE_CNT-1:0]  stb2stb_wstrb;  // burst_store→axi_stb：字节使能
wire                    stb2stb_done;     // axi_stb→burst_store：事务完成反馈

// 3. axi_stb ↔ axi_stb_s 连接信号（AXI上游s_*）
wire                    s_awvalid;      // axi_stb→axi_stb_s：地址有效
wire [ADDR_WIDTH-1:0]   s_awaddr;       // axi_stb→axi_stb_s：写地址
wire [7:0]              s_awlen;        // axi_stb→axi_stb_s：burst长度
wire [2:0]              s_awsize;       // axi_stb→axi_stb_s：数据宽度
wire [1:0]              s_awburst;      // axi_stb→axi_stb_s：burst模式
wire                    s_awready;      // axi_stb_s→axi_stb：地址就绪
wire                    s_wvalid;       // axi_stb→axi_stb_s：数据有效
wire [DATA_WIDTH-1:0]   s_wdata;        // axi_stb→axi_stb_s：写数据（含随机数据）
wire [UR_BYTE_CNT-1:0]  s_wstrb;        // axi_stb→axi_stb_s：字节使能
wire                    s_wlast;        // axi_stb→axi_stb_s：最后一拍标志
wire                    s_wready;       // axi_stb_s→axi_stb：数据就绪
wire                    s_bvalid;       // axi_stb_s→axi_stb：响应有效
wire [1:0]              s_bresp;        // axi_stb_s→axi_stb：响应码
wire                    s_bready;       // axi_stb→axi_stb_s：响应就绪

// 4. axi_stb_s ↔ axi_mem_model 连接信号（AXI下游m_*）
wire                    m_awvalid;      // axi_stb_s→axi_mem_model：地址有效
wire [ADDR_WIDTH-1:0]   m_awaddr;       // axi_stb_s→axi_mem_model：写地址
wire [7:0]              m_awlen;        // axi_stb_s→axi_mem_model：burst长度
wire [2:0]              m_awsize;       // axi_stb_s→axi_mem_model：数据宽度
wire [1:0]              m_awburst;      // axi_stb_s→axi_mem_model：burst模式
wire                    m_awready;      // axi_mem_model→axi_stb_s：地址就绪
wire                    m_wvalid;       // axi_stb_s→axi_mem_model：数据有效
wire [DATA_WIDTH-1:0]   m_wdata;        // axi_stb_s→axi_mem_model：写数据（含随机数据）
wire [UR_BYTE_CNT-1:0]  m_wstrb;        // axi_stb_s→axi_mem_model：字节使能
wire                    m_wlast;        // axi_stb_s→axi_mem_model：最后一拍标志
wire                    m_wready;       // axi_mem_model→axi_stb_s：数据就绪
wire                    m_bvalid;       // axi_mem_model→axi_stb_s：响应有效
wire [1:0]              m_bresp;        // axi_mem_model→axi_stb_s：响应码
wire                    m_bready;       // axi_stb_s→axi_mem_model：响应就绪

// 5. 测试完成信号（连接测试平台）
reg                     tb_done_reg;
assign tb_done = tb_done_reg;


// -------------------------- 模块实例化与连接 --------------------------
// 1. 实例化ur_model（随机数据生成器）
ur_model #(
    .DATA_WIDTH(DATA_WIDTH),
    .LFSR_WIDTH(32),
    .LFSR_POLY(32'h8000000B),
    .ADDR_WIDTH(11),
    .MAX_ID(16)
) ur_model_inst (
    .clk(clk),
    .rst_n(rst_n),
    // UR读接口（连接burst_store）
    .ur_re(ur_re),                  // 输入：burst_store发起的读请求
    .ur_id(stb_u_ur_id),            // 输入：测试平台指定的UR ID
    .ur_addr(ur_addr),              // 输入：burst_store指定的UR地址
    .ur_rdata(ur_rdata),            // 输出：随机数据→burst_store
    // 未使用接口（置默认值）
    .ur_we(1'b0),
    .ur_wdata({DATA_WIDTH{1'b0}}),
    .ur_wstrb({DATA_WIDTH/8{1'b0}}),
    .err_inject(ur_err_inject),
    .err_type(ur_err_type),
    .err_addr_mask(ur_err_addr_mask),
    .read_count(),
    .write_count(),
    .error_count()
);

// 2. 实例化burst_store（指令解析+随机数据中继）
burst_store #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .SMC_COUNT(SMC_COUNT),
    .UR_BYTE_CNT(UR_BYTE_CNT),
    .INTLV_STEP(INTLV_STEP)
) burst_store_inst (
    .clk(clk),
    .rst_n(rst_n),
    // STB指令输入（连接测试平台）
    .stb_u_valid(stb_u_valid),
    .stb_u_smc_strb(stb_u_smc_strb),
    .stb_u_byte_strb(stb_u_byte_strb),
    .stb_u_brst(stb_u_brst),
    .stb_u_gr_base_addr(stb_u_gr_base_addr),
    .stb_u_ur_id(stb_u_ur_id),
    .stb_u_ur_addr(stb_u_ur_addr),
    // UR数据输入（连接ur_model）
    .ur_rdata(ur_rdata),            // 输入：ur_model生成的随机数据
    // STB指令反馈（连接测试平台）
    .stb_d_valid(stb_d_valid),
    .stb_d_done(stb_d_done),
    .stb_d_ready(stb_d_ready),
    // UR读请求（连接ur_model）
    .ur_re(ur_re),                  // 输出：向ur_model发起读请求
    .ur_addr(ur_addr),              // 输出：向ur_model指定读地址
    // 事务包输出（连接axi_stb）
    .stb2stb_valid(stb2stb_valid),
    .stb2stb_addr(stb2stb_addr),
    .stb2stb_data(stb2stb_data),
    .stb2stb_burst_len(stb2stb_burst_len),
    .stb2stb_wstrb(stb2stb_wstrb),
    // 事务完成反馈（连接axi_stb）
    .stb2stb_done(stb2stb_done)
);

// 调试信号：burst_store状态（输出到测试平台）
assign burst_store_state = burst_store_inst.state;

// 3. 实例化axi_stb（事务包→AXI信号转换）
axi_stb #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .UR_BYTE_CNT(UR_BYTE_CNT)
) axi_stb_inst (
    .clk(clk),
    .rst_n(rst_n),
    // 事务包输入（连接burst_store）
    .stb2stb_valid(stb2stb_valid),
    .stb2stb_addr(stb2stb_addr),
    .stb2stb_data(stb2stb_data),
    .stb2stb_burst_len(stb2stb_burst_len),
    .stb2stb_wstrb(stb2stb_wstrb),
    // 事务完成反馈（输出到burst_store）
    .stb2stb_done(stb2stb_done),
    // AXI主接口（输出到axi_stb_s的上游s_*接口）
    .axi_awvalid(s_awvalid),
    .axi_awaddr(s_awaddr),
    .axi_awlen(s_awlen),
    .axi_awsize(s_awsize),
    .axi_awburst(s_awburst),
    .axi_awready(s_awready),
    .axi_wvalid(s_wvalid),
    .axi_wdata(s_wdata),
    .axi_wstrb(s_wstrb),
    .axi_wlast(s_wlast),
    .axi_wready(s_wready),
    .axi_bvalid(s_bvalid),
    .axi_bresp(s_bresp),
    .axi_bready(s_bready)
);

// 4. 实例化axi_stb_s（AXI信号透传）
axi_stb_s #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) axi_stb_s_inst (
    .clk(clk),
    .rst_n(rst_n),
    // 上游AXI从接口（连接axi_stb的AXI主接口）
    .s_awvalid(s_awvalid),
    .s_awaddr(s_awaddr),
    .s_awlen(s_awlen),
    .s_awsize(s_awsize),
    .s_awburst(s_awburst),
    .s_awready(s_awready),
    .s_wvalid(s_wvalid),
    .s_wdata(s_wdata),
    .s_wstrb(s_wstrb),
    .s_wlast(s_wlast),
    .s_wready(s_wready),
    .s_bvalid(s_bvalid),
    .s_bresp(s_bresp),
    .s_bready(s_bready),
    // 下游AXI主接口（连接axi_mem_model的AXI从接口）
    .m_awvalid(m_awvalid),
    .m_awaddr(m_awaddr),
    .m_awlen(m_awlen),
    .m_awsize(m_awsize),
    .m_awburst(m_awburst),
    .m_awready(m_awready),
    .m_wvalid(m_wvalid),
    .m_wdata(m_wdata),
    .m_wstrb(m_wstrb),
    .m_wlast(m_wlast),
    .m_wready(m_wready),
    .m_bvalid(m_bvalid),
    .m_bresp(m_bresp),
    .m_bready(m_bready)
);

// 5. 实例化axi_mem_model（内存存储）
axi_mem_model #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .MEM_SIZE(MEM_SIZE)
) axi_mem_model_inst (
    .clk(clk),
    .rst_n(rst_n),
    // AXI从接口（连接axi_stb_s的下游主接口）
    .axi_awvalid(m_awvalid),
    .axi_awaddr(m_awaddr),
    .axi_awlen(m_awlen),
    .axi_awsize(m_awsize),
    .axi_awburst(m_awburst),
    .axi_awready(m_awready),
    .axi_wvalid(m_wvalid),
    .axi_wdata(m_wdata),            // 输入：axi_stb_s转发的随机数据
    .axi_wstrb(m_wstrb),
    .axi_wlast(m_wlast),
    .axi_wready(m_wready),
    .axi_bvalid(m_bvalid),
    .axi_bresp(m_bresp),
    .axi_bready(m_bready)
    // 未使用的UR接口（注释避免多驱动）
    // .ur_re(),
    // .ur_addr(),
    // .ur_rdata()
);

// 6. 实例化axi_protocol_checker（AXI协议监控）
axi_protocol_checker #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
) axi_protocol_checker_inst (
    .clk(clk),
    .rst_n(rst_n),
    // AXI信号（监控axi_stb→axi_stb_s的链路，核心传输段）
    .axi_awvalid(s_awvalid),
    .axi_awready(s_awready),
    .axi_awaddr(s_awaddr),
    .axi_wvalid(s_wvalid),
    .axi_wready(s_wready),
    .axi_wdata(s_wdata),
    .axi_wstrb(s_wstrb),
    .axi_wlast(s_wlast),
    .axi_bvalid(s_bvalid),
    .axi_bready(s_bready),
    .axi_bresp(s_bresp),
    // 协议错误输出（连接测试平台）
    .protocol_error(protocol_error),
    .error_code(error_code)
);

// -------------------------- 测试完成逻辑 --------------------------
// 当burst_store指令完成（stb_d_done）且无协议错误时，标记测试完成
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tb_done_reg <= 1'b0;
    end else if (tb_en) begin
        if (stb_d_done && !protocol_error) begin
            tb_done_reg <= 1'b1;
            $display("[AXI_TOP] 时间%0t: 测试完成（无AXI协议错误）", $time);
        end else if (protocol_error) begin
            tb_done_reg <= 1'b1;
            $display("[AXI_TOP] 时间%0t: 测试完成（检测到AXI协议错误，错误码=0x%h）", $time, error_code);
        end
    end else begin
        tb_done_reg <= 1'b0;
    end
end

// -------------------------- 监控信号（调试用） --------------------------
// 打印关键信号变化，便于仿真调试
always @(posedge clk) begin
    if (tb_en) begin
        // 每500个时钟周期打印一次链路状态
        if ($time % 500 == 0) begin
            $display("[AXI_TOP] 时间%0t: 链路状态 - UR数据=0x%h | 事务包就绪=%h | AXI数据=0x%h | 内存写入地址=0x%h | 协议错误=%h",
                     $time, ur_rdata, stb2stb_valid, s_wdata, m_awaddr, protocol_error);
        end
    end
end

endmodule
    