`include "./defines.v"

// IF 阶段：维护 PC 并从指令存储器取指令
//
// PC 由 sequencer/顶层控制，stall 和 o_ready 预留供未来五级流水使用。
// 地址转换：32 位字节地址 → IMEM 字地址（取高 [IMEM_AW+1:2] 位）。
module rvcpu_if_stage (
    input wire clk, input wire rst_n,
    output wire [`RVC_IMEM_AW-1:0] imem_addr,    // IMEM 字地址
    input wire [31:0] imem_rdata,                // 指令数据输入
    input wire ctrl_pc_sel,                      // 1=跳转，0=顺序执行
    input wire [31:0] ctrl_pc_next,              // 跳转目标地址
    input wire stall,                            // 流水线暂停
    output wire o_valid,                         // 输出有效
    input wire o_ready,                          // 下游就绪
    output wire [31:0] o_ir,                     // 输出指令
    output wire [31:0] o_pc                      // 输出PC
);
    reg [31:0] pc_r;                             // PC 寄存器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_r <= `RVC_RESET_PC;                                // 复位 PC = 0
        else if (!stall && o_ready)                               // 未被暂停且下游就绪时更新
            pc_r <= ctrl_pc_sel ? ctrl_pc_next : pc_r + 32'd4;    // 跳转或顺序+4
    end
    assign imem_addr = pc_r[`RVC_IMEM_AW+1:2];
    assign o_ir = imem_rdata;
    assign o_pc = pc_r;
    assign o_valid = 1'b1;
endmodule
