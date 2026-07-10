//==============================================================================
// Designer   : [你的名字]
//
// Description:
//   rvcpu_sram.v — 通用 SRAM 封装
//
// Phase 1 中不需要（直接用 reg 数组即可）。
// Phase 3 引入 ICB 总线后，这个模块用于封装 ITCM/DTCM 的 SRAM 接口。
//
// 参考设计 (E203 general/sirv_gnrl_ram.v):
//   E203 用行为模型和仿真模型分离的方式处理 SRAM：
//     - 仿真模型: 直接用 Verilog reg 数组
//     - 综合模型: 用 FPGA/ASIC 厂商的 SRAM IP
//
// 你的任务：
//   Phase 1 & 2: 此文件留空
//   Phase 3: 添加 ICB 总线到 SRAM 时序的转换逻辑
//==============================================================================

`include "defines.v"

module rvcpu_sram ();
    // Phase 3 中实现
    // 接口：
    //   - ICB cmd channel (cmd_valid, cmd_ready, cmd_addr, cmd_read, cmd_wdata, cmd_wmask)
    //   - ICB rsp channel (rsp_valid, rsp_ready, rsp_rdata, rsp_err)
    //   - SRAM 物理接口 (cs, we, addr, wem, din, dout)
endmodule
