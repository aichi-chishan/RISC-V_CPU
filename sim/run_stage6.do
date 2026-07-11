onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -work work -sv +incdir+src/rtl/core -f src/filelist.f
vsim -c work.rvcpu_rv32m_tb
run -all
