`include "./defines.v"

//==============================================================================
// RV32I 译码器：按 opcode/funct3/funct7 生成唯一的 dec_info 宽控制总线。
// 低位为公共字段，高位为按指令组复用的独热控制字段。
//==============================================================================
module rvcpu_decode (
    input  wire [31:0] instr,
    input  wire [`RVC_PC_WIDTH-1:0] pc,
    output reg  [`RVC_DECINFO_WIDTH-1:0] dec_info,
    output wire [`RVC_RFIDX_WIDTH-1:0] rs1_idx,
    output wire [`RVC_RFIDX_WIDTH-1:0] rs2_idx,
    output wire rs1_en,
    output wire rs2_en
);
    // 指令字段拆分
    wire [6:0] opcode = instr[6:0];
    wire [2:0] funct3 = instr[14:12];
    wire [6:0] funct7 = instr[31:25];
    wire [4:0] rd = instr[11:7];
    // 六种立即数格式：I/S/B/U/J 型，均以 [31] 符号位扩展至 32 位
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // 寄存器地址直接从指令字段取出（无需译码）
    assign rs1_idx = instr[19:15];
    assign rs2_idx = instr[24:20];
    // 读使能从译码结果中读取（译码决定哪些寄存器被用到）
    assign rs1_en = dec_info[`RVC_DECINFO_RS1EN];
    assign rs2_en = dec_info[`RVC_DECINFO_RS2EN];

    // 译码主逻辑：按 opcode 区分指令类型，设置 dec_info 对应位域
    always @(*) begin
        dec_info = {`RVC_DECINFO_WIDTH{1'b0}};              // 默认全零
        dec_info[`RVC_DECINFO_RS1IDX] = instr[19:15];       // 三段寄存器地址始终写入
        dec_info[`RVC_DECINFO_RS2IDX] = instr[24:20];
        dec_info[`RVC_DECINFO_RDIDX]  = rd;
        dec_info[`RVC_DECINFO_PC]     = pc;
        dec_info[`RVC_DECINFO_WB_SEL] = `RVC_WB_SEL_ALU;    // 默认写回 ALU 结果

        case (opcode)
            7'b0110011: begin // R 型：寄存器 - 寄存器运算（rs1 OP rs2 → rd）
                dec_info[`RVC_DECINFO_GRP]  = `RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RS1EN]= 1'b1;
                dec_info[`RVC_DECINFO_RS2EN]= 1'b1;
                dec_info[`RVC_DECINFO_RDWEN]= 1'b1;
                case (funct3)
                    3'b000: if (funct7[5]) dec_info[`RVC_DECINFO_ALU_SUB]=1'b1;   // SUB
                            else           dec_info[`RVC_DECINFO_ALU_ADD]=1'b1;   // ADD
                    3'b001: dec_info[`RVC_DECINFO_ALU_SLL] = 1'b1;                // SLL
                    3'b010: dec_info[`RVC_DECINFO_ALU_SLT] = 1'b1;                // SLT
                    3'b011: dec_info[`RVC_DECINFO_ALU_SLTU]= 1'b1;                // SLTU
                    3'b100: dec_info[`RVC_DECINFO_ALU_XOR] = 1'b1;                // XOR
                    3'b101: if (funct7[5]) dec_info[`RVC_DECINFO_ALU_SRA]=1'b1;   // SRA
                            else           dec_info[`RVC_DECINFO_ALU_SRL]=1'b1;   // SRL
                    3'b110: dec_info[`RVC_DECINFO_ALU_OR]  = 1'b1;                // OR
                    3'b111: dec_info[`RVC_DECINFO_ALU_AND] = 1'b1;                // AND
                    default: begin end  // 安全默认，避免推断锁存器
                endcase
            end
            7'b0010011: begin // I 型：立即数运算（rs1 OP imm → rd）
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]=1'b1;          // ALU op2 选立即数
                dec_info[`RVC_DECINFO_IMM]=imm_i;
                case (funct3)
                    3'b000: dec_info[`RVC_DECINFO_ALU_ADD]=1'b1;                  // ADDI
                    3'b001: dec_info[`RVC_DECINFO_ALU_SLL]=1'b1;                  // SLLI
                    3'b010: dec_info[`RVC_DECINFO_ALU_SLT]=1'b1;                  // SLTI
                    3'b011: dec_info[`RVC_DECINFO_ALU_SLTU]=1'b1;                 // SLTIU
                    3'b100: dec_info[`RVC_DECINFO_ALU_XOR]=1'b1;                  // XORI
                    3'b101: if (instr[30]) dec_info[`RVC_DECINFO_ALU_SRA]=1'b1;   // SRAI
                            else           dec_info[`RVC_DECINFO_ALU_SRL]=1'b1;   // SRLI
                    3'b110: dec_info[`RVC_DECINFO_ALU_OR]=1'b1;                   // ORI
                    3'b111: dec_info[`RVC_DECINFO_ALU_AND]=1'b1;                  // ANDI
                    default: begin end  // 安全默认，避免推断锁存器
                endcase
            end
            7'b0000011, 7'b0100011: begin // Load / Store
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_LSU;
                dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]=1'b1;          // 基址+偏移，op2 选立即数
                dec_info[`RVC_DECINFO_ALU_ADD]=1'b1;         // ALU 做地址加法
                dec_info[`RVC_DECINFO_LSU_SIZE]=funct3[1:0]; // 字长：00=byte,01=half,10=word
                if (opcode == 7'b0000011) begin
                    // Load：ALU 结果作为地址读 DMEM，结果写回 rd
                    dec_info[`RVC_DECINFO_LSU_LOAD]=1'b1;
                    dec_info[`RVC_DECINFO_LSU_USIGN]=funct3[2]; // 0=有符号扩展,1=无符号扩展
                    dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                    dec_info[`RVC_DECINFO_WB_SEL]=`RVC_WB_SEL_MEM; // 写回选 MEM 读出数据
                    dec_info[`RVC_DECINFO_IMM]=imm_i;
                end else begin
                    // Store：ALU 结果作为地址，rs2 数据写入 DMEM
                    dec_info[`RVC_DECINFO_LSU_STORE]=1'b1;
                    dec_info[`RVC_DECINFO_RS2EN]=1'b1;
                    dec_info[`RVC_DECINFO_IMM]=imm_s;
                end
            end
            7'b1100011: begin // 条件分支：BEQ/BNE/BLT/BGE/BLTU/BGEU
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_BJP;
                dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                dec_info[`RVC_DECINFO_RS2EN]=1'b1;
                dec_info[`RVC_DECINFO_IMM]=imm_b;            // B 型立即数（已 x2 对齐，末位 0）
                case (funct3)
                    3'b000: dec_info[`RVC_DECINFO_BJP_BEQ]=1'b1;
                    3'b001: dec_info[`RVC_DECINFO_BJP_BNE]=1'b1;
                    3'b100: dec_info[`RVC_DECINFO_BJP_BLT]=1'b1;
                    3'b101: dec_info[`RVC_DECINFO_BJP_BGE]=1'b1;
                    3'b110: dec_info[`RVC_DECINFO_BJP_BLTU]=1'b1;
                    3'b111: dec_info[`RVC_DECINFO_BJP_BGEU]=1'b1;
                    default: begin end  // 安全默认，避免推断锁存器
                endcase
            end
            7'b1101111, 7'b1100111: begin // JAL / JALR（无条件跳转并链接）
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_BJP;
                dec_info[`RVC_DECINFO_RDWEN]=1'b1;              // 保存返回地址到 rd
                dec_info[`RVC_DECINFO_WB_SEL]=`RVC_WB_SEL_PC4;  // 写回 PC+4
                dec_info[`RVC_DECINFO_IMM]=(opcode==7'b1101111)?imm_j:imm_i;
                if (opcode==7'b1101111) dec_info[`RVC_DECINFO_BJP_JAL]=1'b1;   // JAL：PC+imm
                else begin
                    dec_info[`RVC_DECINFO_BJP_JALR]=1'b1;                      // JALR：rs1+imm
                    dec_info[`RVC_DECINFO_RS1EN]=1'b1;
                end
            end
            7'b0110111, 7'b0010111: begin // LUI / AUIPC
                dec_info[`RVC_DECINFO_GRP]=`RVC_DECINFO_GRP_ALU;
                dec_info[`RVC_DECINFO_RDWEN]=1'b1;
                dec_info[`RVC_DECINFO_OP2SEL]=1'b1;             // op2 选立即数
                dec_info[`RVC_DECINFO_IMM]=imm_u;
                if (opcode==7'b0110111) dec_info[`RVC_DECINFO_ALU_LUI]=1'b1;   // LUI：立即数直通
                else begin
                    dec_info[`RVC_DECINFO_ALU_AUIPC]=1'b1;                     // AUIPC：PC+立即数
                    dec_info[`RVC_DECINFO_OP1SEL]=1'b1;                        // op1 选 PC
                end
            end
            default: dec_info[`RVC_DECINFO_ALU_NOP]=1'b1;       // 未知指令当作 NOP（ADDI x0,x0,0）
        endcase
    end
endmodule
