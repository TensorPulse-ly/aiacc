#!/bin/bash

# ML Shape Computation Optimizer - 自动化测试脚本
# 使用方法: ./run-tests.sh [--verbose]

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SHAPE_OPT="../build/shape-opt"
TEMP_DIR="./temp"
VERBOSE=false

# 检查命令行参数
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

# 函数：打印带颜色的消息
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo "=================================================="
    print_status $BLUE "$1"
    echo "=================================================="
}

print_test_header() {
    echo "--------------------------------------------------"
    print_status $YELLOW "Testing: $1"
    echo "--------------------------------------------------"
}

# 检查工具是否存在
check_tool() {
    if [[ ! -f "$SHAPE_OPT" ]]; then
        print_status $RED "Error: shape-opt tool not found at $SHAPE_OPT"
        print_status $YELLOW "Please build the project first:"
        print_status $YELLOW "  cd ../framework"
        print_status $YELLOW "  mkdir build && cd build"
        print_status $YELLOW "  cmake .. && make"
        exit 1
    fi
}

# 创建临时目录
setup_temp() {
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
}

# 清理临时文件
cleanup() {
    rm -rf "$TEMP_DIR"
}

# 运行单个测试
run_test() {
    local test_name=$1
    local input_file="input/${test_name}.mlir"
    local expected_file="expected/${test_name}.mlir"
    local output_file="$TEMP_DIR/${test_name}_output.mlir"
    
    print_test_header "$test_name"
    
    # 检查输入文件是否存在
    if [[ ! -f "$input_file" ]]; then
        print_status $RED "✗ MISSING: Input file $input_file not found"
        return 1
    fi
    
    # 检查期望文件是否存在
    if [[ ! -f "$expected_file" ]]; then
        print_status $RED "✗ MISSING: Expected file $expected_file not found"
        return 1
    fi
    
    # 运行优化工具
    print_status $BLUE "Running: $SHAPE_OPT --shape-optimizer $input_file"
    if ! "$SHAPE_OPT" --shape-optimizer "$input_file" > "$output_file" 2>"$TEMP_DIR/${test_name}_error.log"; then
        print_status $RED "✗ FAILED: shape-opt crashed or returned error"
        if [[ "$VERBOSE" == "true" ]]; then
            print_status $YELLOW "Error output:"
            cat "$TEMP_DIR/${test_name}_error.log"
        fi
        return 1
    fi
    
    # 验证输出文件语法
    print_status $BLUE "Validating output syntax..."
    if ! mlir-opt --verify-diagnostics "$output_file" >/dev/null 2>&1; then
        print_status $RED "✗ FAILED: Output MLIR has syntax errors"
        if [[ "$VERBOSE" == "true" ]]; then
            print_status $YELLOW "Syntax check output:"
            mlir-opt --verify-diagnostics "$output_file" 2>&1 || true
        fi
        return 1
    fi
    
    # 比较结果（忽略空白行和注释）
    print_status $BLUE "Comparing with expected output..."
    
    # 规范化文件（移除注释和多余空白）
    normalize_mlir() {
        grep -v '^[[:space:]]*\/\/' "$1" | grep -v '^[[:space:]]*$' | sed 's/[[:space:]]*$//' | sort
    }
    
    normalize_mlir "$output_file" > "$TEMP_DIR/${test_name}_normalized_output.mlir"
    normalize_mlir "$expected_file" > "$TEMP_DIR/${test_name}_normalized_expected.mlir"
    
    if diff -q "$TEMP_DIR/${test_name}_normalized_expected.mlir" "$TEMP_DIR/${test_name}_normalized_output.mlir" >/dev/null; then
        print_status $GREEN "✓ PASSED: $test_name"
        return 0
    else
        print_status $RED "✗ FAILED: $test_name - Output doesn't match expected"
        
        if [[ "$VERBOSE" == "true" ]]; then
            print_status $YELLOW "Expected:"
            cat "$expected_file"
            echo ""
            print_status $YELLOW "Got:"
            cat "$output_file"
            echo ""
            print_status $YELLOW "Diff:"
            diff "$TEMP_DIR/${test_name}_normalized_expected.mlir" "$TEMP_DIR/${test_name}_normalized_output.mlir" || true
        fi
        return 1
    fi
}

# 主函数
main() {
    print_header "ML Shape Computation Optimizer - Test Suite"
    
    check_tool
    setup_temp
    
    # 测试用例列表
    test_cases=("conv_shape" "dynamic_shape" "conditional_shape" "matrix_chain")
    
    passed=0
    failed=0
    failed_tests=()
    
    print_status $BLUE "Found tool: $SHAPE_OPT"
    print_status $BLUE "Running ${#test_cases[@]} test cases..."
    echo ""
    
    # 运行所有测试
    for test_case in "${test_cases[@]}"; do
        if run_test "$test_case"; then
            ((passed++))
        else
            ((failed++))
            failed_tests+=("$test_case")
        fi
        echo ""
    done
    
    # 打印总结
    print_header "Test Results Summary"
    
    print_status $GREEN "Passed: $passed"
    print_status $RED "Failed: $failed"
    
    if [[ $failed -gt 0 ]]; then
        print_status $RED "Failed tests: ${failed_tests[*]}"
        echo ""
        print_status $YELLOW "Tips for debugging:"
        print_status $YELLOW "  1. Run with --verbose flag for detailed output"
        print_status $YELLOW "  2. Check the temp/ directory for intermediate files"
        print_status $YELLOW "  3. Manually run: $SHAPE_OPT --shape-optimizer input/test_name.mlir"
        print_status $YELLOW "  4. Use mlir-opt --verify-diagnostics to check syntax"
    else
        print_status $GREEN "🎉 All tests passed! Great job!"
        print_status $BLUE "Your Shape Computation Optimizer is working correctly."
    fi
    
    cleanup
    
    # 返回失败测试的数量作为退出码
    exit $failed
}

# 错误处理
trap cleanup EXIT

# 运行主函数
main