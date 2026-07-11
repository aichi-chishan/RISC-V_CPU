`include "../core/defines.v"

//==============================================================================
// FPGA 上板包装层
//
// reset_n 可以直接接按键/板级复位。异步拉低、同步释放可避免不同触发器
// 在复位撤销边沿进入不一致状态。调试信号可接 ILA，也可自行截取连接 LED。
// IMEM_INIT_FILE 应指向 Vivado 可访问的 .hex 文件，用于初始化指令 ROM。
//==============================================================================
module rvcpu_fpga_top #(
    parameter IMEM_INIT_FILE = "src/riscv-tests/smoke_test.hex"
) (
    input  wire        sys_clk,
    input  wire        reset_n,
    output wire [31:0] debug_pc,
    output wire [2:0]  debug_stage,
    output wire        debug_wb_we,
    output wire [4:0]  debug_wb_rd,
    output wire [31:0] debug_wb_data
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync;

    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};
    end

    rvcpu_top #(.IMEM_INIT_FILE(IMEM_INIT_FILE)) u_core (
        .clk           (sys_clk),
        .rst_n         (reset_sync[1]),
        .debug_pc      (debug_pc),
        .debug_stage   (debug_stage),
        .debug_wb_we   (debug_wb_we),
        .debug_wb_rd   (debug_wb_rd),
        .debug_wb_data (debug_wb_data)
    );
endmodule
