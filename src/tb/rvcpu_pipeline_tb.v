`timescale 1ns/1ps
`include "../rtl/core/defines.v"

//==============================================================================
// 第二阶段五级流水定向测试
//
// 该程序刻意把生产者和消费者紧邻放置，覆盖 EX/MEM、MEM/WB 前推以及
// Load-Use 单拍停顿；同时构造后向循环、前向已采用分支、JAL 和 JALR，
// 从功能结果及内部统计量两方面验证静态预测与错误路径冲刷。
//==============================================================================
module rvcpu_pipeline_tb;
    reg clk;
    reg rst_n;
    integer i;
    integer failures;
    wire [31:0] debug_pc;
    wire [2:0] debug_stage;

    function [31:0] enc_i;
        input integer imm; input [4:0] rs1; input [2:0] funct3;
        input [4:0] rd; input [6:0] opcode;
        reg [11:0] v;
        begin v=imm[11:0]; enc_i={v,rs1,funct3,rd,opcode}; end
    endfunction
    function [31:0] enc_s;
        input integer imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        reg [11:0] v;
        begin v=imm[11:0]; enc_s={v[11:5],rs2,rs1,funct3,v[4:0],7'b0100011}; end
    endfunction
    function [31:0] enc_b;
        input integer imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        reg [12:0] v;
        begin
            v=imm[12:0];
            enc_b={v[12],v[10:5],rs2,rs1,funct3,v[4:1],v[11],7'b1100011};
        end
    endfunction
    function [31:0] enc_j;
        input integer imm; input [4:0] rd; reg [20:0] v;
        begin v=imm[20:0]; enc_j={v[20],v[10:1],v[11],v[19:12],rd,7'b1101111}; end
    endfunction

    task expect_reg;
        input [4:0] index; input [31:0] expected; input [8*36-1:0] name;
        reg [31:0] actual;
        begin
            actual=u_dut.u_core.u_id_stage.u_regfile.rf[index];
            if (actual !== expected) begin
                $display("[FAIL] %-36s x%0d got=%08h expect=%08h",name,index,actual,expected);
                failures=failures+1;
            end else $display("[PASS] %-36s x%0d=%08h",name,index,actual);
        end
    endtask

    rvcpu_top u_dut(
        .clk(clk),.rst_n(rst_n),.debug_pc(debug_pc),.debug_stage(debug_stage),
        .irq_software(1'b0),.irq_timer(1'b0),.irq_external(1'b0),
        .uart_rx(1'b1),
        .pixel_clk(clk),
        .pixel_rst_n(rst_n),
        .debug_wb_we(),.debug_wb_rd(),.debug_wb_data(),
        .periph_led_we(),.periph_led_wdata(),.uart_tx(),
        .video_hsync(),.video_vsync(),.video_de(),.video_rgb());

    always #5 clk=~clk;

    initial begin
        clk=0; rst_n=0; failures=0;
        for (i=0;i<`RVC_IMEM_DEPTH;i=i+1) u_dut.u_imem.mem[i]=`RVC_NOP_INSTR;
        for (i=0;i<`RVC_DMEM_DEPTH;i=i+1) u_dut.u_dmem.mem[i]=32'b0;

        u_dut.u_imem.mem[ 0]=enc_i(1, 0,3'b000, 1,7'b0010011); // x1=1
        u_dut.u_imem.mem[ 1]=enc_i(2, 1,3'b000, 2,7'b0010011); // EX/MEM RAW: x2=3
        u_dut.u_imem.mem[ 2]=enc_s(0, 2,0,3'b010);             // Store 数据也要前推
        u_dut.u_imem.mem[ 3]=enc_i(0, 0,3'b010, 3,7'b0000011); // x3=mem[0]
        u_dut.u_imem.mem[ 4]=enc_i(4, 3,3'b000, 4,7'b0010011); // Load-Use: x4=7
        u_dut.u_imem.mem[ 5]=enc_i(0, 0,3'b000, 5,7'b0010011); // 循环计数器
        u_dut.u_imem.mem[ 6]=enc_i(1, 5,3'b000, 5,7'b0010011); // loop: x5++
        u_dut.u_imem.mem[ 7]=enc_i(3, 0,3'b000, 6,7'b0010011); // x6=3
        u_dut.u_imem.mem[ 8]=enc_b(-8,6,5,3'b100);             // BLT 后向预测跳
        u_dut.u_imem.mem[ 9]=enc_b(8, 6,5,3'b000);             // BEQ 前向预测不跳，实际跳
        u_dut.u_imem.mem[10]=enc_i(99,0,3'b000,7,7'b0010011);  // 错误路径，必须冲刷
        u_dut.u_imem.mem[11]=enc_i(9, 0,3'b000,7,7'b0010011);  // x7=9
        u_dut.u_imem.mem[12]=enc_j(8,8);                       // JAL 预测跳，x8=52
        u_dut.u_imem.mem[13]=enc_i(99,0,3'b000,9,7'b0010011);  // 错误路径
        u_dut.u_imem.mem[14]=enc_i(1, 8,3'b000,9,7'b0010011);  // x9=53，PC+4 前推
        u_dut.u_imem.mem[15]=enc_i(72,0,3'b000,10,7'b0010011); // JALR 目标
        u_dut.u_imem.mem[16]=enc_i(0,10,3'b000,11,7'b1100111); // JALR 在 EX 纠正
        u_dut.u_imem.mem[17]=enc_i(99,0,3'b000,12,7'b0010011); // 错误路径
        u_dut.u_imem.mem[18]=enc_i(1,11,3'b000,12,7'b0010011); // x12=69
        u_dut.u_imem.mem[19]=enc_s(1020,12,0,3'b010);          // 完成标志

        repeat(4) @(posedge clk); rst_n=1;
        i=0;
        while ((u_dut.u_dmem.mem[255] !== 32'd69) && (i<160)) begin
            @(posedge clk); i=i+1;
        end
        repeat(3) @(posedge clk);

        expect_reg(2, 32'd3,  "EX/MEM 前推");
        expect_reg(4, 32'd7,  "Load-Use 单拍停顿与 MEM/WB 前推");
        expect_reg(5, 32'd3,  "后向循环完成");
        expect_reg(7, 32'd9,  "前向已采用分支冲刷错误路径");
        expect_reg(8, 32'd52, "JAL 链接地址");
        expect_reg(9, 32'd53, "JAL PC+4 结果前推");
        expect_reg(11,32'd68, "JALR 链接地址");
        expect_reg(12,32'd69, "JALR 冲刷及依赖前推");
        if (u_dut.u_core.load_stall_count !== 32'd1) begin
            $display("[FAIL] Load-Use 停顿次数 got=%0d expect=1",u_dut.u_core.load_stall_count);
            failures=failures+1;
        end else $display("[PASS] Load-Use 精确停顿一拍");
        if (u_dut.u_core.branch_mispredict_count !== 32'd3) begin
            $display("[FAIL] 预测失败次数 got=%0d expect=3",u_dut.u_core.branch_mispredict_count);
            failures=failures+1;
        end else $display("[PASS] BTFNT/JAL/JALR 预测纠错覆盖完整");

        if (failures==0) $display("========== PIPELINE_TEST_PASSED ==========");
        else $display("========== PIPELINE_TEST_FAILED: %0d ==========" ,failures);
        $finish;
    end
endmodule
