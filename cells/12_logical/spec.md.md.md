# Logical/Shift Unit 设计规范 (logical_spec.md)

> **版本**：v1.1  
> **作者**：cypher 
> **覆盖**：128-bit SIMD 逻辑/移位/选择操作，支持32-bit×4通道或16-bit×8通道，单周期执行  

---

## 1. 项目概述
实现 **128-bit SIMD 多功能逻辑/移位单元**，支持：
- **逻辑操作**：AND / OR / XOR / NOT / COPY  
- **选择操作**：GT / EQ / LS（基于浮点比较结果）  
- **移位操作**：逻辑/算术/循环移位，可配置方向（左/右）与精度（32/16-bit）  
- **接口**：128-bit 输入×2，128-bit 输出，单周期延迟

---

## 2. 特性总览
| 特性           | 说明 |
|----------------|------|
| **精度模式**   | 1 位 `logical_precision_i`：0=16-bit×8通道，1=32-bit×4通道 |
| **操作码**     | 4 位 `logical_op_i`，支持 16 种操作 |
| **移位方向与量** | 由 `src1` 每通道独立提供移位量 |
| **延迟**       | 单周期（非流水线） |
| **比较来源**   | 128-bit `dvr_logic_st`，每通道3位 `{GT,EQ,LS}` |
| **复位**       | 异步低有效 `rst_n` |

---

## 3. 接口定义
```verilog
module logical_unit (
    input wire clk,
    input wire rst_n,
    input wire [5:0] cru_logic,        // {valid, op[3:0], precision}
    input wire [127:0] dvr_logic_s0,   // 源操作数 A
    input wire [127:0] dvr_logic_s1,   // 源操作数 B / 移位量
    input wire [127:0] dvr_logic_st,   // 每通道3位比较状态
    output reg [127:0] dr_logic_d      // 结果
);
```

---

## 4. 操作码表
| 操作码 | 名称                | 描述                             |
|--------|---------------------|----------------------------------|
| 0000   | op_and              | 按位与                           |
| 0001   | op_or               | 按位或                           |
| 0010   | op_xor              | 按位异或                         |
| 0011   | op_not              | 按位取反                         |
| 0100   | op_copy             | 复制 src0                        |
| 0101   | op_select_great     | 若 GT=1 选 src0，否则选 src1     |
| 0110   | op_select_equal     | 若 EQ=1 选 src0，否则选 src1     |
| 0111   | op_select_less      | 若 LS=1 选 src0，否则选 src1     |
| 1000   | op_logic_left_shift | 逻辑左移                         |
| 1001   | op_arith_left_shift | 算术左移                         |
| 1010   | op_rotate_left_shift| 循环左移                         |
| 1011   | op_logic_right_shift| 逻辑右移                         |
| 1100   | op_arith_right_shift| 算术右移                         |
| 1101   | op_rotate_right_shift| 循环右移                        |
| 1110   | op_get_first_one    | 获取最低置1位索引                |
| 1111   | op_get_first_zero   | 获取最低置0位索引                |

---

## 5. 移位操作细节
- **32-bit 模式**：每通道独立移位，移位量取自 `src1[4:0]`
- **16-bit 模式**：每通道独立移位，移位量取自 `src1[3:0]`
- **循环移位**：自动取模处理（32-bit模32，16-bit模16）
- **算术右移**：符号位扩展，支持有符号数

---

## 6. DPI-C 黄金模型
| 功能                | 接口 |
|---------------------|------|
| **舍入模式设置**    | `set_softfloat_rounding_mode(0)` |
| **清除异常标志**    | `clear_softfloat_flags()` |
| **获取异常标志**    | `get_softfloat_flags()` |
| **32-bit 比较**     | `fp32_compare_softfloat(a, b)` → {0=EQ,1=LS,2=GT} |
| **16-bit 比较**     | `fp16_compare_softfloat(a, b)` → {0=EQ,1=LS,2=GT} |

---

## 7. 验证与交付
| 项            | 内容 |
|---------------|------|
| **黄金模型**  | SoftFloat-DPI (`softfloat_dpi.c`) |
| **仿真脚本**  | `run_sim.sh`（VCS + Verdi + Urg） |
| **覆盖率**    | 行≥95%，分支≥90%，功能点 100% |
| **测试用例**  | 逻辑、移位、选择、边界、符号扩展、全0/全1输入 |
| **日志**      | `sim.log`（pass/fail 统计） |
| **波形**      | `tb_logical_unit.vcd` |

---

## 8. 快速上手
```bash
# 1. 获取所有文件
logical.v
tb_logical.v
softfloat_dpi.c
run_sim.sh

# 2. 一键运行
chmod +x run_sim.sh
./run_sim.sh
# 结果查看 sim_output/coverage_report/dashboard.html
```

---

