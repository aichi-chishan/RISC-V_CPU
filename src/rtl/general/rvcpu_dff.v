//==============================================================================
// Designer   : [你的名字]
//
// Description:
//   rvcpu_dff.v — 通用 D 触发器库
//
// 用途:
//   - 流水线寄存器 (Phase 2+)
//   - 控制信号打拍
//   - 同步化跨时钟域信号
//
// 建议的触发器类型:
//   1. 基本 DFF : 最简单的触发器
//   2. 带使能 DFF : en=1 时才更新
//   3. 带复位 DFF : 同步/异步复位
//   4. 多比特 DFF : 宽位宽数据 DFF
//
// Phase 1 可能不需要，但建议先建好，Phase 2 流水线会大量用到。
//
// 参考设计 (E203 general/sirv_gnrl_dffs.v):
//   E203 有一个通用的 DFF 库，包含:
//     - sirv_gnrl_dffl : 基本 DFF
//     - sirv_gnrl_dffr : 带异步复位的 DFF
//     - sirv_gnrl_dfflr : 带使能和异步复位的 DFF
//     - sirv_gnrl_ltch : Latch (低功耗设计)
//
// 你的任务：
//   Phase 1 留空或写一个简单的 DFF 模板即可
//   Phase 2 再完善
//==============================================================================

`include "defines.v"

//==============================================================================
// 示例：基本 DFF
//==============================================================================
// module rvcpu_dff (
//     input  wire        clk,
//     input  wire        d,
//     output wire        q
// );
//     reg q_reg;
//     always @(posedge clk) begin
//         q_reg <= d;
//     end
//     assign q = q_reg;
// endmodule
//
// TODO: 根据你的需求添加:
//   - rvcpu_dff_en    : 带使能的 DFF
//   - rvcpu_dff_rst   : 带复位的 DFF
//   - rvcpu_dff_bus   : 多比特版本的 DFF

endmodule
