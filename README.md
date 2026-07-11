# RV32I 多周期处理器

本工程实现一个按 IF、ID、EX、MEM、WB 五个节拍执行的 RV32I 处理器。当前每次只执行一条指令，CPI 固定为 5，因此暂时不需要前推、阻塞和流水线冲刷。指令存储器采用组合读 `reg` 数组，数据存储器采用组合读、带字节掩码的同步写 `reg` 数组；不实现 CSR、异常和中断。

## 模块划分

- `rvcpu_sequencer.v`：保存 PC，产生五个执行节拍，并在 WB 后更新 PC。
- `rvcpu_decode.v`：译码 RV32I，将控制信息打包到 `dec_info` 总线。
- `rvcpu_regfile.v`：32×32 位寄存器堆，x0 恒为零。
- `rvcpu_*_stage.v`：分别实现五个阶段的组合逻辑。
- `rvcpu_imem.v`、`rvcpu_dmem.v`：仿真用简单存储器。
- `rvcpu_top.v`：连接阶段数据寄存器、控制器和存储器。
- `rvcpu_pipeline_reg.v`：支持 valid/ready、阻塞和 flush 的弹性流水寄存器。
- `rvcpu_hazard_unit.v`：为五级流水预留的前推和 Load-use 冒险控制。
- `rvcpu_fpga_top.v`：复位同步、ROM 初始化参数和 Vivado ILA 调试出口。

代码结构借鉴蜂鸟 E203 的 `config/defines` 分层、译码信息总线、模块职责划分和简洁注释方式；本工程没有照搬 E203 的流水握手、总线、CSR 或异常系统。

## 仿真

在工程根目录执行：

```bash
bash src/scripts/build.sh simulate
```

也可以在 PowerShell 中执行：

```powershell
New-Item -ItemType Directory -Force build | Out-Null
iverilog -g2012 -s rvcpu_tb -o build/rvcpu_tb.vvp -f src/filelist.f
Push-Location build; vvp ./rvcpu_tb.vvp; Pop-Location
```

冒烟程序最终向数据存储器字节地址 `0x100` 写入 `1`，测试平台打印 `TEST PASSED`。

ModelSim/Questa 批处理：

```bash
bash src/scripts/build.sh modelsim
```

脚本位于 `src/scripts/modelsim.do`。本机 ModelSim 2020.4 已验证全部文件编译为
`0 errors, 0 warnings`；如果仿真启动时报 `Unable to checkout qhsimvl/msimhdlsim`，
需要先修复本机 ModelSim 许可证，RTL 编译本身不受影响。

Vivado 上板顶层为 `rvcpu_fpga_top`，当前工程器件是 `xc7z020clg400-2`。生成
bitstream 前必须根据具体开发板补充时钟周期和引脚 XDC；`debug_*` 信号可直接
加入 ILA。`src/scripts/vivado_synth.tcl` 用于无约束综合检查。

## VS Code 跳转配置

扩展 `mshr-h.veriloghdl` 1.28.1 已删除旧版 ctags 索引，跨文件定义、悬停、引用和跳转由 `slang-server` 完成。本机实测 bundled WASM 在连续打开文档后会停止响应，因此工程固定使用官方 native `slang-server` 0.2.5：

- `.vscode/settings.json`：启用 `.tools/slang-server/slang-server.exe`，并保留 xvlog 单文件检查。
- `.slang/server.json`：指定工程 filelist、索引目录和 include 路径。
- `src/filelist.f`：列出全部 RTL 与测试平台文件。

修改配置后，在 VS Code 命令面板执行 `Developer: Reload Window`。状态栏应显示 `slang-server: native`；若仍异常，执行 `Verilog: Doctor` 和 `Verilog: Show slang-server Output`。源码中的 include 使用显式相对路径，因此文件路径、跨文件模块、宏和信号定义均可 Ctrl+左键跳转。
