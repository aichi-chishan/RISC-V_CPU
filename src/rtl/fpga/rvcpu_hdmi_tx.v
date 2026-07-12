// 三数据通道加时钟通道的 DVI-compatible HDMI 发送器（无音频/数据岛）。
module rvcpu_hdmi_tx(
    input wire pixel_clk,input wire pixel_clk_5x,input wire reset,
    input wire[23:0]rgb,input wire hsync,input wire vsync,input wire de,
    output wire tmds_clk_p,output wire tmds_clk_n,
    output wire[2:0]tmds_data_p,output wire[2:0]tmds_data_n
);
    wire[9:0]sym_b,sym_g,sym_r;wire[3:0]serial;
    rvcpu_tmds_encoder u_b(.clk(pixel_clk),.rst(reset),.data(rgb[7:0]),
        .c0(hsync),.c1(vsync),.de(de),.symbol(sym_b));
    rvcpu_tmds_encoder u_g(.clk(pixel_clk),.rst(reset),.data(rgb[15:8]),
        .c0(1'b0),.c1(1'b0),.de(de),.symbol(sym_g));
    rvcpu_tmds_encoder u_r(.clk(pixel_clk),.rst(reset),.data(rgb[23:16]),
        .c0(1'b0),.c1(1'b0),.de(de),.symbol(sym_r));
    rvcpu_hdmi_serializer u_sb(.reset(reset),.pixel_clk(pixel_clk),.pixel_clk_5x(pixel_clk_5x),.parallel_data(sym_b),.serial_data(serial[0]));
    rvcpu_hdmi_serializer u_sg(.reset(reset),.pixel_clk(pixel_clk),.pixel_clk_5x(pixel_clk_5x),.parallel_data(sym_g),.serial_data(serial[1]));
    rvcpu_hdmi_serializer u_sr(.reset(reset),.pixel_clk(pixel_clk),.pixel_clk_5x(pixel_clk_5x),.parallel_data(sym_r),.serial_data(serial[2]));
    rvcpu_hdmi_serializer u_sc(.reset(reset),.pixel_clk(pixel_clk),.pixel_clk_5x(pixel_clk_5x),.parallel_data(10'b1111100000),.serial_data(serial[3]));
`ifdef SYNTHESIS
    OBUFDS #(.IOSTANDARD("TMDS_33"),.SLEW("FAST"))o0(.I(serial[0]),.O(tmds_data_p[0]),.OB(tmds_data_n[0]));
    OBUFDS #(.IOSTANDARD("TMDS_33"),.SLEW("FAST"))o1(.I(serial[1]),.O(tmds_data_p[1]),.OB(tmds_data_n[1]));
    OBUFDS #(.IOSTANDARD("TMDS_33"),.SLEW("FAST"))o2(.I(serial[2]),.O(tmds_data_p[2]),.OB(tmds_data_n[2]));
    OBUFDS #(.IOSTANDARD("TMDS_33"),.SLEW("FAST"))oc(.I(serial[3]),.O(tmds_clk_p),.OB(tmds_clk_n));
`else
    assign tmds_data_p=serial[2:0];assign tmds_data_n=~serial[2:0];
    assign tmds_clk_p=serial[3];assign tmds_clk_n=~serial[3];
`endif
endmodule
