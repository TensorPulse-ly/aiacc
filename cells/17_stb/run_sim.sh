#!/bin/bash

# SMC项目仿真脚本（无DPI/SoftFloat依赖）

# 路径变量
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR

# 设计和测试文件（直接在项目根目录）
TOP_FILE=$PROJ_ROOT/axi_top.v
BURST_STORE_FILE=$PROJ_ROOT/burst_store.v
UR_MODEL_FILE=$PROJ_ROOT/ur_model.v
AXI_STB_FILE=$PROJ_ROOT/axi_stb.v
AXI_STB_S_FILE=$PROJ_ROOT/axi_stb_s.v
MEM_MODEL_FILE=$PROJ_ROOT/axi_mem_model.v
PROTOCOL_CHECKER_FILE=$PROJ_ROOT/axi_protocol_checker.v
TB_FILE=$PROJ_ROOT/burst_store_tb.v

# 输出目录
OUTPUT_DIR=$PROJ_ROOT/sim_output

# 清理并创建输出目录
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 设置环境变量，避免DVE GUI相关问题
export DISPLAY=

echo "=========================================="
echo "          SMC项目仿真脚本启动"
echo "=========================================="

# 检查必要文件
for f in "$TOP_FILE" "$BURST_STORE_FILE" "$UR_MODEL_FILE" "$AXI_STB_FILE" "$AXI_STB_S_FILE" "$MEM_MODEL_FILE" "$PROTOCOL_CHECKER_FILE" "$TB_FILE"; do
    if [ ! -f "$f" ]; then
        echo "错误: 找不到文件 $f"
        exit 1
    fi
    echo "  ✓ 已找到文件: $f"
done

# 步骤 1: 编译 Verilog 文件
echo "
步骤 1: 编译Verilog文件..."

# 检查VCS编译器是否可用
if command -v vcs &> /dev/null; then
    echo "使用Synopsys VCS编译器"
    # 使用用户指定的VCS编译命令格式，添加调试选项
    vcs -sverilog +v2k -full64 -timescale=1ns/1ps \
        -debug_access+r \
        -cm line+cond+fsm+tgl \
        "$TOP_FILE" \
        "$BURST_STORE_FILE" \
        "$UR_MODEL_FILE" \
        "$AXI_STB_FILE" \
        "$AXI_STB_S_FILE" \
        "$MEM_MODEL_FILE" \
        "$PROTOCOL_CHECKER_FILE" \
        "$TB_FILE" \
        -o simv \
        -l $OUTPUT_DIR/compile.log
    
    COMPILE_RESULT=$?
    
    if [ $COMPILE_RESULT -ne 0 ]; then
        echo "VCS编译失败"; exit 1
    fi
else
    echo "错误: 未找到Synopsys VCS编译器，请先安装"
    exit 1
fi

# 确保日志文件存在
touch $OUTPUT_DIR/compile.log

# 编译成功
if [ $COMPILE_RESULT -eq 0 ]; then
    echo "编译成功完成"
fi

# 步骤 2: 运行仿真
echo "
步骤 2: 运行仿真..."

# 执行仿真命令，覆盖率选项与编译保持一致
./simv -cm line+cond+fsm+tgl -l sim.log

if [ $? -ne 0 ]; then
    echo "仿真失败"; exit 1
else
    echo "仿真完成"
    echo ""
fi

# 步骤 3: 检查波形文件
echo "
步骤 3: 检查波形文件..."
if [ -f "sim_output.vcd" ]; then
    VCD_SIZE=$(du -h sim_output.vcd | cut -f1)
    echo "VCD波形文件生成成功: sim_output.vcd (大小: $VCD_SIZE)"
else
    echo "警告: 未找到VCD波形文件"
fi

# 步骤 4: 检查AXI协议错误
echo "
步骤 4: 检查AXI协议错误..."
PROTOCOL_ERROR=$(grep -c "AXI Protocol Error" sim.log)
if [ $PROTOCOL_ERROR -ne 0 ]; then
    echo "警告: 仿真日志中发现$PROTOCOL_ERROR个AXI协议错误，请查看$OUTPUT_DIR/sim.log"
else
    echo "未发现AXI协议错误"
fi

# 步骤 5: 生成覆盖率报告
echo "
步骤 5: 生成覆盖率报告..."
if command -v vcs &> /dev/null && [ -d "simv.vdb" ]; then
    urg -dir simv.vdb -format both -report coverage_report
    if [ $? -ne 0 ]; then
        echo "警告: 覆盖率报告生成失败"
    else
        echo "覆盖率报告生成完成"
        echo "HTML报告: $OUTPUT_DIR/coverage_report/dashboard.html"
        echo "文本报告: $OUTPUT_DIR/coverage_report/dashboard.txt"
    fi
else
    echo "跳过覆盖率报告生成 (VCS未找到或覆盖率数据库不存在)"
fi

# 回到项目根目录
cd "$PROJ_ROOT"

echo "
=========================================="
echo "          仿真脚本执行完成"
echo "=========================================="
echo "所有仿真结果都在: $OUTPUT_DIR/"
echo ""
echo "主要文件列表:"
echo "  - 仿真可执行文件: $OUTPUT_DIR/simv"
echo "  - 编译日志: $OUTPUT_DIR/compile.log"
echo "  - 仿真日志: $OUTPUT_DIR/sim.log"
echo "  - 波形文件: $OUTPUT_DIR/sim_output.vcd (如果生成)"
echo "  - 覆盖率报告: $OUTPUT_DIR/coverage_report/ (如果生成)"
echo ""
exit 0