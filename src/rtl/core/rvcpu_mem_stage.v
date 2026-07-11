`include "./defines.v"

//==============================================================================
// MEM 阶段：生成 Store 字节掩码，完成 Load 数据抽取和符号扩展。
// 地址在 EX 已算好；这里把字节地址拆成“字地址 + 字内偏移”。未来接同步
// BRAM 时，可用 valid/ready 将 o_valid 延后一拍，无需修改译码格式。
//==============================================================================
module rvcpu_mem_stage (
    input wire clk, input wire rst_n,
    input wire i_valid, output wire i_ready,
    input wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,
    input wire [31:0] i_alu_result, input wire [31:0] i_store_data,
    input wire [31:0] i_pc, input wire [31:0] i_ir,
    output wire [`RVC_DMEM_AW-1:0] dmem_addr,
    output reg [31:0] dmem_wdata, output reg [3:0] dmem_wmask,
    output wire dmem_wen, input wire [31:0] dmem_rdata,
    output wire o_valid, input wire o_ready,
    output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,
    output wire [31:0] o_alu_result, output reg [31:0] o_mem_result,
    output wire [31:0] o_pc, output wire [31:0] o_ir
);
    wire is_lsu = i_dec_info[`RVC_DECINFO_GRP] == `RVC_DECINFO_GRP_LSU;
    wire is_load = is_lsu && i_dec_info[`RVC_DECINFO_LSU_LOAD];
    wire is_store= is_lsu && i_dec_info[`RVC_DECINFO_LSU_STORE];
    wire [1:0] size = i_dec_info[`RVC_DECINFO_LSU_SIZE];
    wire unsign = i_dec_info[`RVC_DECINFO_LSU_USIGN];
    wire [1:0] off = i_alu_result[1:0];
    reg [7:0] byte_v; reg [15:0] half_v;

    assign dmem_addr = i_alu_result[`RVC_DMEM_AW+1:2];
    always @(*) begin
        dmem_wmask=4'b0; dmem_wdata=32'b0;
        case (size)
            2'b00: begin dmem_wmask=4'b0001 << off; dmem_wdata=i_store_data << (off*8); end
            2'b01: begin dmem_wmask=4'b0011 << {off[1],1'b0}; dmem_wdata=i_store_data << (off[1]*16); end
            default: begin dmem_wmask=4'b1111; dmem_wdata=i_store_data; end
        endcase
    end
    always @(*) begin
        byte_v = dmem_rdata >> (off*8);
        half_v = dmem_rdata >> (off[1]*16);
        case (size)
            2'b00: o_mem_result = unsign ? {24'b0,byte_v} : {{24{byte_v[7]}},byte_v};
            2'b01: o_mem_result = unsign ? {16'b0,half_v} : {{16{half_v[15]}},half_v};
            default: o_mem_result = dmem_rdata;
        endcase
    end
    assign dmem_wen=i_valid && is_store;
    assign i_ready=o_ready; assign o_valid=i_valid; assign o_dec_info=i_dec_info;
    assign o_alu_result=i_alu_result; assign o_pc=i_pc; assign o_ir=i_ir;
endmodule
