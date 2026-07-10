//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_id_stage.v — ID 阶段 (Instruction Decode)
//
//   这是五级流水的第二级。在 Phase 1 (单周期) 中:
//     - 译码器 (rvcpu_decode) — 纯组合逻辑
//     - 寄存器堆 (rvcpu_regfile) — 2 组合读 + 1 时序写
//     - 立即数生成器 (rvcpu_immgen) — 纯组合逻辑
//     - 所有逻辑用 valid/ready 握手与上下游通信
//
//   到 Phase 2 (五级流水):
//     在 IF/ID 和 ID/EX 之间插入流水寄存器即可。
//     寄存器堆的读端口仍然是组合逻辑 (同周期读取)。
//
//   这个模块的职责:
//     1. 接收 IF 阶段的指令 + PC
//     2. 译码 → 生成 dec_info 总线
//     3. 读寄存器堆 → 获取 RS1, RS2
//     4. 生成立即数 → imm
//     5. 把所有信息打包传给 EX 阶段
//
// E203 参考:
//   e203_exu_decode.v — 译码器, 纯组合逻辑
//   e203_exu_regfile.v — 寄存器堆
//   E203 的做法: 译码器的输出 dec_info 是一个宽位宽总线,
//   其中所有控制信号按位域编码。这个总线贯穿后续所有阶段。
//   这是 E203 最值得学习的设计模式之一。
//
// 你的任务 (Phase 1):
//   Step 1: 定义端口
//   Step 2: 例化 rvcpu_decode   — 译码器 (输出 dec_info)
//   Step 3: 例化 rvcpu_regfile  — 寄存器堆 (2 读 + 1 写端口)
//   Step 4: 例化 rvcpu_immgen   — 立即数生成器
//   Step 5: 将译码/寄存器/立即数打包输出给 EX 阶段
//
// 思考题:
//   Q1: 为什么寄存器堆的读是组合逻辑, 写是时序逻辑?
//       答: 在 ID 阶段读出 RS1/RS2 (组合逻辑) → 同周期 EX 计算 →
//           同周期 MEM 访存 → 同周期 WB 写入。这保证了 Load 指令的
//           数据在同周期被写回, 不需要等待下一个时钟沿。
//           但这也意味着: 如果同时读写同一寄存器, 读到的是旧值。
//           在单周期中这不会发生 (一条指令只在一个阶段活跃)。
//   Q2: Phase 2 中, 当两条指令同时在流水线中时 (一条在 WB 写, 一条在 ID 读),
//       如何确保 ID 读到的是正确的值?
//       答: 需要前推 (forwarding) — 把 WB 阶段的结果在写入寄存器堆之前
//           直接旁路到 ID 的读数据上。这是 Phase 2 的核心挑战。
//==============================================================================

`include "defines.v"

module rvcpu_id_stage (
    //==========================================================================
    // TODO: 定义以下端口
    //==========================================================================

    // --- 时钟与复位 ---
    // input  wire        clk,
    // input  wire        rst_n,

    // --- 来自 IF 阶段 ---
    // input  wire                      i_valid,    — 指令有效
    // output wire                      i_ready,    — ID 就绪 (Phase 1: 1)
    // input  wire [31:0]               i_ir,       — 32 位指令
    // input  wire [`RVC_PC_WIDTH-1:0]  i_pc,       — 指令 PC

    // --- 来自 WB 阶段的写回 (连接到寄存器堆写端口) ---
    // input  wire                      wb_we,      — 写使能
    // input  wire [`RVC_RFIDX_WIDTH-1:0] wb_wa,    — 写地址
    // input  wire [`RVC_XLEN-1:0]      wb_wd,      — 写数据

    // --- 输出到 EX 阶段 (打包所有译码信息) ---
    // output wire                      o_valid,
    // input  wire                      o_ready,
    // output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,  — 译码信息总线
    // output wire [`RVC_XLEN-1:0]      o_rs1,       — RS1 的值
    // output wire [`RVC_XLEN-1:0]      o_rs2,       — RS2 的值
    // output wire [`RVC_XLEN-1:0]      o_imm,       — 立即数
    // output wire [`RVC_PC_WIDTH-1:0]  o_pc,        — PC (传递给后续阶段)
    // output wire [31:0]               o_ir         — 原始指令 (Phase 4 异常用)
);


    //==========================================================================
    // 一、内部互联信号 — 连接 ID 阶段的子模块
    //==========================================================================

    // TODO: 定义以下 wire 信号

    // 译码器 → ID 顶层
    // wire [`RVC_DECINFO_WIDTH-1:0]  dec_info;
    // wire [`RVC_RFIDX_WIDTH-1:0]    dec_rs1idx, dec_rs2idx, dec_rdidx;
    // wire                            dec_rs1en, dec_rs2en, dec_rdwen;
    // wire [`RVC_XLEN-1:0]           dec_imm;

    // 寄存器堆 → ID 顶层
    // wire [`RVC_XLEN-1:0]           rf_rs1, rf_rs2;

    // 立即数生成器 → ID 顶层
    // wire [`RVC_XLEN-1:0]           immgen_imm;


    //==========================================================================
    // 二、例化译码器 (rvcpu_decode)
    //==========================================================================
    // TODO: 实例化译码器
    //
    // rvcpu_decode u_decode (
    //     .i_instr    (i_ir),
    //     .i_pc       (i_pc),
    //     .o_dec_info (dec_info),
    //     .o_rs1idx   (dec_rs1idx),
    //     .o_rs2idx   (dec_rs2idx),
    //     .o_rdidx    (dec_rdidx),
    //     .o_rs1en    (dec_rs1en),
    //     .o_rs2en    (dec_rs2en),
    //     .o_rdwen    (dec_rdwen),
    //     .o_imm      (dec_imm)
    // );
    //
    // 译码器是纯组合逻辑。输入 32 位指令, 输出所有译码信息。


    //==========================================================================
    // 三、例化寄存器堆 (rvcpu_regfile)
    //==========================================================================
    // TODO: 实例化寄存器堆
    //
    // rvcpu_regfile u_regfile (
    //     .clk  (clk),
    //     // 读端口 1 (组合逻辑)
    //     .ra1  (dec_rs1idx),
    //     .rd1  (rf_rs1),
    //     // 读端口 2 (组合逻辑)
    //     .ra2  (dec_rs2idx),
    //     .rd2  (rf_rs2),
    //     // 写端口 (时序逻辑)
    //     .wa   (wb_wa),
    //     .wd   (wb_wd),
    //     .we   (wb_we)
    // );
    //
    // 注意: 读地址直接来自译码器的输出,
    //       写地址和数据来自 WB 阶段的输出。
    //       Phase 1 中, 同一条指令的 ID 读和 WB 写发生在同一周期,
    //       但时钟沿的顺序保证了读到的是旧值 (正确行为)。
    //
    // 你已有的 regfile.v 可以直接作为 rvcpu_regfile 使用。


    //==========================================================================
    // 四、例化立即数生成器 (rvcpu_immgen)
    //==========================================================================
    // TODO: 实例化立即数生成器
    //
    // rvcpu_immgen u_immgen (
    //     .i_instr (i_ir),
    //     .o_imm   (immgen_imm)
    // );
    //
    // 立即数生成器是纯组合逻辑, 根据 opcode 选择正确的立即数格式:
    //   I-type  → {{20{instr[31]}}, instr[31:20]}
    //   S-type  → {{20{instr[31]}}, instr[31:25], instr[11:7]}
    //   B-type  → {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
    //   U-type  → {instr[31:12], 12'b0}
    //   J-type  → {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
    //
    // 注意: 译码器中也可以生成立即数 (dec_imm),
    //       这里可以用独立的 immgen 模块, 也可以用译码器的输出。
    //       E203 的做法是在译码器中一并生成 dec_info 中的立即数字段。
    //       两种做法都可以, 关键在于保持译码信息集中管理。


    //==========================================================================
    // 五、打包输出给 EX 阶段
    //==========================================================================
    // TODO: 将 ID 阶段的所有信息打包传递给 EX 阶段
    //
    // 提示:
    //   assign o_valid    = i_valid;            — Phase 1 直通
    //   assign i_ready    = o_ready;            — Phase 1 直通
    //   assign o_dec_info = dec_info;           — 译码信息总线
    //   assign o_rs1      = rf_rs1;             — RS1 值
    //   assign o_rs2      = rf_rs2;             — RS2 值
    //   assign o_imm      = dec_imm;            — 立即数
    //   assign o_pc       = i_pc;               — PC 直通
    //   assign o_ir       = i_ir;               — 原始指令直通
    //
    // 思考: 为什么要把 o_pc 和 o_ir 也传给后续阶段?
    //       答: o_pc → AUIPC/JAL/JALR 需要 PC 参与地址计算,
    //                   异常处理需要记录出错的 PC 值存入 mepc。
    //           o_ir → Phase 4 异常处理需要原始指令来填充 mtval。

endmodule
