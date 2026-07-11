`include "../core/defines.v"

//==============================================================================
// FPGA 上板包装层
//
// reset_n 可以直接接按键/板级复位。异步拉低、同步释放可避免不同触发器
// 在复位撤销边沿进入不一致状态。调试信号可接 ILA，也可自行截取连接 LED。
// IMEM_INIT_FILE 应指向 Vivado 可访问的 .hex 文件，用于初始化指令 ROM。
//==============================================================================
module rvcpu_fpga_top #(
    parameter IMEM_INIT_FILE = "src/riscv-tests/led_flow.hex"
) (
    input  wire        sys_clk,
    input  wire        reset_n,
    output wire [1:0]  led
);
    // 异步复位同步释放：防止复位撤销边沿多个触发器进入不一致状态
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync;
    reg [1:0] led_reg;
    wire core_led_we;
    wire [31:0] core_led_wdata;

    // 调试信号不再作为 FPGA 顶层端口占用物理引脚；需要波形时可在 Vivado
    // "Set Up Debug" 中把这些已标记网络接入 ILA。
    (* MARK_DEBUG = "TRUE" *) wire [31:0] debug_pc;
    (* MARK_DEBUG = "TRUE" *) wire [2:0]  debug_stage;
    (* MARK_DEBUG = "TRUE" *) wire        debug_wb_we;
    (* MARK_DEBUG = "TRUE" *) wire [4:0]  debug_wb_rd;
    (* MARK_DEBUG = "TRUE" *) wire [31:0] debug_wb_data;

    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n)
            reset_sync <= 2'b00;
        else
            reset_sync <= {reset_sync[0], 1'b1};    // 逐拍传递 1，两拍后稳定为高
    end

    // 板载 LED 外设寄存器：CPU 对 0x4000_0000 的写操作在此提交。
    // 配套例程以 01/10 驱动两盏 LED，因此保持同一逻辑极性与引脚顺序。
    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n)
            led_reg <= 2'b01;
        else if (core_led_we)
            led_reg <= core_led_wdata[1:0];
    end

    assign led = led_reg;

    rvcpu_top #(.IMEM_INIT_FILE(IMEM_INIT_FILE)) u_core (
        .clk           (sys_clk),
        .rst_n         (reset_sync[1]),
        .debug_pc      (debug_pc),
        .debug_stage   (debug_stage),
        .debug_wb_we   (debug_wb_we),
        .debug_wb_rd   (debug_wb_rd),
        .debug_wb_data (debug_wb_data),
        .periph_led_we (core_led_we),
        .periph_led_wdata(core_led_wdata)
    );
endmodule
