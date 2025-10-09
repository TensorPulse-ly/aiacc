#!/bin/bash

#==============================================================================
# 脚本名称: run_coverage.sh
# 脚本功能: 运行FPtoINT模块仿真并生成覆盖率报告
#==============================================================================
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR
DPI_C_FILE=$PROJ_ROOT/csrc/fpto_int_dpi.c

# 编译输出目录
OUTPUT_DIR=$PROJ_ROOT/coverage_output
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

# DPI 共享库名称
DPI_SO_NAME=libfpto_int_softfloat.so

echo "====================================="
echo "FPtoINT模块覆盖率收集脚本"
echo "====================================="

# 检查DPI-C文件
if [ ! -f "$DPI_C_FILE" ]; then
    echo "警告: 找不到DPI-C文件 $DPI_C_FILE,将跳过DPI编译"
    USE_DPI=false
else
    USE_DPI=true
fi

# 步骤 1: 编译 DPI-C 文件
if [ "$USE_DPI" = true ]; then
    echo "步骤 1: 编译 DPI-C 共享库..."
    /home/zwz/Oliver/SMC/compile_softfloat_dpi.sh $DPI_C_FILE $DPI_SO_NAME

    if [ $? -ne 0 ]; then
        echo "错误: DPI-C 文件编译失败"
        exit 1
    fi

    echo "成功创建共享库: $PWD/$DPI_SO_NAME"
    echo ""
fi

# 获取 SoftFloat 包含路径
SOFTFLOAT_INCLUDE="/home/zwz/Oliver/SMC/berkeley-softfloat-3-master/source/include"

# 编译并运行单元测试覆盖率
echo "=========================================="
echo "运行 FPtoINT 单元测试覆盖率收集"
echo "=========================================="

echo "步骤 2: 编译带覆盖率的单元测试..."
VCS_CMD="vcs -sverilog +v2k -full64 +fsdb -timescale=1ns/1ps"
VCS_CMD="$VCS_CMD -debug_access+all -cm line+cond+fsm+branch+tgl"
VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/fpto_int.v"
VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/tb_fpto_int.v"
VCS_CMD="$VCS_CMD -CFLAGS \"-I$SOFTFLOAT_INCLUDE\""
VCS_CMD="$VCS_CMD -LDFLAGS \"-Wl,-rpath,$(pwd)\""
VCS_CMD="$VCS_CMD -LDFLAGS \"-L$(pwd)\""
VCS_CMD="$VCS_CMD -LDFLAGS \"-lfpto_int_softfloat\""
VCS_CMD="$VCS_CMD -o tb_fpto_int_cov"

echo "VCS 编译命令: $VCS_CMD"
eval $VCS_CMD

if [ $? -eq 0 ]; then
    echo "Verilog 编译成功"
else
    echo "错误: Verilog 编译失败"
    exit 1
fi

echo ""
echo "步骤 3: 运行单元测试覆盖率收集..."
./tb_fpto_int_cov -cm line+cond+fsm+branch+tgl

if [ $? -eq 0 ]; then
    echo "单元测试覆盖率收集完成"
else
    echo "错误: 单元测试仿真失败"
    exit 1
fi

# 编译并运行阵列测试覆盖率
echo ""
echo "=========================================="
echo "运行 FPtoINT 阵列测试覆盖率收集"
echo "=========================================="

echo "步骤 4: 编译带覆盖率的阵列测试..."
VCS_CMD="vcs -sverilog +v2k -full64 +fsdb -timescale=1ns/1ps"
VCS_CMD="$VCS_CMD -debug_access+all -cm line+cond+fsm+branch+tgl"
VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/fpto_int.v"
VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/fpto_int_array.v"
VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/tb_fpto_int_array.v"
VCS_CMD="$VCS_CMD -CFLAGS \"-I$SOFTFLOAT_INCLUDE\""
VCS_CMD="$VCS_CMD -LDFLAGS \"-Wl,-rpath,$(pwd)\""
VCS_CMD="$VCS_CMD -LDFLAGS \"-L$(pwd)\""
VCS_CMD="$VCS_CMD -LDFLAGS \"-lfpto_int_softfloat\""
VCS_CMD="$VCS_CMD -o tb_fpto_int_array_cov"

echo "VCS 编译命令: $VCS_CMD"
eval $VCS_CMD

if [ $? -eq 0 ]; then
    echo "Verilog 编译成功"
else
    echo "错误: Verilog 编译失败"
    exit 1
fi

echo ""
echo "步骤 5: 运行阵列测试覆盖率收集..."
./tb_fpto_int_array_cov -cm line+cond+fsm+branch+tgl

if [ $? -eq 0 ]; then
    echo "阵列测试覆盖率收集完成"
else
    echo "错误: 阵列测试仿真失败"
    exit 1
fi

# 生成覆盖率报告
echo ""
echo "=========================================="
echo "生成覆盖率报告"
echo "=========================================="

echo "步骤 6: 使用 urg 工具生成覆盖率报告..."
urg -dir tb_fpto_int_cov.vdb -dir tb_fpto_int_array_cov.vdb -report coverage_report

if [ $? -eq 0 ]; then
    echo "覆盖率报告生成成功"
    echo "报告位置: $OUTPUT_DIR/coverage_report"
    echo ""
    echo "可以使用浏览器查看报告:"
    echo "firefox $OUTPUT_DIR/coverage_report/dashboard.html &"
else
    echo "错误: 覆盖率报告生成失败"
    exit 1
fi

echo ""
echo "====================================="
echo "FPtoINT模块覆盖率收集完成"
echo "====================================="