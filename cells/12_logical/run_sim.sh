#!/bin/bash

# 脚本路径变量
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR
TB_FILE="$PROJ_ROOT/tb_logical.v"
DUT_FILE="$PROJ_ROOT/logical.v"
DPI_C_FILE="$PROJ_ROOT/softfloat_dpi.c"

# 编译输出目录
OUTPUT_DIR="$PROJ_ROOT/sim_output"

# 清理并创建输出目录
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# DPI 共享库名称
DPI_SO_NAME=libruntime.so

# 清理旧的输出文件
rm -f "$DPI_SO_NAME"
# 清理 VCS 编译缓存
rm -rf *.daidir
rm -rf *.vdb
rm -f .vcs.timestamp

# 步骤 1: 使用一体化脚本编译 DPI-C 文件
echo "使用一体化脚本编译 DPI-C 文件..."
/home/zwz/FPADD/test/compile_softfloat_dpi.sh "$DPI_C_FILE" "$DPI_SO_NAME"

if [ $? -ne 0 ]; then
    echo "错误: DPI-C 文件编译失败"
    exit 1
fi

echo "成功创建共享库: $PWD/$DPI_SO_NAME"

# 获取 SoftFloat 包含路径
SOFTFLOAT_INCLUDE="/home/zwz/FPADD/test/berkeley-softfloat-3-master/source/include"

# 步骤 2: 编译 Verilog 文件并运行仿真 
echo "正在使用 Synopsys VCS 编译和仿真 Verilog 文件..."
vcs -sverilog +v2k -full64 +fsdb -timescale=1ns/1ps \
    -cm line+cond+fsm+branch+tgl \
    "$DUT_FILE" \
    "$TB_FILE" \
    -CFLAGS "-I$SOFTFLOAT_INCLUDE" \
    -LDFLAGS "-Wl,-rpath,$(pwd)" \
    -LDFLAGS "-L$(pwd)" \
    -LDFLAGS "-lruntime" \
    -o simv

if [ $? -ne 0 ]; then
    echo "VCS Verilog 编译失败。"
    exit 1
fi

# 运行仿真
echo "正在运行仿真..."
./simv -l sim.log -cm line+cond+fsm+branch+tgl

if [ $? -ne 0 ]; then
    echo "VCS 仿真失败。查看 $OUTPUT_DIR/sim.log 获取详情。"
    exit 1
else
    echo "VCS 仿真完成。日志文件: $OUTPUT_DIR/sim.log"
fi

# 步骤 3: 生成和查看覆盖率报告
echo "正在生成覆盖率报告..."
# 生成HTML格式的覆盖率报告
urg -dir simv.vdb -format both -report coverage_report
if [ $? -ne 0 ]; then
    echo "覆盖率报告生成失败。"
else
    echo "覆盖率报告生成完成。报告位置: $OUTPUT_DIR/coverage_report/"
    echo "HTML报告: $OUTPUT_DIR/coverage_report/urgReport/dashboard.html"
    echo "文本报告: $OUTPUT_DIR/coverage_report/urgReport/summary.txt"
    
    # 打印文本格式的覆盖率摘要
    if [ -f "coverage_report/urgReport/summary.txt" ]; then
        echo "覆盖率摘要:"
        cat coverage_report/urgReport/summary.txt
    fi
fi

# 回到项目根目录
cd "$PROJ_ROOT"

echo "脚本执行完毕。"
echo "所有仿真结果都在: $OUTPUT_DIR/"
