//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_decode.v — 译码器 (纯组合逻辑)
//
//   这是 CPU 中最核心的模块之一。根据 32 位指令的 opcode/funct3/funct7,
//   生成 dec_info 总线 — 后续所有阶段的控制信号都从这里来。
//
//   输出信号:
//     1. dec_info — 译码信息总线 (包含所有控制和数据信息)
//     2. 寄存器地址 — rs1idx, rs2idx, rdidx
//     3. 使能信号 — rs1en, rs2en, rdwen
//     4. 立即数 — 已拼接符号扩展的 32 位值
//
// E203 参考: e203_exu_decode.v — 分段译码, opcode→grp→sub-opcode
//   值得学习的 E203 模式:
//     1. 先根据 opcode 判定指令组 (GRP), 再根据 funct3/funct7 判定子操作
//     2. 每个位域从 dec_info 中分配固定位置 (在 defines.v 中定义)
//     3. 译码结果全部组合到 dec_info 中, 一根总线穿 5 级流水
//
// RV32I opcode 速查表:
//   ┌──────────┬──────────┬─────────────────────────────┐
//   │ opcode   │ 指令类型  │ 具体指令                     │
//   ├──────────┼──────────┼─────────────────────────────┤
//   │ 0110111  │ U-type   │ LUI                          │
//   │ 0010111  │ U-type   │ AUIPC                        │
//   │ 1101111  │ J-type   │ JAL                          │
//   │ 1100111  │ I-type   │ JALR                         │
//   │ 1100011  │ B-type   │ BEQ/BNE/BLT/BGE/BLTU/BGEU   │
//   │ 0000011  │ I-type   │ LB/LH/LW/LBU/LHU             │
//   │ 0100011  │ S-type   │ SB/SH/SW                     │
//   │ 0010011  │ I-type   │ ADDI/SLTI/SLTIU/XORI/ORI/    │
//   │          │          │ ANDI/SLLI/SRLI/SRAI           │
//   │ 0110011  │ R-type   │ ADD/SUB/SLL/SLT/SLTU/XOR/    │
//   │          │          │ SRL/SRA/OR/AND                │
//   │ 0001111  │ I-type   │ FENCE/FENCE.I                │
//   │ 1110011  │ I-type   │ ECALL/EBREAK                  │
//   └──────────┴──────────┴─────────────────────────────┘
//
// 你的任务:
//   Step 1: 提取指令字段 (opcode/funct3/funct7/rd/rs1/rs2)
//   Step 2: 根据 opcode 判定指令组 (GRP)
//   Step 3: 根据 funct3/funct7 设定子操作 (独热码)
//   Step 4: 设定通用字段 (寄存器地址、使能、操作数选择、写回选择)
//   Step 5: 生成各格式立即数并选择
//   Step 6: 将所有字段打包进 dec_info
//==============================================================================

`include "defines.v"

module rvcpu_decode (
    //==========================================================================
    // TODO: 定义以下端口
    //==========================================================================

    // --- 输入 ---
    // input  wire [31:0]               i_instr,     — 32位指令
    // input  wire [`RVC_PC_WIDTH-1:0]  i_pc,        — 当前指令的 PC

    // --- 输出: 译码信息总线 ---
    // output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,

    // --- 输出: 寄存器地址 (方便 ID 阶段直接连接 RegFile) ---
    // output wire [`RVC_RFIDX_WIDTH-1:0]    o_rs1idx,
    // output wire [`RVC_RFIDX_WIDTH-1:0]    o_rs2idx,
    // output wire [`RVC_RFIDX_WIDTH-1:0]    o_rdidx,

    // --- 输出: 使能信号 ---
    // output wire                           o_rs1en,
    // output wire                           o_rs2en,
    // output wire                           o_rdwen,

    // --- 输出: 立即数 ---
    // output wire [`RVC_XLEN-1:0]           o_imm


    //==========================================================================
    // 一、提取指令字段
    //==========================================================================
    // TODO: 从 32 位指令中提取标准 RISC-V 字段
    //
    // 提示:
    //   wire [6:0]  opcode  = i_instr[6:0];
    //   wire [4:0]  rd      = i_instr[11:7];
    //   wire [2:0]  funct3  = i_instr[14:12];
    //   wire [4:0]  rs1     = i_instr[19:15];
    //   wire [4:0]  rs2     = i_instr[24:20];
    //   wire [6:0]  funct7  = i_instr[31:25];
    //
    //   立即数位 (在各格式中取不同的位, 在步骤五中拼接):
    //   wire [11:0] imm_i   = i_instr[31:20];   — I-type 立即数


    //==========================================================================
    // 二、指令组判定 (GRP) — 根据 opcode
    //==========================================================================
    // TODO: 用 case 或 if-else 判定指令组
    //
    // 提示:
    //   reg [2:0] grp;
    //   always @(*) begin
    //       case (opcode)
    //           7'b0110111: grp = `RVC_DECINFO_GRP_ALU;   // LUI
    //           7'b0010111: grp = `RVC_DECINFO_GRP_ALU;   // AUIPC
    //           7'b0110011: grp = `RVC_DECINFO_GRP_ALU;   // OP (R-type)
    //           7'b0010011: grp = `RVC_DECINFO_GRP_ALU;   // OP-IMM
    //           7'b0000011: grp = `RVC_DECINFO_GRP_LSU;   // LOAD
    //           7'b0100011: grp = `RVC_DECINFO_GRP_LSU;   // STORE
    //           7'b1100011: grp = `RVC_DECINFO_GRP_BJP;   // BRANCH
    //           7'b1101111: grp = `RVC_DECINFO_GRP_BJP;   // JAL
    //           7'b1100111: grp = `RVC_DECINFO_GRP_BJP;   // JALR
    //           7'b0001111: grp = `RVC_DECINFO_GRP_SYS;   // FENCE
    //           7'b1110011: grp = `RVC_DECINFO_GRP_SYS;   // ECALL/EBREAK
    //           default:    grp = `RVC_DECINFO_GRP_ALU;   // 默认/非法→NOP
    //       endcase
    //   end
    //
    // E203 技巧: 可以先判断 opcode[4:2] 压缩 case 分支:
    //   opcode[4:2] = 3'b000 → LOAD / STORE / FENCE
    //   opcode[4:2] = 3'b100 → OP / OP-IMM / SYSTEM


    //==========================================================================
    // 三、子操作设定 — 根据 funct3/funct7 设定独热码位
    //==========================================================================
    // TODO: 在确定了指令组后, 设定该组的独热码子字段
    //
    // 提示 (ALU 组):
    //   当 opcode=0110011 (R-type) 或 0010011 (I-type ALU) 时:
    //
    //   // 检测 NOP: ADDI x0, x0, 0 → rd=0, op=0010011, funct3=000, imm=0
    //   wire is_nop = (rd == 5'd0) && (opcode == 7'b0010011)
    //              && (funct3 == 3'b000) && (i_instr[31:20] == 12'd0);
    //
    //   case (funct3)
    //       3'b000: begin // ADD/SUB or ADDI
    //           if (is_nop)         子操作 = NOP;
    //           else if (opcode[5]) 子操作 = SUB;   // R-type + funct7[5]=1 → SUB
    //           else                子操作 = ADD;   // I-type 或 R-type(funct7[5]=0)
    //       end
    //       3'b001: 子操作 = SLL;   // SLL/SLLI
    //       3'b010: 子操作 = SLT;   // SLT/SLTI
    //       3'b011: 子操作 = SLTU;  // SLTU/SLTIU
    //       3'b100: 子操作 = XOR;   // XOR/XORI
    //       3'b101: begin // SRL/SRA or SRLI/SRAI
    //           if (funct7[5]) 子操作 = SRA;
    //           else           子操作 = SRL;
    //       end
    //       3'b110: 子操作 = OR;    // OR/ORI
    //       3'b111: 子操作 = AND;   // AND/ANDI
    //   endcase
    //
    //   当 opcode=0110111: 子操作 = LUI;
    //   当 opcode=0010111: 子操作 = AUIPC;
    //
    // 提示 (LSU 组):
    //   当 opcode=0000011 (LOAD) 或 0100011 (STORE):
    //   子操作 = opcode[3] ? STORE : LOAD;
    //   根据 funct3 设定 lsu_size 和 lsu_usign
    //
    // 提示 (BJP 组):
    //   根据 opcode 和 funct3:
    //   JAL → BJP_JAL;  JALR → BJP_JALR;
    //   funct3=000 → BEQ,  001 → BNE
    //   funct3=100 → BLT,  101 → BGE
    //   funct3=110 → BLTU, 111 → BGEU
    //
    // 提示 (SYS 组):
    //   当 funct3=000:
    //     如果 i_instr[20] → ECALL
    //     如果是其他 imm  → EBREAK
    //   当 funct3=001: FENCE


    //==========================================================================
    // 四、通用字段设定
    //==========================================================================
    // TODO: 设定寄存器地址、使能、操作数选择、写回选择
    //
    // 提示: 各指令类型的通用字段对照表:
    //
    // ┌──────────┬───────┬───────┬───────┬────────┬────────┬────────┬──────────┐
    // │ 指令类型  │ rs1en │ rs2en │ rdwen │ op1sel │ op2sel │ wb_sel │ 说明     │
    // ├──────────┼───────┼───────┼───────┼────────┼────────┼────────┼──────────┤
    // │ R-type   │   1   │   1   │   1   │    0   │    0   │ ALU(00)│ ADD等    │
    // │ I-ALU    │   1   │   0   │   1   │    0   │    1   │ ALU(00)│ ADDI等   │
    // │ LOAD     │   1   │   0   │   1   │    0   │    1   │ MEM(01)│ LB/LH/LW │
    // │ STORE    │   1   │   1   │   0   │    0   │    1   │   -    │ SB/SH/SW │
    // │ B-type   │   1   │   1   │   0   │    0   │    0   │   -    │ BEQ等    │
    // │ JAL      │   0   │   0   │   1   │    1   │    1   │ PC4(10)│跳转+链接 │
    // │ JALR     │   1   │   0   │   1   │    1   │    1   │ PC4(10)│间接跳转  │
    // │ LUI      │   0   │   0   │   1   │    0   │    1   │ ALU(00)│加载立即数 │
    // │ AUIPC    │   0   │   0   │   1   │    1   │    1   │ ALU(00)│PC+立即数  │
    // │ FENCE    │   0   │   0   │   0   │    -   │    -   │   -    │          │
    // │ ECALL    │   0   │   0   │   0   │    -   │    -   │   -    │ Phase 4  │
    // │ EBREAK   │   0   │   0   │   0   │    -   │    -   │   -    │ Phase 4  │
    // └──────────┴───────┴───────┴───────┴────────┴────────┴────────┴──────────┘
    //
    // op1sel: 0=RS1, 1=PC    — AUIPC 和 JAL/JALR 需要 PC 参与地址计算
    // op2sel: 0=RS2, 1=IMM   — 所有 I-type、U-type、J-type 用立即数
    // wb_sel: 00=ALU, 01=MEM(LSU), 10=PC+4(JAL/JALR返回地址)


    //==========================================================================
    // 五、立即数生成 — 6 种格式拼接 + 选择
    //==========================================================================
    // TODO: 生成各格式的立即数候选值, 然后根据 opcode 选择
    //
    // 提示:
    //   // I-type: ADDI, LOAD, JALR (12位有符号 → 32位)
    //   wire [31:0] imm_i_type = {{20{i_instr[31]}}, i_instr[31:20]};
    //
    //   // S-type: STORE (12位有符号, 分两段)
    //   wire [31:0] imm_s_type = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};
    //
    //   // B-type: BRANCH (13位有符号, 分四段, 最低位隐含为0)
    //   wire [31:0] imm_b_type = {{19{i_instr[31]}}, i_instr[31], i_instr[7],
    //                              i_instr[30:25], i_instr[11:8], 1'b0};
    //
    //   // U-type: LUI, AUIPC (20位在高位, 低12位为0)
    //   wire [31:0] imm_u_type = {i_instr[31:12], 12'b0};
    //
    //   // J-type: JAL (21位有符号, 分五段, 最低位隐含为0)
    //   wire [31:0] imm_j_type = {{11{i_instr[31]}}, i_instr[31], i_instr[19:12],
    //                              i_instr[20], i_instr[30:21], 1'b0};
    //
    //   // 根据 opcode 选择立即数
    //   always @(*) begin
    //       case (opcode)
    //           7'b0110111, 7'b0010111:  imm = imm_u_type;  // LUI, AUIPC
    //           7'b1101111:              imm = imm_j_type;  // JAL
    //           7'b1100011:              imm = imm_b_type;  // BRANCH
    //           7'b0100011:              imm = imm_s_type;  // STORE
    //           default:                 imm = imm_i_type;  // 其他: I-type 格式
    //       endcase
    //   end
    //
    // 注意: 移位指令 (SLLI/SRLI/SRAI) 的立即数是 shamt (5位无符号),
    //       在 I-type 的 imm[4:0] 中。译码器产出的 imm 仍然是 12 位符号扩展的,
    //       但 ALU 在使用时会只取 op2[4:0]。这是 RISC-V 规范规定的,
    //       所以立即数生成不需要对移位指令做特殊处理。


    //==========================================================================
    // 六、打包 dec_info 总线
    //==========================================================================
    // TODO: 将所有译码结果组合到 dec_info 中
    //
    // 使用 E203 风格的位域赋值:
    //   assign o_dec_info = {(`RVC_DECINFO_WIDTH){1'b0}};     // 先全部清零
    //
    //   // 通用字段
    //   assign o_dec_info[`RVC_DECINFO_GRP]      = grp;
    //   assign o_dec_info[`RVC_DECINFO_RS1IDX]   = rs1;
    //   assign o_dec_info[`RVC_DECINFO_RS2IDX]   = rs2;
    //   assign o_dec_info[`RVC_DECINFO_RDIDX]    = rd;
    //   assign o_dec_info[`RVC_DECINFO_RDWEN]    = rdwen;
    //   assign o_dec_info[`RVC_DECINFO_RS1EN]    = rs1en;
    //   assign o_dec_info[`RVC_DECINFO_RS2EN]    = rs2en;
    //   assign o_dec_info[`RVC_DECINFO_OP1SEL]   = op1sel;
    //   assign o_dec_info[`RVC_DECINFO_OP2SEL]   = op2sel;
    //   assign o_dec_info[`RVC_DECINFO_WB_SEL]   = wb_sel;
    //   assign o_dec_info[`RVC_DECINFO_IMM]      = imm;
    //   assign o_dec_info[`RVC_DECINFO_PC]       = i_pc;
    //
    //   // 组子字段 — 根据 grp 填充对应组的独热码位
    //   // ALU 组
    //   assign o_dec_info[`RVC_DECINFO_ALU_ADD]  = ...;
    //   assign o_dec_info[`RVC_DECINFO_ALU_SUB]  = ...;
    //   ...
    //   assign o_dec_info[`RVC_DECINFO_ALU_NOP]  = is_nop;
    //   // LSU 组
    //   assign o_dec_info[`RVC_DECINFO_LSU_LOAD]  = ...;
    //   // BJP 组
    //   assign o_dec_info[`RVC_DECINFO_BJP_JAL]   = ...;
    //   // SYS 组
    //   assign o_dec_info[`RVC_DECINFO_SYS_ECALL] = ...;


    //==========================================================================
    // 七、直接输出信号
    //==========================================================================
    // TODO: 输出寄存器地址和使能
    //
    // 提示:
    //   assign o_rs1idx = rs1;
    //   assign o_rs2idx = rs2;
    //   assign o_rdidx  = rd;
    //   assign o_rs1en  = rs1en;
    //   assign o_rs2en  = rs2en;
    //   assign o_rdwen  = rdwen;
    //   assign o_imm    = imm;

endmodule
