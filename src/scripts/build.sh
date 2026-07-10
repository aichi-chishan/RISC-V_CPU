#!/bin/bash
#==============================================================================
# build.sh — 编译/仿真/清理脚本 for RISC-V CPU Phase 1 (单周期, 五阶段架构)
#==============================================================================
set -e

SIMULATOR="iverilog"
TOP_MODULE="rvcpu_tb"
OUTPUT_DIR="./build"
WAVE_FILE="rvcpu_tb.vcd"

# 五阶段架构文件列表
RTL_FILES=(
    "src/rtl/core/config.v"
    "src/rtl/core/defines.v"
    "src/rtl/core/rvcpu_decode.v"
    "src/rtl/core/rvcpu_regfile.v"
    "src/rtl/core/rvcpu_immgen.v"
    "src/rtl/core/rvcpu_if_stage.v"
    "src/rtl/core/rvcpu_id_stage.v"
    "src/rtl/core/rvcpu_ex_stage.v"
    "src/rtl/core/rvcpu_mem_stage.v"
    "src/rtl/core/rvcpu_wb_stage.v"
    "src/rtl/core/rvcpu_top.v"
    "src/rtl/mems/rvcpu_imem.v"
    "src/rtl/mems/rvcpu_dmem.v"
)

TB_FILES=(
    "src/tb/rvcpu_tb.v"
)

ALL_FILES=("${RTL_FILES[@]}" "${TB_FILES[@]}")

simulate_iverilog() {
    echo "==> Compiling with Icarus Verilog..."
    mkdir -p $OUTPUT_DIR
    cd $OUTPUT_DIR
    iverilog -o ${TOP_MODULE}.vvp \
        -I ../src/rtl/core \
        -I ../src/rtl/mems \
        -I ../src/tb \
        -g2012 \
        ${ALL_FILES[@]/#/../}
    echo "==> Running simulation..."
    vvp ${TOP_MODULE}.vvp
    echo "==> Simulation finished."
    [ -f "$WAVE_FILE" ] && echo "    Waveform: $OUTPUT_DIR/$WAVE_FILE"
}

compile_only() {
    echo "==> Syntax check..."
    for f in "${ALL_FILES[@]}"; do
        echo "    $f"
        iverilog -g2012 -o /dev/null \
            -I src/rtl/core -I src/rtl/mems -I src/tb "$f" 2>&1 || true
    done
    echo "==> Done."
}

view_wave() {
    command -v gtkwave &>/dev/null && gtkwave $OUTPUT_DIR/$WAVE_FILE &
}

clean() {
    echo "==> Cleaning..."
    rm -rf $OUTPUT_DIR *.vcd *.vvp *.wdb 2>/dev/null
    echo "==> Done."
}

case "${1:-simulate}" in
    simulate)  simulate_iverilog ;;
    compile)   compile_only ;;
    wave)      view_wave ;;
    clean)     clean ;;
    *)         echo "Usage: $0 {simulate|compile|clean|wave}" ;;
esac
