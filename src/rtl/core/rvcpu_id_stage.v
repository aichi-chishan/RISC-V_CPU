`include "./defines.v"

//==============================================================================
// ID 阶段：译码、读取寄存器堆，并形成送往 EX 的统一 payload。
// 寄存器堆写口集中从 WB 返回，保持单写口结构，便于以后增加写回仲裁器。
//==============================================================================
module rvcpu_id_stage (
    input wire clk, input wire rst_n,
    input wire i_valid, output wire i_ready,
    input wire [31:0] i_ir, input wire [`RVC_PC_WIDTH-1:0] i_pc,
    input wire wb_we, input wire [`RVC_RFIDX_WIDTH-1:0] wb_wa,
    input wire [`RVC_XLEN-1:0] wb_wd,
    output wire o_valid, input wire o_ready,
    output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,
    output wire [`RVC_XLEN-1:0] o_rs1, output wire [`RVC_XLEN-1:0] o_rs2
);
    wire [4:0] rs1_idx, rs2_idx;
    wire rs1_en, rs2_en;
    wire [31:0] rs1_raw, rs2_raw;

    rvcpu_decode u_decode(.instr(i_ir), .pc(i_pc), .dec_info(o_dec_info),
        .rs1_idx(rs1_idx), .rs2_idx(rs2_idx), .rs1_en(rs1_en), .rs2_en(rs2_en));
    rvcpu_regfile u_regfile(.clk(clk), .rst_n(rst_n), .rs1_addr(rs1_idx),
        .rs2_addr(rs2_idx), .rs1_data(rs1_raw), .rs2_data(rs2_raw),
        .wb_we(wb_we), .wb_wa(wb_wa), .wb_wd(wb_wd));

    assign i_ready = o_ready;
    assign o_valid = i_valid;
    assign o_rs1 = rs1_en ? rs1_raw : 32'b0; // 减少数据线翻转，降低功耗
    assign o_rs2 = rs2_en ? rs2_raw : 32'b0; // 减少数据线翻转，降低功耗
    // imm 与 PC 已分别位于 dec_info 的公共字段中，不能再通过独立端口重复传递。
endmodule
