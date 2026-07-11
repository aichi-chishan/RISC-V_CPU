`include "./defines.v"

// RV32I 六种立即数格式生成器
//
// 根据 opcode 选择对应的立即数格式（I/S/B/U/J），并做符号扩展。
module rvcpu_immgen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    wire [6:0] opcode = instr[6:0];
    always @(*) begin
        case (opcode)
            7'b0010011, 7'b0000011, 7'b1100111:
                imm = {{20{instr[31]}}, instr[31:20]};              // I 型：12 位立即数，符号扩展到 32 位
            7'b0100011:
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]}; // S 型：12 位，分两段存放
            7'b1100011:
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};            // B 型：13 位（末位恒 0），12 位编码
            7'b0110111, 7'b0010111:
                imm = {instr[31:12], 12'b0};                        // U 型：高 20 位，低 12 位补 0
            7'b1101111:
                imm = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};              // J 型：21 位（末位恒 0），20 位编码
            default: imm = 32'b0;
        endcase
    end
endmodule
