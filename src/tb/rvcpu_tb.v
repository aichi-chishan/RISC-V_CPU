`timescale 1ns / 1ps

//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_tb.v — 多周期 CPU 仿真测试平台
//   Phase 1: 验证多周期 RV32I CPU 的基本功能
//
//   每条指令 5 个周期 (IF/ID/EX/MEM/WB):
//     - 冒烟测试有 9 条指令 → 约 9×5 = 45 个周期
//
//   冒烟测试程序 (smoke_test.hex):
//     ADDI x1, x0, 5     → x1 = 5
//     ADDI x2, x0, 3     → x2 = 3
//     ADD  x3, x1, x2    → x3 = 8
//     ADDI x4, x0, 8     → x4 = 8 (期望值)
//     BNE  x3, x4, 0x10  → x3==x4, 不跳转
//     ADDI x5, x0, 1     → x5 = 1 (PASS flag)
//     LUI  x4, 0x10000   → x4 = 0x1000_0000
//     SW   x5, 0x100(x0)  → mem[0x100] = 1
//     死循环
//
// 验证点:
//   1. DMEM[0x40] (字节地址 0x100>>2) 被写入 1 → PASS
//   2. PC 正确更新 (每 5 周期 +4)
//
// 用法:
//   bash src/scripts/build.sh simulate
//==============================================================================

`include "../rtl/core/defines.v"

module rvcpu_tb;

    // 可用 +IMEM_HEX=<path> 覆盖，便于 Icarus、ModelSim 和 Vivado 共用 TB。
    reg [8*256-1:0] imem_hex_file;

    //==========================================================================
    // 一、时钟与复位
    //==========================================================================
    reg clk;
    reg rst_n;
    wire [31:0] debug_pc;
    wire [2:0]  debug_stage;
    wire        debug_wb_we;
    wire [4:0]  debug_wb_rd;
    wire [31:0] debug_wb_data;
    // rvcpu_top 新增的 LED 外设内部总线在本 smoke 测试中不检查，
    // 仍显式连接以避免 ModelSim 将遗漏端口报告为潜在设计错误。
    wire        periph_led_we;
    wire [31:0] periph_led_wdata;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;                                    // 100MHz
    end

    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("=== Multi-Cycle CPU Reset Released at t=%0t ===", $time);
    end

    //==========================================================================
    // 二、例化 DUT
    //==========================================================================
    rvcpu_top u_dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .debug_pc      (debug_pc),
        .debug_stage   (debug_stage),
        .debug_wb_we   (debug_wb_we),
        .debug_wb_rd   (debug_wb_rd),
        .debug_wb_data (debug_wb_data),
        .periph_led_we(periph_led_we),
        .periph_led_wdata(periph_led_wdata)
    );

    //==========================================================================
    // 三、加载测试程序到 IMEM
    //==========================================================================
    initial begin
        if (!$value$plusargs("IMEM_HEX=%s", imem_hex_file))
            imem_hex_file = "src/riscv-tests/smoke_test.hex";
        $readmemh(imem_hex_file, u_dut.u_imem.mem);
        $display("=== Test program loaded from %0s ===", imem_hex_file);
    end

    //==========================================================================
    // 四、监控 — 每个节拍结束时打印阶段信息
    //==========================================================================
    // 多周期中每 5 个周期执行一条指令, 以下监控按节拍分组显示
    always @(posedge clk) begin
        if (rst_n) begin
            case (u_dut.cycle_cnt)
                `RVC_STAGE_IF: begin
                    // IF 阶段: 显示当前 PC 和取到的指令
                    $display("[t=%4t] IF : PC=%08h | IR=%08h",
                             $time, u_dut.pc, u_dut.if_ir);
                end
                `RVC_STAGE_ID: begin
                    // ID 阶段: 显示被译码的指令的 rs1/rs2/rd
                    $display("[t=%4t] ID : IR=%08h",
                             $time, u_dut.if_id_ir);
                end
                `RVC_STAGE_EX: begin
                    // EX 阶段: 显示 ALU 结果和分支判定
                    $display("[t=%4t] EX : ALU=%08h | branch=%0d",
                             $time, u_dut.ex_alu_result,
                             u_dut.ex_branch_taken);
                end
                `RVC_STAGE_MEM: begin
                    // MEM 阶段: 显示访存操作
                    if (u_dut.u_core.dmem_wen)
                        $display("[t=%4t] MEM: STORE addr=%08h data=%08h",
                                 $time,
                                 {u_dut.u_core.dmem_addr, 2'b00},  // 字地址→字节地址
                                 u_dut.u_core.dmem_wdata);
                    else
                        $display("[t=%4t] MEM: (no store)", $time);
                end
                `RVC_STAGE_WB: begin
                    // WB 阶段: 显示写回
                    if (u_dut.wb_we)
                        $display("[t=%4t] WB : x%0d <= %08h",
                                 $time, u_dut.wb_wa, u_dut.wb_wd);
                    else
                        $display("[t=%4t] WB : (no writeback)", $time);
                end
            endcase
        end
    end

    //==========================================================================
    // 五、检测测试结果
    //==========================================================================
    // Store 指令在第 8 条 (从 0 开始数), 字节地址 0x100 → 字地址 0x40
    // 8 条指令 × 5 周期 = 40 个周期后, MEM 阶段 (cycle 3) 写 DMEM
    // 第 8 条指令的 cycle 3 发生在大约第 8*5 + 3 = 43 个周期
    always @(posedge clk) begin
        if (rst_n && u_dut.u_core.dmem_wen && u_dut.u_core.dmem_addr == 8'h40) begin
            if (u_dut.u_core.dmem_wdata == 32'd1) begin
                $display("");
                $display("+==============================+");
                $display("|        TEST PASSED !         |");
                $display("+==============================+");
                $display("");
            end else begin
                $display("");
                $display("+==============================+");
                $display("|        TEST FAILED !         |");
                $display("|  DMEM[0x100] = %d (expect 1)|", u_dut.u_core.dmem_wdata);
                $display("+==============================+");
                $display("");
            end
            $finish;
        end
    end

    //==========================================================================
    // 六、超时保护 — 多周期需要更长时间
    //==========================================================================
    initial begin
        #500000;                                 // 500us 超时
        $display("TIMEOUT: Simulation did not finish");
        $finish;
    end

    //==========================================================================
    // 七、VCD 波形
    //==========================================================================
    initial begin
        $dumpfile("rvcpu_tb.vcd");
        $dumpvars(0, rvcpu_tb);
    end

endmodule
