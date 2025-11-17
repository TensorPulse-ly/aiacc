#!/bin/bash

# MLIR linalg Dialect Lab 测试脚本
# 用于验证所有阶段的代码是否正确

echo "🧪 MLIR linalg Dialect Lab 测试开始..."

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0

# 测试函数
test_stage() {
    local stage=$1
    local file=$2
    local stage_name=$3
    
    echo ""
    echo "📋 测试 $stage_name..."
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if mlir-opt "$file" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ $stage_name 语法检查通过${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ $stage_name 语法检查失败${NC}"
        echo "错误详情："
        mlir-opt "$file"
    fi
}

# 检查文件是否存在
check_file() {
    if [ ! -f "$1" ]; then
        echo -e "${RED}❌ 文件 $1 不存在${NC}"
        return 1
    fi
    return 0
}

echo "🔍 检查必要文件..."

# 检查所有必要文件
files=(
    "stage1_fill_tensor.mlir"
    "stage2_matmul.mlir" 
    "stage3_transpose.mlir"
)

missing_files=0
for file in "${files[@]}"; do
    if ! check_file "$file"; then
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -gt 0 ]; then
    echo -e "${RED}❌ 有 $missing_files 个文件缺失，请先创建所有必要的文件${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 所有文件都存在${NC}"

# 运行所有测试
test_stage "阶段1" "stage1_fill_tensor.mlir" "张量填充操作"
test_stage "阶段2" "stage2_matmul.mlir" "矩阵乘法操作"  
test_stage "阶段3" "stage3_transpose.mlir" "张量转置操作"

# 输出测试结果摘要
echo ""
echo "📊 测试结果摘要："
echo "=================="
echo "总测试数: $TOTAL_TESTS"
echo "通过测试: $PASSED_TESTS"
echo "失败测试: $((TOTAL_TESTS - PASSED_TESTS))"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}🎉 恭喜！所有测试都通过了！${NC}"
else
    echo -e "${YELLOW}⚠️  有部分测试失败，请检查代码并修复错误${NC}"
    exit 1
fi