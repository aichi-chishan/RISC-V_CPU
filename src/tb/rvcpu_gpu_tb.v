`timescale 1ns/1ps
module rvcpu_gpu_tb;
    reg clk,rst_n,bus_valid,bus_write,is_reg,is_fb;
    reg[31:0]bus_addr,bus_wdata;reg[3:0]bus_wmask;
    wire[31:0]bus_rdata;wire irq_vblank,hs,vs,de;wire[23:0]rgb;wire[9:0]x,y;
    integer active_count,hs_low_count,vs_low_count,failures,color_count;
    reg[23:0]colors[0:3];reg start_count;reg last_toggle;
    reg enc_rst,enc_de,enc_c0,enc_c1;reg[7:0]enc_data;wire[9:0]enc_symbol;
    rvcpu_gpu u_gpu(.bus_clk(clk),.bus_rst_n(rst_n),.bus_valid(bus_valid),
        .bus_write(bus_write),.is_reg(is_reg),.is_fb(is_fb),.bus_addr(bus_addr),
        .bus_wdata(bus_wdata),.bus_wmask(bus_wmask),.bus_rdata(bus_rdata),
        .irq_vblank(irq_vblank),.pixel_clk(clk),.pixel_rst_n(rst_n),
        .video_hsync(hs),.video_vsync(vs),.video_de(de),.video_rgb(rgb),
        .debug_x(x),.debug_y(y));
    rvcpu_tmds_encoder u_enc(.clk(clk),.rst(enc_rst),.data(enc_data),
        .c0(enc_c0),.c1(enc_c1),.de(enc_de),.symbol(enc_symbol));
    always #1 clk=~clk;
    task write_bus;
        input[31:0]addr;input[31:0]data;input reg_sel;input fb_sel;
        begin @(negedge clk);bus_addr=addr;bus_wdata=data;is_reg=reg_sel;is_fb=fb_sel;
            bus_wmask=4'hf;bus_write=1;bus_valid=1;@(negedge clk);bus_valid=0;bus_write=0;end
    endtask
    always @(posedge clk)if(rst_n&&start_count)begin
        if(de)begin active_count=active_count+1;
            if(color_count<4)begin colors[color_count]=rgb;color_count=color_count+1;end
        end
        if(!hs)hs_low_count=hs_low_count+1;if(!vs)vs_low_count=vs_low_count+1;
    end
    initial begin
        clk=0;rst_n=0;bus_valid=0;bus_write=0;is_reg=0;is_fb=0;bus_addr=0;
        bus_wdata=0;bus_wmask=0;failures=0;active_count=0;hs_low_count=0;
        vs_low_count=0;color_count=0;start_count=0;enc_rst=1;enc_de=0;enc_c0=0;
        enc_c1=0;enc_data=0;repeat(4)@(posedge clk);rst_n=1;enc_rst=0;

        // 一个 32 位写同时放入红、绿两个 RGB565 像素。
        write_bus(32'h5000_0000,{16'h07e0,16'hf800},0,1);
        write_bus(32'h4000_2000,32'h3,1,0); // enable + vblank irq
        last_toggle=u_gpu.vblank_toggle;
        wait(u_gpu.vblank_toggle!=last_toggle);last_toggle=u_gpu.vblank_toggle;
        start_count=1;
        wait(u_gpu.vblank_toggle!=last_toggle);start_count=0;
        repeat(5)@(posedge clk);
        if(active_count!=640*480)begin $display("[FAIL] active像素数=%0d",active_count);failures=failures+1;end
        else $display("[PASS] 640x480 活动区像素计数");
        if(hs_low_count!=96*525||vs_low_count!=2*800)begin
            $display("[FAIL] 同步宽度 hs=%0d vs=%0d",hs_low_count,vs_low_count);failures=failures+1;
        end else $display("[PASS] 640x480 HS/VS 标准时序");
        if(colors[0]!==24'hff0000||colors[1]!==24'hff0000||
           colors[2]!==24'h00ff00||colors[3]!==24'h00ff00)begin
            $display("[FAIL] RGB565 2x缩放 %h %h %h %h",colors[0],colors[1],colors[2],colors[3]);failures=failures+1;
        end else $display("[PASS] CPU帧缓冲 RGB565 读取与2x缩放");
        if(!irq_vblank)begin $display("[FAIL] vblank中断未置位");failures=failures+1;end
        else $display("[PASS] vblank toggle跨时钟域与中断");

        // TMDS 消隐控制码和两个零失衡起点的数据码。
        enc_de=0;enc_c1=0;enc_c0=0;@(posedge clk);#0.1;
        if(enc_symbol!==10'b1101010100)begin $display("[FAIL] TMDS CTL00");failures=failures+1;end
        enc_c0=1;@(posedge clk);#0.1;
        if(enc_symbol!==10'b0010101011)begin $display("[FAIL] TMDS CTL01");failures=failures+1;end
        enc_c0=0;enc_data=8'h00;enc_de=1;@(posedge clk);#0.1;
        if(enc_symbol!==10'b0100000000)begin $display("[FAIL] TMDS data00=%010b",enc_symbol);failures=failures+1;end
        enc_de=0;@(posedge clk);enc_data=8'hff;enc_de=1;@(posedge clk);#0.1;
        if(enc_symbol!==10'b1000000000)begin $display("[FAIL] TMDS dataff=%010b",enc_symbol);failures=failures+1;end
        if(failures==0)$display("========== GPU_TEST_PASSED ==========");
        else $fatal(1,"GPU regression failed:%0d",failures);$finish;
    end
endmodule
