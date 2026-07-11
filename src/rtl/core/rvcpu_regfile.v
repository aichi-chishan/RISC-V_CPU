`include "./defines.v"

//==============================================================================
// 32×32 位通用寄存器堆：双组合读、单同步写，x0 恒为零。
// 单写口配合集中写回仲裁，结构简单，也容易推断成 FPGA 分布式 RAM。
//==============================================================================
module rvcpu_regfile (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [`RVC_RFIDX_WIDTH-1:0]  rs1_addr,
    input  wire [`RVC_RFIDX_WIDTH-1:0]  rs2_addr,
    output wire [`RVC_XLEN-1:0]         rs1_data,
    output wire [`RVC_XLEN-1:0]         rs2_data,
    input  wire                         wb_we,
    input  wire [`RVC_RFIDX_WIDTH-1:0]  wb_wa,
    input  wire [`RVC_XLEN-1:0]         wb_wd
);
    reg [`RVC_XLEN-1:0] rf [0:`RVC_RFREG_NUM-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < `RVC_RFREG_NUM; i = i + 1)
                rf[i] <= {`RVC_XLEN{1'b0}};
        end else if (wb_we && (wb_wa != 0)) begin
            rf[wb_wa] <= wb_wd;
        end
    end

    assign rs1_data = (rs1_addr == 0) ? 32'b0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'b0 : rf[rs2_addr];
endmodule
