//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_wb_stage.v — WB 阶段 (Write-Back)
//
//   这是五级流水的最后一级。在 Phase 1 (单周期) 中:
//     - 写回数据选择 — 组合逻辑 MUX (ALU结果 / MEM结果 / PC+4)
//     - 写回寄存器堆 — 连接到 ID 阶段的寄存器堆写端口
//     - 所有逻辑用 valid/ready 握手与上游通信
//
//   到 Phase 2 (五级流水):
//     在 MEM/WB 之间插入流水寄存器即可。
//     WB 阶段的逻辑几乎不变 — 它只是一个选择器 + 写使能生成。
//
// E203 参考:
//   e203_exu_wbck.v — E203 的写回仲裁模块,
//   它负责仲裁 ALU 写回 和 Long-Pipe 写回 (LSU/MULDIV/NICE),
//   将最终的写数据/写地址/写使能传给寄存器堆。
//
//   关键设计 (E203 风格):
//     ALU (1 cycle) 和 Long-pipe (multi cycle) 的写回结果是异步到达的,
//     wbck 模块需要仲裁: ALU 的写回优先级最低,
//     Long-pipe 的写回优先级最高。
//     Phase 1 中所有指令都是 1 cycle (包括 Load — 组合读 DMEM),
//     所以写回只有一个来源, 不需要仲裁。
//     Phase 2 中 Load 可能变为多周期 (如果 DMEM 是同步 BRAM),
//     此时就需要引入类似 E203 的写回仲裁机制。
//
// 你的任务 (Phase 1):
//   Step 1: 根据 dec_info 中的 WB_SEL 字段选择写回数据源
//   Step 2: 生成写回寄存器堆的使能信号
//   Step 3: 输出 wb_we, wb_wa, wb_wd 给 ID 阶段的寄存器堆
//
// 思考题:
//   Q1: 为什么写回仲裁要用 WBCK 模块而不是直接在寄存器堆端口上 MUX?
//       答: E203 中写回可能来自多个源 (ALU, LSU, MULDIV, NICE),
//           且它们的时序不同。WBCK 模块集中管理写回仲裁,
//           让寄存器堆只需要一个写端口。Phase 2 中你的 Load 指令
//           可能在 MEM 阶段就需要把数据写好 (如果 DMEM 是组合读),
//           但如果 DMEM 是同步读, Load 结果要到 WB 阶段才能拿到,
//           这时候就需要 WBCK 来接收异步的 Load 结果。
//==============================================================================

`include "defines.v"

module rvcpu_wb_stage (
    //==========================================================================
    // TODO: 定义以下端口
    //==========================================================================

    // --- 来自 MEM 阶段 ---
    // input  wire                      i_valid,
    // output wire                      i_ready,
    // input  wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,  — 译码信息 (提取 wb_sel/rdidx/rdwen)
    // input  wire [`RVC_XLEN-1:0]      i_alu_result, — ALU 结果
    // input  wire [`RVC_XLEN-1:0]      i_mem_result, — Load 结果
    // input  wire [`RVC_PC_WIDTH-1:0]  i_pc,        — PC (用来算 PC+4)

    // --- 输出到 ID 阶段的寄存器堆写端口 ---
    // output wire                      wb_we,       — 写使能
    // output wire [`RVC_RFIDX_WIDTH-1:0] wb_wa,     — 写地址 (rd)
    // output wire [`RVC_XLEN-1:0]      wb_wd        — 写数据


    //==========================================================================
    // 一、提取译码信息 (WB 专用字段)
    //==========================================================================
    // TODO: 从 i_dec_info 中提取
    //
    // 提示:
    //   wire        rdwen   = i_dec_info[`RVC_DECINFO_RDWEN];   — 是否需要写回
    //   wire [1:0]  wb_sel  = i_dec_info[`RVC_DECINFO_WB_SEL];  — 写回数据来源选择
    //   wire [4:0]  rdidx   = i_dec_info[`RVC_DECINFO_RDIDX];   — 目标寄存器号


    //==========================================================================
    // 二、写回数据选择 — MUX
    //==========================================================================
    // TODO: 根据 WB_SEL 选择写回数据源
    //
    // 提示 (E203 风格):
    //   // 候选数据
    //   wire [31:0] pc_plus_4 = i_pc + 32'd4;
    //
    //   // MUX 选择
    //   wire [31:0] wb_data;
    //   assign wb_data =
    //       (wb_sel == `RVC_WB_SEL_ALU) ? i_alu_result :   // ALU 结果
    //       (wb_sel == `RVC_WB_SEL_MEM) ? i_mem_result :   // Load 结果
    //       (wb_sel == `RVC_WB_SEL_PC4) ? pc_plus_4 :      // PC+4 (JAL/JALR返回地址)
    //       32'b0;
    //
    // 写回来源映射:
    //   ALU  → ADD, SUB, ADDI, XORI, ORI, ANDI, SLLI, SRLI, SRAI,
    //           SLTI, SLTIU, LUI, AUIPC
    //   MEM  → LB, LH, LW, LBU, LHU
    //   PC+4 → JAL, JALR (保存返回地址到 rd)


    //==========================================================================
    // 三、写回使能生成
    //==========================================================================
    // TODO: 生成寄存器堆写使能
    //
    // 提示:
    //   assign wb_we = i_valid & rdwen;
    //   assign wb_wa = rdidx;
    //   assign wb_wd = wb_data;
    //
    // 注意: Phase 1 中 wb_we = rdwen (因为 i_valid 恒为 1)
    //       但保留 i_valid 条件可以让 Phase 2 的流水线无效数据不写回。
    //
    // 思考: 如果 rdwen=1 但 rdidx=x0 怎么办?
    //       答: 寄存器堆中 x0 是硬连线为 0 的, we 且 wa=0 时不会写入。
    //           这是 RISC-V 规范的关键特性 (x0 始终为 0)。

endmodule
