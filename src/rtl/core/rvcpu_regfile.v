//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_regfile.v — 寄存器堆
//   32 个 32 位寄存器，x0 硬连线为 0 (RISC-V 规范要求)
//   2 组合读端口 + 1 时序写端口
//
// 这个模块你可以直接复用你已有的 regfile.v 代码。
// 只需注意:
//   1. 使用 defines.v 中的宏 `RVC_RFIDX_WIDTH 和 `RVC_XLEN 和 `RVC_RFREG_NUM
//   2. 读端口是组合逻辑 — 所有读数据同周期有效
//   3. 写端口是时序逻辑 — posedge clk 写入
//   4. x0 寄存器永远返回 0, 且不可写入
//
// 你的已有 regfile.v 完全满足上述要求, 只需把头文件改为 `include "defines.v"。
//
// 到 Phase 2 五级流水时, 寄存器堆本身不需要修改 —
// 前推 (forwarding) 逻辑在 EX 阶段的操作数选择中实现,
// 而不是在寄存器堆内部实现。
// 这是 E203 的设计模式: 寄存器堆保持干净, 冲突解决在外部。
//
// 值得从 E203 学习的:
//   E203 的寄存器堆支持 latch-based 实现 (节省功耗和面积),
//   以及 FPGA 的 BRAM 实现。Phase 1 我们直接用 flip-flop 即可。
//
// 你的任务:
//   Step 1: 使用 RVC_* 宏 (不是硬编码数字) 定义端口和存储体
//   Step 2: 实现组合读 (x0 返回 0)
//   Step 3: 实现时序写 (x0 不可写)
//==============================================================================

`include "defines.v"

module rvcpu_regfile (
    //==========================================================================
    // TODO: 定义端口
    //==========================================================================

    // input  wire                            clk,
    //
    // // 读端口 1 (组合逻辑)
    // input  wire [`RVC_RFIDX_WIDTH-1:0]     ra1,
    // output wire [`RVC_XLEN-1:0]            rd1,
    //
    // // 读端口 2 (组合逻辑)
    // input  wire [`RVC_RFIDX_WIDTH-1:0]     ra2,
    // output wire [`RVC_XLEN-1:0]            rd2,
    //
    // // 写端口 (时序逻辑)
    // input  wire [`RVC_RFIDX_WIDTH-1:0]     wa,
    // input  wire [`RVC_XLEN-1:0]            wd,
    // input  wire                            we


    //==========================================================================
    // TODO: 实现寄存器堆
    //==========================================================================
    //
    // 提示 (来自你已有的 regfile.v):
    //
    //   reg [`RVC_XLEN-1:0] rf [`RVC_RFREG_NUM-1:0];
    //
    //   // 读: 组合逻辑, x0 返回 0
    //   assign rd1 = (ra1 == 0) ? `RVC_XLEN'd0 : rf[ra1];
    //   assign rd2 = (ra2 == 0) ? `RVC_XLEN'd0 : rf[ra2];
    //
    //   // 写: 时序逻辑, x0 不可写
    //   always @(posedge clk) begin
    //       if (we && (wa != 0))
    //           rf[wa] <= wd;
    //   end

endmodule
