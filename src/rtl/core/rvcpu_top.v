//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_top.v — 单周期 CPU 顶层模块
//
//   这是一个 **单周期** RV32I 处理器，但按五级流水的阶段来组织模块。
//   在 Phase 1 (单周期) 中:
//     - 5 个阶段模块直接连线, 阶段间是纯组合逻辑通路
//     - valid/ready 握手信号均为直通 (i_valid→o_valid, o_ready→i_ready)
//     - IF: PC寄存器 (时序) + IMEM 读 (组合)
//     - ID: 译码 (组合) + 寄存器堆读 (组合)
//     - EX: ALU (组合) + 分支判定 (组合)
//     - MEM: DMEM 读写 (组合读 + 时序写)
//     - WB: 写回数据选择 (组合)
//
//   到 Phase 2 (五级流水):
//     只需在阶段间插入 IF/ID, ID/EX, EX/MEM, MEM/WB 流水寄存器,
//     加上 forwarding 和 hazard detection 逻辑。
//     各阶段模块本身的代码几乎不需要修改。
//
// 顶层架构:
//
//                    ┌──── 单周期控制通路 ──────┐
//                    │  pc_sel/pc_next 从 EX 回传给 IF │
//                    │                                │
//   ┌─────┐   ┌─────┐   ┌─────┐   ┌──────┐   ┌─────┐ │
//   │ IF  │──▶│ ID  │──▶│ EX  │──▶│ MEM  │──▶│ WB  │─┤
//   │Stage│   │Stage│   │Stage│   │Stage │   │Stage│ │
//   └──┬──┘   └──┬──┘   └──┬──┘   └──┬───┘   └──┬──┘ │
//      │         │         │         │          │     │
//      │         │◀────────│─────────│──────────│─────┘ wb_we/wa/wd 回 ID
//      │         │         │         │          │
//   ┌──▼──┐      │         │    ┌────▼───┐      │
//   │IMEM │      │         │    │ DMEM   │      │
//   └─────┘      │         │    └────────┘      │
//           ┌────▼────┐    │                    │
//           │ RegFile │◀───│────────────────────┘
//           └─────────┘
//
// E203 参考:
//   e203_cpu_top.v — 顶层例化了 CPU Core + SRAMs
//   e203_cpu.v     — CPU 层例化了 reset_ctrl + clk_ctrl + irq_sync + e203_core
//   e203_core.v    — Core 层例化了 IFU + EXU + LSU + BIU
//
// 我们把它简化为: rvcpu_top → 直接例化 5 个阶段 + 存储器
//
// 你的任务:
//   Step 1: 定义所有阶段间的互联 wire 信号
//   Step 2: 例化 5 个阶段模块并连接
//   Step 3: 例化 IMEM 和 DMEM
//   Step 4: 连接 PC 控制回传 (EX → IF)
//   Step 5: 连接写回通路 (WB → ID → RegFile)
//
// 思考题:
//   Q: Phase 1 中 EX 阶段的 pc_sel/pc_next 回传给 IF 是组合逻辑路径,
//      从 ID 读寄存器到 EX 算完分支判定, 再回传到 IF, 最后 IF 输出下一个 PC。
//      这条组合逻辑路径很长, 这会带来什么问题?
//       答: 这是单周期 CPU 的主要瓶颈 — 最长的组合逻辑路径决定了
//           时钟周期的最小值。五级流水通过插入寄存器来拆分这条路径,
//           每次只需完成一小段, 从而可以跑更高的频率。
//==============================================================================

`include "defines.v"

module rvcpu_top (
    //==========================================================================
    // TODO: 定义以下端口
    //==========================================================================

    // --- 时钟与复位 ---
    // input  wire        clk,
    // input  wire        rst_n

    // Phase 3 扩展: 总线接口
    // Phase 4 扩展: 中断输入
);


    //==========================================================================
    // 一、IF ↔ ID 阶段互联信号
    //==========================================================================
    // TODO: 定义 IF 阶段到 ID 阶段的信号
    //
    // 提示:
    //   wire                      if_valid;
    //   wire                      if_ready;
    //   wire [31:0]               if_ir;
    //   wire [`RVC_PC_WIDTH-1:0]  if_pc;


    //==========================================================================
    // 二、ID ↔ EX 阶段互联信号
    //==========================================================================
    // TODO: 定义 ID 阶段到 EX 阶段的信号
    //
    // 提示:
    //   wire                      id_valid;
    //   wire                      id_ready;
    //   wire [`RVC_DECINFO_WIDTH-1:0] id_dec_info;
    //   wire [`RVC_XLEN-1:0]      id_rs1;
    //   wire [`RVC_XLEN-1:0]      id_rs2;
    //   wire [`RVC_XLEN-1:0]      id_imm;
    //   wire [`RVC_PC_WIDTH-1:0]  id_pc;
    //   wire [31:0]               id_ir;


    //==========================================================================
    // 三、EX ↔ MEM 阶段互联信号
    //==========================================================================
    // TODO: 定义 EX 阶段到 MEM 阶段的信号
    //
    // 提示:
    //   wire                      ex_valid;
    //   wire                      ex_ready;
    //   wire [`RVC_DECINFO_WIDTH-1:0] ex_dec_info;
    //   wire [`RVC_XLEN-1:0]      ex_alu_result;
    //   wire [`RVC_XLEN-1:0]      ex_store_data;
    //   wire [`RVC_PC_WIDTH-1:0]  ex_pc;
    //   wire [31:0]               ex_ir;


    //==========================================================================
    // 四、MEM ↔ WB 阶段互联信号
    //==========================================================================
    // TODO: 定义 MEM 阶段到 WB 阶段的信号
    //
    // 提示:
    //   wire                      mem_valid;
    //   wire                      mem_ready;
    //   wire [`RVC_DECINFO_WIDTH-1:0] mem_dec_info;
    //   wire [`RVC_XLEN-1:0]      mem_alu_result;
    //   wire [`RVC_XLEN-1:0]      mem_mem_result;
    //   wire [`RVC_PC_WIDTH-1:0]  mem_pc;
    //   wire [31:0]               mem_ir;


    //==========================================================================
    // 五、写回到 ID 阶段的信号 (WB → RegFile)
    //==========================================================================
    // TODO: 定义 WB 阶段到 ID 阶段寄存器堆写端口的信号
    //
    // 提示:
    //   wire                      wb_we;
    //   wire [`RVC_RFIDX_WIDTH-1:0] wb_wa;
    //   wire [`RVC_XLEN-1:0]      wb_wd;


    //==========================================================================
    // 六、PC 控制信号 (EX → IF)
    //==========================================================================
    // TODO: 定义 EX 阶段回传给 IF 阶段的 PC 控制信号
    //
    // 提示:
    //   wire                      pc_sel;
    //   wire [`RVC_PC_WIDTH-1:0]  pc_next;


    //==========================================================================
    // 七、存储器接口信号 (IMEM, DMEM)
    //==========================================================================
    // TODO: 定义 IMEM 和 DMEM 的互联信号
    //
    // 提示:
    //   wire [`RVC_IMEM_AW-1:0]  imem_addr;
    //   wire [31:0]              imem_rdata;
    //   wire [`RVC_DMEM_AW-1:0]  dmem_addr;
    //   wire [31:0]              dmem_wdata;
    //   wire [3:0]               dmem_wmask;
    //   wire                     dmem_wen;
    //   wire [31:0]              dmem_rdata;


    //==========================================================================
    // 八、例化 IF 阶段
    //==========================================================================
    // TODO: 例化 rvcpu_if_stage
    //
    // rvcpu_if_stage u_if_stage (
    //     .clk          (clk),
    //     .rst_n        (rst_n),
    //     // IMEM 接口
    //     .imem_addr    (imem_addr),
    //     .imem_rdata   (imem_rdata),
    //     // PC 控制 (来自 EX)
    //     .ctrl_pc_sel  (pc_sel),
    //     .ctrl_pc_next (pc_next),
    //     .stall        (1'b0),         — Phase 1 不阻塞
    //     // 输出到 ID
    //     .o_valid      (if_valid),
    //     .o_ready      (if_ready),
    //     .o_ir         (if_ir),
    //     .o_pc         (if_pc)
    // );


    //==========================================================================
    // 九、例化 ID 阶段
    //==========================================================================
    // TODO: 例化 rvcpu_id_stage
    //
    // rvcpu_id_stage u_id_stage (
    //     .clk      (clk),
    //     .rst_n    (rst_n),
    //     // 来自 IF
    //     .i_valid  (if_valid),
    //     .i_ready  (if_ready),
    //     .i_ir     (if_ir),
    //     .i_pc     (if_pc),
    //     // 来自 WB 的写回
    //     .wb_we    (wb_we),
    //     .wb_wa    (wb_wa),
    //     .wb_wd    (wb_wd),
    //     // 输出到 EX
    //     .o_valid  (id_valid),
    //     .o_ready  (id_ready),
    //     .o_dec_info(id_dec_info),
    //     .o_rs1    (id_rs1),
    //     .o_rs2    (id_rs2),
    //     .o_imm    (id_imm),
    //     .o_pc     (id_pc),
    //     .o_ir     (id_ir)
    // );


    //==========================================================================
    // 十、例化 EX 阶段
    //==========================================================================
    // TODO: 例化 rvcpu_ex_stage
    //
    // rvcpu_ex_stage u_ex_stage (
    //     .clk          (clk),
    //     .rst_n        (rst_n),
    //     // 来自 ID
    //     .i_valid      (id_valid),
    //     .i_ready      (id_ready),
    //     .i_dec_info   (id_dec_info),
    //     .i_rs1        (id_rs1),
    //     .i_rs2        (id_rs2),
    //     .i_imm        (id_imm),
    //     .i_pc         (id_pc),
    //     .i_ir         (id_ir),
    //     // PC 控制 (回传给 IF)
    //     .o_pc_sel     (pc_sel),
    //     .o_pc_next    (pc_next),
    //     // Phase 2: 前推输入
    //     .fwd_mem_result(32'b0),
    //     .fwd_mem_valid (1'b0),
    //     .fwd_wb_result (32'b0),
    //     .fwd_wb_valid  (1'b0),
    //     // 输出到 MEM
    //     .o_valid      (ex_valid),
    //     .o_ready      (ex_ready),
    //     .o_dec_info   (ex_dec_info),
    //     .o_alu_result (ex_alu_result),
    //     .o_store_data (ex_store_data),
    //     .o_pc         (ex_pc),
    //     .o_ir         (ex_ir)
    // );


    //==========================================================================
    // 十一、例化 MEM 阶段
    //==========================================================================
    // TODO: 例化 rvcpu_mem_stage
    //
    // rvcpu_mem_stage u_mem_stage (
    //     .clk          (clk),
    //     .rst_n        (rst_n),
    //     // 来自 EX
    //     .i_valid      (ex_valid),
    //     .i_ready      (ex_ready),
    //     .i_dec_info   (ex_dec_info),
    //     .i_alu_result (ex_alu_result),
    //     .i_store_data (ex_store_data),
    //     .i_pc         (ex_pc),
    //     .i_ir         (ex_ir),
    //     // DMEM 接口
    //     .dmem_addr    (dmem_addr),
    //     .dmem_wdata   (dmem_wdata),
    //     .dmem_wmask   (dmem_wmask),
    //     .dmem_wen     (dmem_wen),
    //     .dmem_rdata   (dmem_rdata),
    //     // 输出到 WB
    //     .o_valid      (mem_valid),
    //     .o_ready      (mem_ready),
    //     .o_dec_info   (mem_dec_info),
    //     .o_alu_result (mem_alu_result),
    //     .o_mem_result (mem_mem_result),
    //     .o_pc         (mem_pc),
    //     .o_ir         (mem_ir)
    // );


    //==========================================================================
    // 十二、例化 WB 阶段
    //==========================================================================
    // TODO: 例化 rvcpu_wb_stage
    //
    // rvcpu_wb_stage u_wb_stage (
    //     // 来自 MEM
    //     .i_valid      (mem_valid),
    //     .i_ready      (mem_ready),
    //     .i_dec_info   (mem_dec_info),
    //     .i_alu_result (mem_alu_result),
    //     .i_mem_result (mem_mem_result),
    //     .i_pc         (mem_pc),
    //     // 写回寄存器堆
    //     .wb_we        (wb_we),
    //     .wb_wa        (wb_wa),
    //     .wb_wd        (wb_wd)
    // );


    //==========================================================================
    // 十三、例化 IMEM 和 DMEM
    //==========================================================================
    // TODO: 例化存储器
    //
    // rvcpu_imem u_imem (
    //     .addr  (imem_addr),
    //     .rdata (imem_rdata)
    // );
    //
    // rvcpu_dmem u_dmem (
    //     .clk   (clk),
    //     .addr  (dmem_addr),
    //     .wdata (dmem_wdata),
    //     .wmask (dmem_wmask),
    //     .wen   (dmem_wen),
    //     .rdata (dmem_rdata)
    // );

endmodule
