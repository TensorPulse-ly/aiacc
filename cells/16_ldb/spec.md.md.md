# LDB (Burst Load Unit) 设计规范 (ldb_spec.md)

> **版本**：v1.3  
> **覆盖**：基于 AXI4 协议的突发读传输控制器，目前支持单个smc(smc0)的使用   
> **作者**：cypher、hamid
---

## 1. 项目概述
实现 **AXI4 Burst Load 控制器**，负责：
-   **指令解析**：解析来自 CRU 的微指令包。
-   **AXI 主控**：发起并管理 AXI4 读突发传输事务。
-   **数据处理**：处理接收到的数据，应用字节使能掩码。
-   **UR 写入**：将处理后的数据写入目标用户寄存器 (UR)。
-   **状态管理**：通过状态机控制整个加载流程，并返回完成状态。

---

## 2. 特性总览
| 特性 | 说明 |
| :--- | :--- |
| **协议支持** | AXI4 (AXI4-Lite 子集，用于读通道) |
| **数据位宽** | 128-bit AXI 数据总线，16-byte 突发传输 |
| **地址位宽** | 64-bit AXI 地址，参数化配置 |
| **突发长度** | 支持 1 至 255 拍的突发传输 (`brst[15:0]`) |
| **字节使能** | 支持 16 种字节使能模式，用于最后一拍数据的部分写入 |
| **SMC 支持** | 参数化支持多 SMC (当前实现固定为 SMC0) |
| **超时处理** | AXI 通道握手超时检测与错误上报 |
| **延迟** | 多周期（可变，取决于突发长度和 AXI 交互） |

---

## 3. 接口定义

### 3.1 顶层接口 (axi_top.v)
```verilog
module axi_top #(
    parameter AXI_ADDR_W = 64,
    parameter AXI_DATA_W = 128,
    parameter AXI_ID_W   = 4,
    parameter MEM_DEPTH  = 1024,
    parameter UR_BYTE_CNT = 16,
    parameter GR_INTLV = 64
)(
    input wire clk,
    input wire rst_n,
    // LDB 指令接口
    input wire [127:0] cru_ldb_i,
    input wire [1:0]   crd_ldb_i,
    output wire [127:0] cru_ldb_o,
    output wire [1:0]   crd_ldb_o,
    // UR 接口
    output wire ur_we,
    output wire [10:0] ur_addr,
    output wire [127:0] ur_wdata
);
```

### 3.2 LDB 核心接口 (ldb.v)
```verilog
module ldb #(
    parameter param_ur_byte_cnt = 16,
    parameter param_gr_intlv_addr = 64,
    parameter param_smc_cnt = 1,
    parameter ur_addr_w = 11,
    parameter gr_addr_w = 64,
    parameter brst_w = 16
)(
    input wire clk,
    input wire rst_n,
    // 指令输入接口
    input wire [127:0] cru_ldb_i,
    input wire [1:0] crd_ldb_i,
    // AXI读取控制接口
    output reg axi_req_valid,
    input wire axi_req_ready,
    output reg [gr_addr_w-1:0] axi_req_addr,
    output reg [8:0] axi_req_len,
    input wire axi_req_done,
    input wire axi_req_err,
    // AXI数据输入接口
    input wire axi_data_valid,
    input wire [127:0] axi_data,
    input wire axi_data_last,
    // UR接口
    output reg ur_we,
    output reg [ur_addr_w-1:0] ur_addr,
    output reg [param_ur_byte_cnt*8-1:0] ur_wdata,
    // 响应输出接口
    output wire [127:0] cru_ldb_o,
    output reg [1:0] crd_ldb_o
);
```
**注**：`param_gr_intlv_addr` 在多 SMC 模式下用于计算每个 SMC 的全局地址偏移，当前单 SMC 实现中未使用。`cru_ldb_o` 是直通输出，`crd_ldb_o` 输出 `{vld, done}`。

---

## 4. 微指令格式 (`cru_ldb_i[127:0]`)
| 字段名 | 位域 | 描述 | 示例/备注 |
| :--- | :--- | :--- | :--- |
| **valid** | `[127]` | 指令有效位 | `1'b1`：有效 |
| **smc_strb** | `[126:121]` | SMC 使能选择 | `6'b000001`：使能 SMC0 |
| **byte_strb** | `[120:117]` | 字节使能编码 | `4'h0`：全使能，`4'h1`：仅最低字节... |
| **brst** | `[116:101]` | 突发长度 | 自然编码，`16'd2` 表示 2 拍数据传输 |
| **gr_base_addr** | `[100:37]` | 全局内存起始地址 | 64 位字节地址，在 LDB 中对齐到 16 字节边界 |
| **ur_id** | `[36:29]` | 目标 UR ID | 当前实现未使用 |
| **ur_addr** | `[28:18]` | 目标 UR 起始地址 | 11 位 UR 地址（字节寻址，但按 16 字节递增） |
| **reserved** | `[17:0]` | 保留位 | 必须为 0 |

---

## 5. 功能细节

### 5.1 状态机 (state_t)
状态机控制整个加载流程，状态定义如下：
-   **IDLE**: 空闲状态，等待有效指令。
-   **PARSE**: 解析指令，准备 AXI 请求。
-   **WAIT_AXI**: 等待 AXI 主设备握手并接受请求。
-   **DATA**: 接收并处理 AXI 数据，写入 UR。
-   **DONE**: 事务完成，输出响应信号。 

### 5.2 字节使能掩码 (`get_byte_mask`)
根据 `byte_strb` 的值生成 16 位的字节掩码，用于最后一个 AXI beat 的数据写入控制。
```systemverilog
function [15:0] get_byte_mask(input [3:0] byte_strb);
    case (byte_strb)
        4'h0: get_byte_mask = 16'hFFFF; // All bytes
        4'h1: get_byte_mask = 16'h0001; // Byte 0 only
        ... // Patterns for 4'h2 to 4'hE
        4'hF: get_byte_mask = 16'h7FFF; // Bytes [14:0]
        default: get_byte_mask = 16'hFFFF;
    endcase
endfunction
```
**注**：非最后一个 beat 总是全字节写入 (`16'hFFFF`)。

### 5.3 AXI 交互
-   **请求**：在 `PARSE` 状态准备 `axi_req_addr` (对齐到 16B)、`axi_req_len` (`brst - 1`)、并拉高 `axi_req_valid`。
-   **传输**：在 `DATA` 状态，每接收到一拍有效数据 (`axi_data_valid`)，则递增 UR 地址，并递减剩余 beat 计数。根据是否为最后一拍应用字节掩码。
-   **完成**：当 `axi_req_done` 拉高（或自身计数结束）且最后一拍数据写入后，转入 `DONE` 状态。

---

## 6. 验证与交付
| 项 | 内容 |
| :--- | :--- |
| **核心实现** | `ldb.v`, `axi_top.v` |
| **辅助模型** | `ldb_axi_read_master.v`, `axi_read_mem_slave.v`, `axi_protocol_checker.v`, `ur_ram.v` |
| **测试平台** | `tb_ldb.v` |
| **仿真脚本** | `run_sim.sh` (VCS) |
| **关键检查** | AXI 协议符合性、字节使能正确性、地址递增、状态转换 |
| **覆盖率** | 状态机、分支、条件、翻转 |
| **波形** | `wave.vcd` |

---

## 7. 快速上手
```bash
# 项目文件
axi_top.v
ldb.v
ldb_axi_read_master.v
axi_read_mem_slave.v
axi_protocol_checker.v
ur_ram.v
tb_ldb.v
run_sim.sh

# 运行仿真 (使用提供的 run_sim.sh)
./run_sim.sh
# 查看输出: sim_output/sim.log
# 查看波形: sim_output/wave.vcd
# 查看覆盖率: sim_output/coverage_report/
```

