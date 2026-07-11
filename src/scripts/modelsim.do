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

vsim -voptargs=+acc work.rvcpu_tb +IMEM_HEX=src/riscv-tests/smoke_test.hex
log -r /*
run -all
