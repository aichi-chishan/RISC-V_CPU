//==============================================================================
// 单 Hart CLINT：兼容常见 RISC-V 地址偏移
// MSIP 0x0000，MTIMECMP 0x4000/0x4004，MTIME 0xBFF8/0xBFFC。
// 64 位寄存器由两个 32 位访问组成，软件更新 mtimecmp 时应先写高位为全 1。
//==============================================================================
module rvcpu_clint (
    input wire clk, input wire rst_n,
    input wire valid, input wire write, input wire [15:0] addr,
    input wire [31:0] wdata, input wire [3:0] wmask,
    output reg [31:0] rdata,
    output wire irq_software, output wire irq_timer
);
    reg msip;
    reg [63:0] mtime, mtimecmp;
    integer b;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin msip<=0; mtime<=0; mtimecmp<=64'hffff_ffff_ffff_ffff; end
        else begin
            mtime<=mtime+1'b1;
            if(valid && write) begin
                if(addr==16'h0000 && wmask[0]) msip<=wdata[0];
                for(b=0;b<4;b=b+1) if(wmask[b]) begin
                    if(addr==16'h4000) mtimecmp[b*8 +: 8]<=wdata[b*8 +: 8];
                    if(addr==16'h4004) mtimecmp[32+b*8 +: 8]<=wdata[b*8 +: 8];
                    if(addr==16'hbff8) mtime[b*8 +: 8]<=wdata[b*8 +: 8];
                    if(addr==16'hbffc) mtime[32+b*8 +: 8]<=wdata[b*8 +: 8];
                end
            end
        end
    end
    always @(*) begin
        case(addr)
            16'h0000:rdata={31'b0,msip};
            16'h4000:rdata=mtimecmp[31:0];
            16'h4004:rdata=mtimecmp[63:32];
            16'hbff8:rdata=mtime[31:0];
            16'hbffc:rdata=mtime[63:32];
            default:rdata=32'b0;
        endcase
    end
    assign irq_software=msip;
    assign irq_timer=(mtime>=mtimecmp);
endmodule
