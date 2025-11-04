# inttofp 设计规范 (inttofp_spec.md)

> **版本**：v1.0  
> **作者**：cypher  
> **覆盖**：128-bit SIMD 整数转浮点转换单元，支持 32-bit×4 或 16-bit×8 通道，支持有符号/无符号输入，单周期执行  

---

## 1. 项目概述  
实现 **128-bit SIMD 整数转浮点转换单元**（inttofp），支持以下功能：
- **输入精度**：32-bit×4 通道 或 16-bit×8 通道
- **输出精度**：32-bit float×4 或 16-bit float×8
- **符号支持**：每通道可配置为有符号或无符号
- **高低位选择**：支持从 32-bit 输入中提取高/低 16-bit 进行转换
- **接口**：128-bit 输入、6-bit 控制信号、128-bit 输出，单周期延迟

---

## 2. 特性总览

| 特性           | 说明 |
|----------------|------|
| **输入精度**   | 1 位 `src_is_32b`：0=16-bit×8通道，1=32-bit×4通道 |
| **输出精度**   | 1 位 `dst_is_32b`：0=16-bit float×8通道，1=32-bit float×4通道 |
| **符号模式**   | 1 位 `src_signed`：0=无符号，1=有符号 |
| **高低位选择** | 1 位 `src_high` / `dst_high`：控制 32↔16 转换时选高/低 16-bit |
| **延迟**       | 单周期（非流水线） |
| **复位**       | 异步低有效 `rst_n` |

---

## 3. 接口定义

```verilog
module inttofp (
    input wire clk,
    input wire rst_n,
    input wire [127:0] dvr_inttofp_s,  // 128-bit 输入数据
    input wire [5:0]   cru_inttofp,    // 控制信号
    output reg [127:0] dr_inttofp_d    // 128-bit 输出结果
);
```

---

## 4. 控制信号说明

|位	|名称	|说明	|
|---|-----|-----|
|5	|valid	|使能信号，高有效	|
|4	|src_is_32b	|0=16-bit 输入，1=32-bit 输入	|
|3	|dst_is_32b	|0=16-bit 输出，1=32-bit 输出	|
|2	|src_signed	|0=无符号，1=有符号	|
|1	|src_high	|32→16 时选高 16-bit，16→32 时选高 16-bit	|
|0	|dst_high	|32→16 输出时选高 16-bit 输出	|

---

## 5. 操作模式

|模式	|描述	|示例	|
|---|-----|-----|
|32→32	|32-bit 有符号/无符号转 32-bit float	|`ctrl=6'b111100`	|
|16→16	|16-bit 有符号/无符号转 16-bit float	|`ctrl=6'b100100`	|
|16→32	|16-bit 有符号/无符号扩展为 32-bit 后转 32-bit float	|`ctrl=6'b101100`	|
|32→16	|32-bit 拆分为两个 16-bit 后分别转 16-bit float	|`ctrl=6'b110010`	|

---

## 6. 子模块说明

|模块	|功能	|
|-----|-----|
|int2fp32	|32-bit 整数 → 32-bit float	|
|int2fp16	|16-bit 整数 → 16-bit float	|

---

## 7. DPI-C 黄金模型

|功能	|接口	|
|-----|-----|
|32-bit 转 float	|`int32_to_fp32(val, is_signed)`	|
|16-bit 转 float	|`int16_to_fp16(val, is_signed)`	|
|float 转 real	|`fp32_to_real(val)` / `fp16_to_real(val)`	|

---

## 8. 验证与交付

|项	|内容	|
|----|----|
|黄金模型	|SoftFloat-DPI (`softfloat_dpi.c`)	|
|仿真脚本	|`run_sim.sh`（VCS + URG）	|
|覆盖率	|行≥95%，分支≥90%，功能点 100%	|
|测试用例	|零值、极值、符号边界、随机数据	|
|日志	|`sim.log`（pass/fail 统计）	|
|波形	|`tb_inttofp.vcd`	|

---

## 9. 快速上手

```bash
# 1. 获取所有文件
inttofp.v
int2fp32.v
int2fp16.v
tb_inttofp.v
softfloat_dpi.c
run_sim.sh

# 2. 一键运行
chmod +x run_sim.sh
./run_sim.sh
# 结果查看 sim_output/coverage_report/dashboard.html
```
