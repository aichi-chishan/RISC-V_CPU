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
    input wire [31:0] i_rs1, input wire [31:0] i_rs2, input wire [31:0] i_imm,
    input wire [31:0] i_pc, input wire [31:0] i_ir,
    output wire o_pc_sel, output wire [31:0] o_pc_next,
    output wire o_branch_taken, output wire [31:0] o_branch_target,
    input wire [31:0] fwd_mem_result, input wire [31:0] fwd_wb_result,
    input wire [1:0] fwd_rs1_sel, input wire [1:0] fwd_rs2_sel,
    output wire o_valid, input wire o_ready,
    output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,
    output reg [31:0] o_alu_result, output wire [31:0] o_store_data,
    output wire [31:0] o_pc, output wire [31:0] o_ir
);
    wire [2:0] grp = i_dec_info[`RVC_DECINFO_GRP];

    // 前推 MUX 与 ALU 操作数 MUX 分开，方便未来独立做时序优化。
    wire [31:0] rs1_fwd = (fwd_rs1_sel == 2'b01) ? fwd_mem_result :
                           (fwd_rs1_sel == 2'b10) ? fwd_wb_result  : i_rs1;
    wire [31:0] rs2_fwd = (fwd_rs2_sel == 2'b01) ? fwd_mem_result :
                           (fwd_rs2_sel == 2'b10) ? fwd_wb_result  : i_rs2;
    wire [31:0] op1 = i_dec_info[`RVC_DECINFO_OP1SEL] ? i_pc : rs1_fwd;
    wire [31:0] op2 = i_dec_info[`RVC_DECINFO_OP2SEL] ? i_imm : rs2_fwd;
    wire is_lui = (grp==`RVC_DECINFO_GRP_ALU) && i_dec_info[`RVC_DECINFO_ALU_LUI];

    always @(*) begin
        o_alu_result = op1 + op2;
        if (is_lui) o_alu_result = i_imm;
        else if (grp == `RVC_DECINFO_GRP_ALU) begin
            if (i_dec_info[`RVC_DECINFO_ALU_SUB])       o_alu_result = op1 - op2;
            else if (i_dec_info[`RVC_DECINFO_ALU_SLL]) o_alu_result = op1 << op2[4:0];
            else if (i_dec_info[`RVC_DECINFO_ALU_SLT]) o_alu_result = ($signed(op1) < $signed(op2));
            else if (i_dec_info[`RVC_DECINFO_ALU_SLTU])o_alu_result = (op1 < op2);
            else if (i_dec_info[`RVC_DECINFO_ALU_XOR]) o_alu_result = op1 ^ op2;
            else if (i_dec_info[`RVC_DECINFO_ALU_SRL]) o_alu_result = op1 >> op2[4:0];
            else if (i_dec_info[`RVC_DECINFO_ALU_SRA]) o_alu_result = $signed(op1) >>> op2[4:0];
            else if (i_dec_info[`RVC_DECINFO_ALU_OR])  o_alu_result = op1 | op2;
            else if (i_dec_info[`RVC_DECINFO_ALU_AND]) o_alu_result = op1 & op2;
        end
    end

    reg take;
    reg [31:0] target;
    always @(*) begin
        take = 1'b0;
        target = i_pc + i_imm;
        if (grp == `RVC_DECINFO_GRP_BJP) begin
            if (i_dec_info[`RVC_DECINFO_BJP_JAL]) take = 1'b1;
            else if (i_dec_info[`RVC_DECINFO_BJP_JALR]) begin take=1'b1; target=(rs1_fwd+i_imm)&32'hffff_fffe; end
            else if (i_dec_info[`RVC_DECINFO_BJP_BEQ])  take = (rs1_fwd == rs2_fwd);
            else if (i_dec_info[`RVC_DECINFO_BJP_BNE]) take = (rs1_fwd != rs2_fwd);
            else if (i_dec_info[`RVC_DECINFO_BJP_BLT]) take = ($signed(rs1_fwd) < $signed(rs2_fwd));
            else if (i_dec_info[`RVC_DECINFO_BJP_BGE]) take = ($signed(rs1_fwd) >= $signed(rs2_fwd));
            else if (i_dec_info[`RVC_DECINFO_BJP_BLTU])take = (rs1_fwd < rs2_fwd);
            else if (i_dec_info[`RVC_DECINFO_BJP_BGEU])take = (rs1_fwd >= rs2_fwd);
        end
    end
    assign i_ready=o_ready; assign o_valid=i_valid; assign o_dec_info=i_dec_info;
    assign o_store_data=rs2_fwd; assign o_pc=i_pc; assign o_ir=i_ir;
    assign o_pc_sel=take; assign o_pc_next=target;
    assign o_branch_taken=take; assign o_branch_target=target;
endmodule
