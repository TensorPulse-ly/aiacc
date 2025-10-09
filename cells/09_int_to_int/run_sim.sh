#!/bin/bash

#==============================================================================
# 脚本名称: run_sim.sh
# 脚本功能: 编译和运行INTtoINT模块仿真
# 使用方法: ./run_sim.sh [unit|array|all]
#==============================================================================
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR
DPI_C_FILE=$PROJ_ROOT/csrc/int_to_int_dpi.c

# 编译输出目录
OUTPUT_DIR=$PROJ_ROOT/sim_output

# 清理并创建输出目录
rm -rf $OUTPUT_DIR
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

# DPI 共享库名称
DPI_SO_NAME=libintto_int.so

echo "====================================="
echo "INTtoINT模块仿真脚本"
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

#=====================DPI_C_FILE文件检查=======================
if [ ! -f "$DPI_C_FILE" ]; then
    echo "警告: 找不到DPI-C文件 $DPI_C_FILE,将跳过DPI编译"
    USE_DPI=false
else
    USE_DPI=true
fi

# 步骤 1: 编译 DPI-C 文件
if [ "$USE_DPI" = true ]; then
    echo "步骤 1: 编译 DPI-C 共享库..."
    gcc -shared -fPIC -o $DPI_SO_NAME $DPI_C_FILE

    if [ $? -ne 0 ]; then
        echo "错误: DPI-C 文件编译失败"
        exit 1
    fi

    echo "成功创建共享库: $PWD/$DPI_SO_NAME"
else
    echo "步骤 1: DPI-C 编译文件不存在"
fi

#==============================================================================
# 单元测试函数
#==============================================================================
run_unit_test() {
    echo "开始INTtoINT单元测试..."
    
    cd $OUTPUT_DIR
    
    if [ "$USE_DPI" = true ]; then
        echo "使用DPI-C版本的测试平台..."
        vcs -full64 -debug_access+all -kdb -sverilog \
            -cm line+cond+fsm+branch+tgl \
            -cm_name intto_int_unit_coverage \
            -cm_dir ./coverage.vdb \
            -I../vsrc \
            ../vsrc/int_to_int.v \
            ../vsrc/tb_int_to_int.v \
            -sv_lib $PWD/$DPI_SO_NAME \
            -o intto_int_unit_sim
    else
        echo "使用纯Verilog版本的测试平台..."
        vcs -full64 -debug_access+all -kdb -sverilog \
            -cm line+cond+fsm+branch+tgl \
            -cm_name intto_int_unit_coverage \
            -cm_dir ./coverage.vdb \
            -I../vsrc \
            ../vsrc/int_to_int.v \
            ../vsrc/tb_int_to_int.v \
            -o intto_int_unit_sim
    fi

    if [ $? -eq 0 ]; then
        echo "编译成功，开始仿真..."
        ./intto_int_unit_sim -cm line+cond+fsm+branch+tgl -cm_name intto_int_unit_coverage -cm_dir ./coverage.vdb > unit_test.log 2>&1
        
        echo "生成覆盖率报告..."
        urg -dir ./coverage.vdb -report ./coverage_report
        
        echo "单元测试完成，结果保存在 $OUTPUT_DIR/unit_test.log"
        echo "覆盖率报告保存在 $OUTPUT_DIR/coverage_report/"
        echo "波形文件保存在 $OUTPUT_DIR/tb_int_to_int.vcd"
    else
        echo "编译失败！"
        return 1
    fi
}

#==============================================================================
# 阵列测试函数
#==============================================================================
run_array_test() {
    echo "开始INTtoINT阵列测试..."
    
    cd $OUTPUT_DIR
    
    if [ "$USE_DPI" = true ]; then
        echo "使用DPI-C版本的测试平台..."
        vcs -full64 -debug_access+all -kdb -sverilog \
            -cm line+cond+fsm+branch+tgl \
            -cm_name intto_int_array_coverage \
            -cm_dir ./array_coverage.vdb \
            -I../vsrc \
            ../vsrc/int_to_int.v \
            ../vsrc/int_to_int_array.v \
            ../vsrc/tb_int_to_int_array.v \
            -sv_lib $PWD/$DPI_SO_NAME \
            -o intto_int_array_sim
    else
        echo "使用纯Verilog版本的测试平台..."
        vcs -full64 -debug_access+all -kdb -sverilog \
            -cm line+cond+fsm+branch+tgl \
            -cm_name intto_int_array_coverage \
            -cm_dir ./array_coverage.vdb \
            -I../vsrc \
            ../vsrc/int_to_int.v \
            ../vsrc/int_to_int_array.v \
            ../vsrc/tb_int_to_int_array.v \
            -o intto_int_array_sim
    fi
        
    if [ $? -eq 0 ]; then
        echo "编译成功，开始仿真..."
        ./intto_int_array_sim -cm line+cond+fsm+branch+tgl -cm_name intto_int_array_coverage -cm_dir ./array_coverage.vdb > array_test.log 2>&1
        
        echo "生成阵列测试覆盖率报告..."
        urg -dir ./array_coverage.vdb -report ./array_coverage_report
        
        echo "阵列测试完成，结果保存在 $OUTPUT_DIR/array_test.log"
        echo "阵列覆盖率报告保存在 $OUTPUT_DIR/array_coverage_report/"
        echo "波形文件保存在 $OUTPUT_DIR/tb_int_to_int_array.vcd"
    else
        echo "编译失败！"
        return 1
    fi
}

#==============================================================================
# 主流程
#==============================================================================

case $TEST_TYPE in
    "unit")
        run_unit_test
        ;;
    "array")
        run_array_test
        ;;
    "all")
        echo "运行所有测试..."
        run_unit_test
        if [ $? -eq 0 ]; then
            echo ""
            run_array_test
        fi
        ;;
    *)
        echo "错误: 未知的测试类型 '$TEST_TYPE'"
        echo "支持的类型: unit, array, all"
        exit 1
        ;;
esac

if [ $? -eq 0 ]; then
    echo ""
    echo "====================================="
    echo "仿真完成！"
    echo "====================================="
else
    echo ""
    echo "====================================="
    echo "仿真失败！请检查错误信息。"
    echo "====================================="
    exit 1
fi