`timescale 1ns/1ps
`include "../rtl/core/defines.v"

//==============================================================================
// 第三阶段 ICB 风格接口定向测试
// 验证命令/响应握手、读写方向、字节地址语义，以及非法未对齐 Store 不得越过
// 核心提交边界。测试使用兼容包装层的零等待从设备，但观察的是实际通道信号。
//==============================================================================
module rvcpu_icb_tb;
    reg clk, rst_n;
    integer i, cycles, failures;
    integer load_handshakes, store_handshakes, bad_unaligned_cmd;

    function [31:0] enc_i;
        input integer imm; input [4:0] rs1; input [2:0] funct3;
        input [4:0] rd; input [6:0] opcode; reg [11:0] v;
        begin v=imm[11:0]; enc_i={v,rs1,funct3,rd,opcode}; end
    endfunction
    function [31:0] enc_s;
        input integer imm; input [4:0] rs2; input [4:0] rs1; input [2:0] funct3;
        reg [11:0] v;
        begin v=imm[11:0]; enc_s={v[11:5],rs2,rs1,funct3,v[4:0],7'b0100011}; end
    endfunction

    rvcpu_top u_dut(.clk(clk),.rst_n(rst_n),.debug_pc(),.debug_stage(),
        .irq_software(1'b0),.irq_timer(1'b0),.irq_external(1'b0),
        .debug_wb_we(),.debug_wb_rd(),.debug_wb_data(),
        .periph_led_we(),.periph_led_wdata());
    always #5 clk=~clk;

    always @(posedge clk) begin
        if (rst_n) begin
            // 零等待包装层的响应必须与已接受命令一一对应。
            if (u_dut.ifu_rsp_valid !== (u_dut.ifu_cmd_valid && u_dut.ifu_cmd_ready)) begin
                $display("[FAIL] IFU command/response 握手不一致"); failures=failures+1;
            end
            if (u_dut.lsu_cmd_valid && u_dut.lsu_cmd_ready) begin
                if (u_dut.lsu_rsp_valid !== 1'b1) begin
                    $display("[FAIL] LSU 已握手命令没有响应"); failures=failures+1;
                end
                if (u_dut.lsu_cmd_addr == 32'h40) begin
                    if (u_dut.lsu_cmd_read) load_handshakes=load_handshakes+1;
                    else store_handshakes=store_handshakes+1;
                end
                if (u_dut.lsu_cmd_addr == 32'h41) bad_unaligned_cmd=bad_unaligned_cmd+1;
            end
        end
    end

    initial begin
        clk=0; rst_n=0; failures=0; load_handshakes=0;
        store_handshakes=0; bad_unaligned_cmd=0;
        for(i=0;i<`RVC_IMEM_DEPTH;i=i+1) u_dut.u_imem.mem[i]=`RVC_NOP_INSTR;
        for(i=0;i<`RVC_DMEM_DEPTH;i=i+1) u_dut.u_dmem.mem[i]=32'b0;
        u_dut.u_imem.mem[0]=enc_i(85,0,3'b000,1,7'b0010011); // x1=0x55
        u_dut.u_imem.mem[1]=enc_s(64,1,0,3'b010);            // SW [0x40]
        u_dut.u_imem.mem[2]=enc_i(64,0,3'b010,2,7'b0000011);// LW x2,[0x40]
        u_dut.u_imem.mem[3]=enc_i(1,2,3'b000,3,7'b0010011); // x3=0x56
        u_dut.u_imem.mem[4]=enc_s(65,3,0,3'b001);            // 未对齐 SH，必须抑制
        u_dut.u_imem.mem[5]=enc_s(1020,3,0,3'b010);          // 完成标志
        repeat(4) @(posedge clk); rst_n=1;
        cycles=0;
        while((u_dut.u_dmem.mem[255] !== 32'h56) && cycles<80) begin
            @(posedge clk); cycles=cycles+1;
        end
        repeat(2) @(posedge clk);
        if(load_handshakes!=1 || store_handshakes!=1) begin
            $display("[FAIL] 0x40 握手计数 load=%0d store=%0d",load_handshakes,store_handshakes);
            failures=failures+1;
        end else $display("[PASS] LSU 读写命令各完成一次握手");
        if(bad_unaligned_cmd!=0) begin
            $display("[FAIL] 未对齐 Store 越过提交边界"); failures=failures+1;
        end else $display("[PASS] 未对齐 Store 未产生 ICB 命令");
        if(u_dut.u_core.u_id_stage.u_regfile.rf[3] !== 32'h56) begin
            $display("[FAIL] ICB Load 数据返回错误"); failures=failures+1;
        end else $display("[PASS] ICB Load 响应正确写回");
        if(failures==0) $display("========== ICB_TEST_PASSED ==========");
        else $fatal(1,"ICB regression failed: %0d",failures);
        $finish;
    end
endmodule
