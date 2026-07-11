//==============================================================================
// 8N1 UART 发送外设
// 0x00 TXDATA：写低 8 位启动发送；0x04 STATUS：bit0 ready、bit1 busy；
// 0x08 BAUDDIV：每个串行 bit 使用的系统时钟周期数，最小值为 1。
//==============================================================================
module rvcpu_uart #(
    parameter RESET_BAUD_DIV = 32'd434
) (
    input wire clk, input wire rst_n,
    input wire valid, input wire write, input wire [3:0] addr,
    input wire [31:0] wdata, input wire [3:0] wmask,
    input wire rx,
    output reg [31:0] rdata, output wire tx,
    output wire irq_tx_empty, output wire irq_rx_valid
);
    reg [31:0] baud_div, baud_count;
    reg [9:0] shift_reg;
    reg [3:0] bits_left;
    reg [1:0] rx_sync;
    reg [1:0] rx_state;
    reg [31:0] rx_count;
    reg [2:0] rx_bit_index;
    reg [7:0] rx_shift, rx_data;
    reg rx_valid_reg;
    wire busy=(bits_left!=0);
    wire tx_start=valid && write && (addr[3:2]==2'd0) && wmask[0] && !busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            baud_div<=RESET_BAUD_DIV; baud_count<=0; shift_reg<=10'h3ff; bits_left<=0;
            rx_sync<=2'b11; rx_state<=0; rx_count<=0; rx_bit_index<=0;
            rx_shift<=0; rx_data<=0; rx_valid_reg<=0;
        end else begin
            rx_sync<={rx_sync[0],rx};
            if(valid && !write && addr[3:2]==2'd3) rx_valid_reg<=1'b0;
            if(valid && write && (addr[3:2]==2'd2)) begin
                if(wmask[0]) baud_div[7:0]<=wdata[7:0];
                if(wmask[1]) baud_div[15:8]<=wdata[15:8];
                if(wmask[2]) baud_div[23:16]<=wdata[23:16];
                if(wmask[3]) baud_div[31:24]<=wdata[31:24];
            end
            if(tx_start) begin
                // LSB 最先输出：start(0)、data[0..7]、stop(1)。
                shift_reg<={1'b1,wdata[7:0],1'b0}; bits_left<=4'd10; baud_count<=0;
            end else if(busy) begin
                if(baud_count >= ((baud_div<2)?0:(baud_div-1))) begin
                    baud_count<=0; shift_reg<={1'b1,shift_reg[9:1]}; bits_left<=bits_left-1'b1;
                end else baud_count<=baud_count+1'b1;
            end

            // RX 在起始位中点确认低电平，随后每隔一个 baud 周期采样数据位。
            case(rx_state)
                2'd0: if(!rx_sync[1]) begin rx_state<=2'd1; rx_count<=baud_div>>1; end
                2'd1: if(rx_count==0) begin
                    if(!rx_sync[1]) begin rx_state<=2'd2;rx_count<=(baud_div<2)?0:baud_div-1;rx_bit_index<=0;end
                    else rx_state<=0;
                end else rx_count<=rx_count-1'b1;
                2'd2: if(rx_count==0) begin
                    rx_shift[rx_bit_index]<=rx_sync[1];rx_count<=(baud_div<2)?0:baud_div-1;
                    if(rx_bit_index==7) rx_state<=2'd3; else rx_bit_index<=rx_bit_index+1'b1;
                end else rx_count<=rx_count-1'b1;
                default: if(rx_count==0) begin
                    if(rx_sync[1]) begin rx_data<=rx_shift;rx_valid_reg<=1'b1;end
                    rx_state<=0;
                end else rx_count<=rx_count-1'b1;
            endcase
        end
    end
    always @(*) begin
        case(addr[3:2])
            2'd0: rdata=32'b0;
            2'd1: rdata={29'b0,rx_valid_reg,busy,!busy};
            2'd2: rdata=baud_div;
            default:rdata={24'b0,rx_data};
        endcase
    end
    assign tx=busy ? shift_reg[0] : 1'b1;
    assign irq_tx_empty=!busy;
    assign irq_rx_valid=rx_valid_reg;
endmodule
