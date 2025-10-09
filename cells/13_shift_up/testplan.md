#

## Shift Up 模块测试计划

>版本：V1.0  
>作者：Oliver

### 1. 测试概述

#### 1.1 测试目标

- 验证级联移位寄存器的指令传递逻辑
- 测试广播模式和非广播模式的数据分发机制
- 验证复位和无效指令处理功能

#### 1.2 测试覆盖率目标

- **功能覆盖率**：100%
- **代码覆盖率**：100%
- **特殊值覆盖率**：100%

---

### 2. 测试分类与用例

#### 2.1 复位功能测试(reset)

- 验证复位状态下所有输出为零
- 验证复位释放后保持稳定

#### 2.2 指令传递测试(instruction_pass)

- **SMC ID匹配**：验证正确更新数据和指令
- **SMC ID较大**：验证仅更新指令寄存器
- **SMC ID较小**：验证不更新任何寄存器

#### 2.3 广播模式测试(broadcast)

- **广播+SMC匹配**：验证更新数据和指令
- **广播+SMC不匹配**：验证更新数据（广播）和指令
- **非广播+SMC不匹配**：验证不更新数据

#### 2.4 SMC_ID不匹配测试(smc_mismatch)

- 先发送一条无效指令清除状态
- **SMC ID较大**：验证仅更新指令寄存器
- **SMC ID较小**：验证不更新任何寄存器

#### 2.5 多周期连续测试(multi_cycle)

- 验证连续指令序列处理
- 验证状态机在序列中的正确转换

#### 2.6 无效指令测试(invalid_instruction)

- 验证无效指令（`vld_in=0`）不更新寄存器
- 验证无效指令后保持先前状态

|用例ID|描述|测试输入(cru_in)|预期输出(cru_out)|预期输出(dr_out)|
|------|----|---------------|-----------------|---------------|
|RS-01|复位|X|135'd0|128'd0|
|IP-01|TEST_ID = SMC_ID|{1,data_1,TEST_ID,0}|{1,data_1,TEST_ID,0}|data_1(应更新)|
|IP-02|TEST_ID > SMC_ID|{1,data_2,TEST_ID+1,0}|{1,data_2,TEST_ID+1,0}|data_1(不应更新)|
|IP-03|TEST_ID < SMC_ID|{1,data_3,TEST_ID-1,0}|{1,data_2,TEST_ID+1,0}(保持前值)|data_1(保持前值)|
|BR-01|广播有效 + SMC_ID匹配|{1,data_4,TEST_ID,1}|{1,data_4,TEST_ID,1}|data_4(应更新)|
|BR-02|广播有效 + SMC_ID不匹配|{1,data_5,TEST_ID+5,1}|{1,data_5,TEST_ID+5,1}|data_5(应更新)|
|BR-03|广播无效 + SMC_ID不匹配|{1,data_6,TEST_ID+3,0}|{1,data_6,TEST_ID+3,0}|data_5(保持前值)|
|SM-00|无效指令清除状态|{1,128'd0,0,0}|X|X|
|SM-01|初始状态|{1,data_1,TEST_ID,0}|{1,data_1,TEST_ID,0}|data_1|
|SM-02|不匹配指令1|{1,data_2,TEST_ID+10,0}|{1,data_2,TEST_ID+10,0}|data_1(不应更新)|
|SM-03|不匹配指令2|{1,data_3,TEST_ID-1,0}|{1,data_2,TEST_ID+10,0}(保持前值)|data_1(保持前值)|
|MC-01|匹配+广播|{1,data_7,TEST_ID,1}|{1,data_1,TEST_ID,1}|data_7(应更新)|
|MC-02|匹配+非广播|{1,data_8,TEST_ID,0}|{1,data_8,TEST_ID,0}|data_8(应更新)|
|MC-03|不匹配+广播|{1,data_9,TEST_ID+8,1}|{1,data_9,TEST_ID+8,1}|data_9(应更新)|
|MC-04|不匹配+非广播|{1,data_A,TEST_ID+3,0}|{1,data_A,TEST_ID+3,0}|data_9(保持前值)|
|II-01|初始状态|{1,data_B,TEST_ID,0}|{1,data_B,TEST_ID,0}|data_B|
|II-02|无效指令1|{0,data_C,TEST_ID,0}|{1,data_B,TEST_ID,0}(保持前值)|data_B(保持前值)|
|II-03|无效指令2|{0,data_D,TEST_ID+5,1}|{1,data_B,TEST_ID,0}(保持前值)|data_B(保持前值)|

>parameter TEST_SMC_ID = 2; // 表中简写为TEST_ID  
>表中data_X统一为128位的数据

---

### 3. 测试环境与工具

- 仿真器：VCS
- 语言：Verilog
- 覆盖率：代码覆盖率 + 功能覆盖率

---

### 4. 验收标准

- [ ] 代码覆盖率 ≥95%
- [ ] 功能覆盖率 ≥95%
- [ ] 所有控制路径验证通过
- [ ] 特殊值处理符合规范
- [ ] 无任何已知功能缺陷

---

**测试计划版本**：V1.0  
**创建日期**：2025年8月12日  
**最后更新**：2025年8月12日  
**责任人**：XXX  
**预计完成**：2025年8月25日

> 附件:
>
> 1. [代码shift_up.v](./vsrc/shift_up.v)  
> 2. [测试平台tb_shift_up.v](./vsrc/tb_shift_up.v)
