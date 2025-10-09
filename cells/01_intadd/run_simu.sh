#!/bin/bash

# INTADD 仿真脚本（仅DPI-C接口和Verilog仿真，无softfloat）

SCRIPT_DIR=$(cd $(dirname "$0") && pwd)
PROJ_ROOT=$SCRIPT_DIR

TB_FILE=$PROJ_ROOT/intadd_tb.v
DUT_FILE=$PROJ_ROOT/intadd.v
ADD8_FILE=$PROJ_ROOT/add8.v
ADD32_FILE=$PROJ_ROOT/add32.v
DPI_C_FILE=$PROJ_ROOT/intadd_interface.c

OUTPUT_DIR=$PROJ_ROOT/sim_output

# 清理并创建输出目录
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 清理旧文件
rm -f simv ucli.key result.txt *.daidir *.vdb

echo "=========================================="
echo "         INTADD 仿真脚本启动"
echo "=========================================="
echo "项目根目录: $PROJ_ROOT"
echo "输出目录: $OUTPUT_DIR"
echo

# 检查必要文件
if [ ! -f "$DUT_FILE" ]; then echo "错误: 找不到 $DUT_FILE"; exit 1; fi
if [ ! -f "$TB_FILE" ]; then echo "错误: 找不到 $TB_FILE"; exit 1; fi
if [ ! -f "$ADD8_FILE" ]; then echo "错误: 找不到 $ADD8_FILE"; exit 1; fi
if [ ! -f "$ADD32_FILE" ]; then echo "错误: 找不到 $ADD32_FILE"; exit 1; fi
if [ ! -f "$DPI_C_FILE" ]; then echo "错误: 找不到 $DPI_C_FILE"; exit 1; fi

# 编译并链接DPI-C接口和Verilog
echo "编译Verilog和C接口..."
vcs -sverilog +v2k -full64 -timescale=1ns/1ps \
    -cm line+cond+fsm+tgl \
    "$DUT_FILE" \
    "$TB_FILE" \
    "$ADD8_FILE" \
    "$ADD32_FILE" \
    -cc gcc -CFLAGS "-fPIC" "$DPI_C_FILE" -o simv

if [ $? -ne 0 ]; then
    echo "VCS编译失败"; exit 1
fi

# 运行仿真
echo "运行仿真..."
./simv -cm line+cond+fsm+tgl
if [ $? -ne 0 ]; then
    echo "仿真失败"; exit 1
fi

echo "仿真完成，结果已写入 result.txt"
echo ""

# 生成覆盖率报告
echo "生成 Verilog 覆盖率报告..."
vcover report simv.vdb -details -html -output coverage_html
vcover report simv.vdb -details > coverage.txt

echo "覆盖率 HTML 报告目录: $OUTPUT_DIR/coverage_html"
echo "覆盖率文本报告: $OUTPUT_DIR/coverage.txt"
echo "=========================================="
echo "         仿真脚本执行完成"
echo "=========================================="
echo "所有仿真结果都在: $OUTPUT_DIR/"
echo ""
# 步骤 4: 生成和查看覆盖率报告
echo "步骤 4: 生成覆盖率报告..."

if [ -d "simv.vdb" ]; then
    urg -dir simv.vdb -format both -report coverage_report
    if [ $? -ne 0 ]; then
        echo "警告: 覆盖率报告生成失败"
    else
        echo "覆盖率报告生成完成"
        echo "报告位置: $OUTPUT_DIR/coverage_report/"
        echo "HTML报告: $OUTPUT_DIR/coverage_report/dashboard.html"
        echo "文本报告: $OUTPUT_DIR/coverage_report/dashboard.txt"
    fi
else
    echo "警告: 找不到覆盖率数据库 simv.vdb"
fi