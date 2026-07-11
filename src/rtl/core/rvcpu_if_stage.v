`include "./defines.v"

//==============================================================================
// IF 阶段：维护 PC，并将字节地址转换成 IMEM 字地址。
// stall 和跳转接口已保留；未来可在其后接弹性 IF/ID 寄存器，并把 IMEM
// 替换为带握手的同步 BRAM、Cache 或片外总线。
//==============================================================================
module rvcpu_if_stage (
    input wire clk, input wire rst_n,
    output wire [`RVC_IMEM_AW-1:0] imem_addr, input wire [31:0] imem_rdata,
    input wire ctrl_pc_sel, input wire [31:0] ctrl_pc_next, input wire stall,
    output wire o_valid, input wire o_ready,
    output wire [31:0] o_ir, output wire [31:0] o_pc
);
    reg [31:0] pc_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pc_r <= `RVC_RESET_PC;
        else if (!stall && o_ready) pc_r <= ctrl_pc_sel ? ctrl_pc_next : pc_r + 32'd4;
    end
    assign imem_addr = pc_r[`RVC_IMEM_AW+1:2];
    assign o_ir = imem_rdata;
    assign o_pc = pc_r;
    assign o_valid = 1'b1;
endmodule
