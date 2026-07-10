//==============================================================================
// Designer   : [your name]
//
// Description:
//   defines.v — 派生宏定义文件
//   ===== 这是整个项目的"宪法"，请先理解再动手 =====
//
//   此文件自动从 config.v 派生出所有宏定义。
//   每个模块开头 `include "defines.v"` 即可使用所有宏。
//
// 核心设计 (从 E203 借鉴):
//   1. 双层宏体系: config.v (用户级) → defines.v (派生级)
//   2. 译码信息总线 (dec_info): 将译码结果打包为宽位宽信号
//   3. 位域 LSB/MSB 定位法: 每个字段用 LSB/MSB/POS 三元组定义位置
//
// 参考设计：E203 e203_defines.v — 完整展示了位域定义的最佳实践
//==============================================================================

`include "config.v"

//==============================================================================
// 一、ISA 宽度宏 — 从 config.v 派生
//==============================================================================
`define RVC_ADDR_WIDTH     `RVC_CFG_ADDR_WIDTH
`define RVC_PC_WIDTH       `RVC_CFG_ADDR_WIDTH      // PC 宽度 = 地址宽度
`define RVC_XLEN           `RVC_CFG_XLEN            // 通用寄存器 / 数据宽度 = 32
`define RVC_XLEN_MW        (`RVC_CFG_XLEN / 8)      // 字节数 = 4
`define RVC_INSTR_WIDTH    32                        // RV32I 指令固定 32 位

//==============================================================================
// 二、寄存器堆参数
//==============================================================================
`define RVC_RFIDX_WIDTH    5                         // log2(32) = 5
`define RVC_RFREG_NUM      32                        // RV32I: 32 个通用寄存器

//==============================================================================
// 三、存储器地址宽度 — 从 IMEM/DMEM 大小计算
//==============================================================================
// 说明: 存储器按 32 位 (4 字节) 编址
//   深度 = (SIZE_KB * 1024) / 4
//   地址宽度 = $clog2(深度)
`define RVC_IMEM_DEPTH     ((`RVC_CFG_IMEM_SIZE_KB * 1024) / 4)
`define RVC_IMEM_AW        $clog2(`RVC_IMEM_DEPTH)
`define RVC_DMEM_DEPTH     ((`RVC_CFG_DMEM_SIZE_KB * 1024) / 4)
`define RVC_DMEM_AW        $clog2(`RVC_DMEM_DEPTH)

//==============================================================================
// 四、译码信息总线 (dec_info) 位域定义
//
// 设计理念 (E203 核心模式):
//   译码是 ID 阶段的职责。它产出一个宽位宽的 dec_info 总线，
//   后续阶段 (EX/MEM/WB) 各自从中提取自己需要的字段。
//
//   位域分为两类:
//     (A) 通用字段 — 所有指令共享 (grp, rs1idx, rdwen, imm, pc, ...)
//     (B) 组子字段 — 每组内的独热码 (alu_add, alu_sub, lsu_load, bjp_beq, ...)
//
//   布局: [ 组子字段 (高位) | 通用字段 (低位) ]
//   每组子字段的起始位相同 (RVC_DECINFO_SUB_LSB)，
//   但各组子字段宽度不同，最终总线宽度取最宽组的长度。
//
//   为什么这么设计？
//     1. 通用字段是所有指令都需要的基础信息 → 放在固定低位
//     2. 组子字段是各组专属的控制位 → 放在高位，由组类型决定解释方式
//     3. 总线宽度由最宽的组决定 → 所有组共用一根总线，布线统一
//==============================================================================

//--------------------------------------------------------------------------
// 4.1 指令组编码 (Group, 3 bits)
// E203 将指令分为 7 个组，Phase 1 只用前 4 个
//--------------------------------------------------------------------------
`define RVC_DECINFO_GRP_WIDTH      3
`define RVC_DECINFO_GRP_ALU        3'd0    // 普通 ALU 指令 (R-type, I-type ALU, LUI, AUIPC)
`define RVC_DECINFO_GRP_LSU        3'd1    // Load / Store 指令
`define RVC_DECINFO_GRP_BJP        3'd2    // Branch / Jump 指令
`define RVC_DECINFO_GRP_SYS        3'd3    // ECALL / EBREAK / FENCE / MRET(Phase4)
// Phase 4: GRP_CSR  3'd4   CSR 指令
// Phase 4: GRP_MULDIV 3'd5 乘除指令

//--------------------------------------------------------------------------
// 4.2 通用字段位域 — dec_info 的低位部分，所有指令共享
//
// 位域定义范式 (E203 风格):
//   `define FIELD_LSB  <起始位号>
//   `define FIELD_MSB  (`FIELD_LSB + <位宽> - 1)
//   `define FIELD      `FIELD_MSB : `FIELD_LSB   ← 用于 Verilog 位选择
//--------------------------------------------------------------------------

// --- Group (3 bits) : 指令组编码 ---
`define RVC_DECINFO_GRP_LSB        0
`define RVC_DECINFO_GRP_MSB        (`RVC_DECINFO_GRP_LSB + `RVC_DECINFO_GRP_WIDTH - 1)
`define RVC_DECINFO_GRP            `RVC_DECINFO_GRP_MSB : `RVC_DECINFO_GRP_LSB

// --- RS1 Index (5 bits) : 源寄存器 1 地址 ---
`define RVC_DECINFO_RS1IDX_LSB     (`RVC_DECINFO_GRP_MSB + 1)
`define RVC_DECINFO_RS1IDX_MSB     (`RVC_DECINFO_RS1IDX_LSB + `RVC_RFIDX_WIDTH - 1)
`define RVC_DECINFO_RS1IDX         `RVC_DECINFO_RS1IDX_MSB : `RVC_DECINFO_RS1IDX_LSB

// --- RS2 Index (5 bits) : 源寄存器 2 地址 ---
`define RVC_DECINFO_RS2IDX_LSB     (`RVC_DECINFO_RS1IDX_MSB + 1)
`define RVC_DECINFO_RS2IDX_MSB     (`RVC_DECINFO_RS2IDX_LSB + `RVC_RFIDX_WIDTH - 1)
`define RVC_DECINFO_RS2IDX         `RVC_DECINFO_RS2IDX_MSB : `RVC_DECINFO_RS2IDX_LSB

// --- RD Index (5 bits) : 目标寄存器地址 ---
`define RVC_DECINFO_RDIDX_LSB      (`RVC_DECINFO_RS2IDX_MSB + 1)
`define RVC_DECINFO_RDIDX_MSB      (`RVC_DECINFO_RDIDX_LSB + `RVC_RFIDX_WIDTH - 1)
`define RVC_DECINFO_RDIDX          `RVC_DECINFO_RDIDX_MSB : `RVC_DECINFO_RDIDX_LSB

// --- RD Write Enable (1 bit) : 是否需要写回 rd ---
`define RVC_DECINFO_RDWEN_LSB      (`RVC_DECINFO_RDIDX_MSB + 1)
`define RVC_DECINFO_RDWEN_MSB      (`RVC_DECINFO_RDWEN_LSB)
`define RVC_DECINFO_RDWEN          `RVC_DECINFO_RDWEN_MSB : `RVC_DECINFO_RDWEN_LSB

// --- RS1 Read Enable (1 bit) : 是否需要读 rs1 ---
`define RVC_DECINFO_RS1EN_LSB      (`RVC_DECINFO_RDWEN_MSB + 1)
`define RVC_DECINFO_RS1EN_MSB      (`RVC_DECINFO_RS1EN_LSB)
`define RVC_DECINFO_RS1EN          `RVC_DECINFO_RS1EN_MSB : `RVC_DECINFO_RS1EN_LSB

// --- RS2 Read Enable (1 bit) : 是否需要读 rs2 ---
`define RVC_DECINFO_RS2EN_LSB      (`RVC_DECINFO_RS1EN_MSB + 1)
`define RVC_DECINFO_RS2EN_MSB      (`RVC_DECINFO_RS2EN_LSB)
`define RVC_DECINFO_RS2EN          `RVC_DECINFO_RS2EN_MSB : `RVC_DECINFO_RS2EN_LSB

// --- ALU Op1 Select (1 bit) : 0=RS1, 1=PC ---
// 用于 AUIPC 和 JAL/JALR 的地址计算
`define RVC_DECINFO_OP1SEL_LSB     (`RVC_DECINFO_RS2EN_MSB + 1)
`define RVC_DECINFO_OP1SEL_MSB     (`RVC_DECINFO_OP1SEL_LSB)
`define RVC_DECINFO_OP1SEL         `RVC_DECINFO_OP1SEL_MSB : `RVC_DECINFO_OP1SEL_LSB

// --- ALU Op2 Select (1 bit) : 0=RS2, 1=Immediate ---
`define RVC_DECINFO_OP2SEL_LSB     (`RVC_DECINFO_OP1SEL_MSB + 1)
`define RVC_DECINFO_OP2SEL_MSB     (`RVC_DECINFO_OP2SEL_LSB)
`define RVC_DECINFO_OP2SEL         `RVC_DECINFO_OP2SEL_MSB : `RVC_DECINFO_OP2SEL_LSB

// --- Write-Back Select (2 bits) : 写回数据来源 ---
// 00 = ALU 结果     (ADD, SUB, ADDI, LUI, AUIPC...)
// 01 = MEM 读数据   (LB, LH, LW, LBU, LHU...)
// 10 = PC + 4       (JAL, JALR — 保存返回地址)
`define RVC_DECINFO_WB_SEL_LSB     (`RVC_DECINFO_OP2SEL_MSB + 1)
`define RVC_DECINFO_WB_SEL_MSB     (`RVC_DECINFO_WB_SEL_LSB + 1)
`define RVC_DECINFO_WB_SEL         `RVC_DECINFO_WB_SEL_MSB : `RVC_DECINFO_WB_SEL_LSB
// WB_SEL 取值
`define RVC_WB_SEL_ALU   2'b00
`define RVC_WB_SEL_MEM   2'b01
`define RVC_WB_SEL_PC4   2'b10

// --- 立即数字段 (32 bits) : 已由译码阶段拼接好的立即数 ---
`define RVC_DECINFO_IMM_LSB        (`RVC_DECINFO_WB_SEL_MSB + 1)
`define RVC_DECINFO_IMM_MSB        (`RVC_DECINFO_IMM_LSB + 31)
`define RVC_DECINFO_IMM            `RVC_DECINFO_IMM_MSB : `RVC_DECINFO_IMM_LSB

// --- PC 字段 (32 bits) : 指令的 PC 值 ---
`define RVC_DECINFO_PC_LSB         (`RVC_DECINFO_IMM_MSB + 1)
`define RVC_DECINFO_PC_MSB         (`RVC_DECINFO_PC_LSB + `RVC_PC_WIDTH - 1)
`define RVC_DECINFO_PC             `RVC_DECINFO_PC_MSB : `RVC_DECINFO_PC_LSB

// --- 通用字段结束位 (也是组子字段的起始位) ---
`define RVC_DECINFO_GENERAL_END    `RVC_DECINFO_PC_MSB
`define RVC_DECINFO_SUB_LSB        (`RVC_DECINFO_GENERAL_END + 1)

//--------------------------------------------------------------------------
// 4.3 ALU 组子字段 — 独热码，每 bit 对应一个 ALU 操作
// 这些位从 RVC_DECINFO_SUB_LSB 开始
//
// 关键设计 (从 E203 学):
//   E203 将 NOP 也作为一个子操作编码 — 因为 NOP 的编码是 ADDI x0,x0,0,
//   译码器把它也分到了 ALU 组。所以在 ALU 模块中需要特殊屏蔽 NOP。
//--------------------------------------------------------------------------
`define RVC_DECINFO_ALU_ADD_LSB    `RVC_DECINFO_SUB_LSB
`define RVC_DECINFO_ALU_ADD_MSB    (`RVC_DECINFO_ALU_ADD_LSB)
`define RVC_DECINFO_ALU_ADD        `RVC_DECINFO_ALU_ADD_MSB : `RVC_DECINFO_ALU_ADD_LSB

`define RVC_DECINFO_ALU_SUB_LSB    (`RVC_DECINFO_ALU_ADD_MSB + 1)
`define RVC_DECINFO_ALU_SUB_MSB    (`RVC_DECINFO_ALU_SUB_LSB)
`define RVC_DECINFO_ALU_SUB        `RVC_DECINFO_ALU_SUB_MSB : `RVC_DECINFO_ALU_SUB_LSB

`define RVC_DECINFO_ALU_SLL_LSB    (`RVC_DECINFO_ALU_SUB_MSB + 1)
`define RVC_DECINFO_ALU_SLL_MSB    (`RVC_DECINFO_ALU_SLL_LSB)
`define RVC_DECINFO_ALU_SLL        `RVC_DECINFO_ALU_SLL_MSB : `RVC_DECINFO_ALU_SLL_LSB

`define RVC_DECINFO_ALU_SLT_LSB    (`RVC_DECINFO_ALU_SLL_MSB + 1)
`define RVC_DECINFO_ALU_SLT_MSB    (`RVC_DECINFO_ALU_SLT_LSB)
`define RVC_DECINFO_ALU_SLT        `RVC_DECINFO_ALU_SLT_MSB : `RVC_DECINFO_ALU_SLT_LSB

`define RVC_DECINFO_ALU_SLTU_LSB   (`RVC_DECINFO_ALU_SLT_MSB + 1)
`define RVC_DECINFO_ALU_SLTU_MSB   (`RVC_DECINFO_ALU_SLTU_LSB)
`define RVC_DECINFO_ALU_SLTU       `RVC_DECINFO_ALU_SLTU_MSB : `RVC_DECINFO_ALU_SLTU_LSB

`define RVC_DECINFO_ALU_XOR_LSB    (`RVC_DECINFO_ALU_SLTU_MSB + 1)
`define RVC_DECINFO_ALU_XOR_MSB    (`RVC_DECINFO_ALU_XOR_LSB)
`define RVC_DECINFO_ALU_XOR        `RVC_DECINFO_ALU_XOR_MSB : `RVC_DECINFO_ALU_XOR_LSB

`define RVC_DECINFO_ALU_SRL_LSB    (`RVC_DECINFO_ALU_XOR_MSB + 1)
`define RVC_DECINFO_ALU_SRL_MSB    (`RVC_DECINFO_ALU_SRL_LSB)
`define RVC_DECINFO_ALU_SRL        `RVC_DECINFO_ALU_SRL_MSB : `RVC_DECINFO_ALU_SRL_LSB

`define RVC_DECINFO_ALU_SRA_LSB    (`RVC_DECINFO_ALU_SRL_MSB + 1)
`define RVC_DECINFO_ALU_SRA_MSB    (`RVC_DECINFO_ALU_SRA_LSB)
`define RVC_DECINFO_ALU_SRA        `RVC_DECINFO_ALU_SRA_MSB : `RVC_DECINFO_ALU_SRA_LSB

`define RVC_DECINFO_ALU_OR_LSB     (`RVC_DECINFO_ALU_SRA_MSB + 1)
`define RVC_DECINFO_ALU_OR_MSB     (`RVC_DECINFO_ALU_OR_LSB)
`define RVC_DECINFO_ALU_OR         `RVC_DECINFO_ALU_OR_MSB : `RVC_DECINFO_ALU_OR_LSB

`define RVC_DECINFO_ALU_AND_LSB    (`RVC_DECINFO_ALU_OR_MSB + 1)
`define RVC_DECINFO_ALU_AND_MSB    (`RVC_DECINFO_ALU_AND_LSB)
`define RVC_DECINFO_ALU_AND        `RVC_DECINFO_ALU_AND_MSB : `RVC_DECINFO_ALU_AND_LSB

`define RVC_DECINFO_ALU_LUI_LSB    (`RVC_DECINFO_ALU_AND_MSB + 1)
`define RVC_DECINFO_ALU_LUI_MSB    (`RVC_DECINFO_ALU_LUI_LSB)
`define RVC_DECINFO_ALU_LUI        `RVC_DECINFO_ALU_LUI_MSB : `RVC_DECINFO_ALU_LUI_LSB

`define RVC_DECINFO_ALU_AUIPC_LSB  (`RVC_DECINFO_ALU_LUI_MSB + 1)
`define RVC_DECINFO_ALU_AUIPC_MSB  (`RVC_DECINFO_ALU_AUIPC_LSB)
`define RVC_DECINFO_ALU_AUIPC      `RVC_DECINFO_ALU_AUIPC_MSB : `RVC_DECINFO_ALU_AUIPC_LSB

`define RVC_DECINFO_ALU_NOP_LSB    (`RVC_DECINFO_ALU_AUIPC_MSB + 1)
`define RVC_DECINFO_ALU_NOP_MSB    (`RVC_DECINFO_ALU_NOP_LSB)
`define RVC_DECINFO_ALU_NOP        `RVC_DECINFO_ALU_NOP_MSB : `RVC_DECINFO_ALU_NOP_LSB

// 未来 Phase 4 扩展 (ECALL/EBREAK/WFI 等系统操作也通过 ALU 组处理)
// `define RVC_DECINFO_ALU_ECAL_LSB ...
// `define RVC_DECINFO_ALU_EBRK_LSB ...

`define RVC_DECINFO_ALU_WIDTH      (`RVC_DECINFO_ALU_NOP_MSB + 1)

//--------------------------------------------------------------------------
// 4.4 LSU 组子字段
//--------------------------------------------------------------------------
`define RVC_DECINFO_LSU_LOAD_LSB   `RVC_DECINFO_SUB_LSB
`define RVC_DECINFO_LSU_LOAD_MSB   (`RVC_DECINFO_LSU_LOAD_LSB)
`define RVC_DECINFO_LSU_LOAD       `RVC_DECINFO_LSU_LOAD_MSB : `RVC_DECINFO_LSU_LOAD_LSB

`define RVC_DECINFO_LSU_STORE_LSB  (`RVC_DECINFO_LSU_LOAD_MSB + 1)
`define RVC_DECINFO_LSU_STORE_MSB  (`RVC_DECINFO_LSU_STORE_LSB)
`define RVC_DECINFO_LSU_STORE      `RVC_DECINFO_LSU_STORE_MSB : `RVC_DECINFO_LSU_STORE_LSB

// LSU Size (2 bits): 00=byte, 01=half, 10=word
`define RVC_DECINFO_LSU_SIZE_LSB   (`RVC_DECINFO_LSU_STORE_MSB + 1)
`define RVC_DECINFO_LSU_SIZE_MSB   (`RVC_DECINFO_LSU_SIZE_LSB + 1)
`define RVC_DECINFO_LSU_SIZE       `RVC_DECINFO_LSU_SIZE_MSB : `RVC_DECINFO_LSU_SIZE_LSB

// LSU Unsigned (1 bit): 1=无符号扩展, 0=有符号扩展 (仅对 LOAD 有效)
`define RVC_DECINFO_LSU_USIGN_LSB  (`RVC_DECINFO_LSU_SIZE_MSB + 1)
`define RVC_DECINFO_LSU_USIGN_MSB  (`RVC_DECINFO_LSU_USIGN_LSB)
`define RVC_DECINFO_LSU_USIGN      `RVC_DECINFO_LSU_USIGN_MSB : `RVC_DECINFO_LSU_USIGN_LSB

`define RVC_DECINFO_LSU_WIDTH      (`RVC_DECINFO_LSU_USIGN_MSB + 1)

//--------------------------------------------------------------------------
// 4.5 BJP 组子字段
//--------------------------------------------------------------------------
`define RVC_DECINFO_BJP_JAL_LSB    `RVC_DECINFO_SUB_LSB
`define RVC_DECINFO_BJP_JAL_MSB    (`RVC_DECINFO_BJP_JAL_LSB)
`define RVC_DECINFO_BJP_JAL        `RVC_DECINFO_BJP_JAL_MSB : `RVC_DECINFO_BJP_JAL_LSB

`define RVC_DECINFO_BJP_JALR_LSB   (`RVC_DECINFO_BJP_JAL_MSB + 1)
`define RVC_DECINFO_BJP_JALR_MSB   (`RVC_DECINFO_BJP_JALR_LSB)
`define RVC_DECINFO_BJP_JALR       `RVC_DECINFO_BJP_JALR_MSB : `RVC_DECINFO_BJP_JALR_LSB

`define RVC_DECINFO_BJP_BEQ_LSB    (`RVC_DECINFO_BJP_JALR_MSB + 1)
`define RVC_DECINFO_BJP_BEQ_MSB    (`RVC_DECINFO_BJP_BEQ_LSB)
`define RVC_DECINFO_BJP_BEQ        `RVC_DECINFO_BJP_BEQ_MSB : `RVC_DECINFO_BJP_BEQ_LSB

`define RVC_DECINFO_BJP_BNE_LSB    (`RVC_DECINFO_BJP_BEQ_MSB + 1)
`define RVC_DECINFO_BJP_BNE_MSB    (`RVC_DECINFO_BJP_BNE_LSB)
`define RVC_DECINFO_BJP_BNE        `RVC_DECINFO_BJP_BNE_MSB : `RVC_DECINFO_BJP_BNE_LSB

`define RVC_DECINFO_BJP_BLT_LSB    (`RVC_DECINFO_BJP_BNE_MSB + 1)
`define RVC_DECINFO_BJP_BLT_MSB    (`RVC_DECINFO_BJP_BLT_LSB)
`define RVC_DECINFO_BJP_BLT        `RVC_DECINFO_BJP_BLT_MSB : `RVC_DECINFO_BJP_BLT_LSB

`define RVC_DECINFO_BJP_BGE_LSB    (`RVC_DECINFO_BJP_BLT_MSB + 1)
`define RVC_DECINFO_BJP_BGE_MSB    (`RVC_DECINFO_BJP_BGE_LSB)
`define RVC_DECINFO_BJP_BGE        `RVC_DECINFO_BJP_BGE_MSB : `RVC_DECINFO_BJP_BGE_LSB

`define RVC_DECINFO_BJP_BLTU_LSB   (`RVC_DECINFO_BJP_BGE_MSB + 1)
`define RVC_DECINFO_BJP_BLTU_MSB   (`RVC_DECINFO_BJP_BLTU_LSB)
`define RVC_DECINFO_BJP_BLTU       `RVC_DECINFO_BJP_BLTU_MSB : `RVC_DECINFO_BJP_BLTU_LSB

`define RVC_DECINFO_BJP_BGEU_LSB   (`RVC_DECINFO_BJP_BLTU_MSB + 1)
`define RVC_DECINFO_BJP_BGEU_MSB   (`RVC_DECINFO_BJP_BGEU_LSB)
`define RVC_DECINFO_BJP_BGEU       `RVC_DECINFO_BJP_BGEU_MSB : `RVC_DECINFO_BJP_BGEU_LSB

`define RVC_DECINFO_BJP_WIDTH      (`RVC_DECINFO_BJP_BGEU_MSB + 1)

//--------------------------------------------------------------------------
// 4.6 SYS 组子字段
//--------------------------------------------------------------------------
`define RVC_DECINFO_SYS_ECALL_LSB  `RVC_DECINFO_SUB_LSB
`define RVC_DECINFO_SYS_ECALL_MSB  (`RVC_DECINFO_SYS_ECALL_LSB)
`define RVC_DECINFO_SYS_ECALL      `RVC_DECINFO_SYS_ECALL_MSB : `RVC_DECINFO_SYS_ECALL_LSB

`define RVC_DECINFO_SYS_EBREAK_LSB (`RVC_DECINFO_SYS_ECALL_MSB + 1)
`define RVC_DECINFO_SYS_EBREAK_MSB (`RVC_DECINFO_SYS_EBREAK_LSB)
`define RVC_DECINFO_SYS_EBREAK     `RVC_DECINFO_SYS_EBREAK_MSB : `RVC_DECINFO_SYS_EBREAK_LSB

`define RVC_DECINFO_SYS_FENCE_LSB  (`RVC_DECINFO_SYS_EBREAK_MSB + 1)
`define RVC_DECINFO_SYS_FENCE_MSB  (`RVC_DECINFO_SYS_FENCE_LSB)
`define RVC_DECINFO_SYS_FENCE      `RVC_DECINFO_SYS_FENCE_MSB : `RVC_DECINFO_SYS_FENCE_LSB

`define RVC_DECINFO_SYS_WIDTH      (`RVC_DECINFO_SYS_FENCE_MSB + 1)

//--------------------------------------------------------------------------
// 4.7 译码信息总线总宽度 — 取所有组中最宽的
// E203 的做法: 所有组子字段从 SUB_LSB 开始放，总宽度 = SUB_LSB + max(各组宽度)
//--------------------------------------------------------------------------
// 下面计算各组需要的总位宽 (通用字段 + 组子字段)
// ALU 组:  通用字段宽度 + ALU 子字段宽度
// LSU 组:  通用字段宽度 + LSU 子字段宽度
// BJP 组:  通用字段宽度 + BJP 子字段宽度
// SYS 组:  通用字段宽度 + SYS 子字段宽度
//
// 通用字段占位数 = RVC_DECINFO_GENERAL_END + 1

// 计算各组子字段相对于 SUB_LSB 的偏移宽度
`define RVC_DECINFO_ALU_SUB_WIDTH    (`RVC_DECINFO_ALU_WIDTH - `RVC_DECINFO_SUB_LSB)
`define RVC_DECINFO_LSU_SUB_WIDTH    (`RVC_DECINFO_LSU_WIDTH - `RVC_DECINFO_SUB_LSB)
`define RVC_DECINFO_BJP_SUB_WIDTH    (`RVC_DECINFO_BJP_WIDTH - `RVC_DECINFO_SUB_LSB)
`define RVC_DECINFO_SYS_SUB_WIDTH    (`RVC_DECINFO_SYS_WIDTH - `RVC_DECINFO_SUB_LSB)

// 各组总宽度 = 子字段起始位 + 该组子字段宽度
`define RVC_DECINFO_ALU_TOTAL_WIDTH  (`RVC_DECINFO_SUB_LSB + `RVC_DECINFO_ALU_SUB_WIDTH)
`define RVC_DECINFO_LSU_TOTAL_WIDTH  (`RVC_DECINFO_SUB_LSB + `RVC_DECINFO_LSU_SUB_WIDTH)
`define RVC_DECINFO_BJP_TOTAL_WIDTH  (`RVC_DECINFO_SUB_LSB + `RVC_DECINFO_BJP_SUB_WIDTH)
`define RVC_DECINFO_SYS_TOTAL_WIDTH  (`RVC_DECINFO_SUB_LSB + `RVC_DECINFO_SYS_SUB_WIDTH)

// 最终总线宽度 = max(各组总宽度)
// 使用宏嵌套技巧: 逐级比较取最大值
`define RVC_DECINFO_WIDTH_CAND_A  (`RVC_DECINFO_ALU_TOTAL_WIDTH > `RVC_DECINFO_LSU_TOTAL_WIDTH ? `RVC_DECINFO_ALU_TOTAL_WIDTH : `RVC_DECINFO_LSU_TOTAL_WIDTH)
`define RVC_DECINFO_WIDTH_CAND_B  (`RVC_DECINFO_BJP_TOTAL_WIDTH > `RVC_DECINFO_SYS_TOTAL_WIDTH ? `RVC_DECINFO_BJP_TOTAL_WIDTH : `RVC_DECINFO_SYS_TOTAL_WIDTH)
`define RVC_DECINFO_WIDTH         (`RVC_DECINFO_WIDTH_CAND_A > `RVC_DECINFO_WIDTH_CAND_B ? `RVC_DECINFO_WIDTH_CAND_A : `RVC_DECINFO_WIDTH_CAND_B)

//==============================================================================
// 五、流水线阶段控制信号宽度 (Phase 2 使用)
//==============================================================================
// 这些宏定义了流水线寄存器打包后的信号宽度，Phase 1 中你不需要关心它们
// 但定义了它们可以让你在 Phase 1 的代码中预留接口
//
// IF → ID 阶段传递: PC + 指令
// `define RVC_IF_ID_WIDTH  (32 + 32)
//
// ID → EX 阶段传递: dec_info + RS1 + RS2 + PC + IMM
// `define RVC_ID_EX_WIDTH  (`RVC_DECINFO_WIDTH + 32 + 32 + 32 + 32)
//
// EX → MEM 阶段传递: ALU结果 + Store数据 + dec_info(LSU部分) + PC
// `define RVC_EX_MEM_WIDTH (32 + 32 + `RVC_DECINFO_WIDTH + 32)
//
// MEM → WB 阶段传递: MEM数据 + ALU结果 + dec_info(WB部分)
// `define RVC_MEM_WB_WIDTH (32 + 32 + `RVC_DECINFO_WIDTH)

//==============================================================================
// 六、固定常量
//==============================================================================
`define RVC_RESET_PC           32'h0000_0000   // 复位 PC
`define RVC_NOP_INSTR          32'h00000013    // ADDI x0, x0, 0
