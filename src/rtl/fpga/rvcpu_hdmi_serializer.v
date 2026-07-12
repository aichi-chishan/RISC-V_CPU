// 7 系列 OSERDESE2 10:1 DDR 串化器。bit0 最先发出，匹配 TMDS 符号定义。
module rvcpu_hdmi_serializer(
    input wire reset,input wire pixel_clk,input wire pixel_clk_5x,
    input wire[9:0]parallel_data,output wire serial_data
);
`ifdef SYNTHESIS
    wire shift1,shift2;
    OSERDESE2 #(.DATA_RATE_OQ("DDR"),.DATA_RATE_TQ("SDR"),.DATA_WIDTH(10),
        .SERDES_MODE("MASTER"),.TRISTATE_WIDTH(1)) u_master(
        .CLK(pixel_clk_5x),.CLKDIV(pixel_clk),.RST(reset),.OCE(1'b1),.OQ(serial_data),
        .D1(parallel_data[0]),.D2(parallel_data[1]),.D3(parallel_data[2]),.D4(parallel_data[3]),
        .D5(parallel_data[4]),.D6(parallel_data[5]),.D7(parallel_data[6]),.D8(parallel_data[7]),
        .SHIFTIN1(shift1),.SHIFTIN2(shift2),.SHIFTOUT1(),.SHIFTOUT2(),.OFB(),
        .T1(1'b0),.T2(1'b0),.T3(1'b0),.T4(1'b0),.TBYTEIN(1'b0),.TCE(1'b0),
        .TBYTEOUT(),.TFB(),.TQ());
    OSERDESE2 #(.DATA_RATE_OQ("DDR"),.DATA_RATE_TQ("SDR"),.DATA_WIDTH(10),
        .SERDES_MODE("SLAVE"),.TRISTATE_WIDTH(1)) u_slave(
        .CLK(pixel_clk_5x),.CLKDIV(pixel_clk),.RST(reset),.OCE(1'b1),.OQ(),
        .D1(1'b0),.D2(1'b0),.D3(parallel_data[8]),.D4(parallel_data[9]),
        .D5(1'b0),.D6(1'b0),.D7(1'b0),.D8(1'b0),.SHIFTIN1(),.SHIFTIN2(),
        .SHIFTOUT1(shift1),.SHIFTOUT2(shift2),.OFB(),.T1(1'b0),.T2(1'b0),
        .T3(1'b0),.T4(1'b0),.TBYTEIN(1'b0),.TCE(1'b0),.TBYTEOUT(),.TFB(),.TQ());
`else
    reg[9:0]shift;reg serial_reg;
    always @(posedge pixel_clk)shift<=parallel_data;
    always @(posedge pixel_clk_5x)begin serial_reg<=shift[0];shift<={1'b0,shift[9:1]};end
    assign serial_data=serial_reg;
`endif
endmodule
