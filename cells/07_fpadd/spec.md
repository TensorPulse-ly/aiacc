
#  子字并行浮点加法器设计规范

> **版本**：v1.1  
> **作者**：cypher  
> **覆盖**：FP16×8 / FP32×4，IEEE-754，四级流水线，SoftFloat-DPI 验证  

---

## 补：1.1版本更新内容
本次更新主要是增加了以下几个方面：
- **新增输入值比较功能**能够比较输入的两个数的大小并将比较结果通过dr_fpadd_st输出  
- **整合1.0版本的微指令**通过cru_fpadd控制寄存器更新、运算精度等
- **优化显示**在测试平台优化比较以及输出结果的显示

---

## 1. 项目概述
本次 RTL 重构在 **功能不变** 的前提下，对 `fp16_adder.v`、`fp32_adder.v`、`subword_adder.v` 及顶层 `fpadd.v` 进行了以下关键更新：  
- **统一特殊值处理逻辑**（NaN/Inf/Zero/Denorm）  
- **修复非规格化数进位 bug**（denorm+denorm→norm）  
- **优化舍入逻辑**（sticky 位计算、carry_out 判断）  
- **增强覆盖率**（新增边界用例，ULP≤1）  
- **DPI-C 模型对齐**（`softfloat_dpi.c` 与 RTL 行为一致）

---

## 2. 特性总览
| 特性 | 说明 |
|------|------|
| **精度模式** | 1 位 `mode_flag`：0=FP16×8，1=FP32×4 |
| **接口宽度** | 128 bit 输入 / 128 bit 输出 |
| **延迟** | 固定 4 拍流水线（取指、译码、执行、回写） |
| **特殊值** | NaN、±Inf、±0、denorm 全支持 |
| **舍入模式** | 最近偶数（round-to-nearest-even） |
| **复位** | 异步低有效 `rst_n`，立即回到 `IDLE` |
| **验证** | SoftFloat DPI-C 黄金模型 |

---

## 3. 接口定义
```verilog
module fpadd #(
    parameter PARAM_DR_FPADD_CNT = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [127:0] dvr_fpadd_s0,
    input  wire [127:0] dvr_fpadd_s1,
    output reg  [127:0] dr_fpadd_d,
    output reg  [127:0] dr_fpadd_st,
    input  wire [3:0]   cru_fpadd   // {update, mode, mode, valid}
);
```

---

## 4. 状态机
| 状态   | 描述                     |
|--------|--------------------------|
| `IDLE` | 等待 `cru_fpadd[0]` 上升沿 |
| `PROC` | 锁存输入，启动子模块计算 |
| `WAIT` | 等待计算完成             |
| `DONE` | 输出结果，更新状态寄存器 |

---

## 5. 子模块变更摘要

### 5.1 `fp16_adder.v` 关键更新
| 变更点 | 旧行为 | 新行为 |
|--------|--------|--------|
| **非规格化进位** | denorm+denorm 可能错判为 denorm | 修正：和≥2048 时规格化，指数=1 |
| **舍入逻辑** | sticky 位计算错误 | 使用 `shift_amt` 精确定位 sticky |
| **NaN 传播** | 符号位未继承 | 采用最高优先级 NaN 的符号位 |
| **Zero 合并** | +0 + -0 可能输出 -0 | 严格遵循 IEEE：结果为 +0 |

### 5.2 `fp32_adder.v` 关键更新
| 变更点 | 旧行为 | 新行为 |
|--------|--------|--------|
| **非规格化进位** | 同 FP16 | 同 FP16 |
| **舍入逻辑** | 尾数 23 位边界处理错误 | 修正 carry_out 判断 |
| **NaN 传播** | 符号位未继承 | 同 FP16 |

### 5.3 `subword_adder.v`
- **无逻辑变更**，仅例化新版 `fp16_adder` / `fp32_adder`。

---

## 6. 特殊值处理速查
| 输入组合        | 结果      | 备注               |
|-----------------|-----------|--------------------|
| NaN + *         | NaN       | 最高优先级         |
| ±Inf + ∓Inf     | NaN       | IEEE 冲突          |
| ±Inf + *        | ±Inf      | 符号同 Inf         |
| ±0 + ∓0         | +0        | IEEE 规定          |
| denorm + denorm | 规格化    | 和≥2048(FP16)/≥2²⁴(FP32) |

---

## 7. 验证与交付
| 项            | 内容                              |
|---------------|-----------------------------------|
| **黄金模型**  | SoftFloat-DPI（`softfloat_dpi.c` 已同步） |
| **容差**      | ULP ≤ 1（新增 100+ 边界用例）     |
| **覆盖率**    | 行≥95%，分支≥90%，特殊值 100%     |
| **仿真脚本**  | `run_sim.sh`（VCS + Verdi）       |
| **日志**      | `fpadd_sim.log`（pass/fail 统计） |

---

## 8. 新增边界用例
| 用例 ID | 描述 | 输入（十六进制） | 预期结果 |
|---------|------|------------------|----------|
| BV-05   | FP16 denorm 进位 | 0x03FF + 0x03FF | 0x0400 |
| BV-06   | FP32 denorm 进位 | 0x007FFFFF + 0x007FFFFF | 0x00800000 |
| RD-04   | FP16 舍入边界 | 0x3BFF + 0x3C00 | 0x4000（carry_out=1） |
| RD-05   | FP32 舍入边界 | 0x437FFFFF + 0x3F800000 | 0x43800000 |

---

## 9. 快速上手
```bash
./run_sim.sh          # 一键编译 + 仿真 + 覆盖率
# 查看报告：
# coverage_report/urgReport/dashboard.html
```

---

## 附录：RTL 文件清单
| 文件 | 说明 |
|------|------|
| `fpadd.v` | 顶层模块 |
| `subword_adder.v` | 子字拆分器 |
| `fp16_adder.v` | 单通道 FP16 |
| `fp32_adder.v` | 单通道 FP32） |
| `softfloat_dpi.c` | DPI-C 黄金模型 |
| `tb_fp_adder.v` | 测试平台 |
