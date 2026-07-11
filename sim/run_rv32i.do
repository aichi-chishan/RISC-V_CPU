# 完整 RV32I 功能回归。与 run_stage2.do 分开启动，是因为测试台中的
# $finish 会结束当前批处理会话，两个顶层不能可靠地串在同一个 vsim 会话中。
onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -work work -sv +incdir+src/rtl/core -f src/filelist.f
vsim -c work.rvcpu_rv32i_tb
run -all
