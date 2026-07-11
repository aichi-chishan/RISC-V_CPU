# 将当前 CPU 源码正式加入已有 vivado/cpu.xpr。
set root [file normalize [file join [file dirname [info script]] ../..]]
set project_file [file join $root vivado cpu.xpr]

open_project $project_file

set design_files [list \
    [file join $root src rtl core rvcpu_decode.v] \
    [file join $root src rtl core rvcpu_regfile.v] \
    [file join $root src rtl core rvcpu_immgen.v] \
    [file join $root src rtl core rvcpu_if_stage.v] \
    [file join $root src rtl core rvcpu_id_stage.v] \
    [file join $root src rtl core rvcpu_ex_stage.v] \
    [file join $root src rtl core rvcpu_mem_stage.v] \
    [file join $root src rtl core rvcpu_wb_stage.v] \
    [file join $root src rtl core rvcpu_pipeline_reg.v] \
    [file join $root src rtl core rvcpu_hazard_unit.v] \
    [file join $root src rtl core rvcpu_sequencer.v] \
    [file join $root src rtl core rvcpu_top.v] \
    [file join $root src rtl mems rvcpu_imem.v] \
    [file join $root src rtl mems rvcpu_dmem.v] \
    [file join $root src rtl fpga rvcpu_fpga_top.v]]

set sim_files [list [file join $root src tb rvcpu_tb.v]]
set hex_file [file join $root src riscv-tests smoke_test.hex]

# add_files 会自动忽略已经存在的同一路径，脚本可以重复运行。
add_files -fileset sources_1 -norecurse $design_files
add_files -fileset sources_1 -norecurse $hex_file
set_property file_type {Memory Initialization Files} [get_files $hex_file]

add_files -fileset sim_1 -norecurse $sim_files
add_files -fileset sim_1 -norecurse $hex_file

set include_dirs [list \
    [file join $root src rtl core] \
    [file join $root src rtl general] \
    [file join $root src rtl mems] \
    [file join $root src rtl fpga] \
    [file join $root src tb]]
set_property include_dirs $include_dirs [get_filesets sources_1]
set_property include_dirs $include_dirs [get_filesets sim_1]

set_property top rvcpu_fpga_top [get_filesets sources_1]
set_property top rvcpu_tb       [get_filesets sim_1]
set_property top_auto_set 0     [get_filesets sources_1]
set_property top_auto_set 0     [get_filesets sim_1]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "RVC_PROJECT_UPDATE_PASSED"
puts "SYNTH_TOP=[get_property top [get_filesets sources_1]]"
puts "SIM_TOP=[get_property top [get_filesets sim_1]]"
close_project
