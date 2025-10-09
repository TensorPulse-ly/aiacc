#!/bin/bash

#==============================================================================
# 脚本名称: run_sim.sh
# 脚本功能: 编译和运行FPtoINT模块仿真
# 使用方法: ./run_sim.sh [单元测试|阵列测试|全部测试]
#==============================================================================
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR
DPI_C_FILE=$PROJ_ROOT/csrc/fpto_int_dpi.c

# 编译输出目录
OUTPUT_DIR=$PROJ_ROOT/sim_output

# 清理并创建输出目录
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

# DPI 共享库名称
DPI_SO_NAME=libfpto_int_softfloat.so

echo "====================================="
echo "FPtoINT模块仿真脚本"
echo "====================================="

# 检查参数
if [ $# -eq 0 ]; then
    echo "使用方法: $0 [unit|array|all]"
    echo "  unit  - 运行单元测试"
    echo "  array - 运行阵列测试" 
    echo "  all   - 运行所有测试"
    exit 1
fi

TEST_TYPE=$1

#=====================DPI_C_FILE文件=======================
if [ ! -f "$DPI_C_FILE" ]; then
    echo "警告: 找不到DPI-C文件 $DPI_C_FILE,将跳过DPI编译"
    USE_DPI=false
else
    USE_DPI=true
fi

# 步骤 1: 编译 DPI-C 文件
if [ "$USE_DPI" = true ]; then
    echo "步骤 1: 编译 DPI-C 共享库..."
    echo "使用一体化脚本编译 DPI-C 文件..."
    /home/zwz/Oliver/SMC/compile_softfloat_dpi.sh $DPI_C_FILE $DPI_SO_NAME

    if [ $? -ne 0 ]; then
        echo "错误: DPI-C 文件编译失败"
        exit 1
    fi

    echo "成功创建共享库: $PWD/$DPI_SO_NAME"
    echo ""
else
    echo "步骤 1: 跳过 DPI-C 编译（文件不存在）"
fi

# 获取 SoftFloat 包含路径
SOFTFLOAT_INCLUDE="/home/zwz/Oliver/SMC/berkeley-softfloat-3-master/source/include"

# 运行单元测试的函数
run_unit_test() {
    echo "=========================================="
    echo "运行 FPtoINT 基础单元测试"
    echo "=========================================="
    
    echo "步骤 2: 编译 Verilog 文件 (单元测试)..."
    
    if [ "$USE_DPI" = true ]; then
        # 使用VCS编译（支持DPI-C）
        VCS_CMD="vcs -sverilog +v2k -full64 +fsdb -timescale=1ns/1ps"
        VCS_CMD="$VCS_CMD -debug_access+all"
        VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/fpto_int.v"
        VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/tb_fpto_int.v"
        VCS_CMD="$VCS_CMD -CFLAGS \"-I$SOFTFLOAT_INCLUDE\""
        VCS_CMD="$VCS_CMD -LDFLAGS \"-Wl,-rpath,$(pwd)\""
        VCS_CMD="$VCS_CMD -LDFLAGS \"-L$(pwd)\""
        VCS_CMD="$VCS_CMD -LDFLAGS \"-lfpto_int_softfloat\""
        VCS_CMD="$VCS_CMD -o tb_fpto_int"
        
        echo "VCS 编译命令: $VCS_CMD"
        eval $VCS_CMD

    fi
    
    if [ $? -eq 0 ]; then
        echo "Verilog 编译成功"
    else
        echo "错误: Verilog 编译失败"
        exit 1
    fi
    
    echo ""
    echo "步骤 3: 运行仿真 (单元测试)..."
    
    ./tb_fpto_int
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "单元测试仿真完成"
    else
        echo "错误: 单元测试仿真失败"
        exit 1
    fi
}

# 运行阵列测试的函数
run_array_test() {
    echo "=========================================="
    echo "运行 FPtoINT 阵列测试"
    echo "=========================================="
    
    echo "步骤 2: 编译 Verilog 文件 (阵列测试)..."
    
    if [ "$USE_DPI" = true ]; then
        # 使用VCS编译（支持DPI-C）
        VCS_CMD="vcs -sverilog +v2k -full64 +fsdb -timescale=1ns/1ps"
        VCS_CMD="$VCS_CMD -debug_access+all"
        VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/fpto_int.v"
        VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/fpto_int_array.v"
        VCS_CMD="$VCS_CMD $PROJ_ROOT/vsrc/tb_fpto_int_array.v"
        VCS_CMD="$VCS_CMD -CFLAGS \"-I$SOFTFLOAT_INCLUDE\""
        VCS_CMD="$VCS_CMD -LDFLAGS \"-Wl,-rpath,$(pwd)\""
        VCS_CMD="$VCS_CMD -LDFLAGS \"-L$(pwd)\""
        VCS_CMD="$VCS_CMD -LDFLAGS \"-lfpto_int_softfloat\""
        VCS_CMD="$VCS_CMD -o tb_fpto_int_array"
        
        echo "VCS 编译命令: $VCS_CMD"
        eval $VCS_CMD

    fi
    
    if [ $? -eq 0 ]; then
        echo "Verilog 编译成功"
    else
        echo "错误: Verilog 编译失败"
        exit 1
    fi
    
    echo ""
    echo "步骤 3: 运行仿真 (阵列测试)..."
    
    ./tb_fpto_int_array
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "阵列测试仿真完成"
    else
        echo "错误: 阵列测试仿真失败"
        exit 1
    fi
}

# 根据参数选择测试类型
case $TEST_TYPE in
    "unit")
        run_unit_test
        ;;
    "array")
        run_array_test
        ;;
    "all")
        run_unit_test
        echo ""
        echo "================================"
        echo ""
        run_array_test
        ;;
    *)
        echo "错误: 未知的测试类型 '$TEST_TYPE'"
        echo "支持的类型: unit, array, all"
        exit 1
        ;;
esac

echo ""
echo "====================================="
echo "FPtoINT模块仿真完成"
echo "====================================="


