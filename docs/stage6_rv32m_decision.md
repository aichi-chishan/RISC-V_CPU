# 第六阶段：扩展指令决策与 RV32M

本阶段选择标准 RV32M，而不是私有图形指令。理由如下：

- GCC/LLVM 可直接用 `-march=rv32im_zicsr` 生成代码，不需要维护私有工具链；
- MUL/DIV 对游戏坐标、碰撞检测、随机数、定时换算和帧缓冲地址计算有直接收益；
- FPGA DSP 能高效实现乘法，除法适合共享迭代器；
- 与 E203 的 MULDIV 长指令思路一致：长操作占据执行单元，年轻指令停止，较老
  MEM/WB 继续排空，并在统一写回口提交结果。

## 实现

支持 MUL、MULH、MULHSU、MULHU、DIV、DIVU、REM、REMU。乘法结果寄存一拍；
除法采用 32 拍 restoring 迭代算法。除零和 `INT_MIN / -1` 严格遵循 RISC-V ISA，
不会错误地产生异常。MDU 输入使用与 ALU 相同的前推值，输出也通过普通 EX/MEM、
MEM/WB 路径前推，因此紧随 MDU 的消费者无需额外软件 NOP。

中断在 MDU 完成边界进入，避免半条除法指令提交。更老的 MEM access fault 仍可
优先杀死尚未提交的年轻 MDU。

## 暂不加入的扩展

- RV32C：有利于代码密度，但需要 IF 半字对齐、跨字取指和预测 PC 步长重构，建议
  在加入取指缓冲/缓存时统一实施；
- RV32A：当前是单 Hart、无 DMA 一致性需求，优先级低于显示 DMA 架构；
- RV32F：资源和软件 ABI 成本较高，小游戏使用定点数更合适；
- 私有 SIMD/像素指令：应先用性能计数器证明热点，再决定是否通过协处理器接口加入。

## 验证

```powershell
vsim -c -do sim/run_stage6.do
```

覆盖八条指令、正负混合高位乘法、除零、规范溢出和 MDU RAW 前推，并检查除法器
确实经历多拍 busy。成功标志为 `RV32M_TEST_PASSED`。
