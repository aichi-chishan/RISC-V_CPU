`timescale 1ns/1ps
`include "../rtl/core/defines.v"

//==============================================================================
// 第六阶段 RV32M 集成回归：覆盖八条指令、除零、溢出和结果前推。
//==============================================================================
module rvcpu_rv32m_tb;
    reg clk,rst_n; integer i,cycles,failures,busy_cycles;
    function [31:0] enc_i;
        input integer imm;input[4:0]rs1;input[2:0]f3;input[4:0]rd;input[6:0]op;
        reg[11:0]v;begin v=imm[11:0];enc_i={v,rs1,f3,rd,op};end
    endfunction
    function [31:0] enc_r;
        input[4:0]rs2;input[4:0]rs1;input[2:0]f3;input[4:0]rd;
        begin enc_r={7'b0000001,rs2,rs1,f3,rd,7'b0110011};end
    endfunction
    function [31:0] enc_s;
        input integer imm;input[4:0]rs2;input[4:0]rs1;input[2:0]f3;reg[11:0]v;
        begin v=imm[11:0];enc_s={v[11:5],rs2,rs1,f3,v[4:0],7'b0100011};end
    endfunction
    function [31:0] enc_u;
        input[19:0]imm20;input[4:0]rd;begin enc_u={imm20,rd,7'b0110111};end
    endfunction
    task expect_reg;
        input[4:0]idx;input[31:0]expected;input[8*24-1:0]name;reg[31:0]actual;
        begin actual=u_dut.u_core.u_id_stage.u_regfile.rf[idx];
            if(actual!==expected)begin $display("[FAIL] %-24s x%0d=%08h expect=%08h",name,idx,actual,expected);failures=failures+1;end
            else $display("[PASS] %-24s x%0d=%08h",name,idx,actual);
        end
    endtask
    rvcpu_top u_dut(.clk(clk),.rst_n(rst_n),.irq_software(1'b0),.irq_timer(1'b0),
        .irq_external(1'b0),.uart_rx(1'b1),.debug_pc(),.debug_stage(),.debug_wb_we(),
        .debug_wb_rd(),.debug_wb_data(),.periph_led_we(),.periph_led_wdata(),.uart_tx());
    always #5 clk=~clk;
    always @(posedge clk)if(rst_n&&u_dut.u_core.mdu_busy)busy_cycles=busy_cycles+1;
    initial begin
        clk=0;rst_n=0;failures=0;busy_cycles=0;
        for(i=0;i<`RVC_IMEM_DEPTH;i=i+1)u_dut.u_imem.mem[i]=`RVC_NOP_INSTR;
        for(i=0;i<`RVC_DMEM_DEPTH;i=i+1)u_dut.u_dmem.mem[i]=0;
        u_dut.u_imem.mem[0]=enc_i(-7,0,3'b000,1,7'b0010011);
        u_dut.u_imem.mem[1]=enc_i(3,0,3'b000,2,7'b0010011);
        u_dut.u_imem.mem[2]=enc_r(2,1,3'b000,3); // MUL
        u_dut.u_imem.mem[3]=enc_r(2,1,3'b001,4); // MULH
        u_dut.u_imem.mem[4]=enc_r(2,1,3'b010,5); // MULHSU
        u_dut.u_imem.mem[5]=enc_r(2,1,3'b011,6); // MULHU
        u_dut.u_imem.mem[6]=enc_r(2,1,3'b100,7); // DIV
        u_dut.u_imem.mem[7]=enc_r(2,1,3'b101,8); // DIVU
        u_dut.u_imem.mem[8]=enc_r(2,1,3'b110,9); // REM
        u_dut.u_imem.mem[9]=enc_r(2,1,3'b111,10);// REMU
        u_dut.u_imem.mem[10]=enc_r(0,1,3'b100,11);// DIV /0
        u_dut.u_imem.mem[11]=enc_r(0,1,3'b110,12);// REM /0
        u_dut.u_imem.mem[12]=enc_u(20'h80000,13);
        u_dut.u_imem.mem[13]=enc_i(-1,0,3'b000,14,7'b0010011);
        u_dut.u_imem.mem[14]=enc_r(14,13,3'b100,15);// INT_MIN/-1
        u_dut.u_imem.mem[15]=enc_r(14,13,3'b110,16);
        u_dut.u_imem.mem[16]=enc_i(6,0,3'b000,17,7'b0010011);
        u_dut.u_imem.mem[17]=enc_i(7,0,3'b000,18,7'b0010011);
        u_dut.u_imem.mem[18]=enc_r(18,17,3'b000,19);
        u_dut.u_imem.mem[19]=enc_i(1,19,3'b000,20,7'b0010011);// MDU RAW
        u_dut.u_imem.mem[20]=enc_s(1020,20,0,3'b010);
        repeat(4)@(posedge clk);rst_n=1;cycles=0;
        while(u_dut.u_dmem.mem[255]!==43&&cycles<600)begin @(posedge clk);cycles=cycles+1;end
        repeat(3)@(posedge clk);
        expect_reg(3,32'hffff_ffeb,"MUL low");
        expect_reg(4,32'hffff_ffff,"MULH signed");
        expect_reg(5,32'hffff_ffff,"MULHSU");
        expect_reg(6,32'h0000_0002,"MULHU");
        expect_reg(7,32'hffff_fffe,"DIV signed");
        expect_reg(8,32'h5555_5553,"DIVU");
        expect_reg(9,32'hffff_ffff,"REM signed");
        expect_reg(10,32'h0,"REMU");
        expect_reg(11,32'hffff_ffff,"DIV by zero");
        expect_reg(12,32'hffff_fff9,"REM by zero");
        expect_reg(15,32'h8000_0000,"DIV overflow");
        expect_reg(16,32'h0,"REM overflow");
        expect_reg(20,32'd43,"MDU result forwarding");
        if(busy_cycles<128)begin $display("[FAIL] 除法器未表现为多拍迭代 busy=%0d",busy_cycles);failures=failures+1;end
        else $display("[PASS] 32拍迭代除法握手 busy=%0d",busy_cycles);
        if(failures==0)$display("========== RV32M_TEST_PASSED ==========");
        else $fatal(1,"RV32M failed:%0d",failures);$finish;
    end
endmodule
