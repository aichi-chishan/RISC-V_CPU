# HDMI 小显卡架构

## 架构目标

显示子系统不是固定彩条发生器，而是 CPU 可编程的 RGB565 帧缓冲：

- 逻辑分辨率 320×240，每像素 16 位，帧缓冲 153600 字节；
- 显示端以 2×整数缩放输出 640×480，像素时钟 25 MHz；
- CPU 通过 `0x5000_0000` write-only 窗口用 SB/SH/SW 绘图；
- 控制寄存器位于 `0x4000_2000`，包含 enable、vblank IRQ、状态和背景色；
- 帧缓冲为双时钟 Block RAM，CPU 写口和像素读口互不阻塞；
- vblank 用 toggle 跨时钟域返回系统时钟域，避免窄脉冲丢失；
- RGB 经三个独立 TMDS 编码器、OSERDESE2 10:1 DDR 串化和 OBUFDS 输出 HDMI。

最终实现使用 38 个 RAMB36（27.14%），适合 XC7Z020，并保留足够 BRAM 给程序、数据和以后
的精灵表。CPU 逐像素读取帧缓冲会破坏 BRAM 同步读推导，因此窗口刻意定义为
write-only；软件用 16 位 Store 即可修改单个像素，不需要 read-modify-write。

## MMIO

| 地址 | 功能 |
|---|---|
| `0x4000_2000` | CTRL：bit0 enable，bit1 vblank IRQ enable |
| `0x4000_2004` | STATUS：bit0 vblank pending，写 1 清除 |
| `0x4000_2008` | SIZE：高 16 位 240，低 16 位 320 |
| `0x4000_200C` | BACKGROUND：显示关闭时的 RGB888 背景 |
| `0x5000_0000..0x5002_57FF` | 320×240 RGB565 framebuffer |

[rvcpu_soc.h](../sw/include/rvcpu_soc.h) 提供寄存器和像素 API，
[gpu_snake_demo.c](../sw/examples/gpu_snake_demo.c) 给出 CPU 驱动的移动蛇形演示。

## 板卡与 Vivado

板卡和管脚来自用户提供的 `24_hdmi_block_move`、`19_uart_loopback` 与
`10_flow_led` 配套例程：器件 `xc7z020clg400-2`，50 MHz 时钟 U18，HDMI 数据
P 端 G19/K19/J20，时钟 P 端 J18。Clocking Wizard 生成 25 MHz 与 125 MHz；
125 MHz 通过 DDR OSERDES 提供 250 Mb/s TMDS 位率。

创建工程并综合：

```powershell
vivado -mode batch -source vivado/create_hdmi_project.tcl
```

若 Vivado 2025.1 报 `Common 17-1297` 或 `Common 17-685`，当前用户 Tcl Store
索引已损坏。关闭 Vivado 后运行：

```powershell
vivado -mode batch -source vivado/repair_tclstore.tcl
```

然后重新运行建工程脚本。修复脚本只调用 `tclapp::reset_tclstore` 重建用户索引。

## 验证

- `sim/run_gpu.do`：完整一帧检查 307200 个活动像素、96/2 行列同步宽度、
  RGB565 读取、2×缩放、vblank CDC 和 TMDS 编码；
- `sim/run_gpu_cpu.do`：CPU 经真实五级流水、LSU 和 SoC 译码写帧缓冲并启用显示；
- `sim/run_all.ps1`：运行阶段一至 HDMI 的全部 ModelSim 回归。

ModelSim 成功标志为 `GPU_TEST_PASSED` 和 `GPU_CPU_TEST_PASSED`。板级完成仍应以
Vivado synthesis/implementation timing、DRC 和显示器实测为最终门槛。

本次 Vivado 2025.1 实现结果：综合和实现均为 0 Error、0 Critical Warning；CPU 50 MHz
时钟分析了 9507 个端点，WNS 4.436 ns、WHS 0.059 ns；25 MHz 像素时钟 WNS 28.394 ns、
WHS 0.121 ns，所有用户时序约束均满足。资源占用为 3794 LUT（7.13%）、1685 寄存器
（1.58%）和 38 个 RAMB36（27.14%）。`ZPS7-1` 是本工程仅使用 Zynq PL、未实例化 PS7
时产生的唯一 DRC Warning，不妨碍通过 JTAG 配置 PL；若以后从 PS 启动，应加入 PS7 与启动工程。
最终位流位于 `build/vivado/rvcpu_fpga_top.bit`。
