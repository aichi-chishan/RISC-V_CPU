//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_imem.v — 指令存储器 (Instruction Memory)
//   Phase 1 用 Verilog reg 数组模拟组合逻辑读存储器。
//
// 关键设计决策:
//   Phase 1 (单周期): 组合逻辑读 — assign rdata = mem[addr]
//     优点: 同周期拿到指令, 不需要时序适应
//     缺点: FPGA 综合时用 LUT 实现 (深度大时面积大)
//
//   Phase 2 (五级流水): 改为同步读 — rdata <= mem[addr] (posedge clk)
//     优点: FPGA BRAM 是同步读, 面积小速度快
//     代价: 需要在 IF 阶段中处理 1 周期读延迟 (通过增加等待周期)
//
// E203 的做法: ITCM 是 64 位宽的同步 SRAM (1 周期延迟),
//   通过 ICB 总线的 valid/ready 握手自动处理延迟。
//
// 你的任务:
//   Step 1: 计算 DEPTH = IMEM_SIZE_KB * 1024 / 4
//   Step 2: 声明 reg [31:0] mem [0:DEPTH-1]
//   Step 3: 实现组合逻辑读 rdata = mem[word_addr]
//   Step 4: 确保 $readmemh 在 initial 块中加载
//
// 注意: TB 通过层次路径 u_dut.u_imem.mem 加载程序,
//   所以 mem 数组不能声明在 always 块内部 (必须模块级 reg)。
//==============================================================================

`include "defines.v"

module rvcpu_imem (
    // TODO: 定义端口
    // input  wire [`RVC_IMEM_AW-1:0]   addr,   — 字地址 (已经 >>2 过)
    // output wire [31:0]              rdata   — 32 位指令


    //==========================================================================
    // 一、参数计算
    //==========================================================================
    // localparam DEPTH = `RVC_IMEM_DEPTH;    — 已在 defines.v 中计算好


    //==========================================================================
    // 二、存储体
    //==========================================================================
    // TODO: 声明 reg 数组
    //
    // reg [31:0] mem [0:DEPTH-1];
    //
    // TB 将通过层次路径访问此数组来加载程序:
    //   $readmemh("smoke_test.hex", u_dut.u_imem.mem);


    //==========================================================================
    // 三、组合逻辑读
    //==========================================================================
    // TODO: 实现组合逻辑读
    //
    // assign rdata = mem[addr];
    //
    // Phase 2 改为:
    //   reg [31:0] rdata_r;
    //   always @(posedge clk) rdata_r <= mem[addr];
    //   assign rdata = rdata_r;

endmodule
