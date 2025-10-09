# 多数据源AXI总线批量写入系统

## 1. 项目概述

本项目实现了一个基于AXI协议的多数据源批量写入系统，主要用于测试和验证AXI总线在多数据源场景下的数据传输功能。系统的核心功能是通过STB（Storage Buffer）接口接收指令，从UR（User Random）模型读取随机生成的数据，并通过AXI总线将数据批量写入内存模型。

### 1.1 系统主要用途

- **AXI协议验证**：测试和验证AXI总线协议的正确性和稳定性
- **多数据源传输测试**：支持6个SMC（Storage Memory Controller）的地址交错写入
- **错误注入测试**：支持向数据流中注入各种类型的错误，验证系统的鲁棒性
- **功能覆盖率测试**：集成覆盖率收集功能，评估测试的全面性

### 1.2 系统特点

- **模块化设计**：采用清晰的模块化架构，便于维护和扩展
- **可配置参数**：支持多种参数配置，适应不同的测试需求
- **完整的监控机制**：包含AXI协议检查器，实时监控总线信号
- **详细的测试报告**：自动生成内存写入结果和随机数据记录

## 2. 系统架构与工作流程

系统采用流水线式架构，数据流为"ur_model→burst_store→axi_stb→axi_stb_s→axi_mem_model"，各模块协同工作完成从指令解析到数据存储的完整流程。同时，axi_protocol_checker模块实时监控AXI总线信号，确保协议合规性。

### 2.1 系统工作流程详解

1. **指令接收阶段**：
   - 测试平台通过STB接口向burst_store发送指令
   - 指令包含SMC选择、字节使能、burst长度、基地址等信息
   - burst_store接收到指令后，解析并准备数据传输

2. **数据读取阶段**：
   - burst_store根据指令向ur_model发送读请求（ur_re和ur_addr）
   - ur_model根据读请求生成128位随机数据（基于LFSR算法）
   - ur_model将随机数据返回给burst_store

3. **事务包生成阶段**：
   - burst_store根据指令和读取的数据生成内部事务包
   - 事务包包含目标地址、数据、burst长度和字节使能信息
   - 对于多SMC指令，burst_store会根据INTLV_STEP计算每个SMC的写入地址

4. **AXI传输阶段**：
   - axi_stb将事务包转换为符合AXI协议的写信号
   - axi_stb_s作为桥接器，将AXI信号透传给axi_mem_model
   - 在整个传输过程中，axi_protocol_checker实时监控AXI信号的合规性

5. **数据存储阶段**：
   - axi_mem_model接收AXI写信号
   - 根据字节使能信号，将数据写入指定的内存地址
   - 向axi_stb_s返回AXI响应信号

6. **完成反馈阶段**：
   - 响应信号通过axi_stb_s和axi_stb回传到burst_store
   - burst_store标记指令完成，并向测试平台发送完成信号
   - 测试平台收到完成信号后，结束当前测试用例

### 2.2 数据流示意图

```
测试平台
    │
    ▼
STB指令 ───► burst_store ───► ur_model（随机数据生成）
                   │             │
                   ▼             │
           事务包生成  ◄───────  随机数据
                   │
                   ▼
           axi_stb（AXI主控制器）
                   │
                   ▼
           axi_stb_s（信号桥接）
                   │
                   ▼
           axi_mem_model（数据存储）
                   │
                   │ （监控）
                   ▼
           axi_protocol_checker（协议检查）
```

## 3. 模块详解

本系统由8个核心模块组成，每个模块负责特定的功能，共同完成数据的传输和存储。以下是每个模块的详细解释：

## 系统架构
系统采用流水线式架构，数据流为"ur_model→burst_store→axi_stb→axi_stb_s→axi_mem_model"，各模块协同工作完成从指令解析到数据存储的完整流程。同时，axi_protocol_checker模块实时监控AXI总线信号，确保协议合规性。

### 模块详解

### 3.1 ur_model（随机数据生成器）

**作用原理**：ur_model模块是系统的数据源，基于LFSR（线性反馈移位寄存器）算法生成高质量的伪随机数据，用于模拟真实的数据源。LFSR是一种常用的随机数生成方法，通过寄存器移位和特定的反馈逻辑生成看似随机的序列。

**核心功能详解**：
- **随机数据生成**：生成128位宽的伪随机数据，数据质量由LFSR多项式决定
- **地址映射**：支持11位地址空间（共2048个存储位置），每个地址对应一个唯一的随机数
- **错误注入**：支持向生成的数据中注入各种类型的错误，用于测试系统的容错能力
- **ID选择**：支持16个不同的UR ID，每个ID对应不同的随机数序列
- **数据记录**：对特殊测试用例（如测试用例3和5）的数据进行记录，便于验证

**关键参数详解**：
- `DATA_WIDTH=128`：定义输出数据的位宽为128位
- `LFSR_WIDTH=32`：定义LFSR移位寄存器的宽度为32位
- `LFSR_POLY=32'h8000000B`：LFSR的多项式系数，决定了随机序列的周期和分布特性
- `ADDR_WIDTH=11`：定义地址总线的宽度为11位，支持2^11=2048个地址
- `MAX_ID=16`：定义最大的UR ID值为16

**内部实现关键点**：

1. **LFSR初始化**：根据UR ID初始化LFSR状态，确保不同ID生成不同的随机序列
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           lfsr_state <= {31'b0, 1'b1} ^ {32{ur_id[0]}}; // 初始状态与UR ID相关
       end
   end
   ```

2. **随机数据生成**：通过LFSR状态生成128位随机数据
   ```verilog
   always @(*) begin
       // 从32位LFSR状态扩展生成128位随机数据
       ur_rdata = {lfsr_state, lfsr_state << 8, lfsr_state << 16, lfsr_state << 24};
   end
   ```

3. **错误注入逻辑**：根据错误类型和地址掩码注入不同类型的错误
   ```verilog
   always @(*) begin
       if (err_inject && ((ur_addr & err_addr_mask) == 0)) begin
           case (err_type)
               4'h1: data_with_error = ur_rdata ^ 128'h00000001;
               4'h2: data_with_error = ur_rdata ^ 128'hFFFFFFFFFFFFFFFF;
               // 其他错误类型...
               default: data_with_error = ur_rdata;
           endcase
       end else begin
           data_with_error = ur_rdata;
       end
   end
   ```

**连接关系**：
- 输入：burst_store的读使能(`ur_re`)、读地址(`ur_addr`)、UR ID(`stb_u_ur_id`)
- 输入：测试平台的错误注入控制信号(`err_inject`、`err_type`、`err_addr_mask`)
- 输出：128位随机数据(`ur_rdata`)到burst_store

### 3.2 burst_store（业务逻辑核心模块）

**作用原理**：burst_store是整个系统的核心，负责解析STB指令、控制数据读取流程、实现多SMC地址交错，并生成内部事务包发送给AXI控制器。它是连接指令层和数据传输层的关键桥梁。

**核心功能详解**：
- **STB指令解析**：解析来自测试平台的STB指令，提取SMC使能、字节使能、burst长度等信息
- **UR数据读取控制**：根据指令向ur_model发送读请求，获取随机数据
- **地址计算**：根据基地址、SMC使能和地址交错步长，计算每个SMC的实际写入地址
- **事务包生成**：将地址、数据、burst长度和字节使能打包成内部事务包
- **状态管理**：通过状态机管理整个数据传输过程，提供完成反馈

**状态机设计详解**：

burst_store模块实现了5个状态的状态机，用于控制数据传输的完整流程：

1. **IDLE状态**：
   - 等待STB指令
   - 当接收到有效的STB指令（stb_u_valid为高）时，进入INIT状态

2. **INIT状态**：
   - 解析STB指令参数（SMC使能、字节使能、burst长度等）
   - 初始化内部计数器和地址变量
   - 根据字节使能编码生成完整的字节使能信号
   - 根据burst长度编码计算实际的burst长度
   - 进入AW_HANDSHAKE状态

3. **AW_HANDSHAKE状态**：
   - 向ur_model发送读请求（设置ur_re为高）
   - 计算当前SMC的写入地址
   - 当ur_model返回数据且axi_stb准备好接收事务包时，进入WAIT_RESP状态

4. **WAIT_RESP状态**：
   - 等待axi_stb的事务完成反馈（stb2stb_done为高）
   - 处理多SMC和多burst长度的情况
   - 当所有数据传输完成时，进入DONE状态

5. **DONE状态**：
   - 标记指令执行完成（设置stb_d_done为高）
   - 等待测试平台的确认信号
   - 当接收到确认信号后，返回IDLE状态

**状态转换图**：
```
IDLE ───────► INIT ───────► AW_HANDSHAKE ───────► WAIT_RESP ───────► DONE
  ▲                                                                 │
  └─────────────────────────────────────────────────────────────────┘
```

**关键参数详解**：
- `ADDR_WIDTH=32`：定义地址总线的宽度为32位
- `DATA_WIDTH=128`：定义数据总线的宽度为128位
- `SMC_COUNT=6`：定义系统支持的SMC数量为6个
- `UR_BYTE_CNT=16`：定义字节使能信号的宽度为16位（对应128位数据）
- `INTLV_STEP=64`：定义SMC地址交错的步长为64字节

**内部实现关键点**：

1. **字节使能扩展**：将4位字节使能编码扩展为16位完整字节使能信号
   ```verilog
   always @(*) begin
       case (stb_u_byte_strb)
           4'h0: byte_strb = 16'hFFFF;  // 全字节有效
           4'h1: byte_strb = 16'h00FF;  // 低8字节有效
           4'h2: byte_strb = 16'h0003;  // 低2字节有效
           4'h3: byte_strb = 16'h000F;  // 低4字节有效
           // 其他字节使能模式...
       endcase
   end
   ```

2. **地址交错计算**：根据SMC索引和交错步长计算实际写入地址
   ```verilog
   always @(*) begin
       // 基地址 + SMC索引 * 交错步长 + 偏移量
       write_addr = stb_u_gr_base_addr + (current_smc * INTLV_STEP) + (current_burst * DATA_WIDTH/8);
   end
   ```

3. **burst长度转换**：将2位burst长度编码转换为实际的burst长度
   ```verilog
   always @(*) begin
       case (stb_u_brst)
           2'b00: burst_len = 8'd1;   // 1拍burst
           2'b01: burst_len = 8'd2;   // 2拍burst
           2'b10: burst_len = 8'd4;   // 4拍burst
           2'b11: burst_len = 8'd8;   // 8拍burst
       endcase
   end
   ```

**连接关系**：
- 输入：测试平台的STB指令信号（`stb_u_valid`、`stb_u_smc_strb`、`stb_u_byte_strb`等）
- 输入：ur_model的随机数据（`ur_rdata`）
- 输出：读请求到ur_model（`ur_re`、`ur_addr`）
- 输出：事务包到axi_stb（`stb2stb_valid`、`stb2stb_addr`、`stb2stb_data`等）
- 输出：指令完成反馈到测试平台（`stb_d_valid`、`stb_d_done`）

### 3.3 axi_stb（AXI主控制器）

**作用原理**：axi_stb模块是AXI协议的主控制器，负责将burst_store生成的内部事务包转换为符合AXI协议规范的写信号，并控制整个AXI写事务的执行过程。

**核心功能详解**：
- **事务包解析**：接收并解析burst_store发送的内部事务包
- **AXI地址通道控制**：生成符合AXI协议的地址通道信号（AW通道）
- **AXI数据通道控制**：生成符合AXI协议的数据通道信号（W通道）
- **AXI响应通道控制**：处理AXI响应通道信号（B通道）
- **超时保护**：实现AXI事务的超时检测和处理机制
- **事务完成反馈**：向burst_store反馈事务执行状态

**状态机设计详解**：

axi_stb模块实现了4个状态的状态机，用于控制AXI写事务的完整流程：

1. **IDLE状态**：
   - 等待内部事务包
   - 当接收到有效的事务包（stb2stb_valid为高）时，进入AW_TRANSFER状态

2. **AW_TRANSFER状态**：
   - 发送AXI地址通道信号（设置axi_awvalid为高）
   - 等待从设备的地址就绪信号（axi_awready为高）
   - 当地址通道握手完成时，进入W_TRANSFER状态

3. **W_TRANSFER状态**：
   - 发送AXI数据通道信号（设置axi_wvalid为高）
   - 对于多拍burst传输，逐拍发送数据
   - 发送最后一拍数据时，设置axi_wlast为高
   - 当所有数据发送完成且数据通道握手完成时，进入B_TRANSFER状态

4. **B_TRANSFER状态**：
   - 等待从设备的响应信号（axi_bvalid为高）
   - 发送响应就绪信号（设置axi_bready为高）
   - 当响应通道握手完成时，标记事务完成并返回IDLE状态

**状态转换图**：
```
IDLE ───────► AW_TRANSFER ───────► W_TRANSFER ───────► B_TRANSFER
  ▲                                                      │
  └──────────────────────────────────────────────────────┘
```

**关键参数详解**：
- `ADDR_WIDTH=32`：定义AXI地址总线的宽度为32位
- `DATA_WIDTH=128`：定义AXI数据总线的宽度为128位
- `UR_BYTE_CNT=16`：定义AXI字节使能信号的宽度为16位（对应128位数据）

**AXI协议关键信号配置**：
- `axi_awsize=3'b100`：设置AXI地址大小为16字节（对应128位数据）
- `axi_awburst=2'b01`：设置AXI突发传输模式为INCR（递增）模式
- `axi_awlen`：设置为burst长度减1（AXI协议定义）

**内部实现关键点**：

1. **AXI地址通道控制**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           axi_awvalid <= 1'b0;
       end else if (state == AW_TRANSFER && axi_awready) begin
           axi_awvalid <= 1'b0;
       end else if (state == IDLE && stb2stb_valid) begin
           axi_awvalid <= 1'b1;
       end
   end
   ```

2. **AXI数据通道控制**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           axi_wvalid <= 1'b0;
           data_count <= 8'd0;
       end else if (state == W_TRANSFER && axi_wready) begin
           if (data_count == burst_len - 1) begin
               axi_wvalid <= 1'b0;
               data_count <= 8'd0;
           end else begin
               data_count <= data_count + 1;
           end
       end else if (state == AW_TRANSFER && axi_awready) begin
           axi_wvalid <= 1'b1;
       end
   end
   
   // 设置最后一拍标志
   assign axi_wlast = (state == W_TRANSFER) && (data_count == burst_len - 1);
   ```

**连接关系**：
- 输入：burst_store的事务包（`stb2stb_valid`、`stb2stb_addr`、`stb2stb_data`等）
- 输出：AXI主接口信号到axi_stb_s（`axi_awvalid`、`axi_awaddr`、`axi_wvalid`等）
- 输出：事务完成反馈到burst_store（`stb2stb_done`）

### 3.4 axi_stb_s（AXI从→主桥接模块）

**作用原理**：axi_stb_s模块作为AXI信号的桥接器，实现上游axi_stb的AXI主接口与下游axi_mem_model的AXI从接口之间的信号透明传输。它主要用于系统扩展和信号中继，使得系统结构更加灵活。

**核心功能详解**：
- **信号透传**：将上游axi_stb的AXI主接口信号透传到下游axi_mem_model
- **响应回传**：将下游axi_mem_model的响应信号回传到上游axi_stb
- **超时保护**：实现AXI信号传输的超时检测和处理机制
- **信号缓冲**：在某些实现中，可能包含信号缓冲功能，用于优化时序

**状态机设计详解**：

axi_stb_s模块实现了4个状态的状态机，用于控制AXI信号的透明传输：

1. **IDLE状态**：
   - 等待上游AXI地址有效信号
   - 当接收到上游的地址有效信号（s_awvalid为高）时，进入FORWARD_AW状态

2. **FORWARD_AW状态**：
   - 将上游的地址信号透传给下游（设置m_awvalid为高）
   - 等待下游的地址就绪信号（m_awready为高）
   - 当地址通道握手完成时，进入FORWARD_W状态

3. **FORWARD_W状态**：
   - 将上游的数据信号透传给下游（设置m_wvalid为高）
   - 等待下游的数据就绪信号（m_wready为高）
   - 当数据通道握手完成且是最后一拍数据时，进入FORWARD_B状态

4. **FORWARD_B状态**：
   - 将下游的响应信号透传给上游（设置s_bvalid为高）
   - 等待上游的响应就绪信号（s_bready为高）
   - 当响应通道握手完成时，返回IDLE状态

**状态转换图**：
```
IDLE ───────► FORWARD_AW ───────► FORWARD_W ───────► FORWARD_B
  ▲                                                     │
  └─────────────────────────────────────────────────────┘
```

**关键参数详解**：
- `ADDR_WIDTH=32`：定义AXI地址总线的宽度为32位
- `DATA_WIDTH=128`：定义AXI数据总线的宽度为128位

**内部实现关键点**：

1. **地址通道信号透传**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           m_awvalid <= 1'b0;
       end else if (state == FORWARD_AW && m_awready) begin
           m_awvalid <= 1'b0;
       end else if (state == IDLE && s_awvalid) begin
           m_awvalid <= 1'b1;
       end
   end
   
   // 地址信号直接连接
   assign m_awaddr = s_awaddr;
   assign m_awlen = s_awlen;
   assign m_awsize = s_awsize;
   assign m_awburst = s_awburst;
   ```

2. **数据通道信号透传**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           m_wvalid <= 1'b0;
       end else if (state == FORWARD_W && m_wready) begin
           if (s_wlast) begin
               m_wvalid <= 1'b0;
           end
       end else if (state == FORWARD_AW && m_awready) begin
           m_wvalid <= 1'b1;
       end
   end
   
   // 数据信号直接连接
   assign m_wdata = s_wdata;
   assign m_wstrb = s_wstrb;
   assign m_wlast = s_wlast;
   ```

3. **响应通道信号透传**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           s_bvalid <= 1'b0;
       end else if (state == FORWARD_B && s_bready) begin
           s_bvalid <= 1'b0;
       end else if (state == FORWARD_W && s_wlast && m_wready) begin
           // 等待下游响应
       end else if (m_bvalid) begin
           s_bvalid <= 1'b1;
       end
   end
   
   // 响应信号直接连接
   assign s_bresp = m_bresp;
   ```

**连接关系**：
- 输入：axi_stb的AXI主接口信号（`s_awvalid`、`s_awaddr`、`s_wvalid`等）
- 输出：AXI主接口信号到axi_mem_model（`m_awvalid`、`m_awaddr`、`m_wvalid`等）
- 输出：AXI从接口信号到axi_stb（`s_awready`、`s_wready`、`s_bvalid`等）

### 3.5 axi_mem_model（内存模型）

**作用原理**：axi_mem_model模块模拟外部存储设备，用于接收和存储通过AXI总线传输的数据。它实现了基本的内存写入功能，并支持地址越界检查和数据导出功能。

**核心功能详解**：
- **内存存储**：实现512KB的存储空间，用于存储AXI写入的数据
- **AXI从接口**：实现符合AXI协议的从接口，接收写地址和数据
- **字节使能处理**：根据字节使能信号，实现精确的字节级数据写入
- **地址越界检查**：检查写入地址是否超出内存范围，提供越界保护
- **响应生成**：生成AXI响应信号，反馈写入操作的结果
- **内存初始化**：在复位时，将内存初始化为特定值
- **数据导出**：支持将内存内容导出到文件，便于验证

**状态机设计详解**：

axi_mem_model模块实现了4个状态的状态机，用于控制内存写入的完整流程：

1. **IDLE状态**：
   - 等待AXI写地址有效信号
   - 当接收到地址有效信号（axi_awvalid为高）时，进入WRITE_ADDR状态

2. **WRITE_ADDR状态**：
   - 锁存AXI写地址和控制信息
   - 执行地址越界检查
   - 设置地址就绪信号（axi_awready为高）
   - 当地址通道握手完成时，进入WRITE_DATA状态

3. **WRITE_DATA状态**：
   - 接收AXI写数据
   - 根据字节使能信号写入数据到内存
   - 设置数据就绪信号（axi_wready为高）
   - 当数据通道握手完成且是最后一拍数据时，进入WRITE_RESP状态

4. **WRITE_RESP状态**：
   - 生成AXI响应信号（设置axi_bvalid为高）
   - 设置响应码（如OKAY、SLVERR等）
   - 当响应通道握手完成时，返回IDLE状态

**状态转换图**：
```
IDLE ───────► WRITE_ADDR ───────► WRITE_DATA ───────► WRITE_RESP
  ▲                                                       │
  └───────────────────────────────────────────────────────┘
```

**关键参数详解**：
- `ADDR_WIDTH=32`：定义AXI地址总线的宽度为32位
- `DATA_WIDTH=128`：定义AXI数据总线的宽度为128位
- `MEM_SIZE=512KB`：定义内存模型的容量为512KB

**内存组织**：
- 内存按128位（16字节）宽度组织
- 总共有512KB / 16B = 32768个内存单元
- 每个内存单元由16个字节组成，每个字节可独立写入

**内部实现关键点**：

1. **内存数组定义**：
   ```verilog
   // 定义512KB内存，每个单元128位
   reg [DATA_WIDTH-1:0] mem [0:(MEM_SIZE*1024)/(DATA_WIDTH/8)-1];
   ```

2. **内存初始化**：
   ```verilog
   integer i;
   initial begin
       // 初始化内存为特定值
       for (i = 0; i < (MEM_SIZE*1024)/(DATA_WIDTH/8); i = i + 1) begin
           mem[i] = 128'hDEADBEEF_00000000_12345678_ABCDEF01;
       end
   end
   ```

3. **字节使能写入**：
   ```verilog
   genvar j;
   generate
       for (j = 0; j < DATA_WIDTH/8; j = j + 1) begin : byte_write
           always @(posedge clk) begin
               if (state == WRITE_DATA && axi_wvalid && axi_wready && axi_wstrb[j]) begin
                   mem[mem_addr][j*8+7:j*8] <= axi_wdata[j*8+7:j*8];
               end
           end
       end
   endgenerate
   ```

4. **地址越界检查**：
   ```verilog
   always @(*) begin
       if (axi_awaddr >= (MEM_SIZE*1024)) begin
           addr_error = 1'b1;
       end else begin
           addr_error = 1'b0;
       end
   end
   ```

**连接关系**：
- 输入：axi_stb_s的AXI主接口信号（`axi_awvalid`、`axi_awaddr`、`axi_wvalid`等）
- 输出：AXI从接口信号到axi_stb_s（`axi_awready`、`axi_wready`、`axi_bvalid`等）

### 3.6 axi_protocol_checker（AXI协议检查器）

**作用原理**：axi_protocol_checker模块实时监控AXI总线信号，检测并报告AXI协议违规行为。它是确保系统AXI总线操作正确性的重要工具。

**核心功能详解**：
- **地址通道监控**：监控AXI写地址通道信号的时序和合规性
- **数据通道监控**：监控AXI写数据通道信号的时序和合规性
- **响应通道监控**：监控AXI写响应通道信号的时序和合规性
- **错误检测与分类**：检测并分类各种类型的AXI协议错误
- **错误报告**：输出错误代码和详细的错误提示信息
- **超时检测**：检测AXI事务的超时情况

**支持检测的错误类型**：

1. **地址通道错误**：
   - AWVALID长时间为高但未得到AWREADY响应（超时）
   - AWADDR/AWLEN/AWSIZE/AWBURST在握手期间发生变化

2. **数据通道错误**：
   - WVALID在AW通道握手前有效
   - WVALID长时间为高但未得到WREADY响应（超时）
   - WLAST未在最后一拍数据时置高
   - WSTRB全为0

3. **响应通道错误**：
   - BVALID在W通道握手完成前有效
   - BVALID长时间为高但未得到BREADY响应（超时）

**关键参数详解**：
- `ADDR_WIDTH=32`：定义AXI地址总线的宽度为32位
- `DATA_WIDTH=128`：定义AXI数据总线的宽度为128位
- `TIMEOUT_CYCLES=100`：定义超时检测的时钟周期数

**错误代码定义**：
- `4'h0`：无错误
- `4'h1`：AWVALID超时
- `4'h2`：WVALID超时
- `4'h3`：BVALID超时
- `4'h4`：WVALID过早有效
- `4'h5`：BVALID过早有效
- `4'h6`：WSTRB全0
- `4'h7`：WLAST错误
- `4'h8`：地址信号变化错误

**内部实现关键点**：

1. **超时检测**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           aw_timeout_cnt <= 8'd0;
       end else if (axi_awvalid && !axi_awready) begin
           if (aw_timeout_cnt < TIMEOUT_CYCLES) begin
               aw_timeout_cnt <= aw_timeout_cnt + 1;
           end else begin
               // 触发AWVALID超时错误
               error_code <= 4'h1;
               protocol_error <= 1'b1;
               $display("[AXI_CHECKER] AWVALID超时错误!");
           end
       end else begin
           aw_timeout_cnt <= 8'd0;
       end
   end
   ```

2. **信号时序检查**：
   ```verilog
   always @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin
           aw_handshake_done <= 1'b0;
       end else if (axi_awvalid && axi_awready) begin
           aw_handshake_done <= 1'b1;
       end
   end
   
   // 检查WVALID是否在AW握手前有效
   always @(posedge clk) begin
       if (!rst_n) begin
           // 复位状态
       end else if (axi_wvalid && !aw_handshake_done) begin
           error_code <= 4'h4;
           protocol_error <= 1'b1;
           $display("[AXI_CHECKER] WVALID过早有效错误!");
       end
   end
   ```

**连接关系**：
- 输入：axi_stb→axi_stb_s的AXI信号（`axi_awvalid`、`axi_awready`、`axi_wvalid`等）
- 输出：协议错误标志到测试平台（`protocol_error`）
- 输出：错误代码到测试平台（`error_code`）

### 3.7 axi_top（顶层模块）

**作用原理**：axi_top模块作为整个系统的顶层容器，负责实例化和连接所有子模块，定义模块间的连接信号，并实现测试完成逻辑和调试监控功能。

**核心功能详解**：
- **模块实例化**：实例化所有子模块，并传递正确的参数
- **信号连接**：定义和连接模块间的所有信号，形成完整的数据流路径
- **测试控制**：实现测试使能和测试完成逻辑
- **调试监控**：提供调试信号和日志输出功能
- **系统集成**：将各个独立的子模块集成为一个完整的系统

**关键参数详解**：
- `ADDR_WIDTH=32`：定义系统地址总线的宽度为32位
- `DATA_WIDTH=128`：定义系统数据总线的宽度为128位
- `SMC_COUNT=6`：定义系统支持的SMC数量为6个
- `UR_BYTE_CNT=16`：定义系统字节使能信号的宽度为16位
- `INTLV_STEP=64`：定义SMC地址交错的步长为64字节
- `MEM_SIZE=512KB`：定义内存模型的容量为512KB

**内部实现关键点**：

1. **模块实例化与参数传递**：
   ```verilog
   // 实例化ur_model（随机数据生成器）
   ur_model #(
       .DATA_WIDTH(DATA_WIDTH),
       .LFSR_WIDTH(32),
       .LFSR_POLY(32'h8000000B),
       .ADDR_WIDTH(11),
       .MAX_ID(16)
   ) ur_model_inst (
       // 端口连接...
   );
   
   // 实例化burst_store（核心业务逻辑）
   burst_store #(
       .ADDR_WIDTH(ADDR_WIDTH),
       .DATA_WIDTH(DATA_WIDTH),
       .SMC_COUNT(SMC_COUNT),
       .UR_BYTE_CNT(UR_BYTE_CNT),
       .INTLV_STEP(INTLV_STEP)
   ) burst_store_inst (
       // 端口连接...
   );
   
   // 其他模块实例化...
   ```

2. **测试完成逻辑**：
   ```verilog
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
   ```

3. **调试监控功能**：
   ```verilog
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
   ```

**连接关系**：
- 连接所有子模块形成完整数据流
- 连接测试平台接口（`tb_en`、`tb_done`等）
- 连接STB指令接口
- 连接错误注入控制接口
- 连接协议检查器输出接口
- 连接调试信号输出接口

### 3.8 burst_store_tb_coverage（覆盖率测试平台）

**作用原理**：burst_store_tb_coverage模块是系统的测试平台，负责生成各种测试用例，控制测试流程，验证系统功能，并收集覆盖率数据。

**核心功能详解**：
- **测试用例生成**：生成多种测试用例，覆盖不同的传输场景和边界条件
- **STB指令发送**：根据测试用例生成并发送STB指令到burst_store
- **测试流程控制**：控制测试的启动、运行和结束
- **覆盖率数据收集**：收集功能覆盖率数据，评估测试的全面性
- **结果验证**：验证系统的输出结果是否符合预期
- **数据导出**：导出内存内容和随机数据到文件，便于分析

**支持的测试用例类型**：

1. **单SMC单burst传输**：测试单个SMC的单次burst传输功能
2. **多SMC多burst传输**：测试多个SMC的多次burst传输功能
3. **全SMC地址交错传输**：测试所有SMC的地址交错传输功能
4. **最大长度burst传输**：测试最大长度的burst传输功能
5. **错误注入测试**：测试系统在错误情况下的容错能力
6. **字节使能测试**：测试不同字节使能模式下的数据传输功能
7. **地址边界测试**：测试地址接近边界值的传输功能
8. **混合模式测试**：测试多种模式混合的传输功能
9. **高频率传输测试**：测试连续发起多个burst传输的功能
10. **协议边界测试**：测试AXI协议边界情况的处理能力

**内部实现关键点**：

1. **测试用例定义**：
   ```verilog
   typedef struct {
       bit [SMC_COUNT-1:0] smc_strb;
       bit [3:0] byte_strb;
       bit [1:0] brst;
       bit [ADDR_WIDTH-1:0] gr_base_addr;
       bit [3:0] ur_id;
       bit [10:0] ur_addr;
       bit err_inject;
       bit [3:0] err_type;
   } test_case_t;
   
   // 定义测试用例数组
   test_case_t test_cases [10] = '{
       '{6'b000001, 4'h0, 2'b00, 32'h00001000, 4'h0, 11'h000, 1'b0, 4'h0}, // 测试用例1
       '{6'b000010, 4'h0, 2'b10, 32'h00002000, 4'h1, 11'h010, 1'b0, 4'h0}, // 测试用例2
       // 其他测试用例...
   };
   ```

2. **测试流程控制**：
   ```verilog
   initial begin
       // 初始化
       rst_n = 1'b0;
       tb_en = 1'b0;
       // 其他信号初始化...
       
       // 复位
       #100 rst_n = 1'b1;
       #100 tb_en = 1'b1;
       
       // 执行所有测试用例
       for (int i = 0; i < 10; i = i + 1) begin
           execute_test_case(test_cases[i], i+1);
       end
       
       // 测试完成
       #1000 $finish;
   end
   
   task execute_test_case(input test_case_t tc, input int case_id);
       // 设置测试用例参数
       stb_u_smc_strb = tc.smc_strb;
       stb_u_byte_strb = tc.byte_strb;
       // 其他参数设置...
       
       // 发送STB指令
       stb_u_valid = 1'b1;
       @(posedge clk);
       stb_u_valid = 1'b0;
       
       // 等待测试完成
       wait(tb_done);
       #100;
       
       // 导出结果
       export_memory(case_id);
   endtask
   ```

3. **内存导出功能**：
   ```verilog
   task export_memory(input int case_id);
       string filename;
       int file;
       
       // 生成文件名
       $sformat(filename, "mem_case%d.txt", case_id);
       
       // 打开文件
       file = $fopen(filename, "w");
       
       // 写入文件头
       $fwrite(file, "// 内存内容导出\n");
       $fwrite(file, "// 导出时间: %0t\n", $time);
       $fwrite(file, "// 测试用例ID: %0d\n\n", case_id);
       
       // 写入内存内容
       // ...
       
       // 关闭文件
       $fclose(file);
   endtask
   ```

**连接关系**：
- 连接axi_top的测试平台接口
- 连接STB指令接口
- 连接错误注入控制接口
- 连接调试监控接口

## STB规范参数详解

STB（Storage Buffer）接口规范定义了系统的核心控制参数和指令格式，以下是各参数的详细解释及其在系统中的体现：

### STB接口信号

| 信号名 | 位宽 | 方向 | 功能描述 | 在模块中的体现 |
|-------|-----|------|---------|--------------|
| CLK | 1 | 输入 | 系统时钟 | 所有模块的时钟信号 |
| RST_N | 1 | 输入 | 系统复位 | 所有模块的复位信号 |
| STB_U_VALID | 1 | 输入 | 指令有效 | burst_store的stb_u_valid信号 |
| STB_U_SMC_STRB | 6 | 输入 | SMC使能编码 | burst_store的stb_u_smc_strb信号，控制SMC选择 |
| STB_U_BYTE_STRB | 4 | 输入 | 字节使能编码 | burst_store的stb_u_byte_strb信号，控制字节使能扩展 |
| STB_U_BRST | 2 | 输入 | burst长度编码 | burst_store的stb_u_brst信号，控制burst长度转换 |
| STB_U_GR_BASE_ADDR | 32 | 输入 | 外部内存基地址 | burst_store的stb_u_gr_base_addr信号，用于计算写入地址 |
| STB_U_UR_ID | 4 | 输入 | 目标UR ID | ur_model的ur_id信号，选择UR数据源 |
| STB_U_UR_ADDR | 11 | 输入 | 目标UR地址 | ur_model的ur_addr信号，选择UR地址 |
| STB_D_VALID | 1 | 输出 | 指令有效反馈 | burst_store的stb_d_valid信号，反馈指令接收状态 |
| STB_D_DONE | 1 | 输出 | 指令完成反馈 | burst_store的stb_d_done信号，反馈指令执行状态 |
| STB_D_READY | 1 | 输入 | 上层就绪信号 | burst_store的stb_d_ready信号，用于握手确认 |

### 相关寄存器

| 寄存器名 | 位宽 | 功能描述 | 在模块中的体现 |
|---------|-----|---------|--------------|
| UR-RE | 1 | UR读使能 | burst_store的ur_re信号，控制ur_model数据读取 |
| UR-ADDR | 11 | UR读地址 | burst_store的ur_addr信号，指定ur_model读取地址 |
| UR-RDATA | 128 | UR读数据 | ur_model的ur_rdata信号，输出随机数据 |
| ERR-INJECT | 1 | 错误注入使能 | ur_model的err_inject信号，控制错误注入 |
| ERR-TYPE | 4 | 错误类型 | ur_model的err_type信号，指定注入错误类型 |
| ERR-ADDR-MASK | 11 | 错误地址掩码 | ur_model的err_addr_mask信号，指定错误发生地址范围 |

### 设计超参

| 超参名 | 数值 | 功能描述 | 在模块中的体现 |
|-------|-----|---------|--------------|
| PARAM-UR-BYTE-CNT | 16 | 字节使能宽度 | 定义在axi_top的UR_BYTE_CNT参数，用于所有需要字节使能的模块 |
| PARAM-SMC-COUNT | 6 | SMC数量 | 定义在axi_top的SMC_COUNT参数，用于burst_store的SMC选择 |
| PARAM-INTLV-STEP | 64 | 地址交错步长 | 定义在axi_top的INTLV_STEP参数，用于burst_store的地址计算。这是多SMC并行访问时的核心参数，当多个SMC同时工作时，系统会为每个SMC分配独立的地址空间，空间之间的间隔即为64字节。计算公式为：实际地址 = 基地址 + SMC索引 * 64。这种设计有效避免了地址冲突，提高了内存带宽利用率和数据传输效率。例如，当基地址为0x3000，SMC0~SMC2同时使能时，各SMC的实际写入地址分别为0x3000、0x3040（0x3000+64）、0x3080（0x3000+128） |
| PARAM-MEM-SIZE | 512KB | 内存大小 | 定义在axi_top的MEM_SIZE参数，用于axi_mem_model的内存容量 |
| PARAM-BURST-MAX | 8 | 最大burst长度 | 在burst_store中实现，支持最大8拍的burst传输 |

### 上行/下行微指令

STB指令通过以下微指令字段控制数据传输：
- **vld**：指令有效性标志（STB_U_VALID）
- **smc_strb**：SMC使能编码（STB_U_SMC_STRB）
- **byte_strb**：字节使能编码（STB_U_BYTE_STRB）
- **brst**：burst长度编码（STB_U_BRST）
- **base_addr**：外部内存基地址（STB_U_GR_BASE_ADDR）
- **ur_id**：目标UR ID（STB_U_UR_ID）
- **ur_addr**：目标UR地址（STB_U_UR_ADDR）

这些微指令字段在burst_store模块中被解析，并转换为相应的控制信号，驱动整个数据传输流程。

## 基础测试用例详解

### 一、测试原理

基础测试用例（1-4）主要用于验证系统的核心功能，包括单次写入、多拍burst传输、多SMC并行访问和字节使能写入。测试原理基于以下几个方面：

#### 1. 状态机监控机制
所有测试用例通过状态机转换判断执行完成状态。测试平台（burst_store_tb）监控burst_store模块的状态从`DONE`转换到`IDLE`，以此确认测试用例执行完毕。每个测试用例均设置超时保护机制（1000-3000周期），防止测试因异常情况无限等待。

#### 2. STB指令配置
每个测试用例通过配置STB接口信号控制不同的写入模式：
- **测试用例1**：配置smc_strb=1（仅SMC0），brst_len=0（单次写入），验证基本写入功能
- **测试用例2**：配置smc_strb=2（仅SMC1），brst_len=3（4拍burst写入），验证连续地址写入
- **测试用例3**：配置smc_strb=7（SMC0-2同时使能），brst_len=1（2拍burst），验证INTLV_STEP=64的地址交错机制
- **测试用例4**：配置smc_strb=1（SMC0），byte_strb=特定值，验证部分字节写入功能

#### 3. 内存写入与AXI协议交互
测试过程中，STB指令首先被burst_store模块解析，然后转换为AXI协议信号。axi_mem_model模块作为AXI从设备接收这些信号，按照AXI协议状态机（IDLE→WRITE_ADDR→WRITE_DATA→WRITE_RESP）处理写入请求，最终将数据写入内存数组。

#### 4. 内存导出验证
每个测试用例执行完成后，系统会调用axi_mem_model中的`export_memory`任务导出内存内容，用于验证写入是否符合预期。

### 二、输出格式

通过分析`axi_mem_model.v`中的`export_memory`函数，测试用例的输出数据格式如下：

#### 1. 文件结构
- **文件路径**：`/home/zwz/zts/17_stb/sim_output/mem.txt`
- **文件内容**：分为三部分：文件头信息、分测试用例的写入地址数据、完整内存内容

#### 2. 文件头信息
```
// 内存内容导出
// 导出时间: [具体时间戳]
// 测试用例ID: [当前测试用例编号]
```

#### 3. 地址与数据格式
- **地址格式**：16进制，32位宽度（如`0x00003000`）
- **数据格式**：16进制，128位宽度（如`0xDEADBEEF_00000000_12345678_ABCDEF01`）
- **数据单位**：每个地址对应16字节（128位）的数据

#### 4. 完整内存内容
文件最后部分包含前512KB地址空间的完整内存内容，按地址顺序排列，每行一个地址-数据对。

### 三、INTLV_STEP=64的应用体现

在测试用例3的输出中，INTLV_STEP=64的地址交错机制得到了清晰展示：
- SMC0的写入地址：0x3000, 0x3010（步进16字节，符合AXI burst传输）
- SMC1的写入地址：0x3040, 0x3050（基地址+64字节）
- SMC2的写入地址：0x3080, 0x3090（基地址+128字节）

这种地址分配方式确保了多个SMC并行写入时不会发生地址冲突，充分利用了内存带宽，提高了系统效率。通过这种输出格式，用户可以直观地验证每个测试用例的执行结果，特别是验证INTLV_STEP=64等关键参数的实际应用效果。



### 四、测试用例详细分析

根据burst_store_tb.v、axi_mem_model.v和ur_model.v文件的实现，四个测试用例执行后会在不同的内存地址写入不同的随机数据，并通过export_memory任务导出到对应的文件中。

#### 测试用例1：单次写入（burst长度=1）
**参数设置**：
- SMC0使能（stb_u_smc_strb=6'b000001）
- burst长度=1（stb_u_brst=0）
- 基地址=0x1000（stb_u_gr_base_addr=32'h00001000）
- UR起始地址=0x00（stb_u_ur_addr=11'h000）
- UR ID=0（stb_u_ur_id=0）
- 全字节有效（stb_u_byte_strb=4'h0）

**内存输出结果**：
- 在地址0x1000处写入一个128位数据
- 该数据来自ur_model的随机数生成器，基于LFSR算法，初始值与ID=0相关
- 导出到mem_case1.txt文件，包含前512个地址和0x1000地址的内容

**示例输出**：
```
// 内存内容导出
// 导出时间: 123456
// 测试用例ID: 1

// 前512个地址内容...
Addr: 0x000001F0, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F4, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F8, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001FC, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01

// 测试用例中实际写入的地址:
Addr: 0x00001000, Data: 0xFFFFFFFF_FFFFFFFE_FFFDFFFC_FFFBFFFA
```

#### 测试用例2：突发写入（burst长度=4）
**参数设置**：
- SMC1使能（stb_u_smc_strb=6'b000010）
- burst长度=4（stb_u_brst=2）
- 基地址=0x2000（stb_u_gr_base_addr=32'h00002000）
- UR起始地址=0x10（stb_u_ur_addr=11'h010）
- UR ID=1（stb_u_ur_id=1）
- 全字节有效（stb_u_byte_strb=4'h0）

**内存输出结果**：
- 在地址0x2000开始的4个连续地址写入数据（0x2000、0x2010、0x2020、0x2030）
- 每个地址写入128位随机数据，数据基于LFSR生成，且每个地址的数据会根据LFSR状态递增
- 导出到mem_case2.txt文件，包含前512个地址和0x2040地址的内容

**示例输出**：
```
// 内存内容导出
// 导出时间: 234567
// 测试用例ID: 2

// 前512个地址内容...
Addr: 0x000001F0, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F4, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F8, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001FC, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01

// 测试用例中实际写入的地址:
Addr: 0x00002040, Data: 0xFFFEFFFD_FFFCFFFB_FFFAFFFB_FFFAFFFA
```











#### 测试用例3：多SMC写入（SMC0~SMC2）
**参数设置**：
- SMC0~SMC2使能（stb_u_smc_strb=6'b000111）
- burst长度=2（stb_u_brst=1）
- 基地址=0x3000（stb_u_gr_base_addr=32'h00003000）
- UR起始地址=0x20（stb_u_ur_addr=11'h020）
- UR ID=2（stb_u_ur_id=2）
- 全字节有效（stb_u_byte_strb=4'h0）

**内存输出结果**：
- 由于多SMC使能，系统会应用地址交错机制，在基地址基础上按照INTLV_STEP=64字节的步长为每个SMC分配独立的地址空间
- 具体计算方法为：实际地址 = 基地址 + SMC索引 * INTLV_STEP
  - SMC0的地址 = 0x3000 + 0 * 64 = 0x3000
  - SMC1的地址 = 0x3000 + 1 * 64 = 0x3040
  - SMC2的地址 = 0x3000 + 2 * 64 = 0x3080
- 这种地址交错设计确保了多个SMC可以并行访问不同区域的内存，避免了地址冲突，提高了内存带宽利用率
- 每个SMC写入2个连续数据（burst长度=2）
- 导出到mem_case3.txt文件，包含前512个地址和0x30C0地址的内容

**示例输出**：
```
// 内存内容导出
// 导出时间: 345678
// 测试用例ID: 3

// 前512个地址内容...
Addr: 0x000001F0, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F4, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F8, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001FC, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01

// 测试用例中实际写入的地址:
Addr: 0x000030C0, Data: 0xFFFDFFFC_FFFBFFFA_FFF9FFFA_FFF9FFF8
```












#### 测试用例4：部分字节写入（低2字节）
**参数设置**：
- SMC3使能（stb_u_smc_strb=6'b001000）
- burst长度=1（stb_u_brst=0）
- 基地址=0x4000（stb_u_gr_base_addr=32'h00004000）
- UR起始地址=0x30（stb_u_ur_addr=11'h030）
- UR ID=3（stb_u_ur_id=3）
- 低2字节有效（stb_u_byte_strb=4'h2）

**内存输出结果**：
- 在地址0x4000处只写入低2字节数据（由byte_strb决定）
- 高14字节保持原有初始化值（DEADBEEF_00000000_12345678_ABCDEF01）
- 导出到mem_case4.txt文件，包含前512个地址和0x41C0地址的内容

**示例输出**：
```
// 内存内容导出
// 导出时间: 456789
// 测试用例ID: 4

// 前512个地址内容...
Addr: 0x000001F0, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F4, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001F8, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01
Addr: 0x000001FC, Data: 0xDEADBEEF_00000000_12345678_ABCDEF01

// 测试用例中实际写入的地址:
Addr: 0x000041C0, Data: 0xDEADBEEF_00000000_12345678_FFFFFEFD
```
### 五、最终内存输出

所有测试用例完成后，系统还会导出一个综合的mem.txt文件，包含所有测试用例写入的地址内容，便于整体分析和验证。这个文件汇总了所有测试用例的执行结果，提供了系统完整功能的验证依据。

### 六、UR随机数据验证

每个测试用例对应的UR随机数据也会导出到对应的ur_random_caseX.txt文件中，记录了生成这些数据时的LFSR状态和相关内存内容，用于验证数据的正确性。这些文件提供了数据生成过程的完整记录，确保系统数据处理的准确性和可追溯性。