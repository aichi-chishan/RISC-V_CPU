//==============================================================================
// 32 位 GPIO 外设
// 0x00 OUT：输出数据；0x04 OE：输出使能；0x08 IN：输入采样（只读）。
// 字节写掩码逐通道生效，符合 CPU 的 SB/SH/SW 语义。
//==============================================================================
module rvcpu_gpio #(
    parameter WIDTH = 32
) (
    input wire clk, input wire rst_n,
    input wire valid, input wire write,
    input wire [3:0] addr,
    input wire [31:0] wdata, input wire [3:0] wmask,
    input wire [WIDTH-1:0] gpio_in,
    output reg [31:0] rdata,
    output wire [WIDTH-1:0] gpio_out,
    output wire [WIDTH-1:0] gpio_oe,
    output wire write_pulse
);
    reg [31:0] out_reg, oe_reg;
    integer b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin out_reg<=32'b0; oe_reg<=32'b0; end
        else if(valid && write) begin
            for(b=0;b<4;b=b+1) if(wmask[b]) begin
                if(addr[3:2]==2'd0) out_reg[b*8 +: 8] <= wdata[b*8 +: 8];
                if(addr[3:2]==2'd1) oe_reg[b*8 +: 8] <= wdata[b*8 +: 8];
            end
        end
    end
    always @(*) begin
        case(addr[3:2])
            2'd0: rdata=out_reg;
            2'd1: rdata=oe_reg;
            2'd2: begin rdata=32'b0; rdata[WIDTH-1:0]=gpio_in; end
            default: rdata=32'b0;
        endcase
    end
    assign gpio_out=out_reg[WIDTH-1:0];
    assign gpio_oe=oe_reg[WIDTH-1:0];
    assign write_pulse=valid && write && (addr[3:2]==2'd0);
endmodule
