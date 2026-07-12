# 用法：vivado -mode batch -source vivado/create_hdmi_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build vivado]
file mkdir $build_dir
# 某些 Vivado 2025.1 Windows 安装的用户 Tcl Store catalog 会损坏，导致
# create_project 懒加载 appinit 时找不到明明存在的包。把安装区包路径显式加入
# auto_path，不修改用户全局配置，也不依赖个人目录。
if {[info exists ::env(XILINX_VIVADO)]} {
    set appinit_dir [file join $::env(XILINX_VIVADO) data XilinxTclStore support appinit]
    if {[file isdirectory $appinit_dir]} {lappend auto_path $appinit_dir}
}
create_project rvcpu_hdmi [file join $build_dir rvcpu_hdmi] -part xc7z020clg400-2 -force
set rtl_files [glob -nocomplain [file join $root src rtl core *.v] \
                               [file join $root src rtl general *.v] \
                               [file join $root src rtl mems *.v] \
                               [file join $root src rtl soc *.v] \
                               [file join $root src rtl video *.v] \
                               [file join $root src rtl fpga *.v]]
add_files -norecurse $rtl_files
add_files -norecurse [file join $root src riscv-tests gpu_demo.hex]
set_property file_type {Memory Initialization Files} [get_files gpu_demo.hex]
set_property include_dirs [list [file join $root src rtl core]] [current_fileset]
add_files -fileset constrs_1 -norecurse [file join $root vivado rvcpu_hdmi.xdc]
set_property top rvcpu_fpga_top [current_fileset]

# 50 MHz 板载时钟生成 25 MHz 像素时钟和 125 MHz OSERDES DDR 时钟。
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 \
          -module_name rvcpu_hdmi_clk_wiz
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {50.000} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
    CONFIG.RESET_TYPE {ACTIVE_HIGH} \
    CONFIG.USE_LOCKED {true}] [get_ips rvcpu_hdmi_clk_wiz]
generate_target all [get_ips rvcpu_hdmi_clk_wiz]
export_ip_user_files -of_objects [get_ips rvcpu_hdmi_clk_wiz] -no_script -sync -force -quiet

update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
report_utilization -file [file join $build_dir utilization_synth.rpt]
report_timing_summary -file [file join $build_dir timing_synth.rpt]
puts "RVC_VIVADO_SYNTHESIS_COMPLETED"

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1
report_utilization -file [file join $build_dir utilization_impl.rpt]
report_timing_summary -file [file join $build_dir timing_impl.rpt]
report_drc -file [file join $build_dir drc_impl.rpt]
set bit_src [file join $build_dir rvcpu_hdmi rvcpu_hdmi.runs impl_1 rvcpu_fpga_top.bit]
if {![file exists $bit_src]} {error "Implementation completed without bitstream: $bit_src"}
file copy -force $bit_src [file join $build_dir rvcpu_fpga_top.bit]
puts "RVC_VIVADO_IMPLEMENTATION_COMPLETED"
