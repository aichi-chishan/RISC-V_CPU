# Vivado 2025.1 报 Common 17-1297/17-685 时使用。该命令仅重建当前用户的
# Xilinx Tcl Store 索引，不修改工程源码或 Vivado 安装目录。
if {[info exists ::env(XILINX_VIVADO)]} {
    set appinit_dir [file join $::env(XILINX_VIVADO) data XilinxTclStore support appinit]
    if {[file isdirectory $appinit_dir]} {lappend auto_path $appinit_dir}
}
package require ::tclapp::support::appinit 1.2
tclapp::reset_tclstore
puts "RVC_TCLSTORE_RESET_COMPLETED"
exit
