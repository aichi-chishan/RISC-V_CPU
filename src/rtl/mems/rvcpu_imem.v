`include "../core/defines.v"

// 组合读指令存储器。仿真由 TB 写入 mem；上板时可通过 INIT_FILE 推断 ROM/BRAM。
module rvcpu_imem #(
    parameter INIT_FILE = ""
) (input wire [`RVC_IMEM_AW-1:0] addr, output wire [31:0] rdata);
    reg [31:0] mem [0:`RVC_IMEM_DEPTH-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign rdata = mem[addr];
endmodule
