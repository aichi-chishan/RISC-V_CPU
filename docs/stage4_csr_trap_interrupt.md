# 第四阶段：CSR、异常与中断

本阶段实现 RV32 机器模式的最小完整特权闭环，并保持五级流水的精确提交语义。
设计参考 E203 的 CSR 集中管理、异常优先级编码和“下一条未提交指令 PC”中断
保存原则，但使用适合本项目五级流水的 EX 提交边界。

## 已实现功能

- Zicsr：CSRRW、CSRRS、CSRRC、CSRRWI、CSRRSI、CSRRCI；
- Machine CSR：mstatus、mie、mtvec、mscratch、mepc、mcause、mtval、mip；
- 计数器：mcycle/mcycleh、minstret/minstreth；
- 只读标识 CSR：mvendorid、marchid、mimpid、mhartid；
- 同步异常：指令地址未对齐、取指访问错误、非法指令、EBREAK、Load/Store
  地址未对齐、Load/Store 访问错误、M-mode ECALL；
- 机器软件、定时器、外部中断，固定优先级 external > software > timer；
- Direct 模式 mtvec 和 MRET；进入 trap 时保存 MIE 到 MPIE，MRET 时恢复。

异常指令不会进入 EX/MEM，因此不能写寄存器或存储器。中断在有效指令边界进入，
`mepc` 保存尚未执行的指令 PC；同步异常保存故障指令 PC。trap 和 MRET 都冲刷
IF/ID、ID/EX，较老的 MEM/WB 指令仍能完成，符合顺序核的精确异常要求。

CSR 文件只使用一个时序块更新状态，优先级为 trap、MRET、普通 CSR 写。CSRRS/
CSRRC 的源为零时按规范视为纯读，不会对只读 CSR 错误地产生写异常。

## 验证

```powershell
vsim -c -do sim/run_stage4.do
```

测试覆盖六条 Zicsr 指令语义、非法指令、ECALL、EBREAK、未对齐 Load、三类机器
中断的优先级和连续服务，以及 MRET 返回。成功标志为 `TRAP_TEST_PASSED`。

当前片内存储器包装层是零等待且不产生 bus error；访问错误通路已保留在核心接口。
连接可返回错误的异步总线时，还应把 LSU 响应异常与未来 outstanding 状态机统一提交。
