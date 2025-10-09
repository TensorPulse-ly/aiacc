#!/bin/bash
# *************************************************************
#  run_sim.sh  —— 在原先基础上把新增模块加进来
#  DPI-C、覆盖率、urg 等功能全部保留
# *************************************************************

# 路径变量
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR

# 所有 RTL / TB 文件（仅此处改动）
TB_FILE="$PROJ_ROOT/tb_ldb.v"
DUT_FILE="$PROJ_ROOT/ldb.v"
DPI_C_FILE="$PROJ_ROOT/softfloat_dpi.c"

# 新增互联及 RAM
EXTRA_FILES="$PROJ_ROOT/axi_top.v $PROJ_ROOT/ur_ram.v $PROJ_ROOT/axi_read_mem_slave.v $PROJ_ROOT/ldb_axi_read_master.v $PROJ_ROOT/axi_protocol_checker.v"

# 输出目录
OUTPUT_DIR="$PROJ_ROOT/sim_output"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# DPI 共享库名称
DPI_SO_NAME=libruntime.so
rm -f "$DPI_SO_NAME"
rm -rf *.daidir *.vdb .vcs.timestamp

# -------------------- 步骤 1：编译 DPI-C --------------------
echo "使用一体化脚本编译 DPI-C 文件..."
/home/zwz/FPADD/test/compile_softfloat_dpi.sh "$DPI_C_FILE" "$DPI_SO_NAME"
if [ $? -ne 0 ]; then
    echo "错误: DPI-C 文件编译失败"
    exit 1
fi
echo "成功创建共享库: $PWD/$DPI_SO_NAME"

# SoftFloat 头文件路径
SOFTFLOAT_INCLUDE="/home/zwz/FPADD/test/berkeley-softfloat-3-master/source/include"

# -------------------- 步骤 2：编译 & 仿真 --------------------
echo "正在使用 Synopsys VCS 编译和仿真..."
vcs -sverilog +v2k -full64 +fsdb -timescale=1ns/1ps \
    -cm line+cond+fsm+branch+tgl \
    $DUT_FILE $TB_FILE $EXTRA_FILES \
    -CFLAGS "-I$SOFTFLOAT_INCLUDE" \
    -LDFLAGS "-Wl,-rpath,$(pwd)" \
    -LDFLAGS "-L$(pwd)" \
    -LDFLAGS "-lruntime" \
    -o simv

if [ $? -ne 0 ]; then
    echo "VCS Verilog 编译失败。"
    exit 1
fi

echo "正在运行仿真..."
./simv -l sim.log -cm line+cond+fsm+branch+tgl
if [ $? -ne 0 ]; then
    echo "VCS 仿真失败。查看 $OUTPUT_DIR/sim.log 获取详情。"
    exit 1
else
    echo "VCS 仿真完成。日志文件: $OUTPUT_DIR/sim.log"
fi

# -------------------- 步骤 3：覆盖率报告 --------------------
echo "正在生成覆盖率报告..."
urg -dir simv.vdb -format both -report coverage_report
if [ $? -ne 0 ]; then
    echo "覆盖率报告生成失败。"
else
    echo "覆盖率报告生成完成。报告位置: $OUTPUT_DIR/coverage_report/"
    echo "HTML报告: $OUTPUT_DIR/coverage_report/urgReport/dashboard.html"
    echo "文本报告: $OUTPUT_DIR/coverage_report/urgReport/summary.txt"
    if [ -f "coverage_report/urgReport/summary.txt" ]; then
        echo "覆盖率摘要:"
        cat coverage_report/urgReport/summary.txt
    fi
fi

# 回到项目根目录
cd "$PROJ_ROOT"
echo "脚本执行完毕。所有仿真结果都在: $OUTPUT_DIR/"
