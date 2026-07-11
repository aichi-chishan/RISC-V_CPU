`include "./defines.v"

// 32×32 通用寄存器堆：x0 恒为零，双口组合读，单口同步写
module rvcpu_regfile (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [`RVC_RFIDX_WIDTH-1:0]  rs1_addr,   // 读端口 1 地址（组合）
    input  wire [`RVC_RFIDX_WIDTH-1:0]  rs2_addr,   // 读端口 2 地址（组合）
    output wire [`RVC_XLEN-1:0]         rs1_data,   // 读端口 1 数据输出
    output wire [`RVC_XLEN-1:0]         rs2_data,   // 读端口 2 数据输出
    input  wire                         wb_we,      // 写使能（同步）
    input  wire [`RVC_RFIDX_WIDTH-1:0]  wb_wa,      // 写地址
    input  wire [`RVC_XLEN-1:0]         wb_wd       // 写数据
);
    reg [`RVC_XLEN-1:0] rf [0:`RVC_RFREG_NUM-1];    // 32 个 32 位寄存器
    integer i;

    // 同步写：复位清零；写地址不为 0 时写入（x0 硬件恒零）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < `RVC_RFREG_NUM; i = i + 1)
                rf[i] <= {`RVC_XLEN{1'b0}};
        end else if (wb_we && (wb_wa != 0)) begin
            rf[wb_wa] <= wb_wd;
        end
    end

    // 组合读：读 x0 时直接返回 0（无论数组中实际值）
    assign rs1_data = (rs1_addr == 0) ? 32'b0 : rf[rs1_addr];
    assign rs2_data = (rs2_addr == 0) ? 32'b0 : rf[rs2_addr];
endmodule
