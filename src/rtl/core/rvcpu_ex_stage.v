`include "./defines.v"

//==============================================================================
// EX 阶段：整数 ALU、访存地址计算和控制转移判定
//
// 前推选择已预留给五级流水：00=寄存器堆，01=MEM，10=WB。
// 当前多周期核没有并行指令，两个选择恒为 00。
//==============================================================================
module rvcpu_ex_stage (
    input wire i_valid, output wire i_ready,
    input wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,
    input wire [31:0] i_rs1, input wire [31:0] i_rs2,
    output wire o_pc_sel, output wire [31:0] o_pc_next,
    output wire o_branch_taken, output wire [31:0] o_branch_target,
    input wire [31:0] fwd_mem_result, input wire [31:0] fwd_wb_result,
    input wire [1:0] fwd_rs1_sel, input wire [1:0] fwd_rs2_sel,
    output wire o_valid, input wire o_ready,
    output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,
    output reg [31:0] o_alu_result, output wire [31:0] o_store_data
);
    //-------- 从 dec_info 提取字段 --------
    // 指令所属组别：ALU / LSU / BJP / SYS
    wire [2:0] grp = i_dec_info[`RVC_DECINFO_GRP];
    // 只从统一 dec_info 取得立即数和 PC，避免与外部 payload 重复。
    wire [31:0] i_imm = i_dec_info[`RVC_DECINFO_IMM];
    wire [31:0] i_pc  = i_dec_info[`RVC_DECINFO_PC];

    //-------- 前推多路选择器（预留五级流水）--------
    // 00 = 寄存器堆直出（当前多周期模式）
    // 01 = MEM 阶段结果前推
    // 10 = WB 阶段结果前推
    // 前推 MUX 与 ALU 操作数 MUX 分开，方便未来独立做时序优化。
    wire [31:0] rs1_fwd = (fwd_rs1_sel == 2'b01) ? fwd_mem_result :
                           (fwd_rs1_sel == 2'b10) ? fwd_wb_result  : i_rs1;
    wire [31:0] rs2_fwd = (fwd_rs2_sel == 2'b01) ? fwd_mem_result :
                           (fwd_rs2_sel == 2'b10) ? fwd_wb_result  : i_rs2;

    //-------- ALU 操作数选择 --------
    // OP1 选：0 = rs1, 1 = PC（AUIPC 和跳转地址计算用）
    // OP2 选：0 = rs2, 1 = 立即数（I 型 ALU、访存地址计算用）
    wire [31:0] op1 = i_dec_info[`RVC_DECINFO_OP1SEL] ? i_pc : rs1_fwd;
    wire [31:0] op2 = i_dec_info[`RVC_DECINFO_OP2SEL] ? i_imm : rs2_fwd;

    // LUI 特殊标记：LUI 不经过 ALU 计算，立即数直接输出
    wire is_lui = (grp==`RVC_DECINFO_GRP_ALU) && i_dec_info[`RVC_DECINFO_ALU_LUI];

    //-------- ALU 运算核心 --------
    // 默认做 op1 + op2（加法是 ALU 最常用的操作，因此设为默认值）
    // LUI 优先：立即数直通
    // 其他 ALU 组指令：按独热码选择对应运算
    // 非 ALU 组（LSU/BJP/SYS）：保持默认加法结果（LSU 用作访存地址）
    always @(*) begin
        o_alu_result = op1 + op2;
        if (is_lui) o_alu_result = i_imm;                                  // LUI：立即数直通
        else if (grp == `RVC_DECINFO_GRP_ALU) begin
            if      (i_dec_info[`RVC_DECINFO_ALU_SUB]) o_alu_result = op1 - op2;
            else if (i_dec_info[`RVC_DECINFO_ALU_SLL]) o_alu_result = op1 << op2[4:0];   // 移位数仅低 5 位有效
            else if (i_dec_info[`RVC_DECINFO_ALU_SLT]) o_alu_result = {31'b0, ($signed(op1) < $signed(op2))};
            else if (i_dec_info[`RVC_DECINFO_ALU_SLTU])o_alu_result = {31'b0, (op1 < op2)};
            else if (i_dec_info[`RVC_DECINFO_ALU_XOR]) o_alu_result = op1 ^ op2;
            else if (i_dec_info[`RVC_DECINFO_ALU_SRL]) o_alu_result = op1 >> op2[4:0];
            else if (i_dec_info[`RVC_DECINFO_ALU_SRA]) o_alu_result = $unsigned($signed(op1) >>> op2[4:0]); // 算术右移保持符号
            else if (i_dec_info[`RVC_DECINFO_ALU_OR])  o_alu_result = op1 | op2;
            else if (i_dec_info[`RVC_DECINFO_ALU_AND]) o_alu_result = op1 & op2;
            // 如果没有任何独热位被置位（如 NOP 指令），保持默认的 op1+op2=0
        end
        // non-ALU 组（LSU 地址计算）保持默认加法：op1 + op2
    end

    //-------- 分支/跳转判定逻辑 --------
    // take：是否跳转
    // target：跳转目标地址
    // JUMP 指令比较特殊：它们在 BJP 组但不是条件分支，take 直接置 1
    reg take;
    reg [31:0] target;
    always @(*) begin
        take = 1'b0;
        target = i_pc + i_imm;   // 默认目标地址 = PC + 偏移（用于 JAL 和条件分支）
        if (grp == `RVC_DECINFO_GRP_BJP) begin
            // JAL：无条件跳转，目标 = PC + imm_j（立即数已在译码阶段 x2 对齐）
            if (i_dec_info[`RVC_DECINFO_BJP_JAL]) take = 1'b1;
            // JALR：无条件跳转，目标 = (rs1 + imm_i) & 0xFFFFFFFE（最低位强制 0，避免未对齐）
            else if (i_dec_info[`RVC_DECINFO_BJP_JALR]) begin take=1'b1; target=(rs1_fwd+i_imm)&32'hffff_fffe; end
            // 条件分支：比较 rs1 和 rs2
            else if (i_dec_info[`RVC_DECINFO_BJP_BEQ])  take = (rs1_fwd == rs2_fwd);
            else if (i_dec_info[`RVC_DECINFO_BJP_BNE])  take = (rs1_fwd != rs2_fwd);
            else if (i_dec_info[`RVC_DECINFO_BJP_BLT])  take = ($signed(rs1_fwd) < $signed(rs2_fwd));
            else if (i_dec_info[`RVC_DECINFO_BJP_BGE])  take = ($signed(rs1_fwd) >= $signed(rs2_fwd));
            else if (i_dec_info[`RVC_DECINFO_BJP_BLTU]) take = (rs1_fwd < rs2_fwd);
            else if (i_dec_info[`RVC_DECINFO_BJP_BGEU]) take = (rs1_fwd >= rs2_fwd);
        end
    end

    //-------- 输出直通 --------
    assign i_ready=o_ready; assign o_valid=i_valid; assign o_dec_info=i_dec_info;
    assign o_store_data=rs2_fwd;   // Store 写入数据 = rs2（传往 MEM 阶段）
    assign o_pc_sel=take; assign o_pc_next=target;
    assign o_branch_taken=take; assign o_branch_target=target;
endmodule
