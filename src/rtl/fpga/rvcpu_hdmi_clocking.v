// Vivado 综合时实例化 Clocking Wizard；普通 RTL 仿真使用直通时钟，避免依赖 IP 模型。
module rvcpu_hdmi_clocking(
    input wire sys_clk,input wire reset,
    output wire pixel_clk,output wire pixel_clk_5x,output wire locked
);
`ifdef SYNTHESIS
    rvcpu_hdmi_clk_wiz u_clk_wiz(.clk_in1(sys_clk),.reset(reset),
        .clk_out1(pixel_clk),.clk_out2(pixel_clk_5x),.locked(locked));
`else
    assign pixel_clk=sys_clk;assign pixel_clk_5x=sys_clk;assign locked=!reset;
`endif
endmodule
