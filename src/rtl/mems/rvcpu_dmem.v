`include "../core/defines.v"

// 数据存储器：组合读、同步写，按字节掩码（wmask）逐字节写入。
// 4 KB = 1024 个 32 位字，wmask[3:0] 分别控制 4 个字节通道。
// 将来替换为 BRAM 或总线从设备时，只需在 MEM stage 适配读延迟和握手。
module rvcpu_dmem(
    input wire clk, input wire [`RVC_DMEM_AW-1:0] addr,
    input wire [31:0] wdata, input wire [3:0] wmask, input wire wen,
    output wire [31:0] rdata
);
    reg [31:0] mem [0:`RVC_DMEM_DEPTH-1];
    assign rdata=mem[addr];
    always @(posedge clk) if (wen) begin
        if(wmask[0]) mem[addr][7:0]   <= wdata[7:0];
        if(wmask[1]) mem[addr][15:8]  <= wdata[15:8];
        if(wmask[2]) mem[addr][23:16] <= wdata[23:16];
        if(wmask[3]) mem[addr][31:24] <= wdata[31:24];
    end
endmodule
