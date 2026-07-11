# 针对现有 Vivado 工程器件 xc7z020clg400-2 做无约束综合检查。
# 这里只验证 RTL 可综合；真正生成 bitstream 前仍需按开发板添加 XDC 引脚和时钟约束。
set root [file normalize [file join [file dirname [info script]] ../..]]
cd $root

set rtl_files [list \
    src/rtl/core/rvcpu_decode.v \
    src/rtl/core/rvcpu_regfile.v \
    src/rtl/core/rvcpu_immgen.v \
    src/rtl/core/rvcpu_if_stage.v \
    src/rtl/core/rvcpu_id_stage.v \
    src/rtl/core/rvcpu_ex_stage.v \
    src/rtl/core/rvcpu_mem_stage.v \
    src/rtl/core/rvcpu_wb_stage.v \
    src/rtl/core/rvcpu_pipeline_reg.v \
    src/rtl/core/rvcpu_hazard_unit.v \
    src/rtl/core/rvcpu_sequencer.v \
    src/rtl/core/rvcpu_top.v \
    src/rtl/mems/rvcpu_imem.v \
    src/rtl/mems/rvcpu_dmem.v \
    src/rtl/fpga/rvcpu_fpga_top.v]

read_verilog -sv $rtl_files
synth_design -top rvcpu_fpga_top -part xc7z020clg400-2 \
    -generic IMEM_INIT_FILE=src/riscv-tests/smoke_test.hex
report_utilization -file build/vivado_utilization.rpt
report_timing_summary -file build/vivado_timing_summary.rpt
puts "RVC_VIVADO_SYNTH_PASSED"
