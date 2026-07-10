`timescale 1ns / 1ps

//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_tb.v — CPU 仿真测试平台 (Testbench)
//   Phase 1: 验证单周期 RV32I CPU 的基本功能
//
// 用法:
//   cd build && iverilog -o rvcpu_tb.vvp -I ../src/rtl/core -I ../src/rtl/mems -I ../src/tb -g2012 ../src/rtl/core/config.v ../src/rtl/core/defines.v ../src/rtl/core/rvcpu_if_stage.v ../src/rtl/core/rvcpu_id_stage.v ../src/rtl/core/rvcpu_ex_stage.v ../src/rtl/core/rvcpu_mem_stage.v ../src/rtl/core/rvcpu_wb_stage.v ../src/rtl/core/rvcpu_decode.v ../src/rtl/core/rvcpu_regfile.v ../src/rtl/core/rvcpu_immgen.v ../src/rtl/mems/rvcpu_imem.v ../src/rtl/mems/rvcpu_dmem.v ../src/rtl/core/rvcpu_top.v ../src/tb/rvcpu_tb.v
//
//   测试程序 (smoke_test):
//     ADDI x1, x0, 5     → x1 = 5
//     ADDI x2, x0, 3     → x2 = 3
//     ADD  x3, x1, x2    → x3 = 8
//     ADDI x4, x0, 8     → x4 = 8 (期望值)
//     BNE  x3, x4, fail  → x3==x8, 不跳转
//     ADDI x5, x0, 1     → x5 = 1 (PASS flag)
//     SW   x5, 0x100(x0) → mem[0x100] = 1
//     死循环
//
// 验证点:
//   1. 寄存器值: x1=5, x2=3, x3=8, x4=8, x5=1
//   2. DMEM[0x100] 被写入 1 (测试通过标志)
//   3. PC 正确更新 (无跳转时 +4, BNE 条件不成立时 +4)
//==============================================================================

`include "defines.v"

module rvcpu_tb;

    //==========================================================================
    // 一、时钟与复位
    //==========================================================================
    reg clk;
    reg rst_n;

    // 时钟生成: 100MHz → 周期 10ns
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // 复位: 前 20ns 低电平, 保证 CPU 正确复位
    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("=== CPU Reset Released at t=%0t ===", $time);
    end

    //==========================================================================
    // 二、例化待测 CPU (DUT)
    //==========================================================================
    rvcpu_top u_dut (
        .clk   (clk),
        .rst_n (rst_n)
    );

    //==========================================================================
    // 三、加载测试程序到 IMEM
    //==========================================================================
    initial begin
        $readmemh("../src/riscv-tests/smoke_test.hex",
                   u_dut.u_imem.mem);
        $display("=== Test program loaded into IMEM ===");
    end

    //==========================================================================
    // 四、监控关键信号
    //==========================================================================
    // 监控 IF 阶段的 PC 和指令
    always @(posedge clk) begin
        if (rst_n) begin
            $display("t=%4t: PC=%08h | IR=%08h",
                     $time,
                     u_dut.u_if_stage.o_pc,
                     u_dut.u_if_stage.o_ir);
        end
    end

    //==========================================================================
    // 五、监测测试结果 (通过 DMEM 写入)
    //==========================================================================
    // 检测: 如果 DMEM[0x100] 被写入 1 → PASS
    //       模拟测试框架的 tohost 机制
    always @(posedge clk) begin
        if (rst_n && u_dut.u_mem_stage.dmem_wen
                 && u_dut.u_mem_stage.dmem_addr == 8'h40) begin // 0x100 >> 2 = 0x40
            if (u_dut.u_mem_stage.dmem_wdata == 32'd1) begin
                $display("");
                $display("╔══════════════════════════════════════╗");
                $display("║          TEST PASSED !               ║");
                $display("╚══════════════════════════════════════╝");
                $display("");
            end else begin
                $display("");
                $display("╔══════════════════════════════════════╗");
                $display("║          TEST FAILED !               ║");
                $display("║   DMEM[0x100] = %d (expected 1)     ║", u_dut.u_mem_stage.dmem_wdata);
                $display("╚══════════════════════════════════════╝");
                $display("");
            end
            $finish;
        end
    end

    //==========================================================================
    // 六、超时保护
    //==========================================================================
    initial begin
        #100000;  // 最大仿真时间: 100us
        $display("TIMEOUT: Simulation did not finish");
        $finish;
    end

    //==========================================================================
    // 七、波形输出 (VCD)
    //==========================================================================
    initial begin
        $dumpfile("rvcpu_tb.vcd");
        $dumpvars(0, rvcpu_tb);
        $display("=== VCD dump started ===");
    end

endmodule
