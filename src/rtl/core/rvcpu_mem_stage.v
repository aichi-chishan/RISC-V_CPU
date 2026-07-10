//==============================================================================
// Designer   : [your name]
//
// Description:
//   rvcpu_mem_stage.v — MEM 阶段 (Memory Access)
//
//   这是五级流水的第四级。在 Phase 1 (单周期) 中:
//     - 数据存储器 (DMEM) 访问 — 组合读 + 时序写
//     - Load 数据对齐 + 符号扩展 — 纯组合逻辑
//     - Store 字节写掩码生成 — 纯组合逻辑
//     - 所有逻辑用 valid/ready 握手与上下游通信
//
//   到 Phase 2 (五级流水):
//     在 EX/MEM 和 MEM/WB 之间插入流水寄存器即可。
//     DMEM 仍然可以是组合读 (但五级流水中通常改用同步 BRAM,
//     此时 Load 指令需要额外处理延迟)。
//
// E203 参考:
//   e203_lsu.v + e203_lsu_ctrl.v — E203 的 LSU 模块,
//   除了基本的内存读写外还包括:
//     - ICB 总线接口 (与 BIU 通信)
//     - 地址空间译码 (ITCM / DTCM / PPI / CLINT / PLIC / MEM)
//     - AMO (原子操作)
//     - 非对齐访问处理
//   Phase 1 你只做基本读写 + ICB 预留接口。
//
// 你的任务 (Phase 1):
//   Step 1: 实现地址转换 (字节地址 → DMEM 字地址)
//   Step 2: 实现 Store 字节写掩码生成 (wmask)
//   Step 3: 实现 Store 数据对齐 (wdata 放到正确的字节位置)
//   Step 4: 实现 Load 数据提取 (从 32 位 DMEM 输出中取 byte/half/word)
//   Step 5: 实现 Load 符号/无符号扩展
//   Step 6: 打包输出给 WB 阶段
//
// 思考题:
//   Q1: 为什么 DMEM 读用组合逻辑, 写用时序逻辑?
//       答: 和寄存器堆同样的道理 — 单周期中同一时钟沿完成写操作,
//           而组合读可以同周期得到数据, 让 Load 指令在一个周期内完成。
//   Q2: 如果 Load 和 Store 在同一周期访问 DMEM 的同一地址,
//       Load 会读到什么? 为什么这在单周期 CPU 中不是问题?
//       答: Store 的写发生在时钟沿, Load 的组合读发生在时钟沿之前,
//           所以 Load 读到的是旧值。单周期中一条指令要么 Load 要么 Store,
//           不可能同时, 所以这不是问题。
//==============================================================================

`include "defines.v"

module rvcpu_mem_stage (
    //==========================================================================
    // TODO: 定义以下端口
    //==========================================================================

    // --- 时钟与复位 ---
    // input  wire        clk,
    // input  wire        rst_n,

    // --- 来自 EX 阶段 ---
    // input  wire                      i_valid,
    // output wire                      i_ready,
    // input  wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,  — 译码信息 (提取 LSU 字段)
    // input  wire [`RVC_XLEN-1:0]      i_alu_result, — ALU 结果 = 访存地址
    // input  wire [`RVC_XLEN-1:0]      i_store_data, — Store 数据 (rs2)
    // input  wire [`RVC_PC_WIDTH-1:0]  i_pc,
    // input  wire [31:0]               i_ir,

    // --- DMEM 接口 ---
    // output wire [`RVC_DMEM_AW-1:0]   dmem_addr,   — DMEM 字地址
    // output wire [31:0]               dmem_wdata,  — 写数据
    // output wire [3:0]                dmem_wmask,  — 字节写掩码
    // output wire                      dmem_wen,    — 写使能
    // input  wire [31:0]               dmem_rdata,  — 读数据

    // --- 输出到 WB 阶段 ---
    // output wire                      o_valid,
    // input  wire                      o_ready,
    // output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,  — 译码信息 (透传)
    // output wire [`RVC_XLEN-1:0]      o_mem_result, — Load 读回的数据 (已对齐+扩展)
    // output wire [`RVC_XLEN-1:0]      o_alu_result, — ALU 结果 (透传, 给非Load指令用)
    // output wire [`RVC_PC_WIDTH-1:0]  o_pc,
    // output wire [31:0]               o_ir
);


    //==========================================================================
    // 一、提取译码信息 (LSU 专用字段)
    //==========================================================================
    // TODO: 从 i_dec_info 中提取 LSU 子字段
    //
    // 提示:
    //   wire        lsu_load  = i_dec_info[`RVC_DECINFO_LSU_LOAD];
    //   wire        lsu_store = i_dec_info[`RVC_DECINFO_LSU_STORE];
    //   wire [1:0]  lsu_size  = i_dec_info[`RVC_DECINFO_LSU_SIZE];   // 00:b, 01:h, 10:w
    //   wire        lsu_usign = i_dec_info[`RVC_DECINFO_LSU_USIGN];  // 1: 无符号
    //
    //   wire [1:0] addr_low = i_alu_result[1:0];   // 地址最低 2 位


    //==========================================================================
    // 二、地址转换 — 字节地址 → DMEM 字地址
    //==========================================================================
    // TODO: 实现地址转换
    //
    // 提示:
    //   assign dmem_addr = i_alu_result[`RVC_DMEM_AW+1 : 2];
    //
    // 字节地址: i_alu_result[31:0], 最低 2 位表示字节偏移
    // DMEM 是 32 位宽: 每个地址存 4 字节 → 字地址 = 字节地址 / 4
    //
    // 例如: i_alu_result = 32'h0000_0108 → 字地址 = 0x42
    //       验证: 0x108 / 4 = 0x42 ✓


    //==========================================================================
    // 三、Store 字节写掩码生成
    //==========================================================================
    // TODO: 根据 lsu_size 和 addr_low 生成 wmask
    //
    // 提示 (E203 风格 — 分开生成候选值, 再 MUX):
    //
    //   // 字节掩码候选 (SB): 写 1 字节
    //   wire [3:0] wmask_byte;
    //   assign wmask_byte = (addr_low == 2'b00) ? 4'b0001 :
    //                       (addr_low == 2'b01) ? 4'b0010 :
    //                       (addr_low == 2'b10) ? 4'b0100 :
    //                       (addr_low == 2'b11) ? 4'b1000 : 4'b0000;
    //
    //   // 半字掩码候选 (SH): 写 2 字节, 必须 2 字节对齐
    //   wire [3:0] wmask_half = (addr_low[1] == 1'b0) ? 4'b0011 : 4'b1100;
    //
    //   // 字掩码候选 (SW): 写 4 字节
    //   wire [3:0] wmask_word = 4'b1111;
    //
    //   // 根据 size 选择
    //   assign dmem_wmask = (lsu_size == 2'b00) ? wmask_byte :
    //                       (lsu_size == 2'b01) ? wmask_half : wmask_word;
    //
    // 注意: 非对齐的 half/word 访问 (如 addr_low=01 时 SH) 在 RV32I 中
    //       会产生异常, Phase 1 中暂时不检测, Phase 4 加入。


    //==========================================================================
    // 四、Store 数据对齐
    //==========================================================================
    // TODO: 将 Store 数据放到正确的字节位置
    //
    // 提示:
    //   // 简单做法: 用移位把数据放到目标字节位置
    //   assign dmem_wdata = i_store_data << (8 * addr_low);
    //
    // 例如: SB 写 0xAB 到地址 0x1001
    //       i_store_data[7:0] = 8'hAB
    //       addr_low = 01
    //       dmem_wdata[15:8] = 8'hAB  ← 移位 8*1 = 8 位
    //
    // 对于 SW: addr_low=00, 不移位, dmem_wdata = i_store_data
    //
    // 思考: 上面的做法对 SB 和 SH 都适用吗?
    //       对 SB: i_store_data 的低 8 位写入目标字节位置 ✓
    //       对 SH: i_store_data 的低 16 位写入目标半字位置 ✓
    //       对 SW: i_store_data 的 32 位写入 (addr_low 必须是 00)


    //==========================================================================
    // 五、Load 数据提取 — 从 32 位 DMEM 输出中取需要的部分
    //==========================================================================
    // TODO: 根据 lsu_size 和 addr_low 提取数据
    //
    // 提示:
    //   // 提取字节 (LB/LBU)
    //   wire [7:0] load_byte;
    //   always @(*) begin
    //       case (addr_low)
    //           2'b00: load_byte = dmem_rdata[7:0];
    //           2'b01: load_byte = dmem_rdata[15:8];
    //           2'b10: load_byte = dmem_rdata[23:16];
    //           2'b11: load_byte = dmem_rdata[31:24];
    //           default: load_byte = dmem_rdata[7:0];
    //       endcase
    //   end
    //
    //   // 提取半字 (LH/LHU)
    //   wire [15:0] load_half;
    //   assign load_half = (addr_low[1] == 1'b0) ?
    //                      dmem_rdata[15:0] : dmem_rdata[31:16];
    //
    //   // 提取字 (LW)
    //   wire [31:0] load_word = dmem_rdata;


    //==========================================================================
    // 六、Load 符号/无符号扩展
    //==========================================================================
    // TODO: 根据 lsu_usign 选择扩展方式
    //
    // 提示:
    //   // 字节扩展
    //   wire [31:0] load_byte_sext = {{24{load_byte[7]}}, load_byte};
    //   wire [31:0] load_byte_uext = {24'b0, load_byte};
    //
    //   // 半字扩展
    //   wire [31:0] load_half_sext = {{16{load_half[15]}}, load_half};
    //   wire [31:0] load_half_uext = {16'b0, load_half};
    //
    //   // 最终选择 (E203 风格 — 先根据 size 选中间值, 再根据 usign 选扩展)
    //   wire [31:0] load_data_pre;
    //   always @(*) begin
    //       case (lsu_size)
    //           2'b00: load_data_pre = lsu_usign ? load_byte_uext : load_byte_sext;
    //           2'b01: load_data_pre = lsu_usign ? load_half_uext : load_half_sext;
    //           2'b10: load_data_pre = load_word;  // 字不需要扩展
    //           default: load_data_pre = 32'b0;
    //       endcase
    //   end


    //==========================================================================
    // 七、DMEM 写使能
    //==========================================================================
    // TODO: 生成 DMEM 写使能信号
    //
    // 提示:
    //   assign dmem_wen = i_valid & lsu_store;   — 只有 Store 指令才写 DMEM


    //==========================================================================
    // 八、输出到 WB 阶段
    //==========================================================================
    // TODO: 打包输出
    //
    // 提示:
    //   assign o_valid      = i_valid;          — Phase 1 直通
    //   assign i_ready      = o_ready;          — Phase 1 直通
    //   assign o_dec_info   = i_dec_info;       — 译码信息透传 (WB用rdwen/rdidx)
    //   assign o_alu_result = i_alu_result;     — ALU 结果透传
    //   assign o_mem_result = load_data_pre;    — Load 数据 (已对齐+扩展)
    //   assign o_pc         = i_pc;
    //   assign o_ir         = i_ir;
    //
    // 思考: 为什么要把 ALU 结果和 MEM 结果都传给 WB?
    //       答: 非 Load 指令 (ADD, ADDI, LUI...) 写回 ALU 结果,
    //           Load 指令 (LB, LH, LW...) 写回 MEM 结果。
    //           WB 阶段根据 dec_info 中的 WB_SEL 字段决定选哪个。

endmodule
