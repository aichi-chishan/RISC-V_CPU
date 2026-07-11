`include "./defines.v"

//==============================================================================
// WB 阶段：在 ALU、Load 数据和 PC+4 中选择最终写回值。
// 当前只有一个来源；未来 M 扩展/CSR/协处理器可在本级之前加入类似 E203
// wbck 的集中仲裁器，寄存器堆仍保持单写口。
//==============================================================================
module rvcpu_wb_stage (
    input wire i_valid, output wire i_ready,
    input wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,
    input wire [31:0] i_alu_result, input wire [31:0] i_mem_result,
    input wire [31:0] i_pc,
    output wire wb_we, output wire [`RVC_RFIDX_WIDTH-1:0] wb_wa,
    output reg [31:0] wb_wd
);
    wire [1:0] sel=i_dec_info[`RVC_DECINFO_WB_SEL];
    always @(*) begin
        case(sel)
            `RVC_WB_SEL_MEM: wb_wd=i_mem_result;
            `RVC_WB_SEL_PC4: wb_wd=i_pc+32'd4;
            default: wb_wd=i_alu_result;
        endcase
    end
    assign wb_we=i_valid && i_dec_info[`RVC_DECINFO_RDWEN];
    assign wb_wa=i_dec_info[`RVC_DECINFO_RDIDX];
    assign i_ready=1'b1;
endmodule
