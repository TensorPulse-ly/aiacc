# FPMUL 浮点乘法器技术规格与设计文档

## 1. 概述
本模块 `fpmul` 是一个支持 **FP16 / FP32 混合精度** 的并行向量浮点乘法单元。顶层一次可并行处理：
- FP32 精度：4 路 (4 lanes) 32-bit 浮点乘法；
- FP16 精度：8 路 (每个 32-bit lane 拆分为两个 16-bit 子操作) 半精度乘法。

支持 IEEE 754-2008 基本规则：规格化数、非规格化数、零、无穷大、NaN，采用 **Round to Nearest, Ties to Even (RNE)** 舍入。实现渐进下溢 (gradual underflow)。


### 1.1 设计目标
- IEEE 754 兼容（binary16 / binary32）
- 向量化并行吞吐（最多 8×FP16 或 4×FP32 / cycle）
- 精确的 G/R/S 舍入链路；支持非规格化输入输出
- 结构简洁，便于综合与后续 pipeline 化扩展

### 1.2 实现状态
- 结构：组合运算 + 1 级结果寄存 (inst_valid 掩码)；无深度流水
- 舍入：已实现 RNE；暂未实现其它模式 (RZ/RU/RD/RNA) —— 可扩展
- 异常标志：内部行为正确（NaN/Inf/Zero/Denorm）
- 参考模型：SoftFloat (DPI-C) 用于比对验证

## 2. 接口规格

### 2.1 顶层端口
```verilog
module fpmul (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] dvr_fpmul_s0,   // 源操作数向量 0 (4×32b 打包)
    input  wire [127:0] dvr_fpmul_s1,   // 源操作数向量 1 (4×32b 打包)
    input  wire [2:0]   cru_fpmul,      // 控制域: {inst_valid, src_precision_is_32b, dst_precision_is_32b}
    output reg  [127:0] dr_fpmul_d      // 结果向量 (与 lane 对齐)
);
```

### 2.2 控制信号编码
| 位 | 名称 | 描述 |
|----|------|------|
| cru_fpmul[2] | inst_valid | 指令有效，高时本周期结果更新 |
| cru_fpmul[1] | src_precision_is_32b | 1=输入按 FP32 解释，每 lane 执行 1 个 FP32 乘；0=输入按 FP16 成对解释，每 lane 执行 2 个 FP16 乘 |
| cru_fpmul[0] | dst_precision_is_32b | 结果打包格式选择：1=按 4×FP32 输出；0=按 8×FP16 输出（当前实现：与 src_precision 一致使用；混合转换待扩展） |

> 说明：当前 RTL 中 `dst_precision_is_32b` 仅用于接口占位，输出与 `src_precision_is_32b` 同步。若未来支持“FP16 输入升 FP32 输出”或“FP32 截断 FP16 输出”，需在尾数/指数路径增加扩展或舍入压缩逻辑。

### 2.3 向量打包与 Lane 映射
| Lane | dvr_fpmul_s0 位段 | dvr_fpmul_s1 位段 | FP32 模式 | FP16 模式 |
|------|------------------|------------------|-----------|-----------|
| 0 | [31:0]   | [31:0]   | 1×FP32 | 低 16 + 高 16 = 2×FP16 |
| 1 | [63:32]  | [63:32]  | 1×FP32 | 2×FP16 |
| 2 | [95:64]  | [95:64]  | 1×FP32 | 2×FP16 |
| 3 | [127:96] | [127:96] | 1×FP32 | 2×FP16 |

FP16 模式下：每个 32-bit lane 拆分为 `{高半字, 低半字}` 两个 binary16，结果 lane 内重新组合为 `{高结果16, 低结果16}`。

### 2.4 数据格式
- FP16: 1(sign) + 5(exp,bias=15) + 10(mant)
- FP32: 1(sign) + 8(exp,bias=127) + 23(mant)

## 3. 功能与算法流程

### 3.1 运算步骤（单个标量乘法）
1. 解析字段：Sign / Exponent / Mantissa
2. 特殊值分类：Zero / Inf / NaN / Denorm
3. 构造隐藏位 (normal→1, denorm→0)
4. 尾数相乘：FP16→11×11=22b；FP32→24×24=48b
5. 规格化：检测最高位；非规格化输入路径左移对齐
6. 提取基础尾数 + 生成 G/R/S 位
7. 舍入 (RNE)：判断 round 条件，尾数 +1 可能产生进位
8. 指数调整：加减偏置，补偿规格化/进位/非规格化移位
9. 下溢路径：根据 exp_pre_round 计算右移（渐进下溢）
10. 结果组装：异常/特殊值优先级 → {sign, exp, mant}

### 3.2 特殊值优先级 (从高到低)
NaN > 无效组合(Inf×0) > Inf > Zero > 正常/非规格化结果

### 3.3 非规格化与渐进下溢
- 对 exp_pre_round <= 0 范围内（且未完全下溢到 0）构造 extended_mantissa 右移
- 重新计算 denorm G/R/S 并再次 RNE 舍入
- 舍入后仍可产生“转为规格化”场景（FP16 中使用 denormal_overflow 分支覆盖）

### 3.4 舍入逻辑 (RNE)
should_round = Guard & (Round | Sticky | (LSB==1 且 Round=0 且 Sticky=0))
- 中点 (仅 G=1 且 R=0 且 S=0) → 依据 LSB 偶数保持/奇数进位
- 进位溢出 → 指数再 +1，尾数清零


## 54. 验证概述
更完整细节见 `testplane.md`。

### 4.1 覆盖目标
- 功能 ≥95% ；代码 ≥95%
- 特殊值 & 边界 100%

### 4.2 主要测试类别
- 规格×非规格 / 非规格×非规格 / 边界指数 / 尾数极值
- 特殊值：Zero / Inf / NaN (QNaN/SNaN) / Denorm 渐进下溢
- 舍入场景：中点、进位、溢出、二次 denorm 舍入
- 随机对比：SoftFloat 位级比对 1e4+ 用例

### 4.3 参考模型
- `csrc/softfloat_dpi.c` 调用 Berkeley SoftFloat (DPI-C)
- 每 lane 独立比对；聚合统计差异

## 5. 目录结构
```
06_fpmul/
  README.md              # 本文档
  vsrc/
    fpmul.v              # 顶层 + fp16/fp32 multiplier + LZC 模块
    tb_fpmul.v           # （测试平台顶层）
  csrc/
    softfloat_dpi.c      # 参考模型接口
  testplane.md           # 详细测试计划
  run_sim.sh             # 仿真脚本 (调用 VCS / 其它仿真器)
```



