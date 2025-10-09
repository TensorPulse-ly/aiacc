#!/bin/bash

################################################################################
# 一体化 Berkeley SoftFloat-3 + DPI-C 编译脚本
# 
# 功能：
# 1. 自动检测和设置 Berkeley SoftFloat-3
# 2. 编译 DPI-C 文件生成共享库
# 
#
# 使用方法：
#   ./compile_softfloat_dpi.sh <dpi_source.c> [output_lib.so]
#
# 示例：
#   ./compile_softfloat_dpi.sh softfloat_dpi.c
#   ./compile_softfloat_dpi.sh softfloat_dpi.c libruntime.so
################################################################################

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 显示用法
print_usage() {
    echo "用法: $0 <dpi_source_file.c> [shared_lib_name]"
    echo ""
    echo "参数说明:"
    echo "  dpi_source_file.c  : DPI-C 源文件路径"
    echo "  shared_lib_name    : 输出共享库名称 (默认: libruntime.so)"
    echo ""
    echo "示例:"
    echo "  $0 softfloat_dpi.c"
    echo "  $0 softfloat_dpi.c libruntime.so"
    echo "  $0 ../softfloat_dpi.c"
}

# 检查参数
if [ $# -lt 1 ]; then
    print_usage
    exit 1
fi

DPI_SOURCE="$1"
SHARED_LIB="${2:-libruntime.so}"

# 检查源文件是否存在
if [ ! -f "$DPI_SOURCE" ]; then
    print_error "DPI源文件不存在: $DPI_SOURCE"
    exit 1
fi

print_info "=== 一体化 SoftFloat DPI-C 编译脚本 ==="
print_info "源文件: $DPI_SOURCE"
print_info "输出库: $SHARED_LIB"

# ============================================================================
# 第一步：自动检测和设置 SoftFloat
# ============================================================================

print_info "第一步: 检测和设置 Berkeley SoftFloat-3"

# 尝试多个可能的 SoftFloat 路径
POSSIBLE_PATHS=(
    "/home/Sunny/SMC/berkeley-softfloat-3-master"
    "./berkeley-softfloat-3-master"
    "../berkeley-softfloat-3-master"
    "../../berkeley-softfloat-3-master"
)

SOFTFLOAT_ROOT=""
for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        SOFTFLOAT_ROOT="$path"
        break
    fi
done

if [ -z "$SOFTFLOAT_ROOT" ]; then
    print_error "未找到 Berkeley SoftFloat 目录"
    print_info "请确保 berkeley-softfloat-3-master 目录存在于以下位置之一:"
    for path in "${POSSIBLE_PATHS[@]}"; do
        echo "  - $path"
    done
    exit 1
fi

print_success "找到 SoftFloat 目录: $SOFTFLOAT_ROOT"

# 设置路径变量
SOFTFLOAT_INCLUDE="$SOFTFLOAT_ROOT/source/include"
SOFTFLOAT_BUILD="$SOFTFLOAT_ROOT/build/Linux-x86_64-GCC"
SOFTFLOAT_LIB="$SOFTFLOAT_BUILD/softfloat.a"

# 检查头文件
if [ ! -f "$SOFTFLOAT_INCLUDE/softfloat.h" ]; then
    print_error "SoftFloat 头文件不存在: $SOFTFLOAT_INCLUDE/softfloat.h"
    exit 1
fi

print_success "找到 SoftFloat 头文件"

# 检查或构建库文件
if [ ! -f "$SOFTFLOAT_LIB" ]; then
    print_warning "SoftFloat 库不存在，正在构建..."
    
    if [ ! -d "$SOFTFLOAT_BUILD" ]; then
        print_error "SoftFloat 构建目录不存在: $SOFTFLOAT_BUILD"
        exit 1
    fi
    
    # 进入构建目录并编译
    cd "$SOFTFLOAT_BUILD"
    print_info "正在构建 SoftFloat 库..."
    
    if make clean >/dev/null 2>&1 && make >/dev/null 2>&1; then
        print_success "SoftFloat 库构建成功"
    else
        print_error "SoftFloat 库构建失败"
        exit 1
    fi
    
    # 返回原目录
    cd - >/dev/null
else
    print_success "找到 SoftFloat 库: $SOFTFLOAT_LIB"
fi

# 验证库文件
LIB_SIZE=$(stat -c%s "$SOFTFLOAT_LIB" 2>/dev/null || stat -f%z "$SOFTFLOAT_LIB" 2>/dev/null)
print_info "库文件大小: $LIB_SIZE 字节"

# ============================================================================
# 第二步：编译 DPI-C 文件
# ============================================================================

print_info "第二步: 编译 DPI-C 文件"

# 生成目标文件名
DPI_DIR=$(dirname "$DPI_SOURCE")
DPI_BASENAME=$(basename "$DPI_SOURCE" .c)
OBJ_FILE="$DPI_DIR/${DPI_BASENAME}.o"

print_info "编译目标文件: $OBJ_FILE"

# 编译 DPI-C 源文件为目标文件
gcc -c -fPIC \
    -I"$SOFTFLOAT_INCLUDE" \
    "$DPI_SOURCE" \
    -o "$OBJ_FILE"

if [ $? -ne 0 ]; then
    print_error "目标文件编译失败"
    exit 1
fi

print_success "目标文件编译成功"

# ============================================================================
# 第三步：创建共享库
# ============================================================================

print_info "第三步: 创建共享库"

# 创建共享库
gcc -shared \
    "$OBJ_FILE" \
    "$SOFTFLOAT_LIB" \
    -o "$SHARED_LIB"

if [ $? -ne 0 ]; then
    print_error "共享库创建失败"
    exit 1
fi

print_success "成功创建共享库: $SHARED_LIB"

# 显示库信息
if [ -f "$SHARED_LIB" ]; then
    SO_SIZE=$(stat -c%s "$SHARED_LIB" 2>/dev/null || stat -f%z "$SHARED_LIB" 2>/dev/null)
    print_info "共享库大小: $SO_SIZE 字节"
fi

# 清理临时文件
rm -f "$OBJ_FILE"
print_info "已清理临时文件"

# ============================================================================
# 第四步：显示使用说明
# ============================================================================

print_info ""
print_success "=== 编译完成 ==="
print_success "✓ DPI-C 共享库: $SHARED_LIB"
print_success "✓ SoftFloat 库: $SOFTFLOAT_LIB"
print_success "✓ 头文件路径: $SOFTFLOAT_INCLUDE"

print_info ""
print_info "=== VCS 使用示例 ==="
echo "vcs -sverilog -full64 -timescale=1ns/1ps \\"
echo "    -CFLAGS \"-I$SOFTFLOAT_INCLUDE\" \\"
echo "    -LDFLAGS \"-Wl,-rpath,\$(pwd)\" \\"
echo "    -LDFLAGS \"-L\$(pwd)\" \\"
echo "    -LDFLAGS \"-lruntime\" \\"
echo "    your_testbench.v your_design.v \\"
echo "    -o simv"

print_info ""
print_info "=== Questa/ModelSim 使用示例 ==="
echo "vlog -sv +incdir+. your_files.v"
echo "vsim -c -sv_lib $SHARED_LIB your_top_module"

print_info ""
print_info "=== 环境变量（可选设置）==="
echo "export LD_LIBRARY_PATH=\"\$(pwd):\$LD_LIBRARY_PATH\""
echo "export SOFTFLOAT_INCLUDE=\"$SOFTFLOAT_INCLUDE\""
echo "export SOFTFLOAT_LIB=\"$SOFTFLOAT_LIB\""

print_success ""
print_success "🎉 DPI-C 共享库编译完成，可以开始仿真了！"
