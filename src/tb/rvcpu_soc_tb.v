`timescale 1ns/1ps
`include "../rtl/core/defines.v"

//==============================================================================
// 第五阶段 SoC 外设与地址译码回归
//==============================================================================
module rvcpu_soc_tb;
    reg clk,rst_n,uart_rx;
    integer i,cycles,failures,seen_access_fault;
    integer uart_sample_count;
    reg [9:0] uart_samples;
    wire uart_tx;

    function [31:0] enc_i;
        input integer imm; input [4:0] rs1; input [2:0] f3;
        input [4:0] rd; input [6:0] op; reg [11:0] v;
        begin v=imm[11:0]; enc_i={v,rs1,f3,rd,op}; end
    endfunction
    function [31:0] enc_s;
        input integer imm; input [4:0] rs2; input [4:0] rs1; input [2:0] f3;
        reg [11:0] v;
        begin v=imm[11:0]; enc_s={v[11:5],rs2,rs1,f3,v[4:0],7'b0100011}; end
    endfunction
    function [31:0] enc_u;
        input [19:0] imm20; input [4:0] rd;
        begin enc_u={imm20,rd,7'b0110111}; end
    endfunction
    function [31:0] enc_csr;
        input [11:0] addr; input [4:0] src; input [2:0] f3; input [4:0] rd;
        begin enc_csr={addr,src,f3,rd,7'b1110011}; end
    endfunction

    rvcpu_top u_dut(.clk(clk),.rst_n(rst_n),
        .irq_software(1'b0),.irq_timer(1'b0),.irq_external(1'b0),
        .uart_rx(uart_rx),
        .debug_pc(),.debug_stage(),.debug_wb_we(),.debug_wb_rd(),.debug_wb_data(),
        .periph_led_we(),.periph_led_wdata(),.uart_tx(uart_tx));
    always #5 clk=~clk;

    always @(posedge clk) begin
        if(rst_n && u_dut.u_core.mem_bus_exception) seen_access_fault=seen_access_fault+1;
        // 在每个 UART bit 周期起点采样真实串行输出，而不是窥视待发送字节。
        if(rst_n && u_dut.u_uart.busy && u_dut.u_uart.baud_count==0 && uart_sample_count<10) begin
            uart_samples[uart_sample_count]=uart_tx;
            uart_sample_count=uart_sample_count+1;
        end
    end

    initial begin
        clk=0;rst_n=0;uart_rx=1;failures=0;seen_access_fault=0;
        uart_sample_count=0;uart_samples=0;
        for(i=0;i<`RVC_IMEM_DEPTH;i=i+1)u_dut.u_imem.mem[i]=`RVC_NOP_INSTR;
        for(i=0;i<`RVC_DMEM_DEPTH;i=i+1)u_dut.u_dmem.mem[i]=0;
        u_dut.u_imem.mem[0]=enc_i(256,0,3'b000,10,7'b0010011);
        u_dut.u_imem.mem[1]=enc_csr(12'h305,10,3'b001,0); // mtvec=0x100
        u_dut.u_imem.mem[2]=enc_u(20'h40000,1);           // GPIO
        u_dut.u_imem.mem[3]=enc_i(3,0,3'b000,2,7'b0010011);
        u_dut.u_imem.mem[4]=enc_s(0,2,1,3'b010);
        u_dut.u_imem.mem[5]=enc_i(0,1,3'b010,3,7'b0000011);
        u_dut.u_imem.mem[6]=enc_u(20'h40001,4);           // UART
        u_dut.u_imem.mem[7]=enc_i(3,0,3'b000,5,7'b0010011);
        u_dut.u_imem.mem[8]=enc_s(8,5,4,3'b010);          // BAUDDIV=3
        u_dut.u_imem.mem[9]=enc_i(65,0,3'b000,6,7'b0010011);
        u_dut.u_imem.mem[10]=enc_s(0,6,4,3'b010);         // 发送 'A'
        u_dut.u_imem.mem[11]=enc_u(20'h02000,7);          // CLINT MSIP
        u_dut.u_imem.mem[12]=enc_i(1,0,3'b000,8,7'b0010011);
        u_dut.u_imem.mem[13]=enc_s(0,8,7,3'b010);
        u_dut.u_imem.mem[14]=enc_i(0,7,3'b010,9,7'b0000011);
        u_dut.u_imem.mem[15]=enc_u(20'h02004,11);         // MTIMECMP low
        u_dut.u_imem.mem[16]=enc_i(200,0,3'b000,12,7'b0010011);
        u_dut.u_imem.mem[17]=enc_s(0,12,11,3'b010);
        u_dut.u_imem.mem[18]=enc_s(4,0,11,3'b010);
        u_dut.u_imem.mem[19]=enc_u(20'h50000,13);         // 未映射地址
        u_dut.u_imem.mem[20]=enc_i(0,13,3'b010,14,7'b0000011);
        u_dut.u_imem.mem[21]=enc_i(7,0,3'b000,15,7'b0010011);
        u_dut.u_imem.mem[22]=enc_s(1020,15,0,3'b010);
        // Load access fault handler：跳过故障访问后返回。
        u_dut.u_imem.mem[64]=enc_csr(12'h341,0,3'b010,20);
        u_dut.u_imem.mem[65]=enc_i(4,20,3'b000,20,7'b0010011);
        u_dut.u_imem.mem[66]=enc_csr(12'h341,20,3'b001,0);
        u_dut.u_imem.mem[67]=32'h3020_0073;

        repeat(4)@(posedge clk);rst_n=1;cycles=0;
        fork begin
            wait(u_dut.u_uart.baud_div==3);
            repeat(3) @(posedge clk); uart_rx=0; // start
            repeat(3) @(posedge clk); uart_rx=0; // 0x5a bit0
            repeat(3) @(posedge clk); uart_rx=1;
            repeat(3) @(posedge clk); uart_rx=0;
            repeat(3) @(posedge clk); uart_rx=1;
            repeat(3) @(posedge clk); uart_rx=1;
            repeat(3) @(posedge clk); uart_rx=0;
            repeat(3) @(posedge clk); uart_rx=1;
            repeat(3) @(posedge clk); uart_rx=0;
            repeat(3) @(posedge clk); uart_rx=1; // stop
        end join_none
        while((u_dut.u_dmem.mem[255]!==7 || !u_dut.u_clint.irq_timer ||
               uart_sample_count<10) && cycles<400) begin @(posedge clk);cycles=cycles+1;end
        repeat(3)@(posedge clk);
        if(u_dut.u_gpio.out_reg!==3 || u_dut.u_core.u_id_stage.u_regfile.rf[3]!==3) begin
            $display("[FAIL] GPIO MMIO 读写");failures=failures+1;
        end else $display("[PASS] GPIO 完整地址译码与读回");
        if(u_dut.u_uart.baud_div!==3 || uart_samples!==10'b1010000010) begin
            $display("[FAIL] UART 8N1 got=%010b",uart_samples);failures=failures+1;
        end else $display("[PASS] UART BAUDDIV 与 8N1 串行帧");
        if(!u_dut.u_uart.rx_valid_reg || u_dut.u_uart.rx_data!==8'h5a) begin
            $display("[FAIL] UART RX got=%02h valid=%b",u_dut.u_uart.rx_data,u_dut.u_uart.rx_valid_reg);
            failures=failures+1;
        end else $display("[PASS] UART RX 过采样接收 8N1 数据");
        if(!u_dut.u_clint.irq_software || !u_dut.u_clint.irq_timer ||
           u_dut.u_core.u_id_stage.u_regfile.rf[9]!==1) begin
            $display("[FAIL] CLINT MSIP/MTIME/MTIMECMP");failures=failures+1;
        end else $display("[PASS] CLINT 软件与定时器请求");
        if(seen_access_fault!=1 || u_dut.u_core.u_id_stage.u_regfile.rf[14]!==0) begin
            $display("[FAIL] 未映射地址精确异常 count=%0d",seen_access_fault);failures=failures+1;
        end else $display("[PASS] 未映射地址产生一次精确 Load access fault");
        if(failures==0)$display("========== SOC_TEST_PASSED ==========");
        else $fatal(1,"SoC regression failed: %0d",failures);
        $finish;
    end
endmodule
