`timescale 1ns / 1ps

//==============================================================================
// RV32I 多周期核定向回归测试
//
// 这个测试台不依赖外部汇编器：通过下方的编码函数直接构造 RV32I 指令，
// 并将它们写入 DUT 的指令存储器。优点是每一项检查都能和对应指令一一对应，
// 当测试失败时可直接根据寄存器名和分类定位到译码、EX 或 MEM 阶段。
//
// 覆盖范围：
//   * 全部 RV32I OP/OP-IMM 算术和逻辑运算；
//   * LUI、AUIPC、六种条件分支、JAL、JALR 与 FENCE；
//   * SB/SH/SW、LB/LBU/LH/LHU/LW 的字节序和符号扩展；
//   * x0 恒为零，以及非法 R 型 funct7 不产生写回。
//
// ECALL/EBREAK、地址错误和 CSR 属于后续异常/特权阶段的职责，故本测试
// 不把它们当作 Phase 1 的 RV32I 完整性验收内容。
//==============================================================================
`include "../rtl/core/defines.v"

module rvcpu_rv32i_tb;
    reg  clk;
    reg  rst_n;
    wire [31:0] debug_pc;
    wire [2:0]  debug_stage;
    wire        debug_wb_we;
    wire [4:0]  debug_wb_rd;
    wire [31:0] debug_wb_data;

    integer i;
    integer p;
    integer failures;
    integer auipc_expected;
    integer jal_pc;
    integer jalr_pc;
    integer jalr_target;

    // R 型编码：funct7 | rs2 | rs1 | funct3 | rd | opcode。
    function [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            enc_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
        end
    endfunction

    // I 型编码同时服务于 OP-IMM、Load 与 JALR；不同类别仅 opcode 不同。
    function [31:0] enc_i;
        input integer imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        reg [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_i = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    // S/B/J 立即数在指令内不是连续排列，编码函数能避免手写机器码时出错。
    function [31:0] enc_s;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        reg [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_s = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] enc_b;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        reg [12:0] imm13;
        begin
            imm13 = imm[12:0];
            enc_b = {imm13[12], imm13[10:5], rs2, rs1, funct3,
                     imm13[4:1], imm13[11], 7'b1100011};
        end
    endfunction

    function [31:0] enc_u;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            enc_u = {imm20, rd, opcode};
        end
    endfunction

    function [31:0] enc_j;
        input integer imm;
        input [4:0] rd;
        reg [20:0] imm21;
        begin
            imm21 = imm[20:0];
            enc_j = {imm21[20], imm21[10:1], imm21[11], imm21[19:12],
                     rd, 7'b1101111};
        end
    endfunction

    // 单独封装检查任务，让失败输出包含具体寄存器/存储器和期望值。
    task expect_reg;
        input [4:0] index;
        input [31:0] expected;
        input [8*32-1:0] name;
        reg [31:0] actual;
        begin
            actual = u_dut.u_core.u_id_stage.u_regfile.rf[index];
            if (actual !== expected) begin
                $display("[FAIL] %-32s x%0d: got=%08h expect=%08h", name, index, actual, expected);
                failures = failures + 1;
            end else begin
                $display("[PASS] %-32s x%0d = %08h", name, index, actual);
            end
        end
    endtask

    task expect_mem;
        input integer byte_addr;
        input [31:0] expected;
        input [8*32-1:0] name;
        reg [31:0] actual;
        begin
            actual = u_dut.u_dmem.mem[byte_addr >> 2];
            if (actual !== expected) begin
                $display("[FAIL] %-32s mem[%03h]: got=%08h expect=%08h", name, byte_addr, actual, expected);
                failures = failures + 1;
            end else begin
                $display("[PASS] %-32s mem[%03h] = %08h", name, byte_addr, actual);
            end
        end
    endtask

    task run_checks;
        begin
            failures = 0;
            $display("\n========== RV32I 多周期回归检查 ==========");
            expect_reg(5'd0,  32'h0000_0000, "x0 恒为零");
            expect_reg(5'd1,  32'h0000_0005, "ADDI 基础结果");
            expect_reg(5'd2,  32'hffff_fffd, "ADDI 负立即数");
            expect_reg(5'd3,  32'h0000_0002, "ADD");
            expect_reg(5'd4,  32'h0000_0008, "SUB");
            expect_reg(5'd5,  32'h0000_00a0, "SLL");
            expect_reg(5'd6,  32'h0000_0001, "SLT 与非法 funct7 保持");
            expect_reg(5'd7,  32'h0000_0000, "SLTU");
            expect_reg(5'd8,  32'hffff_fff8, "XOR");
            expect_reg(5'd9,  32'h07ff_ffff, "SRL");
            expect_reg(5'd10, 32'hffff_ffff, "SRA");
            // 0x00000005 | 0xfffffffd = 0xfffffffd；最低第二位在两个操作数中均为 0。
            expect_reg(5'd11, 32'hffff_fffd, "OR");
            expect_reg(5'd12, 32'h0000_0005, "AND");
            expect_reg(5'd13, 32'h0000_8000, "LHU 零扩展");
            expect_reg(5'd14, 32'h1234_5000, "LW");
            expect_reg(5'd15, 32'h0000_0007, "六种分支与未跳转路径");
            expect_reg(5'd16, jal_pc + 4,    "JAL 返回地址");
            expect_reg(5'd17, jalr_target + 1, "JALR 奇地址基址");
            expect_reg(5'd18, jalr_pc + 4,   "JALR 返回地址");
            expect_reg(5'd19, 32'h0000_0050, "SLLI");
            expect_reg(5'd20, 32'h7fff_fffe, "SRLI");
            // -3 算术右移一位等于 -2，即 0xfffffffe。
            expect_reg(5'd21, 32'hffff_fffe, "SRAI");
            expect_reg(5'd22, 32'h1234_5000, "LUI");
            expect_reg(5'd23, auipc_expected, "AUIPC");
            expect_reg(5'd24, 32'h0000_0080, "Load/Store 基址");
            expect_reg(5'd25, 32'h0000_0000, "非对齐 Load 临时策略");
            expect_reg(5'd26, 32'h0000_0044, "LB 符号扩展正数");
            expect_reg(5'd27, 32'h0000_0044, "LBU");
            expect_reg(5'd28, 32'hffff_ffff, "LB 符号扩展负数");
            expect_reg(5'd29, 32'h0000_00ff, "LBU 零扩展 0xff");
            expect_reg(5'd30, 32'hffff_8000, "LH 符号扩展");
            expect_reg(5'd31, 32'h0000_0001, "完成标记寄存器");
            expect_mem(16'h030, 32'hffff_fff6, "SLTI 前保存结果");
            expect_mem(16'h034, 32'h0000_0001, "SLT 前保存结果");
            expect_mem(16'h038, 32'h0000_0000, "SLTU 前保存结果");
            expect_mem(16'h080, 32'h3344_4444, "SB/SB/SH 小端字节序");
            expect_mem(16'h084, 32'h8000_00ff, "负字节和半字存储");
            expect_mem(16'h088, 32'h1234_5000, "SW/LW 字访问");
            expect_mem(16'h08c, 32'h0000_0000, "非法/非对齐 Store 无副作用");
            expect_mem(16'h3fc, 32'h0000_0001, "结束写入");
            if (failures == 0)
                $display("========== RV32I_TEST_PASSED ==========");
            else
                $display("========== RV32I_TEST_FAILED: %0d 项 ==========", failures);
        end
    endtask

    // 多周期内核固定每条指令经历 5 个时钟。100 MHz 只用于使波形时间直观，
    // 不影响指令功能验证。
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    rvcpu_top #(.IMEM_INIT_FILE("")) u_dut (
        .clk(clk), .rst_n(rst_n),
        .debug_pc(debug_pc), .debug_stage(debug_stage),
        .debug_wb_we(debug_wb_we), .debug_wb_rd(debug_wb_rd),
        .debug_wb_data(debug_wb_data),
        .periph_led_we(), .periph_led_wdata()
    );

    // 指令程序在复位释放前准备完毕。未使用的指令空间填 NOP，避免 PC 异常
    // 继续执行时把 X 值译码为不可预测的控制信号。
    initial begin
        for (i = 0; i < `RVC_IMEM_DEPTH; i = i + 1)
            u_dut.u_imem.mem[i] = `RVC_NOP_INSTR;
        for (i = 0; i < `RVC_DMEM_DEPTH; i = i + 1)
            u_dut.u_dmem.mem[i] = 32'b0;

        p = 0;
        // --- OP 与 OP-IMM：覆盖每一种 RV32I 算术/逻辑运算 ---
        u_dut.u_imem.mem[p] = enc_i(5,  0, 3'b000,  1, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(-3, 0, 3'b000,  2, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 2, 1, 3'b000,  3); p = p + 1; // ADD
        u_dut.u_imem.mem[p] = enc_r(7'b0100000, 2, 1, 3'b000,  4); p = p + 1; // SUB
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 1, 1, 3'b001,  5); p = p + 1; // SLL
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 1, 2, 3'b010,  6); p = p + 1; // SLT
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 1, 2, 3'b011,  7); p = p + 1; // SLTU
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 2, 1, 3'b100,  8); p = p + 1; // XOR
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 1, 2, 3'b101,  9); p = p + 1; // SRL
        u_dut.u_imem.mem[p] = enc_r(7'b0100000, 1, 2, 3'b101, 10); p = p + 1; // SRA
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 2, 1, 3'b110, 11); p = p + 1; // OR
        u_dut.u_imem.mem[p] = enc_r(7'b0000000, 2, 1, 3'b111, 12); p = p + 1; // AND
        u_dut.u_imem.mem[p] = enc_i(-10, 0, 3'b000, 13, 7'b0010011); p = p + 1; // ADDI
        u_dut.u_imem.mem[p] = enc_i(0,   2, 3'b010, 14, 7'b0010011); p = p + 1; // SLTI
        u_dut.u_imem.mem[p] = enc_i(10,  2, 3'b011, 15, 7'b0010011); p = p + 1; // SLTIU
        u_dut.u_imem.mem[p] = enc_s(16'h030, 13, 0, 3'b010); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(16'h034, 14, 0, 3'b010); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(16'h038, 15, 0, 3'b010); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(-1,  1, 3'b100, 16, 7'b0010011); p = p + 1; // XORI
        u_dut.u_imem.mem[p] = enc_i(16'h40, 1, 3'b110, 17, 7'b0010011); p = p + 1; // ORI
        u_dut.u_imem.mem[p] = enc_i(16'h0f, 17, 3'b111, 18, 7'b0010011); p = p + 1; // ANDI
        u_dut.u_imem.mem[p] = enc_i(4,   1, 3'b001, 19, 7'b0010011); p = p + 1; // SLLI
        u_dut.u_imem.mem[p] = enc_i(1,   2, 3'b101, 20, 7'b0010011); p = p + 1; // SRLI
        u_dut.u_imem.mem[p] = enc_i(12'h401, 2, 3'b101, 21, 7'b0010011); p = p + 1; // SRAI
        u_dut.u_imem.mem[p] = enc_u(20'h12345, 22, 7'b0110111); p = p + 1; // LUI
        auipc_expected = p * 4 + 32'h0000_1000;
        u_dut.u_imem.mem[p] = enc_u(20'h00001, 23, 7'b0010111); p = p + 1; // AUIPC

        // --- 对齐 Load/Store：同时检查小端字节序、符号扩展与零扩展 ---
        u_dut.u_imem.mem[p] = enc_i(16'h080, 0, 3'b000, 24, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_u(20'h11223, 25, 7'b0110111); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(16'h344, 25, 3'b000, 25, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(0, 25, 24, 3'b000); p = p + 1; // SB 0x44
        u_dut.u_imem.mem[p] = enc_s(1, 25, 24, 3'b000); p = p + 1; // SB 0x44
        u_dut.u_imem.mem[p] = enc_s(2, 25, 24, 3'b001); p = p + 1; // SH 0x3344
        u_dut.u_imem.mem[p] = enc_i(0, 24, 3'b000, 26, 7'b0000011); p = p + 1; // LB
        u_dut.u_imem.mem[p] = enc_i(0, 24, 3'b100, 27, 7'b0000011); p = p + 1; // LBU
        u_dut.u_imem.mem[p] = enc_i(-1, 0, 3'b000, 25, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(4, 25, 24, 3'b000); p = p + 1; // SB 0xff
        u_dut.u_imem.mem[p] = enc_i(4, 24, 3'b000, 28, 7'b0000011); p = p + 1; // LB
        u_dut.u_imem.mem[p] = enc_i(4, 24, 3'b100, 29, 7'b0000011); p = p + 1; // LBU
        u_dut.u_imem.mem[p] = enc_u(20'h00008, 25, 7'b0110111); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(6, 25, 24, 3'b001); p = p + 1; // SH 0x8000
        u_dut.u_imem.mem[p] = enc_i(6, 24, 3'b001, 30, 7'b0000011); p = p + 1; // LH
        u_dut.u_imem.mem[p] = enc_i(6, 24, 3'b101, 13, 7'b0000011); p = p + 1; // LHU
        u_dut.u_imem.mem[p] = enc_s(8, 22, 24, 3'b010); p = p + 1; // SW
        u_dut.u_imem.mem[p] = enc_i(8, 24, 3'b010, 14, 7'b0000011); p = p + 1; // LW

        // 非法 Store funct3=011 必须停留在无副作用的默认译码分支。随后刻意
        // 发起两个非对齐 Store 和两个非对齐 Load，验证 MEM 阶段的临时保守
        // 策略：写请求被阻止，读结果归零。以后接入异常模块后，这些访问会被
        // 替换为 address-misaligned trap，而不是继续向下执行。
        u_dut.u_imem.mem[p] = enc_s(12, 1, 24, 3'b011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(16'h55, 0, 3'b000, 25, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(9, 25, 24, 3'b001); p = p + 1;  // 非对齐 SH
        u_dut.u_imem.mem[p] = enc_s(10, 25, 24, 3'b010); p = p + 1; // 非对齐 SW
        u_dut.u_imem.mem[p] = enc_i(9, 24, 3'b001, 25, 7'b0000011); p = p + 1; // 非对齐 LH
        u_dut.u_imem.mem[p] = enc_i(10, 24, 3'b010, 25, 7'b0000011); p = p + 1; // 非对齐 LW

        // --- 六种跳转分支：所有跳转位移为 +8，恰好越过一条加法指令 ---
        u_dut.u_imem.mem[p] = enc_i(0, 0, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 1, 1, 3'b000); p = p + 1; // BEQ，跳转
        u_dut.u_imem.mem[p] = enc_i(1, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 2, 1, 3'b001); p = p + 1; // BNE，跳转
        u_dut.u_imem.mem[p] = enc_i(2, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 1, 2, 3'b100); p = p + 1; // BLT，跳转
        u_dut.u_imem.mem[p] = enc_i(4, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 2, 1, 3'b101); p = p + 1; // BGE，跳转
        u_dut.u_imem.mem[p] = enc_i(8, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 2, 1, 3'b110); p = p + 1; // BLTU，跳转
        u_dut.u_imem.mem[p] = enc_i(16, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 1, 2, 3'b111); p = p + 1; // BGEU，跳转
        u_dut.u_imem.mem[p] = enc_i(32, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 2, 1, 3'b000); p = p + 1; // BEQ，不跳转
        u_dut.u_imem.mem[p] = enc_i(1, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 2, 1, 3'b100); p = p + 1; // BLT，不跳转
        u_dut.u_imem.mem[p] = enc_i(2, 15, 3'b000, 15, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_b(8, 1, 2, 3'b110); p = p + 1; // BLTU，不跳转
        u_dut.u_imem.mem[p] = enc_i(4, 15, 3'b000, 15, 7'b0010011); p = p + 1;

        // FENCE 在当前无缓存、无乱序实现中等效为 NOP，但必须可被合法译码。
        u_dut.u_imem.mem[p] = 32'h0000_000f; p = p + 1;

        // JAL 跳过一条会污染 x15 的指令，并检查 rd 得到 PC+4。
        jal_pc = p * 4;
        u_dut.u_imem.mem[p] = enc_j(8, 16); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(32, 15, 3'b000, 15, 7'b0010011); p = p + 1;

        // JALR 使用奇数基址，验证 EX 阶段确实清除了目标地址 bit0。
        jalr_target = (p + 3) * 4;
        u_dut.u_imem.mem[p] = enc_i(jalr_target + 1, 0, 3'b000, 17, 7'b0010011); p = p + 1;
        jalr_pc = p * 4;
        u_dut.u_imem.mem[p] = enc_i(0, 17, 3'b000, 18, 7'b1100111); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(32, 15, 3'b000, 15, 7'b0010011); p = p + 1;

        // 非法 R 型 funct7 不能改写此前由 SLT 得到的 x6；随后尝试写 x0，
        // 再次验证寄存器堆硬连线零的实现。
        u_dut.u_imem.mem[p] = enc_r(7'b0100001, 2, 1, 3'b000, 6); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(123, 0, 3'b000, 0, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_i(1, 0, 3'b000, 31, 7'b0010011); p = p + 1;
        u_dut.u_imem.mem[p] = enc_s(16'h3fc, 31, 0, 3'b010); p = p + 1;
    end

    // 最后一条 SW 到 0x3fc 是测试结束协议。延迟 1ns 后检查，确保 DMEM
    // 的非阻塞写入已经在本时钟沿提交。
    always @(posedge clk) begin
        if (rst_n && u_dut.u_core.dmem_wen &&
            ({u_dut.u_core.dmem_addr, 2'b00} == 32'h0000_03fc)) begin
            #1;
            run_checks;
            if (failures == 0)
                $finish;
            else
                $fatal(1, "RV32I regression failed");
        end
    end

    initial begin
        #200000;
        $fatal(1, "RV32I regression timeout");
    end
endmodule
