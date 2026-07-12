# 正点原子领航者 V2（XC7Z020-CLG400-2），管脚来自配套 flow_led、UART、HDMI 例程。
# Clocking Wizard 会在其局部 clk_in1 上自动创建 50 MHz 时钟，但综合后
# CPU 所使用的顶层直连分支不会被该局部约束覆盖。这里用 -add 建立同频的
# CPU 时钟；-add 可保留 IP 已创建的时钟，避免 Constraints 18-1056 覆盖告警。
create_clock -add -period 20.000 -name cpu_sys_clk [get_ports sys_clk]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33 PULLUP true} [get_ports reset_n]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T19 IOSTANDARD LVCMOS33} [get_ports uart_rx]
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports uart_tx]

# HDMI 差分对只约束 P 端物理管脚，N 端由 OBUFDS 自动使用配对管脚。
set_property -dict {PACKAGE_PIN G19 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[0]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[1]}]
set_property -dict {PACKAGE_PIN J20 IOSTANDARD TMDS_33} [get_ports {tmds_data_p[2]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD TMDS_33} [get_ports tmds_clk_p]

# OSERDES 输出由 Clocking Wizard 的专用时钟资源驱动。

# 配置寄存器和 vblank toggle 通过显式两级同步器跨域，只切断到第一级的路径。
set_false_path -to [get_pins -hier -regexp {.*u_gpu/vblank_sync_reg\[0\]/D}]
set_false_path -to [get_pins -hier -regexp {.*u_gpu/enable_sync_reg\[0\]/D}]
set_false_path -to [get_pins -hier -regexp {.*u_gpu/background_q1_reg\[[0-9]+\]/D}]
