`include "./defines.v"

//==============================================================================
// RV32I 指令译码器
//
// 本模块只负责回答两件事：
//   1. 当前 32 位指令是不是本阶段支持的、编码合法的 RV32I 指令；
//   2. 若合法，后续 EX/MEM/WB 阶段各自需要做什么。
//
// 所有控制信息都装入 dec_info。这样可以避免不同阶段重复译码同一条指令，
// 也是后续改造为五级流水时最重要的接口边界。
//
// 当前 Phase 1 尚未实现异常单元，因此非法编码被安全地当作 NOP：不读写
// 存储器、不改写通用寄存器，也不改变 PC 的正常顺序流。将来加入异常后，
// 只需在默认分支中补充 illegal-instruction 异常标记即可。
//==============================================================================
module rvcpu_decode (
    input  wire [31:0] instr,
    input  wire [`RVC_PC_WIDTH-1:0] pc,
    output reg  [`RVC_DECINFO_WIDTH-1:0] dec_info,
    output wire [`RVC_RFIDX_WIDTH-1:0] rs1_idx,
    output wire [`RVC_RFIDX_WIDTH-1:0] rs2_idx,
    output wire rs1_en,
    output wire rs2_en,
    output wire illegal
);
    // RV32I 的公共指令字段。
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rd     = instr[11:7];

    // 各类立即数均在译码阶段扩展为 32 位字节偏移/操作数。
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                         instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                         instr[20], instr[30:21], 1'b0};

    assign rs1_idx = instr[19:15];
    assign rs2_idx = instr[24:20];
    assign rs1_en  = dec_info[`RVC_DECINFO_RS1EN];
    assign rs2_en  = dec_info[`RVC_DECINFO_RS2EN];

    // 将一条普通 ALU 指令共有的控制字段放在这里，正文中每次只需选择
    // 运算种类即可。这里不能设为 task，因为 dec_info 是组合逻辑输出，
    // 明确地在每个合法分支中赋值更便于波形分析和综合检查。
    always @(*) begin
        // 默认是无副作用 NOP。特别注意：RDWEN 默认为 0，防止错误编码
        // 因为 rd 字段碰巧非零而破坏寄存器堆。
        dec_info = {`RVC_DECINFO_WIDTH{1'b0}};
        dec_info[`RVC_DECINFO_RS1IDX] = instr[19:15];
        dec_info[`RVC_DECINFO_RS2IDX] = instr[24:20];
        dec_info[`RVC_DECINFO_RDIDX]  = rd;
        dec_info[`RVC_DECINFO_PC]     = pc;
        dec_info[`RVC_DECINFO_WB_SEL] = `RVC_WB_SEL_ALU;
        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b1;

        case (opcode)
            //----------------------------------------------------------------------
            // OP：寄存器-寄存器整数运算。RV32I 只允许 funct7 为 0000000，
            // ADD/SUB、SRL/SRA 两对例外分别还允许 0100000。
            //----------------------------------------------------------------------
            7'b0110011: begin
                if (funct7 == 7'b0000001) begin
                    dec_info[`RVC_DECINFO_GRP] = `RVC_DECINFO_GRP_MULDIV;
                    dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                    dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                    dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                    dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                    dec_info[`RVC_DECINFO_MDU_OP] = funct3;
                end else begin
                case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                            dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                            dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                            dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                            dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                            dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                            if (funct7 == 7'b0000000)
                                dec_info[`RVC_DECINFO_ALU_ADD] = 1'b1;
                            else
                                dec_info[`RVC_DECINFO_ALU_SUB] = 1'b1;
                        end
                    end
                    3'b001: if (funct7 == 7'b0000000) begin // SLL
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_SLL] = 1'b1;
                    end
                    3'b010: if (funct7 == 7'b0000000) begin // SLT
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_SLT] = 1'b1;
                    end
                    3'b011: if (funct7 == 7'b0000000) begin // SLTU
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_SLTU] = 1'b1;
                    end
                    3'b100: if (funct7 == 7'b0000000) begin // XOR
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_XOR] = 1'b1;
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                            dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                            dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                            dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                            dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                            dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                            if (funct7 == 7'b0000000)
                                dec_info[`RVC_DECINFO_ALU_SRL] = 1'b1;
                            else
                                dec_info[`RVC_DECINFO_ALU_SRA] = 1'b1;
                        end
                    end
                    3'b110: if (funct7 == 7'b0000000) begin // OR
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_OR] = 1'b1;
                    end
                    3'b111: if (funct7 == 7'b0000000) begin // AND
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_AND] = 1'b1;
                    end
                    default: begin end
                endcase
                end
            end

            //----------------------------------------------------------------------
            // OP-IMM：立即数运算。移位立即数在 RV32I 中的高 7 位不是任意值，
            // 必须严格检查，以免将 M/保留扩展错误解释为普通移位。
            //----------------------------------------------------------------------
            7'b0010011: begin
                case (funct3)
                    3'b000, 3'b010, 3'b011, 3'b100, 3'b110, 3'b111: begin
                        dec_info[`RVC_DECINFO_GRP]    = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN]  = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN]  = 1'b1;
                        dec_info[`RVC_DECINFO_OP2SEL] = 1'b1;
                        dec_info[`RVC_DECINFO_IMM]    = imm_i;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        case (funct3)
                            3'b000: dec_info[`RVC_DECINFO_ALU_ADD]  = 1'b1; // ADDI
                            3'b010: dec_info[`RVC_DECINFO_ALU_SLT]  = 1'b1; // SLTI
                            3'b011: dec_info[`RVC_DECINFO_ALU_SLTU] = 1'b1; // SLTIU
                            3'b100: dec_info[`RVC_DECINFO_ALU_XOR]  = 1'b1; // XORI
                            3'b110: dec_info[`RVC_DECINFO_ALU_OR]   = 1'b1; // ORI
                            default: dec_info[`RVC_DECINFO_ALU_AND] = 1'b1; // ANDI
                        endcase
                    end
                    3'b001: if (funct7 == 7'b0000000) begin // SLLI
                        dec_info[`RVC_DECINFO_GRP]    = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN]  = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN]  = 1'b1;
                        dec_info[`RVC_DECINFO_OP2SEL] = 1'b1;
                        dec_info[`RVC_DECINFO_IMM]    = imm_i;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        dec_info[`RVC_DECINFO_ALU_SLL] = 1'b1;
                    end
                    3'b101: if (funct7 == 7'b0000000 || funct7 == 7'b0100000) begin
                        dec_info[`RVC_DECINFO_GRP]    = `RVC_DECINFO_GRP_ALU;
                        dec_info[`RVC_DECINFO_RS1EN]  = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN]  = 1'b1;
                        dec_info[`RVC_DECINFO_OP2SEL] = 1'b1;
                        dec_info[`RVC_DECINFO_IMM]    = imm_i;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        if (funct7 == 7'b0000000)
                            dec_info[`RVC_DECINFO_ALU_SRL] = 1'b1; // SRLI
                        else
                            dec_info[`RVC_DECINFO_ALU_SRA] = 1'b1; // SRAI
                    end
                    default: begin end
                endcase
            end

            //----------------------------------------------------------------------
            // Load：只接收 LB/LH/LW/LBU/LHU 五种 funct3 组合。
            //----------------------------------------------------------------------
            7'b0000011: begin
                case (funct3)
                    3'b000, 3'b001, 3'b010, 3'b100, 3'b101: begin
                        dec_info[`RVC_DECINFO_GRP]       = `RVC_DECINFO_GRP_LSU;
                        dec_info[`RVC_DECINFO_RS1EN]     = 1'b1;
                        dec_info[`RVC_DECINFO_RDWEN]     = 1'b1;
                        dec_info[`RVC_DECINFO_OP2SEL]    = 1'b1;
                        dec_info[`RVC_DECINFO_IMM]       = imm_i;
                        dec_info[`RVC_DECINFO_ALU_ADD]   = 1'b1;
                        dec_info[`RVC_DECINFO_LSU_LOAD]  = 1'b1;
                        dec_info[`RVC_DECINFO_WB_SEL]    = `RVC_WB_SEL_MEM;
                        dec_info[`RVC_DECINFO_ALU_NOP]   = 1'b0;
                        case (funct3)
                            3'b000: dec_info[`RVC_DECINFO_LSU_SIZE] = 2'b00; // LB
                            3'b001: dec_info[`RVC_DECINFO_LSU_SIZE] = 2'b01; // LH
                            3'b010: dec_info[`RVC_DECINFO_LSU_SIZE] = 2'b10; // LW
                            3'b100: begin                                  // LBU
                                dec_info[`RVC_DECINFO_LSU_SIZE]  = 2'b00;
                                dec_info[`RVC_DECINFO_LSU_USIGN] = 1'b1;
                            end
                            default: begin                                  // LHU
                                dec_info[`RVC_DECINFO_LSU_SIZE]  = 2'b01;
                                dec_info[`RVC_DECINFO_LSU_USIGN] = 1'b1;
                            end
                        endcase
                    end
                    default: begin end
                endcase
            end

            // Store：只接收 SB/SH/SW。非法 funct3 不得产生写存储器使能。
            7'b0100011: begin
                case (funct3)
                    3'b000, 3'b001, 3'b010: begin
                        dec_info[`RVC_DECINFO_GRP]        = `RVC_DECINFO_GRP_LSU;
                        dec_info[`RVC_DECINFO_RS1EN]      = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN]      = 1'b1;
                        dec_info[`RVC_DECINFO_OP2SEL]     = 1'b1;
                        dec_info[`RVC_DECINFO_IMM]        = imm_s;
                        dec_info[`RVC_DECINFO_ALU_ADD]    = 1'b1;
                        dec_info[`RVC_DECINFO_LSU_STORE]  = 1'b1;
                        dec_info[`RVC_DECINFO_LSU_SIZE]   = funct3[1:0];
                        dec_info[`RVC_DECINFO_ALU_NOP]    = 1'b0;
                    end
                    default: begin end
                endcase
            end

            // 六种条件分支。分支不写 rd，但两个比较操作数都需要从寄存器堆读取。
            7'b1100011: begin
                case (funct3)
                    3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111: begin
                        dec_info[`RVC_DECINFO_GRP]   = `RVC_DECINFO_GRP_BJP;
                        dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                        dec_info[`RVC_DECINFO_RS2EN] = 1'b1;
                        dec_info[`RVC_DECINFO_IMM]   = imm_b;
                        dec_info[`RVC_DECINFO_ALU_NOP] = 1'b0;
                        case (funct3)
                            3'b000: dec_info[`RVC_DECINFO_BJP_BEQ]  = 1'b1;
                            3'b001: dec_info[`RVC_DECINFO_BJP_BNE]  = 1'b1;
                            3'b100: dec_info[`RVC_DECINFO_BJP_BLT]  = 1'b1;
                            3'b101: dec_info[`RVC_DECINFO_BJP_BGE]  = 1'b1;
                            3'b110: dec_info[`RVC_DECINFO_BJP_BLTU] = 1'b1;
                            default: dec_info[`RVC_DECINFO_BJP_BGEU] = 1'b1;
                        endcase
                    end
                    default: begin end
                endcase
            end

            // JAL 的 rd 保存 PC+4；JALR 额外要求 funct3 必须为 000。
            7'b1101111: begin
                dec_info[`RVC_DECINFO_GRP]      = `RVC_DECINFO_GRP_BJP;
                dec_info[`RVC_DECINFO_RDWEN]    = 1'b1;
                dec_info[`RVC_DECINFO_WB_SEL]   = `RVC_WB_SEL_PC4;
                dec_info[`RVC_DECINFO_IMM]      = imm_j;
                dec_info[`RVC_DECINFO_BJP_JAL]  = 1'b1;
                dec_info[`RVC_DECINFO_ALU_NOP]  = 1'b0;
            end
            7'b1100111: if (funct3 == 3'b000) begin
                dec_info[`RVC_DECINFO_GRP]       = `RVC_DECINFO_GRP_BJP;
                dec_info[`RVC_DECINFO_RS1EN]     = 1'b1;
                dec_info[`RVC_DECINFO_RDWEN]     = 1'b1;
                dec_info[`RVC_DECINFO_WB_SEL]    = `RVC_WB_SEL_PC4;
                dec_info[`RVC_DECINFO_IMM]       = imm_i;
                dec_info[`RVC_DECINFO_BJP_JALR]  = 1'b1;
                dec_info[`RVC_DECINFO_ALU_NOP]   = 1'b0;
            end

            // LUI 将 U 立即数直接送到写回端；AUIPC 则使用 PC 作为 ALU 的第一个操作数。
            7'b0110111: begin
                dec_info[`RVC_DECINFO_GRP]      = `RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RDWEN]    = 1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]   = 1'b1;
                dec_info[`RVC_DECINFO_IMM]      = imm_u;
                dec_info[`RVC_DECINFO_ALU_LUI]  = 1'b1;
                dec_info[`RVC_DECINFO_ALU_NOP]  = 1'b0;
            end
            7'b0010111: begin
                dec_info[`RVC_DECINFO_GRP]       = `RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RDWEN]     = 1'b1;
                dec_info[`RVC_DECINFO_OP1SEL]    = 1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]    = 1'b1;
                dec_info[`RVC_DECINFO_IMM]       = imm_u;
                dec_info[`RVC_DECINFO_ALU_AUIPC] = 1'b1;
                dec_info[`RVC_DECINFO_ALU_NOP]   = 1'b0;
            end

            // FENCE 属于 RV32I 基本指令，但当前单发射、多周期内核没有乱序存储
            // 或缓存，因此其可见效果就是等待此前指令完成后作为 NOP 继续执行。
            7'b0001111: if (funct3 == 3'b000) begin
                dec_info[`RVC_DECINFO_ALU_NOP] = 1'b1;
                dec_info[`RVC_DECINFO_GRP] = `RVC_DECINFO_GRP_SYS;
                dec_info[`RVC_DECINFO_SYS_FENCE] = 1'b1;
            end

            // SYSTEM：支持机器模式 ECALL/EBREAK/MRET 和 Zicsr 六条指令。
            // CSR 地址直接保留在流水中的原始指令里，避免扩大公共译码总线。
            7'b1110011: begin
                if (instr == 32'h0000_0073) begin
                    dec_info[`RVC_DECINFO_GRP] = `RVC_DECINFO_GRP_SYS;
                    dec_info[`RVC_DECINFO_SYS_ECALL] = 1'b1;
                end else if (instr == 32'h0010_0073) begin
                    dec_info[`RVC_DECINFO_GRP] = `RVC_DECINFO_GRP_SYS;
                    dec_info[`RVC_DECINFO_SYS_EBREAK] = 1'b1;
                end else if (instr == 32'h3020_0073) begin
                    dec_info[`RVC_DECINFO_GRP] = `RVC_DECINFO_GRP_SYS;
                    dec_info[`RVC_DECINFO_SYS_MRET] = 1'b1;
                end else if (funct3 != 3'b000 && funct3 != 3'b100) begin
                    dec_info[`RVC_DECINFO_GRP] = `RVC_DECINFO_GRP_SYS;
                    dec_info[`RVC_DECINFO_SYS_CSR] = 1'b1;
                    dec_info[`RVC_DECINFO_SYS_CSR_CMD] = funct3[1:0];
                    dec_info[`RVC_DECINFO_SYS_CSR_IMM] = funct3[2];
                    dec_info[`RVC_DECINFO_RDWEN] = 1'b1;
                    dec_info[`RVC_DECINFO_WB_SEL] = `RVC_WB_SEL_CSR;
                    if (!funct3[2]) dec_info[`RVC_DECINFO_RS1EN] = 1'b1;
                end
            end

            default: begin end
        endcase
    end

    // 默认译码仍保留 ALU_NOP。只有规范 NOP、合法 FENCE 或已识别的 SYSTEM
    // 指令可以在 ALU_NOP 保持为 1 时被视为合法，其余保留编码触发非法指令异常。
    assign illegal = dec_info[`RVC_DECINFO_ALU_NOP] &&
                     (instr != `RVC_NOP_INSTR) &&
                     !dec_info[`RVC_DECINFO_SYS_FENCE] &&
                     !dec_info[`RVC_DECINFO_SYS_ECALL] &&
                     !dec_info[`RVC_DECINFO_SYS_EBREAK] &&
                     !dec_info[`RVC_DECINFO_SYS_MRET] &&
                     !dec_info[`RVC_DECINFO_SYS_CSR];
endmodule
