#!/bin/bash

# ================================================================
# shift_down 模块仿真脚本
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
DUT_FILE="$PROJ_ROOT/vsrc/shift_down.v"
TB_FILE="$PROJ_ROOT/vsrc/tb_shift_down.v"
COV_DIR="$OUTPUT_DIR/coverage_report"

# 依赖检查
check_dependencies() {
    if ! command -v vcs &> /dev/null; then
        echo "[ERROR] VCS not found! Please ensure VCS is installed and in PATH"
        return 1
    fi
    
    if [ "$COVERAGE" = true ] && ! command -v urg &> /dev/null; then
        echo "[WARNING] urg not found! Coverage reporting will be disabled"
        COVERAGE=false
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
    find . -name "cov_work" -delete
    find . -name "vcs.key" -delete
    rm -rf urgReport  # 清理URG默认报告目录
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

# 优化编译函数
compile_design() {
    cd "$OUTPUT_DIR" || exit 1
    
    local vcs_opts=(
        "-sverilog" "+v2k" "-full64"
        "-debug_access+all"
        "-timescale=1ns/1ps"
        "-lca"  # 启用VCS 18的高级功能
    )
    
    # 覆盖率选项 - 仅启用实际存在的覆盖类型
    if [ "$COVERAGE" = true ]; then
        vcs_opts+=(
            "-cm" "line+tgl"  # 仅保留实际支持的覆盖类型
            "-cm_dir" "coverage.vdb"
        )
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
    
    # 使用标准重定向记录日志
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
        sim_opts+=("-cm" "line+tgl")  # 与实际编译选项匹配
        sim_opts+=("-cm_dir" "coverage.vdb")
    fi
    
    echo "Starting simulation..."
    ./simv "${sim_opts[@]}"
    
    if grep -q "All shift_down tests passed" sim.log; then
        echo "✅ 所有测试通过!"
        return 0
    else
        echo "❌ 测试失败! 查看日志: $OUTPUT_DIR/sim.log"
        echo "=== 失败测试摘要 ==="
        grep -i "fail\|error" sim.log
        return 1
    fi
}

# 兼容VCS 2018的覆盖率报告生成
generate_coverage_report() {
    if [ "$COVERAGE" != true ]; then
        echo "Coverage reporting disabled"
        return 0
    fi
    
    cd "$OUTPUT_DIR" || exit 1
    
    echo "Generating coverage report..."
    mkdir -p "$COV_DIR"
    
    # 使用基本URG命令（不指定-report选项）
    urg -dir coverage.vdb -format both > coverage_urg.log 2>&1
    
    # 检查URG是否生成了默认报告目录
    if [ -d "urgReport" ]; then
        echo "✅ 覆盖率报告已生成"
        
        # 复制报告到指定目录
        cp -r urgReport/* "$COV_DIR/"
        
        # 检查HTML报告
        if [ -f "$COV_DIR/index.html" ]; then
            echo "    HTML报告: file://$(readlink -f "$COV_DIR/index.html")"
        fi
        
        # 检查文本报告
        if [ -f "$COV_DIR/dashboard.txt" ]; then
            echo "    文本报告: $COV_DIR/dashboard.txt"
            echo "=== 覆盖率摘要 ==="
            head -n 20 "$COV_DIR/dashboard.txt"
        fi
    else
        echo "[WARNING] 未找到覆盖率报告目录"
        echo "查看URG日志: $OUTPUT_DIR/coverage_urg.log"
        
        # 尝试直接生成文本报告
        urg -dir coverage.vdb -format text > "$COV_DIR/coverage.txt" 2>&1
        if [ -s "$COV_DIR/coverage.txt" ]; then
            echo "基本覆盖率报告: $COV_DIR/coverage.txt"
            echo "=== 覆盖率摘要 ==="
            head -n 20 "$COV_DIR/coverage.txt"
        else
            echo "[INFO] 无法生成覆盖率报告，但仿真已完成"
        fi
    fi
    
    return 0
}

# 主流程
main() {
    echo "========================================"
    echo "        Shift_Down 模块仿真"
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
    
    # 生成覆盖率报告
    generate_coverage_report
    
    echo "========================================"
    echo "      仿真成功完成!"
    echo "      输出目录: $OUTPUT_DIR"
    echo "      波形文件: $OUTPUT_DIR/tb_shift_down.vcd"
    if [ "$COVERAGE" = true ]; then
        echo "      覆盖率报告: $COV_DIR"
    fi
    echo "========================================"
}

# 启动
main