`include "./defines.v"

// RV32I 译码器。控制信息打包进 dec_info，供后续阶段按位域读取。
module rvcpu_decode (
    input  wire [31:0] instr,
    input  wire [`RVC_PC_WIDTH-1:0] pc,
    output reg  [`RVC_DECINFO_WIDTH-1:0] dec_info,
    output wire [`RVC_RFIDX_WIDTH-1:0] rs1_idx,
    output wire [`RVC_RFIDX_WIDTH-1:0] rs2_idx,
    output wire rs1_en,
    output wire rs2_en
);
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rd = instr[11:7];
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    assign rs1_idx = instr[19:15];
    assign rs2_idx = instr[24:20];
    assign rs1_en = dec_info[`RVC_DECINFO_RS1EN];
    assign rs2_en = dec_info[`RVC_DECINFO_RS2EN];

    always @(*) begin
        dec_info = {`RVC_DECINFO_WIDTH{1'b0}};
        dec_info[`RVC_DECINFO_RS1IDX] = instr[19:15];
        dec_info[`RVC_DECINFO_RS2IDX] = instr[24:20];
        dec_info[`RVC_DECINFO_RDIDX]  = rd;
        dec_info[`RVC_DECINFO_PC]     = pc;
        dec_info[`RVC_DECINFO_WB_SEL] = `RVC_WB_SEL_ALU;

        case (opcode)
            7'b0110011: begin // R 型整数运算
                dec_info[`RVC_DECINFO_GRP]  = `RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RS1EN]= 1'b1;
                dec_info[`RVC_DECINFO_RS2EN]= 1'b1;
                dec_info[`RVC_DECINFO_RDWEN]= 1'b1;
                case (funct3)
                    3'b000: if (funct7[5]) dec_info[`RVC_DECINFO_ALU_SUB]=1'b1;
                            else           dec_info[`RVC_DECINFO_ALU_ADD]=1'b1;
                    3'b001: dec_info[`RVC_DECINFO_ALU_SLL] = 1'b1;
                    3'b010: dec_info[`RVC_DECINFO_ALU_SLT] = 1'b1;
                    3'b011: dec_info[`RVC_DECINFO_ALU_SLTU]= 1'b1;
                    3'b100: dec_info[`RVC_DECINFO_ALU_XOR] = 1'b1;
                    3'b101: if (funct7[5]) dec_info[`RVC_DECINFO_ALU_SRA]=1'b1;
                            else           dec_info[`RVC_DECINFO_ALU_SRL]=1'b1;
                    3'b110: dec_info[`RVC_DECINFO_ALU_OR]  = 1'b1;
                    3'b111: dec_info[`RVC_DECINFO_ALU_AND] = 1'b1;
                endcase
            end
            7'b0010011: begin // I 型整数运算
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]=1'b1;
                dec_info[`RVC_DECINFO_IMM]=imm_i;
                case (funct3)
                    3'b000: dec_info[`RVC_DECINFO_ALU_ADD]=1'b1;
                    3'b001: dec_info[`RVC_DECINFO_ALU_SLL]=1'b1;
                    3'b010: dec_info[`RVC_DECINFO_ALU_SLT]=1'b1;
                    3'b011: dec_info[`RVC_DECINFO_ALU_SLTU]=1'b1;
                    3'b100: dec_info[`RVC_DECINFO_ALU_XOR]=1'b1;
                    3'b101: if (instr[30]) dec_info[`RVC_DECINFO_ALU_SRA]=1'b1;
                            else           dec_info[`RVC_DECINFO_ALU_SRL]=1'b1;
                    3'b110: dec_info[`RVC_DECINFO_ALU_OR]=1'b1;
                    3'b111: dec_info[`RVC_DECINFO_ALU_AND]=1'b1;
                endcase
            end
            7'b0000011, 7'b0100011: begin // Load / Store
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_LSU;
                dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]=1'b1;
                dec_info[`RVC_DECINFO_ALU_ADD]=1'b1;
                dec_info[`RVC_DECINFO_LSU_SIZE]=funct3[1:0];
                if (opcode == 7'b0000011) begin
                    dec_info[`RVC_DECINFO_LSU_LOAD]=1'b1;
                    dec_info[`RVC_DECINFO_LSU_USIGN]=funct3[2];
                    dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                    dec_info[`RVC_DECINFO_WB_SEL]=`RVC_WB_SEL_MEM;
                    dec_info[`RVC_DECINFO_IMM]=imm_i;
                end else begin
                    dec_info[`RVC_DECINFO_LSU_STORE]=1'b1;
                    dec_info[`RVC_DECINFO_RS2EN]=1'b1;
                    dec_info[`RVC_DECINFO_IMM]=imm_s;
                end
            end
            7'b1100011: begin // 条件分支
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_BJP;
                dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                dec_info[`RVC_DECINFO_RS2EN]=1'b1;
                dec_info[`RVC_DECINFO_IMM]=imm_b;
                case (funct3)
                    3'b000: dec_info[`RVC_DECINFO_BJP_BEQ]=1'b1;
                    3'b001: dec_info[`RVC_DECINFO_BJP_BNE]=1'b1;
                    3'b100: dec_info[`RVC_DECINFO_BJP_BLT]=1'b1;
                    3'b101: dec_info[`RVC_DECINFO_BJP_BGE]=1'b1;
                    3'b110: dec_info[`RVC_DECINFO_BJP_BLTU]=1'b1;
                    3'b111: dec_info[`RVC_DECINFO_BJP_BGEU]=1'b1;
                endcase
            end
            7'b1101111, 7'b1100111: begin // JAL / JALR
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_BJP;
                dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                dec_info[`RVC_DECINFO_WB_SEL]=`RVC_WB_SEL_PC4;
                dec_info[`RVC_DECINFO_IMM]=(opcode==7'b1101111)?imm_j:imm_i;
                if (opcode==7'b1101111) dec_info[`RVC_DECINFO_BJP_JAL]=1'b1;
                else begin
                    dec_info[`RVC_DECINFO_BJP_JALR]=1'b1;
                    dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                end
            end
            7'b0110111, 7'b0010111: begin // LUI / AUIPC
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]=1'b1;
                dec_info[`RVC_DECINFO_IMM]=imm_u;
                if (opcode==7'b0110111) dec_info[`RVC_DECINFO_ALU_LUI]=1'b1;
                else begin
                    dec_info[`RVC_DECINFO_ALU_AUIPC]=1'b1;
                    dec_info[`RVC_DECINFO_OP1SEL]=1'b1;
                end
            end
            default: dec_info[`RVC_DECINFO_ALU_NOP]=1'b1;
        endcase
    end
endmodule
