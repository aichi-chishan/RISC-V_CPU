`include "./defines.v"

//==============================================================================
// WB 阶段：在 ALU、Load 数据和 PC+4 中选择最终写回值。
// 当前只有一个来源；未来 M 扩展/CSR/协处理器可在本级之前加入类似 E203
// wbck 的集中仲裁器，寄存器堆仍保持单写口。
//==============================================================================
module rvcpu_wb_stage (
    input wire i_valid, output wire i_ready,
    input wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,
    input wire [31:0] i_alu_result,        // ALU 运算结果（ADD/SUB/AND 等）
    input wire [31:0] i_mem_result,        // 从 DMEM 读出的数据（LW/LB 等）
    output wire wb_we,                     // 寄存器堆写使能
    output wire [`RVC_RFIDX_WIDTH-1:0] wb_wa, // 写回目标寄存器地址（rd）
    output reg [31:0] wb_wd               // 写回寄存器堆的数据
);
    // 从 dec_info 中提取写回选择信号和 PC
    wire [1:0] sel = i_dec_info[`RVC_DECINFO_WB_SEL];  // 00=ALU, 01=MEM, 10=PC+4
    wire [31:0] i_pc = i_dec_info[`RVC_DECINFO_PC];

    //-------- 三选一写回多路器 --------
    always @(*) begin
        case(sel)
            `RVC_WB_SEL_MEM: wb_wd = i_mem_result;       // Load 指令：MEM 读出数据
            `RVC_WB_SEL_PC4: wb_wd = i_pc + 32'd4;       // JAL/JALR：返回地址 PC+4
            default:         wb_wd = i_alu_result;         // ALU 指令/其他：ALU 结果
        endcase
    end

    //-------- 写回控制 --------
    // wb_we 由两个条件共同决定：
    //   1. i_valid — 当前阶段有有效指令
    //   2. RDWEN — 译码阶段决定这条指令是否需要写回（如 ADD/LW/JAL 需要，SW/BEQ 不需要）
    // wb_wa 直接从 dec_info 取出，不额外译码
    assign wb_we = i_valid && i_dec_info[`RVC_DECINFO_RDWEN];
    assign wb_wa = i_dec_info[`RVC_DECINFO_RDIDX];
    assign i_ready = 1'b1;  // 始终就绪（多周期模式下 WB 阶段永不反压）
endmodule
