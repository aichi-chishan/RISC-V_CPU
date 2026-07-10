//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_ex_stage.v — EX 阶段 (Execution)
//
//   这是五级流水的第三级。在 Phase 1 (单周期) 中:
//     - ALU — 纯组合逻辑 (13 种运算)
//     - 分支判定 — 纯组合逻辑 (比较 + PC 选择)
//     - 操作数选择 — 纯组合逻辑 (RS1/PC, RS2/IMM)
//     - 访存地址计算 — 纯组合逻辑 (rs1 + imm → addr)
//
//   E203 中这对应 e203_exu_alu.v + e203_exu_alu_rglr.v:
//     - e203_exu_alu.v:      ALU 数据通路 (datapath), 纯组合逻辑
//     - e203_exu_alu_rglr.v: ALU 控制层, 负责 dec_info 解析和 valid/ready 握手
//
//   关键设计:
//   E203 将 ALU 分为两层:
//     (a) datapath: 纯运算, 所有运算结果并行计算, MUX 选择输出
//     (b) control:  从 dec_info 中提取控制信号, 管理 handshake
//   这种分离让数据通路和控制通路可以独立优化。
//
// 你的任务 (Phase 1):
//   Step 1: 定义端口
//   Step 2: 实现 ALU 操作数选择 — 根据 dec_info 选择 op1/op2
//   Step 3: 实现 ALU 数据通路 — 所有运算并行计算 + MUX
//   Step 4: 实现分支判定 — 比较 + 条件求值
//   Step 5: 生成访存地址 — rs1 + imm (传给 MEM 阶段)
//   Step 6: 生成 PC 控制信号 — pc_sel/pc_next (传给 IF 阶段)
//   Step 7: 打包输出给 MEM 阶段
//
// 思考题:
//   Q1: 为什么 ALU 要"并行计算所有结果再 MUX", 而不是用 case 分支?
//       答: E203 的做法让综合器可以更好地优化并行路径,
//           避免了 case 嵌套可能产生的优先级链。
//   Q2: 分支判定在 EX 阶段完成, 但 IF 阶段已经取了下一条指令。
//       在单周期中这不是问题 (因为所有阶段是组合逻辑串联,
//       同周期内就能得到分支结果并回传给 IF)。
//       但在五级流水中, IF 和 EX 之间隔了 ID 两个阶段,
//       分支判定结果要到 EX 结束才能回传给 IF, 此时 IF 已经
//       取了 2 条错误的指令。这在 Phase 2 中会通过冲刷 (flush) 来处理。
//==============================================================================

`include "defines.v"

module rvcpu_ex_stage (
    //==========================================================================
    // TODO: 定义以下端口
    //==========================================================================

    // --- 时钟与复位 (Phase 1 ALU 不需要 clk, 但为 Phase 2 预留) ---
    // input  wire        clk,
    // input  wire        rst_n,

    // --- 来自 ID 阶段 ---
    // input  wire                      i_valid,
    // output wire                      i_ready,
    // input  wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,  — 译码信息总线
    // input  wire [`RVC_XLEN-1:0]      i_rs1,       — RS1 的值
    // input  wire [`RVC_XLEN-1:0]      i_rs2,       — RS2 的值
    // input  wire [`RVC_XLEN-1:0]      i_imm,       — 立即数
    // input  wire [`RVC_PC_WIDTH-1:0]  i_pc,        — 当前 PC
    // input  wire [31:0]               i_ir,        — 原始指令 (Phase 4 使用)

    // --- 来自 MEM 阶段的反馈 (Phase 2: 前推数据) ---
    // input  wire [`RVC_XLEN-1:0]      fwd_mem_result,   — MEM 阶段的前推结果
    // input  wire                      fwd_mem_valid,    — MEM 前推有效
    // --- 来自 WB 阶段的反馈 (Phase 2: 前推数据) ---
    // input  wire [`RVC_XLEN-1:0]      fwd_wb_result,    — WB 阶段的前推结果
    // input  wire                      fwd_wb_valid,     — WB 前推有效

    // --- PC 控制输出 (回传给 IF 阶段) ---
    // output wire                      o_pc_sel,    — 1: 使用跳转目标
    // output wire [`RVC_PC_WIDTH-1:0]  o_pc_next,   — 跳转目标地址

    // --- 输出到 MEM 阶段 ---
    // output wire                      o_valid,
    // input  wire                      o_ready,
    // output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,  — 译码信息 (透传)
    // output wire [`RVC_XLEN-1:0]      o_alu_result, — ALU 计算结果
    // output wire [`RVC_XLEN-1:0]      o_store_data, — Store 数据 (rs2)
    // output wire [`RVC_PC_WIDTH-1:0]  o_pc,        — PC (透传, 用于异常)
    // output wire [31:0]               o_ir         — 原始指令 (透传)
);


    //==========================================================================
    // 一、提取译码信息 (从 dec_info 总线中获取本阶段需要的字段)
    //==========================================================================
    // TODO: 从 i_dec_info 中提取子字段
    //
    // E203 风格:
    //   wire [2:0]  grp     = i_dec_info[`RVC_DECINFO_GRP];
    //   wire        op1sel  = i_dec_info[`RVC_DECINFO_OP1SEL];
    //   wire        op2sel  = i_dec_info[`RVC_DECINFO_OP2SEL];
    //
    //   // ALU 组子字段 (独热码)
    //   wire        alu_add  = i_dec_info[`RVC_DECINFO_ALU_ADD];
    //   wire        alu_sub  = i_dec_info[`RVC_DECINFO_ALU_SUB];
    //   wire        alu_sll  = i_dec_info[`RVC_DECINFO_ALU_SLL];
    //   // ... 其他 ALU 操作
    //   wire        alu_nop  = i_dec_info[`RVC_DECINFO_ALU_NOP];
    //
    //   // BJP 组子字段
    //   wire        bjp_jal  = i_dec_info[`RVC_DECINFO_BJP_JAL];
    //   wire        bjp_beq  = i_dec_info[`RVC_DECINFO_BJP_BEQ];
    //   // ... 其他分支/跳转类型


    //==========================================================================
    // 二、操作数选择 — 决定 ALU 的两个输入
    //==========================================================================
    // TODO: 实现操作数选择
    //
    // 提示:
    //   assign alu_op1 = (op1sel == 1'b1) ? i_pc : i_rs1;
    //   assign alu_op2 = (op2sel == 1'b1) ? i_imm : i_rs2;
    //
    // 规则:
    //   - op1sel=PC:  AUIPC 的地址计算用 PC、JAL/JALR 也通常需要 PC
    //   - op2sel=IMM: I-type 指令用立即数、U-type 用 imm (LUI 直接选 op2)
    //
    // Phase 2 扩展: 前推数据选择
    //   如果 fwd_mem_valid 且 MEM 阶段的 rd == 当前指令的 rs1,
    //   那么 alu_op1 = fwd_mem_result 而不是 i_rs1。
    //   这就是前推 (forwarding) — 从后续阶段直接获取最新的寄存器值。


    //==========================================================================
    // 三、ALU 数据通路 — 并行计算 + MUX
    //==========================================================================
    // TODO: 实现 ALU 运算
    //
    // E203 风格 (并行计算):
    //   wire [31:0] add_res  = alu_op1 + alu_op2;
    //   wire [31:0] sub_res  = alu_op1 - alu_op2;
    //   wire [31:0] xor_res  = alu_op1 ^ alu_op2;
    //   wire [31:0] or_res   = alu_op1 | alu_op2;
    //   wire [31:0] and_res  = alu_op1 & alu_op2;
    //   wire [31:0] sll_res  = alu_op1 << alu_op2[4:0];
    //   wire [31:0] srl_res  = alu_op1 >> alu_op2[4:0];
    //   wire [31:0] sra_res  = $signed(alu_op1) >>> alu_op2[4:0];
    //   wire [31:0] slt_res  = ($signed(alu_op1) < $signed(alu_op2)) ? 32'd1 : 32'd0;
    //   wire [31:0] sltu_res = (alu_op1 < alu_op2) ? 32'd1 : 32'd0;
    //   wire [31:0] lui_res  = alu_op2;          // LUI: 直接输出立即数
    //
    // MUX 选择:
    //   always @(*) begin
    //       if (alu_add)          alu_result = add_res;
    //       else if (alu_sub)     alu_result = sub_res;
    //       else if (alu_xor)     alu_result = xor_res;
    //       else if (alu_or)      alu_result = or_res;
    //       else if (alu_and)     alu_result = and_res;
    //       else if (alu_sll)     alu_result = sll_res;
    //       else if (alu_srl)     alu_result = srl_res;
    //       else if (alu_sra)     alu_result = sra_res;
    //       else if (alu_slt)     alu_result = slt_res;
    //       else if (alu_sltu)    alu_result = sltu_res;
    //       else if (alu_lui)     alu_result = lui_res;
    //       else if (alu_nop)     alu_result = 32'b0;
    //       else                  alu_result = add_res; // 默认 ADD (AUIPC 等)
    //   end
    //
    // E203 特别注意: NOP 的编码是 ADDI x0,x0,0,
    // 译码器把它分到了 ALU 组, 且同时标记了 ADD 和 NOP。
    // 所以 ALU 在判到 NOP 时必须优先输出 0, 否则 NOP 会当成 ADD 执行。


    //==========================================================================
    // 四、分支判定 — 比较 + 条件求值
    //==========================================================================
    // TODO: 实现分支判定逻辑
    //
    // 提示:
    //   // 比较结果 (组合逻辑)
    //   wire cmp_eq   = (i_rs1 == i_rs2);
    //   wire cmp_ne   = (i_rs1 != i_rs2);
    //   wire cmp_lt   = ($signed(i_rs1) <  $signed(i_rs2));
    //   wire cmp_ge   = ($signed(i_rs1) >= $signed(i_rs2));
    //   wire cmp_ltu  = (i_rs1  <  i_rs2);
    //   wire cmp_geu  = (i_rs1  >= i_rs2);
    //
    //   // 分支条件求值
    //   wire branch_taken;
    //   assign branch_taken =
    //       (bjp_beq  &  cmp_eq ) |
    //       (bjp_bne  &  cmp_ne ) |
    //       (bjp_blt  &  cmp_lt ) |
    //       (bjp_bge  &  cmp_ge ) |
    //       (bjp_bltu &  cmp_ltu) |
    //       (bjp_bgeu &  cmp_geu) |
    //       (bjp_jal)             |   // JAL 无条件跳转
    //       (bjp_jalr);               // JALR 无条件跳转
    //
    //   // 跳转目标地址
    //   wire [31:0] pc_branch = i_pc + i_imm;       // 分支 / JAL
    //   wire [31:0] pc_jalr   = alu_result & ~32'h1; // JALR (最低位清零)
    //
    //   assign o_pc_sel  = branch_taken;
    //   assign o_pc_next = (bjp_jalr) ? pc_jalr : pc_branch;


    //==========================================================================
    // 五、输出到 MEM 阶段
    //==========================================================================
    // TODO: 打包输出
    //
    // 提示:
    //   assign o_valid      = i_valid;        — Phase 1 直通
    //   assign i_ready      = o_ready;        — Phase 1 直通
    //   assign o_dec_info   = i_dec_info;     — 译码信息透传
    //   assign o_alu_result = alu_result;     — ALU 计算结果 (= 访存地址)
    //   assign o_store_data = i_rs2;          — Store 数据 (may be forwarded Phase2)
    //   assign o_pc         = i_pc;           — PC 透传
    //   assign o_ir         = i_ir;           — 原始指令透传

endmodule
