//==============================================================================
// CPU 可编程帧缓冲显示控制器
// - 逻辑画布 320x240，RGB565，每个 32 位字容纳相邻两个像素；
// - 输出 640x480@约60Hz，水平和垂直各重复两次；
// - 帧缓冲采用双时钟双端口写/读形式，面向 Xilinx Block RAM 推导；
// - CPU 端帧缓冲为写合并友好的 write-only 窗口，控制寄存器可读写。
//==============================================================================
module rvcpu_gpu (
    input wire bus_clk, input wire bus_rst_n,
    input wire bus_valid, input wire bus_write,
    input wire is_reg, input wire is_fb,
    input wire [31:0] bus_addr, input wire [31:0] bus_wdata,
    input wire [3:0] bus_wmask, output reg [31:0] bus_rdata,
    output wire irq_vblank,
    input wire pixel_clk, input wire pixel_rst_n,
    output reg video_hsync, output reg video_vsync, output reg video_de,
    output reg [23:0] video_rgb,
    output reg [9:0] debug_x, output reg [9:0] debug_y
);
    localparam FB_WORDS=38400; // 320*240/2
    (* ram_style="block", ram_decomp="power" *) reg [31:0] framebuffer[0:FB_WORDS-1];
    reg enable, irq_enable, vblank_pending;
    reg [23:0] background;
    (* ASYNC_REG="TRUE" *) reg [1:0] vblank_sync;
    reg vblank_toggle;
    integer b;
    wire [31:0] fb_word_index=(bus_addr-32'h5000_0000)>>2;
    reg fb_write_pending;
    reg [15:0] fb_write_index;
    reg [31:0] fb_write_data;
    reg [3:0] fb_write_mask;

    // CPU 写口。Framebuffer 不提供组合读，以确保综合为真正 BRAM，而不是消耗
    // 大量 LUT 的异步读存储器；游戏通常以软件维护对象状态后整块重绘。
    always @(posedge bus_clk or negedge bus_rst_n) begin
        if(!bus_rst_n) begin
            enable<=0;irq_enable<=0;background<=0;vblank_sync<=0;vblank_pending<=0;
        end else begin
            vblank_sync<={vblank_sync[0],vblank_toggle};
            if(vblank_sync[1]^vblank_sync[0])vblank_pending<=1'b1;
            if(bus_valid&&bus_write&&is_reg)case(bus_addr[5:2])
                0:begin if(bus_wmask[0])begin enable<=bus_wdata[0];irq_enable<=bus_wdata[1];end end
                1:if(bus_wmask[0]&&bus_wdata[0])vblank_pending<=1'b0;
                3:begin
                    if(bus_wmask[0])background[7:0]<=bus_wdata[7:0];
                    if(bus_wmask[1])background[15:8]<=bus_wdata[15:8];
                    if(bus_wmask[2])background[23:16]<=bus_wdata[23:16];
                end
                default:begin end
            endcase
        end
    end
    // 在 BRAM 写口前放置同步复位的命令寄存器，避免 CPU 流水寄存器的异步
    // 复位直接驱动 RAM 地址/使能引脚，从而消除 REQP-1839 异步控制警告。
    always @(posedge bus_clk) begin
        if(!bus_rst_n) fb_write_pending<=1'b0;
        else begin
            fb_write_pending<=bus_valid&&bus_write&&is_fb&&(fb_word_index<FB_WORDS);
            if(bus_valid&&bus_write&&is_fb&&(fb_word_index<FB_WORDS))begin
                fb_write_index<=fb_word_index[15:0];
                fb_write_data<=bus_wdata;fb_write_mask<=bus_wmask;
            end
        end
    end
    always @(posedge bus_clk) begin
        if(fb_write_pending)
            for(b=0;b<4;b=b+1)if(fb_write_mask[b])
                framebuffer[fb_write_index][b*8 +:8]<=fb_write_data[b*8 +:8];
    end
    always @(*)begin
        if(is_reg)case(bus_addr[5:2])
            0:bus_rdata={30'b0,irq_enable,enable};
            1:bus_rdata={31'b0,vblank_pending};
            2:bus_rdata={16'd240,16'd320};
            3:bus_rdata={8'b0,background};
            default:bus_rdata=0;
        endcase else bus_rdata=0;
    end
    assign irq_vblank=irq_enable&&vblank_pending;

    // 跨到像素域的配置寄存器采用两级采样。配置只由软件低频改写，不需要为
    // 每个位建立握手；vblank 事件反向则使用 toggle，保证窄脉冲不会丢失。
    (* ASYNC_REG="TRUE" *) reg [1:0] enable_sync;
    (* ASYNC_REG="TRUE" *) reg [23:0] background_q1;
    reg [23:0] background_q2;
    reg [9:0] h_count,v_count;
    reg [15:0] read_addr;
    reg read_half,de_s1,hs_s1,vs_s1;
    reg [31:0] read_word;
    reg half_s2,de_s2,hs_s2,vs_s2;
    wire active=(h_count<640)&&(v_count<480);
    wire hs_now=!((h_count>=656)&&(h_count<752));
    wire vs_now=!((v_count>=490)&&(v_count<492));
    wire [8:0] logical_x=h_count[9:1];
    wire [7:0] logical_y=v_count[8:1];
    wire [15:0] logical_word_addr=logical_y*160+(logical_x>>1);
    wire [15:0] selected_pixel=half_s2?read_word[31:16]:read_word[15:0];
    wire [23:0] rgb565_expand={{selected_pixel[15:11],selected_pixel[15:13]},
                               {selected_pixel[10:5],selected_pixel[10:9]},
                               {selected_pixel[4:0],selected_pixel[4:2]}};
    // BRAM 像素读端口同样不带复位，复位只清空其下游 valid/DE 流水。
    always @(posedge pixel_clk) read_word<=framebuffer[read_addr];
    always @(posedge pixel_clk) begin
        if(!pixel_rst_n) read_addr<=0;
        else read_addr<=logical_word_addr;
    end
    always @(posedge pixel_clk or negedge pixel_rst_n)begin
        if(!pixel_rst_n)begin
            enable_sync<=0;background_q1<=0;background_q2<=0;h_count<=0;v_count<=0;
            read_half<=0;half_s2<=0;
            de_s1<=0;hs_s1<=1;vs_s1<=1;de_s2<=0;hs_s2<=1;vs_s2<=1;
            video_de<=0;video_hsync<=1;video_vsync<=1;video_rgb<=0;
            debug_x<=0;debug_y<=0;vblank_toggle<=0;
        end else begin
            enable_sync<={enable_sync[0],enable};
            background_q1<=background;background_q2<=background_q1;
            if(h_count==799)begin h_count<=0;if(v_count==524)v_count<=0;else v_count<=v_count+1'b1;end
            else h_count<=h_count+1'b1;
            if(h_count==0&&v_count==480)vblank_toggle<=~vblank_toggle;

            read_half<=logical_x[0];
            de_s1<=active;hs_s1<=hs_now;vs_s1<=vs_now;
            half_s2<=read_half;
            de_s2<=de_s1;hs_s2<=hs_s1;vs_s2<=vs_s1;
            video_de<=de_s2;video_hsync<=hs_s2;video_vsync<=vs_s2;
            video_rgb<=de_s2?(enable_sync[1]?rgb565_expand:background_q2):24'b0;
            debug_x<=h_count;debug_y<=v_count;
        end
    end
endmodule
