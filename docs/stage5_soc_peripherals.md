# 第五阶段：SoC 外设

本阶段将 MMIO 地址译码从 CPU 数据通路移到 `rvcpu_top` SoC 包装层。CPU 只产生
ICB 风格 LSU 事务，各外设仅在 `cmd_valid && cmd_ready` 时提交副作用。

## 地址映射

| 地址范围 | 外设 | 寄存器 |
|---|---|---|
| `0x0000_0000` 起 | 片内 DMEM | 容量由 `RVC_CFG_DMEM_SIZE_KB` 决定 |
| `0x0200_0000` | CLINT | MSIP |
| `0x0200_4000/4004` | CLINT | MTIMECMP low/high |
| `0x0200_BFF8/BFFC` | CLINT | MTIME low/high |
| `0x4000_0000` | GPIO | OUT |
| `0x4000_0004` | GPIO | OE |
| `0x4000_0008` | GPIO | IN |
| `0x4000_1000` | UART | TXDATA |
| `0x4000_1004` | UART | STATUS：TX ready/busy、RX valid |
| `0x4000_1008` | UART | BAUDDIV |
| `0x4000_100C` | UART | RXDATA |

UART 实现可编程波特率的 8N1 收发器；RX 输入经过双触发器同步，在起始位中点
确认后逐位采样。CLINT 为单 Hart，产生机器软件和机器定时器中断。GPIO 支持
32 位 OUT/OE/IN 和逐字节写掩码，原 LED 地址保持为 GPIO OUT，因此旧软件兼容。

所有地址采用完整 32 位译码，MMIO 不会因截取低地址而写坏 DMEM。未映射访问返回
bus error；错误在 MEM 级作为精确 Load/Store access fault 提交，优先级高于年轻
EX 指令，故年轻 CSR/Store 不会在较老访问失败后产生副作用。

## 验证

```powershell
vsim -c -do sim/run_stage5.do
```

回归覆盖 GPIO 读写、UART TX/RX 完整 8N1 帧、可编程 BAUDDIV、CLINT MSIP、
MTIME/MTIMECMP，以及未映射 Load 的精确异常。成功标志为 `SOC_TEST_PASSED`。
