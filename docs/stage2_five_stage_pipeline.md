# 第二阶段：真正的五级流水

本阶段把原先“每条指令固定占用五拍”的多周期调度替换为 IF、ID、EX、MEM、WB
并行工作的五级流水。每组流水寄存器都有独立 `valid` 位，气泡、停顿和冲刷不再
依赖把某条合法指令伪装成 NOP。

## 控制与冒险策略

- 数据冒险：EX/MEM 前推优先于 MEM/WB；Store 数据和分支比较操作数也使用同一套前推。
- Load-Use：消费者在 ID 停一拍，同时向 ID/EX 注入气泡，较老阶段继续前进。
- WB/ID 同拍冲突：ID 端显式写优先旁路，行为不依赖 FPGA RAM 的 read-during-write 模式。
- 控制优先级：复位、预测失败冲刷、Load-Use 停顿、正常推进，顺序不可交换。
- 精确副作用：只有 `valid` 的 MEM 指令可写 DMEM 或 LED，只有 `valid` 的 WB 指令可写寄存器堆。

## 静态分支预测

条件分支使用 BTFNT（Backward Taken, Forward Not Taken）：立即数符号位为 1 的后向
分支预测跳转，前向分支预测不跳转。JAL 的目标只依赖 PC 和立即数，因此在 IF 预测
跳转；JALR 目标依赖寄存器值，当前实现预测不跳转并在 EX 纠正。预测元数据随指令
进入 ID/EX，EX 比较预测下一 PC 与实际下一 PC；不一致时仅冲刷两条更年轻的指令。

这种结构借鉴 E203 的分支早期预测、流水 valid 语义和冲刷边界，但保留了本项目清晰
的五级教学流水划分。第三阶段会进一步把存储器边界改造成 E203 ICB 风格的命令/响应接口。

## 仿真

在仓库根目录分别运行：

```powershell
vsim -c -do sim/run_stage2.do
vsim -c -do sim/run_rv32i.do
```

两个脚本分别执行流水定向回归和完整 RV32I 指令回归。成功标志分别为
`RV32I_TEST_PASSED` 与 `PIPELINE_TEST_PASSED`。
