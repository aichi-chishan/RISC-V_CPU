#!/bin/bash
# 在工程根目录执行：bash src/scripts/build.sh {simulate|modelsim|compile|wave|clean}
set -e

TOP_MODULE="rvcpu_tb"
OUTPUT_DIR="build"
FILELIST="src/filelist.f"
INCLUDES=(-I src/rtl/core -I src/rtl/general -I src/rtl/mems -I src/tb)

simulate_iverilog() {
    mkdir -p "$OUTPUT_DIR"
    echo "==> Icarus: compile"
    iverilog -g2012 -s "$TOP_MODULE" -o "$OUTPUT_DIR/$TOP_MODULE.vvp" \
        "${INCLUDES[@]}" -f "$FILELIST"
    echo "==> Icarus: simulate"
    vvp "$OUTPUT_DIR/$TOP_MODULE.vvp" +IMEM_HEX=src/riscv-tests/smoke_test.hex
}

simulate_modelsim() {
    mkdir -p "$OUTPUT_DIR/modelsim_work"
    echo "==> ModelSim: compile and simulate"
    vsim -c -do "do src/scripts/modelsim.do; quit -f"
}

compile_only() {
    mkdir -p "$OUTPUT_DIR"
    iverilog -g2012 -s "$TOP_MODULE" -o "$OUTPUT_DIR/$TOP_MODULE.vvp" \
        "${INCLUDES[@]}" -f "$FILELIST"
}

case "${1:-simulate}" in
    simulate) simulate_iverilog ;;
    modelsim) simulate_modelsim ;;
    compile)  compile_only ;;
    wave)     gtkwave "$OUTPUT_DIR/rvcpu_tb.vcd" & ;;
    clean)    rm -rf "$OUTPUT_DIR" transcript vsim.wlf ;;
    *) echo "Usage: $0 {simulate|modelsim|compile|wave|clean}"; exit 2 ;;
esac
