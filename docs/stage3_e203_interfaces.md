# 第三阶段：参考 E203 重构接口

本阶段把流水执行主体命名为 `rvcpu_core`，并把指令、数据存储器从核心中移出。
核心边界采用 E203 ICB 风格的两组 command/response 通道：

- IFU：`cmd_valid/ready/addr` 与 `rsp_valid/ready/rdata/err`；
- LSU：在上述信号外增加 `read`、`wdata` 和四位字节写掩码 `wmask`；
- 所有地址在核心边界均为 32 位字节地址，存储宏的字地址截取只出现在包装层；
- Store 副作用由命令握手提交，未对齐 Store 和 LED MMIO 不会误发到片内 RAM。

`rvcpu_top` 保留原有端口，作为零等待片内 IMEM/DMEM 的兼容包装层，因此 FPGA
顶层不需要同步改端口。总线、缓存或 AXI 桥可以改为直接实例化 `rvcpu_core`。

## 当前契约和后续工作

当前核心采用零等待从设备契约，即包装层在命令握手同一周期产生响应。这一步的目标
是先稳定模块职责和总线边界，不虚假声称已经支持任意延迟。若后续连接 AXI，应增加
IFU 请求队列、LSU 单 outstanding 状态机，并把反压逐级接入流水 `valid/ready`；现有
端口定义无需改变。`ifu_rsp_err/lsu_rsp_err` 已预留，异常阶段可将其接入精确异常提交。

运行接口回归：

```powershell
vsim -c -do sim/run_stage3.do
```

成功标志为 `ICB_TEST_PASSED`。第二阶段的两套回归仍应同时通过。
