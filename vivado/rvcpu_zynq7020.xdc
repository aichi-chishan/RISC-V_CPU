# 正点原子领航者(V2) ZYNQ-7020 配套例程的时钟、复位和 LED 引脚。
# 50 MHz oscillator on U18, active-low reset on N16, two board LEDs on H15/L15.
create_clock -period 20.000 -name sys_clk -waveform {0.000 10.000} [get_ports sys_clk]

set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports sys_clk]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports reset_n]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN L15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
