#!/bin/bash

# 运行覆盖率增强测试的脚本

# 设置输出目录
OUTPUT_DIR="sim_output2/coverage_test"

# 清理旧的覆盖率测试文件
if [ -d "$OUTPUT_DIR" ]; then
    echo "清理旧的覆盖率测试文件..."
    rm -rf $OUTPUT_DIR/*
    echo "已清理$OUTPUT_DIR/下的所有文件"
fi

# 创建输出目录（如果不存在）
mkdir -p $OUTPUT_DIR

# 复制ucli.key文件到输出目录
if [ -f "ucli.key" ]; then
    cp ucli.key $OUTPUT_DIR/
    echo "已复制ucli.key到$OUTPUT_DIR/"
fi

# 编译并运行覆盖率增强测试
# 使用VCS或其他Verilog仿真器编译
# 这里假设使用vcs作为仿真器
# 如果使用其他仿真器，请修改相应的命令

# 编译命令（根据VCS O-2018.09-SP2版本调整）
# 使用正确的覆盖率收集选项，采用绝对路径指定源文件
vcs -full64 -sverilog +v2k -cm line+cond+fsm+tgl +vcs+lic+wait -debug_access+all \
/home/zwz/zts/17_stb/axi_top.v \
/home/zwz/zts/17_stb/burst_store.v \
/home/zwz/zts/17_stb/burst_store_tb_coverage.v \
/home/zwz/zts/17_stb/axi_stb.v \
/home/zwz/zts/17_stb/axi_stb_s.v \
/home/zwz/zts/17_stb/axi_mem_model.v \
/home/zwz/zts/17_stb/ur_model.v \
/home/zwz/zts/17_stb/axi_protocol_checker.v \
-top burst_store_tb_coverage \
-o $OUTPUT_DIR/simv_coverage \
-l $OUTPUT_DIR/compile.log

# 原始file_list.f方式已被替换为直接使用绝对路径指定源文件

# 运行仿真
if [ -f "$OUTPUT_DIR/simv_coverage" ]; then
    echo "开始运行覆盖率增强测试..."
    # 运行仿真，指定生成的ucli.key放在sim_output2目录下
    cd $OUTPUT_DIR && ./simv_coverage -l sim.log -cm line+cond+fsm+tgl
    cd - > /dev/null 2>&1
    # 如果在当前目录生成了ucli.key，移动到sim_output2目录
    if [ -f "ucli.key" ]; then
        mv ucli.key sim_output2/
        echo "已将覆盖率测试生成的ucli.key移动到sim_output2/"
    fi
else
    echo "编译失败，请检查编译日志: $OUTPUT_DIR/compile.log"
    exit 1
fi

# 生成覆盖率报告
# 注意：这部分命令需要根据实际使用的仿真器和覆盖率工具进行调整
# 以下是VCS的示例命令
if [ -d "$OUTPUT_DIR/simv_coverage.vdb" ]; then
    echo "覆盖率数据已生成，准备生成报告..."
    urg -dir $OUTPUT_DIR/simv_coverage.vdb -format both -report $OUTPUT_DIR/coverage_report
    echo "覆盖率报告已生成到: $OUTPUT_DIR/coverage_report"
else
    echo "仿真未生成覆盖率数据，请检查仿真日志: $OUTPUT_DIR/sim.log"
    exit 1
fi

# 打印覆盖率摘要
if [ -f "$OUTPUT_DIR/coverage_report/summary.txt" ]; then
    echo "\n覆盖率摘要："
    cat $OUTPUT_DIR/coverage_report/summary.txt
else
    echo "无法找到覆盖率摘要文件，但覆盖率数据已生成"
fi

echo "\n覆盖率增强测试执行完成！"