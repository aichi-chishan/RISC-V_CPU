//==============================================================================
// sim_main.cpp — Verilator 仿真主程序 (C++)
//
// 这是用于 Verilator 的仿真入口。
// Verilator 将 Verilog 编译为 C++，然后你需要写一个 main() 来驱动仿真。
//
// 使用方式:
//   verilator --cc --build --exe -o rvcpu_tb \
//       -I src/rtl/core -I src/rtl/mems -I src/rtl/general -I src/tb \
//       ${RTL_FILES} src/tb/sim_main.cpp
//   ./obj_dir/Vrvcpu_tb
//
// 你的任务：
//   Phase 1 推荐先用 iverilog (更简单)，
//   Phase 2+ 考虑用 Verilator (速度快，适合大型测试)
//==============================================================================

#include "Vrvcpu_tb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vrvcpu_tb* top = new Vrvcpu_tb;

    // 波形输出
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("rvcpu_tb.vcd");

    // 复位
    top->clk = 0;
    top->rst_n = 0;
    for (int i = 0; i < 10; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(i);
        top->clk = !top->clk;
        top->eval();
        tfp->dump(i);
    }
    top->rst_n = 1;

    // 运行仿真
    for (int i = 10; i < 1000; i++) {
        top->clk = !top->clk;
        top->eval();
        tfp->dump(i);
        top->clk = !top->clk;
        top->eval();
        tfp->dump(i);
    }

    top->final();
    tfp->close();
    delete top;
    return 0;
}
