#!/bin/bash

echo "清理之前的仿真文件..."
rm -rf sim_output
mkdir -p sim_output
cd sim_output

# 使用一体化脚本编译 DPI-C 文件
/home/sunny/SMC/compile_softfloat_dpi.sh ../csrc/softfloat_dpi.c libfpmul_softfloat.so

if [ $? -ne 0 ]; then
    echo "错误: DPI-C 文件编译失败"
    exit 1
fi

echo "设置库路径..."
# 设置LD_LIBRARY_PATH以便VCS能找到共享库
LIB_PATH=$(pwd)
export LD_LIBRARY_PATH="$LIB_PATH:$PWD/..:$LD_LIBRARY_PATH"

# 获取 SoftFloat 包含路径
SOFTFLOAT_INCLUDE="/home/Sunny/SMC/berkeley-softfloat-3-master/source/include"

echo "运行 VCS 编译..."
# 使用 VCS 编译 Verilog 文件，支持DPI-C和覆盖率
vcs -sverilog +v2k -full64 -debug_access+all \
    -kdb \
    -timescale=1ns/1ps \
    +fsdb \
    -cm line+cond+fsm+tgl+branch \
    -cm_dir coverage_db \
    -CFLAGS "-I$SOFTFLOAT_INCLUDE -fPIC" \
    -LDFLAGS "-Wl,-rpath,$LIB_PATH" \
    -LDFLAGS "-L$LIB_PATH" \
    -LDFLAGS "-lfpmul_softfloat" \
    ../vsrc/tb_fpmul.v \
    ../vsrc/fpmul.v \
    -o simv

if [ $? -ne 0 ]; then
    echo "错误: VCS 编译失败"
    exit 1
fi

echo "运行仿真..."
# 确保库路径正确设置
export LD_LIBRARY_PATH=".:$LD_LIBRARY_PATH"

./simv -cm line+cond+fsm+tgl+branch -cm_dir coverage_db +fsdb+autoflush > sim_output.log 2>&1

if [ $? -ne 0 ]; then
    echo "错误: 仿真运行失败"
    exit 1
fi

echo "仿真完成！"

echo "生成覆盖率报告..."
urg -dir coverage_db -report both

echo "=========================================="
echo "        FPMUL 仿真完成"
echo "=========================================="
