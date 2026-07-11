# ModelSim/Questa 批处理脚本；从工程根目录运行。
onerror {quit -code 1 -force}

set work_dir build/modelsim_work
if {[file exists $work_dir]} {
    vdel -lib $work_dir -all
}
vlib $work_dir
vmap work $work_dir

# -sv 保证宏表达式和 SystemVerilog 语法由同一前端解析。
vlog -sv -work work \
    +incdir+src/rtl/core \
    +incdir+src/rtl/general \
    +incdir+src/rtl/mems \
    +incdir+src/tb \
    -f src/filelist.f

# rvcpu_tb 的 smoke_test 在检测到成功时会调用 $finish。ModelSim 会把该
# 系统任务视为本次仿真会话结束，后续 Tcl 命令不会再继续执行；因此默认脚本
# 直接运行覆盖面更完整的 rvcpu_rv32i_tb。smoke_test 仍可手动通过：
#   vsim -c work.rvcpu_tb +IMEM_HEX=src/riscv-tests/smoke_test.hex
puts "==> 运行完整 RV32I 多周期回归测试"
vsim -voptargs=+acc work.rvcpu_rv32i_tb
log -r /*
run -all
