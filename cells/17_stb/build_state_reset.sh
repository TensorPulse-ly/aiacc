#!/usr/bin/env bash

#  仿真脚本
# ----------------------------------------------------------------------------
# 说明：
#   - 将“可配置项（宏）”集中在顶部，便于他人修改适配
#   - 下方“固定逻辑区”尽量不要改动
# ============================================================================

set -euo pipefail

# ============================= 可配置项 =============================
# 工程根目录
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# 本 cell 目录
CELL_DIR="$(cd "$(dirname "$0")" && pwd)"

# 输出目录
OUT_DIR="sim_output"

# DPI 配置
ENABLE_DPI=0   #1
DPI_COMPILE_SCRIPT="${ROOT_DIR}/compile_softfloat_dpi.sh"    # 外部一体化编译脚本
DPI_SRC="${CELL_DIR}/intadd_interface.c"      # DPI 源文件
DPI_LIB_BASENAME="intadd_interface"              # 生成 lib${BASENAME}.so 并链接 -l${BASENAME}

# 头文件路径
SOFTFLOAT_INCLUDE="${ROOT_DIR}/berkeley-softfloat-3-master/source/include"

# Verilog 源文件
VSRC_FILES=(
    "${CELL_DIR}/vsrc/stb_shell_state_test_tb.v"
    "${CELL_DIR}/vsrc/memory_model.v"
    "${CELL_DIR}/vsrc/stb_shell.v"
    "${CELL_DIR}/vsrc/stb_top.v"
    "${CELL_DIR}/vsrc/ur_axi_conv.v"
    "${CELL_DIR}/vsrc/user_reg_model.v"
    "${CELL_DIR}/vsrc/DW_axi_gm_bcm06.v"
    "${CELL_DIR}/vsrc/DW_axi_gm_bcm57.v"
    "${CELL_DIR}/vsrc/DW_axi_gm_bcm65.v"
    "${CELL_DIR}/vsrc/DW_axi_gm_core.v"
    "${CELL_DIR}/vsrc/DW_axi_gm-undef.v"
    "${CELL_DIR}/vsrc/DW_axi_gm.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_bcm06.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_bcm57.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_bcm65.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_exclusive.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_fifo.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_req.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_resp.v"
    "${CELL_DIR}/vsrc/DW_axi_gs_sm.v"
    "${CELL_DIR}/vsrc/DW_axi_gs-undef.v"
    "${CELL_DIR}/vsrc/DW_axi_gs.v"
    "${CELL_DIR}/vsrc/DW_axi_gm_all_includes.vh"
    "${CELL_DIR}/vsrc/DW_axi_gm_bcm_params.vh"
    "${CELL_DIR}/vsrc/DW_axi_gm_cc_constants.vh"
    "${CELL_DIR}/vsrc/DW_axi_gm_constants.vh"
    "${CELL_DIR}/vsrc/DW_axi_gs_all_includes.vh"
    "${CELL_DIR}/vsrc/DW_axi_gs_bcm_params.vh"
    "${CELL_DIR}/vsrc/DW_axi_gs_cc_constants.vh"
    "${CELL_DIR}/vsrc/DW_axi_gs_constants.vh"
)

# 仿真选项
ENABLE_COVERAGE=1     # 1 收集覆盖率；0 不收集
ENABLE_FSDB=1        # 1 使能 +fsdb；0 关闭
ENABLE_KDB=1         # 1 使能 -kdb；0 关闭
RUN_URG=1            # 1 生成 URG 报告；0 跳过
TIMESCALE="1ns/1ps"  # 仿真时间精度
#TODO
# spyglass
# =========================== 可配置项结束 ===========================


# ============================== 固定逻辑区 ===============================
echo "准备仿真环境..."
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cd "${OUT_DIR}"
LIB_PATH="$(pwd)"

# 编译 DPI 共享库（如果需要）
if [[ ${ENABLE_DPI} -eq 1 ]]; then
    echo "编译 DPI 库..."
    [[ -x "${DPI_COMPILE_SCRIPT}" && -f "${DPI_SRC}" ]] || {
        echo "错误: DPI 脚本或源文件不存在"
        exit 1
    }

    #gcc -std=c99 -fPIC -I${SOFTFLOAT_INCLUDE} -c "${DPI_SRC}" -o intadd_interface.o
    #gcc -shared -o "lib${DPI_LIB_BASENAME}.so" intadd_interface.o
    gcc -std=c99 -fPIC -I${SOFTFLOAT_INCLUDE} -c "${DPI_SRC}" -o lib${DPI_LIB_BASENAME}.o
    gcc -shared -o "lib${DPI_LIB_BASENAME}.so" lib${DPI_LIB_BASENAME}.o

    #"${DPI_COMPILE_SCRIPT}" "${DPI_SRC}" "lib${DPI_LIB_BASENAME}.so"
fi

# 设置动态库搜索路径
export LD_LIBRARY_PATH=".:${PWD}:${LD_LIBRARY_PATH:-}"

# 构建 VCS 编译命令
VCS_CMD=(vcs -sverilog +v2k -full64 -debug_access+all +incdir+/datahdd/riscv/zhuzhenglong/aiacc/aiacc/cells/17_stb/vsrc/ -timescale="${TIMESCALE}")



# 添加覆盖率选项
if [[ ${ENABLE_COVERAGE} -eq 1 ]]; then
    VCS_CMD+=(-cm line+cond+fsm+tgl+branch -cm_dir coverage_db)
fi

# 添加波形选项
if [[ ${ENABLE_FSDB} -eq 1 ]]; then
    VCS_CMD+=(+fsdb)
fi

# 添加 KDB 选项（用于 Verdi 调试）
if [[ ${ENABLE_KDB} -eq 1 ]]; then
    VCS_CMD+=(-kdb)
fi

# 添加 DPI 相关编译选项
if [[ ${ENABLE_DPI} -eq 1 ]]; then
    # 重要：VCS 最终链接发生在 sim_output/csrc 下，使用绝对路径避免 -L. 找不到库
    VCS_CMD+=(-CFLAGS "-fPIC -I${SOFTFLOAT_INCLUDE}" \
              -LDFLAGS "-Wl,-rpath,${LIB_PATH}" \
              -LDFLAGS "-L${LIB_PATH}" \
              -LDFLAGS "-l${DPI_LIB_BASENAME}")
fi

# 添加源文件和输出目标
VCS_CMD+=("${VSRC_FILES[@]}" -o simv)

echo "编译 RTL..."
"${VCS_CMD[@]}"

# 运行仿真
echo "运行仿真..."
RUN_CMD=(./simv)

# 设置仿真运行时选项
[[ ${ENABLE_COVERAGE} -eq 1 ]] && RUN_CMD+=(-cm line+cond+fsm+tgl+branch -cm_dir coverage_db)
[[ ${ENABLE_FSDB} -eq 1 ]] && RUN_CMD+=(+fsdb+autoflush)

# 执行仿真并检查结果
if ! "${RUN_CMD[@]}" > sim_output.log 2>&1; then
    echo "错误: 仿真失败，详情见 $(pwd)/sim_output.log"
    exit 1
fi

# 生成覆盖率报告（如果启用且工具存在）
if [[ ${ENABLE_COVERAGE} -eq 1 && ${RUN_URG} -eq 1 ]] && command -v urg >/dev/null 2>&1; then
    echo "生成覆盖率报告..."
    # 生成 HTML 和文本格式的覆盖率报告
    urg -dir coverage_db.vdb -report coverage_report -format both 2>/dev/null || true
    echo "HTML 报告: coverage_report/dashboard.html"
    echo "文本报告: coverage_report/dashboard.txt"
fi

echo "=================================================="
echo "                     仿真完成"
echo " 输出目录: $(pwd)"
echo "=================================================="

# ============================ 固定逻辑区 结束 ============================
