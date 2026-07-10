# RISC-V CPU 项目

## 项目概述

从零设计一个 32 位 RISC-V 处理器，**以经典五级流水为目标，在 Phase 1 实现单周期版本**。支持 RV32I 基本整数指令集。

## 核心设计哲学

**单周期就是五级流水的"退化"版本** — 五级流水的阶段之间去掉流水寄存器就是单周期：

```
Phase 1 (单周期):    IF ─▶ ID ─▶ EX ─▶ MEM ─▶ WB    (组合逻辑链)
Phase 2 (五级流水):  IF → | IF/ID | → ID → | ID/EX | → EX → | EX/MEM | → MEM → | MEM/WB | → WB
```

每个阶段模块 (`*_stage.v`) 是纯组合逻辑（除 PC 和写端口），Phase 2 只需在阶段间插入流水寄存器 + 前推/阻塞逻辑。

## 借鉴 E203 的设计模式

| E203 模式 | 本项目对应 | 说明 |
|-----------|-----------|------|
| dec_info 译码总线 | `defines.v` 位域定义 + `rvcpu_decode.v` | 宽位宽控制总线，贯穿全部阶段 |
| config.v + defines.v 双层宏 | `config.v` (用户) + `defines.v` (派生) | 参数一处改、全局生效 |
| valid/ready 握手 | 每个阶段模块的 i_valid/o_valid | 为流水线反压做准备 |
| 功能单元分工 (IFU/EXU/LSU/BIU) | 五阶段 (IF/ID/EX/MEM/WB) | 按流水级分模块而非按功能分 |

## 目录结构

```
src/
├── rtl/core/
│   ├── config.v              ← 参数配置（你修改参数的地方）
│   ├── defines.v             ← 派生宏 + dec_info 位域定义
│   ├── rvcpu_if_stage.v      ← IF: 取指阶段
│   ├── rvcpu_id_stage.v      ← ID: 译码 + 寄存器堆读
│   ├── rvcpu_ex_stage.v      ← EX: ALU + 分支判定
│   ├── rvcpu_mem_stage.v     ← MEM: 数据存储器访问
│   ├── rvcpu_wb_stage.v      ← WB: 写回选择
│   ├── rvcpu_decode.v        ← 译码器（纯组合逻辑）
│   ├── rvcpu_regfile.v       ← 寄存器堆（复用你的 regfile.v）
│   ├── rvcpu_immgen.v        ← 立即数生成器（纯组合逻辑）
│   └── rvcpu_top.v           ← 顶层：连接 5 个阶段 + 存储器
├── rtl/mems/
│   ├── rvcpu_imem.v          ← 指令存储器（组合读）
│   └── rvcpu_dmem.v          ← 数据存储器（组合读 + 时序写）
├── tb/
│   └── rvcpu_tb.v            ← 主测试平台
├── riscv-tests/
│   ├── smoke_test.hex        ← 冒烟测试
│   └── smoke_test.S          ← 测试汇编源码
└── scripts/
    └── build.sh              ← 编译/仿真脚本
```

## 推荐实现顺序

从简单到复杂，每个模块都能独立验证：

| # | 模块 | 复杂度 | 说明 |
|---|------|--------|------|
| 1 | `rvcpu_regfile.v` | ⭐ | 已有代码直接复用 |
| 2 | `rvcpu_immgen.v` | ⭐ | 6 种格式，纯组合逻辑 |
| 3 | `rvcpu_decode.v` | ⭐⭐⭐ | **最核心**，47 条指令译码 |
| 4 | `rvcpu_if_stage.v` | ⭐⭐ | PC 寄存器 + IMEM 接口 |
| 5 | `rvcpu_id_stage.v` | ⭐⭐ | 例化 decode + regfile + immgen |
| 6 | `rvcpu_ex_stage.v` | ⭐⭐⭐ | ALU + 分支判定 |
| 7 | `rvcpu_mem_stage.v` | ⭐⭐ | DMEM 读写 + 对齐/扩展 |
| 8 | `rvcpu_wb_stage.v` | ⭐ | 写回 MUX |
| 9 | `rvcpu_imem.v` + `rvcpu_dmem.v` | ⭐ | 存储器 |
| 10 | `rvcpu_top.v` | ⭐⭐ | 顶层连线 |
| 11 | `rvcpu_tb.v` | ⭐⭐ | 测试平台 |

## 快速开始

```bash
# 语法检查
bash src/scripts/build.sh compile

# 运行仿真（需要 iverilog）
bash src/scripts/build.sh simulate

# 查看波形
bash src/scripts/build.sh wave

# 清理
bash src/scripts/build.sh clean
```

## 参考设计

- 蜂鸟 E203: `D:\Project\e203_hbirdv2\rtl\e203`
- RISC-V 规范: https://riscv.org/technical/specifications/
