`timescale 1ns/1ps
`include "../rtl/core/defines.v"
// CPU 软件通过实际 LSU/MMIO 通路写帧缓冲和显示控制寄存器。
module rvcpu_gpu_cpu_tb;
    reg clk,rst_n;integer i,cycles,failures;
    function[31:0]enc_i;input integer imm;input[4:0]rs1;input[2:0]f3;input[4:0]rd;input[6:0]op;reg[11:0]v;
        begin v=imm[11:0];enc_i={v,rs1,f3,rd,op};end endfunction
    function[31:0]enc_s;input integer imm;input[4:0]rs2;input[4:0]rs1;input[2:0]f3;reg[11:0]v;
        begin v=imm[11:0];enc_s={v[11:5],rs2,rs1,f3,v[4:0],7'b0100011};end endfunction
    function[31:0]enc_u;input[19:0]imm20;input[4:0]rd;begin enc_u={imm20,rd,7'b0110111};end endfunction
    rvcpu_top u_dut(.clk(clk),.rst_n(rst_n),.irq_software(1'b0),.irq_timer(1'b0),
        .irq_external(1'b0),.uart_rx(1'b1),.pixel_clk(clk),.pixel_rst_n(rst_n),.debug_pc(),.debug_stage(),
        .debug_wb_we(),.debug_wb_rd(),.debug_wb_data(),.periph_led_we(),
        .periph_led_wdata(),.uart_tx(),.video_hsync(),.video_vsync(),.video_de(),.video_rgb());
    always #5 clk=~clk;
    initial begin
        clk=0;rst_n=0;failures=0;
        for(i=0;i<`RVC_IMEM_DEPTH;i=i+1)u_dut.u_imem.mem[i]=`RVC_NOP_INSTR;
        for(i=0;i<`RVC_DMEM_DEPTH;i=i+1)u_dut.u_dmem.mem[i]=0;
        u_dut.u_imem.mem[0]=enc_u(20'h50000,1);             // framebuffer base
        u_dut.u_imem.mem[1]=enc_u(20'h07e10,2);
        u_dut.u_imem.mem[2]=enc_i(-2048,2,3'b000,2,7'b0010011); // 07e0_f800
        u_dut.u_imem.mem[3]=enc_s(0,2,1,3'b010);
        u_dut.u_imem.mem[4]=enc_u(20'h40002,3);             // GPU registers
        u_dut.u_imem.mem[5]=enc_i(3,0,3'b000,4,7'b0010011);
        u_dut.u_imem.mem[6]=enc_s(0,4,3,3'b010);
        u_dut.u_imem.mem[7]=enc_i(1,0,3'b000,5,7'b0010011);
        u_dut.u_imem.mem[8]=enc_s(1020,5,0,3'b010);
        repeat(4)@(posedge clk);rst_n=1;cycles=0;
        while(u_dut.u_dmem.mem[255]!==1&&cycles<80)begin @(posedge clk);cycles=cycles+1;end
        repeat(3)@(posedge clk);
        if(u_dut.u_gpu.framebuffer[0]!==32'h07e0_f800)begin
            $display("[FAIL] CPU framebuffer write=%08h",u_dut.u_gpu.framebuffer[0]);failures=failures+1;
        end else $display("[PASS] CPU 经 LSU 写入两个 RGB565 像素");
        if(!u_dut.u_gpu.enable||!u_dut.u_gpu.irq_enable)begin
            $display("[FAIL] CPU GPU control write");failures=failures+1;
        end else $display("[PASS] CPU 经 MMIO 启用显示和 vblank 中断");
        if(failures==0)$display("========== GPU_CPU_TEST_PASSED ==========");
        else $fatal(1,"GPU CPU integration failed");$finish;
    end
endmodule
