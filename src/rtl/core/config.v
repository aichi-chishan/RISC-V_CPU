`ifndef RVC_CONFIG_V
`define RVC_CONFIG_V

//==============================================================================
// Designer   : [你的名字]
//
// Description:
//   config.v — 顶层参数配置文件
//   这是你项目中唯一需要手动修改参数的地方。
//   所有其他模块通过 `include "defines.v"` 自动获取派生参数。
//
// 用法：
//   开启某个功能 → 取消对应 `define 的注释
//   关闭某个功能 → 注释掉对应 `define
//   修改数值     → 修改 `define 后面的值
//
// 当前阶段 (Phase 1) : 多周期处理器 (5 周期完成一条指令, 阶段间有流水寄存器)
//==============================================================================

//==============================================================================
// 一、ISA 基本配置
//==============================================================================
`define RVC_CFG_ADDR_WIDTH    32    // 地址总线宽度 (32位)
`define RVC_CFG_XLEN          32    // 通用寄存器 / 数据宽度

//==============================================================================
// 二、存储器配置 (Phase 1 用 Verilog 数组模拟)
//==============================================================================
// 教学上板默认只分配 4 KB，避免组合读 reg 数组消耗大量 LUT RAM。
// 接入同步 BRAM/总线后可在这里直接增大容量，其他模块无需修改。
`define RVC_CFG_IMEM_SIZE_KB  4     // 指令存储器大小 (KB)
`define RVC_CFG_DMEM_SIZE_KB  4     // 数据存储器大小 (KB)

//==============================================================================
// 三、功能开关 (按 Phase 逐步开启)
//==============================================================================

// --- Phase 1: 多周期处理器 (当前阶段) ---
//     每条指令 5 个周期 (IF/ID/EX/MEM/WB)
//     阶段间用流水寄存器连接, 每次只有 1 条指令
//     不需要分支预测、前推、冲突检测
`define RVC_CFG_MULTI_CYCLE          // 【多周期模式】注释掉即回到单周期模式
`define RVC_CFG_CYCLES_PER_INSTR 5   // 每条指令的周期数

// --- Phase 2: 五级流水 (未来开启) ---
// `define RVC_CFG_PIPELINE_5STAGE   // 允许多条指令并发执行
// `define RVC_CFG_HAS_FORWARDING    // 前推逻辑 (解决 RAW 冲突)
// `define RVC_CFG_HAS_HAZARD        // 流水线冲突检测 + 阻塞 + 冲刷

// --- Phase 3: 总线与外设 ---
// `define RVC_CFG_HAS_BUS_ICB       // ICB 总线协议
// `define RVC_CFG_HAS_ITCM          // 指令紧耦合存储器 (同步读 SRAM)
// `define RVC_CFG_HAS_DTCM          // 数据紧耦合存储器
// `define RVC_CFG_HAS_PERIPHERALS   // UART, GPIO, SPI 等外设

// --- Phase 4: CSR / 异常 / 中断 ---
// `define RVC_CFG_HAS_CSR           // CSR 寄存器 + CSR 指令
// `define RVC_CFG_HAS_EXCEPTION     // 异常处理 (ecall/ebreak/非法指令/非对齐)
// `define RVC_CFG_HAS_INTERRUPT     // 中断处理 (timer/software/external)
// `define RVC_CFG_HAS_MULDIV        // M 扩展 (乘除法, 多周期)

// --- 未来扩展 ---
// `define RVC_CFG_HAS_AMO           // A 扩展 (原子指令)
// `define RVC_CFG_HAS_RVC           // C 扩展 (16位压缩指令)
// `define RVC_CFG_HAS_FPU           // F/D 扩展

//==============================================================================
// 四、地址空间布局 (Phase 3 使用, 参考 E203 config.v)
//==============================================================================
// `define RVC_CFG_IMEM_BASE_ADDR   32'h0000_0000
// `define RVC_CFG_DMEM_BASE_ADDR   32'h1000_0000
// `define RVC_CFG_PPI_BASE_ADDR    32'h2000_0000
// `define RVC_CFG_CLINT_BASE_ADDR  32'h0200_0000

`endif
