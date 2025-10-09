#!/bin/bash

# ================================================================
# shift_up 模块仿真脚本 
# ================================================================

# 配置参数
SIM_TOOL="vcs"
WAVE_FORMAT="vcd"
COVERAGE=true
DEBUG=true

# 路径配置
SCRIPT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
PROJ_ROOT=$SCRIPT_DIR
OUTPUT_DIR="$PROJ_ROOT/sim_output"
DUT_FILE="$PROJ_ROOT/vsrc/shift_up.v"
TB_FILE="$PROJ_ROOT/vsrc/tb_shift_up.v"

# 依赖检查
check_dependencies() {
    if ! command -v vcs &> /dev/null; then
        echo "[ERROR] VCS not found! Please ensure VCS is installed and in PATH"
        return 1
    fi
    return 0
}

# 清理工作区
clean_workspace() {
    echo "Cleaning workspace..."
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    find . -name "*.vcd" -delete
    find . -name "*.fsdb" -delete
    find . -name "*.log" -delete
    find . -name "simv" -delete
    find . -name "simv.daidir" -delete
}

# 文件检查
check_files() {
    local missing=()
    [ ! -f "$DUT_FILE" ] && missing+=("设计文件: $DUT_FILE")
    [ ! -f "$TB_FILE" ] && missing+=("测试平台: $TB_FILE")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "缺失关键文件:"
        for file in "${missing[@]}"; do
            echo "  - $file"
        done
        return 1
    fi
    return 0
}

# 修复后的编译函数
compile_design() {
    cd "$OUTPUT_DIR" || exit 1
    
    local vcs_opts=(
        "-sverilog" "+v2k" "-full64"
        "-debug_access+all"
        "-timescale=1ns/1ps"
    )
    
    # 旧版VCS兼容的覆盖率选项
    if [ "$COVERAGE" = true ]; then
        vcs_opts+=("-cm" "line+cond+fsm+tgl")
    fi
    
    # 波形选项
    case "$WAVE_FORMAT" in
        "vcd")
            vcs_opts+=("+vcd+vcdpluson")
            ;;
        "fsdb")
            vcs_opts+=("+fsdb")
            ;;
    esac
    
    echo "Compiling design with VCS..."
    
    # 使用标准重定向记录日志（修复核心错误）
    vcs "${vcs_opts[@]}" "$DUT_FILE" "$TB_FILE" -o simv > compile.log 2>&1
    
    if [ $? -ne 0 ]; then
        echo "[ERROR] 编译失败! 查看日志: $OUTPUT_DIR/compile.log"
        echo "=== 编译错误摘要 ==="
        grep -i "error" compile.log | head -n 5
        return 1
    fi
    
    echo "编译成功完成"
    return 0
}

# 运行仿真
run_simulation() {
    cd "$OUTPUT_DIR" || exit 1
    
    local sim_opts=("-l" "sim.log")
    
    if [ "$COVERAGE" = true ]; then
        sim_opts+=("-cm" "line+cond+fsm+tgl")
    fi
    
    echo "Starting simulation..."
    ./simv "${sim_opts[@]}"
    
    if grep -q "All tests passed" sim.log; then
        echo "✅ 所有测试通过!"
        return 0
    else
        echo "❌ 测试失败! 查看日志: $OUTPUT_DIR/sim.log"
        echo "=== 失败测试摘要 ==="
        grep -i "fail\|error" sim.log
        return 1
    fi
}

# 主流程
main() {
    echo "========================================"
    echo "        Shift_Up 模块仿真"
    echo "========================================"
    
    # 执行检查
    check_dependencies || exit 1
    check_files || exit 1
    clean_workspace
    
    # 编译设计
    if ! compile_design; then
        exit 1
    fi
    
    # 运行仿真
    if ! run_simulation; then
        exit 1
    fi
    
    echo "========================================"
    echo "      仿真成功完成!"
    echo "      输出目录: $OUTPUT_DIR"
    echo "      波形文件: $OUTPUT_DIR/tb_shift_up.vcd"
    echo "========================================"
}

# 启动
main