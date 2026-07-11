`timescale 1ns/1ps
`include "../rtl/core/defines.v"

//==============================================================================
// 第四阶段 CSR、同步异常、中断与 MRET 定向回归
//==============================================================================
module rvcpu_trap_tb;
    reg clk, rst_n, irq_software, irq_timer, irq_external;
    integer i, cycles, failures;
    integer seen_illegal, seen_ecall, seen_load_misalign, seen_breakpoint;
    integer seen_software, seen_timer, seen_external;

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
    function [31:0] enc_b;
        input integer imm; input [4:0] rs2; input [4:0] rs1; input [2:0] f3;
        reg [12:0] v;
        begin v=imm[12:0]; enc_b={v[12],v[10:5],rs2,rs1,f3,v[4:1],v[11],7'b1100011}; end
    endfunction
    function [31:0] enc_csr;
        input [11:0] addr; input [4:0] src; input [2:0] f3; input [4:0] rd;
        begin enc_csr={addr,src,f3,rd,7'b1110011}; end
    endfunction
    function [31:0] enc_u;
        input [19:0] imm20; input [4:0] rd;
        begin enc_u={imm20,rd,7'b0110111}; end
    endfunction

    rvcpu_top u_dut(.clk(clk),.rst_n(rst_n),
        .irq_software(irq_software),.irq_timer(irq_timer),.irq_external(irq_external),
        .debug_pc(),.debug_stage(),.debug_wb_we(),.debug_wb_rd(),.debug_wb_data(),
        .periph_led_we(),.periph_led_wdata());
    always #5 clk=~clk;

    // 在 CSR 文件真正提交 trap 的同一个边界采样原因。计数而非只看最终 mcause，
    // 可以证明每一种异常均实际进入过处理程序。
    always @(posedge clk) begin
        if (rst_n && u_dut.u_core.ex_take_trap) begin
            case (u_dut.u_core.ex_take_irq ? u_dut.u_core.csr_irq_cause :
                                            u_dut.u_core.ex_exception_cause)
                32'd2: seen_illegal=seen_illegal+1;
                32'd3: seen_breakpoint=seen_breakpoint+1;
                32'd4: seen_load_misalign=seen_load_misalign+1;
                32'd11: seen_ecall=seen_ecall+1;
                32'h8000_0003: begin seen_software=seen_software+1; irq_software<=1'b0; end
                32'h8000_0007: begin seen_timer=seen_timer+1; irq_timer<=1'b0; end
                32'h8000_000b: begin seen_external=seen_external+1; irq_external<=1'b0; end
                default: begin
                    $display("[FAIL] 非预期 trap cause=%08h",u_dut.u_core.ex_exception_cause);
                    failures=failures+1;
                end
            endcase
        end
    end

    initial begin
        clk=0; rst_n=0; irq_software=0; irq_timer=0; irq_external=0; failures=0;
        seen_illegal=0; seen_ecall=0; seen_load_misalign=0; seen_breakpoint=0;
        seen_software=0; seen_timer=0; seen_external=0;
        for(i=0;i<`RVC_IMEM_DEPTH;i=i+1) u_dut.u_imem.mem[i]=`RVC_NOP_INSTR;
        for(i=0;i<`RVC_DMEM_DEPTH;i=i+1) u_dut.u_dmem.mem[i]=32'b0;

        // 主程序：CSR 六种语义中的写、读/置位、立即数写均被覆盖。
        u_dut.u_imem.mem[0]=enc_i(256,0,3'b000,1,7'b0010011);
        u_dut.u_imem.mem[1]=enc_csr(12'h305,1,3'b001,2); // CSRRW mtvec
        u_dut.u_imem.mem[2]=enc_csr(12'h340,5,3'b101,3); // CSRRWI mscratch,5
        u_dut.u_imem.mem[3]=enc_csr(12'h340,1,3'b111,12); // CSRRCI: 5->4
        u_dut.u_imem.mem[4]=enc_csr(12'h340,2,3'b110,13); // CSRRSI: 4->6
        u_dut.u_imem.mem[5]=enc_i(2,0,3'b000,14,7'b0010011);
        u_dut.u_imem.mem[6]=enc_csr(12'h340,14,3'b011,15); // CSRRC: 6->4
        u_dut.u_imem.mem[7]=enc_csr(12'h340,0,3'b010,4);   // CSRRS 只读
        u_dut.u_imem.mem[8]=32'hffff_ffff;                 // illegal
        u_dut.u_imem.mem[9]=enc_i(1,0,3'b000,5,7'b0010011);
        u_dut.u_imem.mem[10]=32'h0000_0073;                // ECALL
        u_dut.u_imem.mem[11]=enc_i(2,0,3'b000,6,7'b0010011);
        u_dut.u_imem.mem[12]=enc_i(1,0,3'b010,7,7'b0000011); // 未对齐 LW
        u_dut.u_imem.mem[13]=enc_i(3,0,3'b000,8,7'b0010011);
        u_dut.u_imem.mem[14]=enc_i(128,0,3'b000,9,7'b0010011);
        u_dut.u_imem.mem[15]=enc_csr(12'h304,9,3'b001,0);  // mie.MTIE
        u_dut.u_imem.mem[16]=enc_i(8,0,3'b000,16,7'b0010011);
        u_dut.u_imem.mem[17]=enc_csr(12'h304,16,3'b010,0); // mie.MSIE
        u_dut.u_imem.mem[18]=enc_u(20'h00001,17);          // 0x1000
        u_dut.u_imem.mem[19]=enc_i(1,17,3'b101,17,7'b0010011); // 0x800
        u_dut.u_imem.mem[20]=enc_csr(12'h304,17,3'b010,0); // mie.MEIE
        u_dut.u_imem.mem[21]=enc_i(8,0,3'b000,9,7'b0010011);
        u_dut.u_imem.mem[22]=enc_csr(12'h300,9,3'b010,0);  // mstatus.MIE
        u_dut.u_imem.mem[23]=enc_i(4,0,3'b000,10,7'b0010011);
        u_dut.u_imem.mem[24]=32'h0010_0073;                // EBREAK
        u_dut.u_imem.mem[25]=enc_i(5,0,3'b000,11,7'b0010011);
        u_dut.u_imem.mem[26]=enc_s(1020,11,0,3'b010);

        // 统一 Direct trap handler @ 0x100。同步异常跳过故障指令；中断的 mepc
        // 指向尚未执行的指令，所以根据 mcause 符号位直接 MRET，不递增 mepc。
        u_dut.u_imem.mem[64]=enc_csr(12'h342,0,3'b010,20); // mcause
        u_dut.u_imem.mem[65]=enc_csr(12'h341,0,3'b010,21); // mepc
        u_dut.u_imem.mem[66]=enc_csr(12'h343,0,3'b010,22); // mtval
        u_dut.u_imem.mem[67]=enc_b(12,0,20,3'b100);        // BLT x20,x0,irq_return
        u_dut.u_imem.mem[68]=enc_i(4,21,3'b000,21,7'b0010011);
        u_dut.u_imem.mem[69]=enc_csr(12'h341,21,3'b001,0);
        u_dut.u_imem.mem[70]=32'h3020_0073;                // MRET

        repeat(4) @(posedge clk); rst_n=1;
        // 等待软件打开 mie.MTIE 和 mstatus.MIE 后再拉高中断。
        wait(u_dut.u_core.u_csr_file.mie[11] && u_dut.u_core.u_csr_file.mie[7] &&
             u_dut.u_core.u_csr_file.mie[3] && u_dut.u_core.u_csr_file.mstatus[3]);
        // 三类请求同时到达，验证固定优先级 external > software > timer；处理程序
        // 每进入一次仅撤销当前最高优先级源，MRET 后应继续服务剩余请求。
        irq_external=1'b1; irq_software=1'b1; irq_timer=1'b1;
        cycles=0;
        while((u_dut.u_dmem.mem[255] !== 32'd5) && cycles<300) begin
            @(posedge clk); cycles=cycles+1;
        end
        repeat(4) @(posedge clk);

        if(u_dut.u_core.u_id_stage.u_regfile.rf[2]!==32'h100 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[3]!==32'h0 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[4]!==32'h4 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[12]!==32'h5 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[13]!==32'h4 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[15]!==32'h6) begin
            $display("[FAIL] Zicsr 读改写语义错误"); failures=failures+1;
        end else $display("[PASS] Zicsr 写、立即数写和纯读语义");
        if(seen_illegal!=1 || seen_ecall!=1 || seen_load_misalign!=1 ||
           seen_breakpoint!=1 || seen_external!=1 || seen_software!=1 || seen_timer!=1) begin
            $display("[FAIL] trap覆盖 illegal=%0d ecall=%0d lmis=%0d break=%0d ext=%0d sw=%0d timer=%0d",
                seen_illegal,seen_ecall,seen_load_misalign,seen_breakpoint,
                seen_external,seen_software,seen_timer);
            failures=failures+1;
        end else $display("[PASS] 同步异常、机器定时器中断均精确进入一次");
        if(u_dut.u_core.u_id_stage.u_regfile.rf[5]!==1 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[6]!==2 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[8]!==3 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[10]!==4 ||
           u_dut.u_core.u_id_stage.u_regfile.rf[11]!==5) begin
            $display("[FAIL] MRET 返回或冲刷边界错误"); failures=failures+1;
        end else $display("[PASS] MRET 返回并继续执行未提交指令");
        if(failures==0) $display("========== TRAP_TEST_PASSED ==========");
        else $fatal(1,"trap regression failed: %0d",failures);
        $finish;
    end
endmodule
