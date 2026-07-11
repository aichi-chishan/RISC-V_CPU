# 第二阶段 ModelSim 自动回归脚本。
# 请从仓库根目录执行：vsim -c -do sim/run_stage2.do
onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -work work -sv +incdir+src/rtl/core -f src/filelist.f

vsim -c work.rvcpu_pipeline_tb
run -all
