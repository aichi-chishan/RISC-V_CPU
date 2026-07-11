`include "./defines.v"

//==============================================================================
// RV32I 多周期处理器顶层
//
// 当前模式：每次只允许一条指令活动，sequencer 用 5 个节拍依次使能
// IF/ID/EX/MEM/WB，所以不存在数据冒险，CPI 固定为 5。
//
// 扩展到五级流水时，各 stage 接口和 dec_info 无需推倒重写：
//   1. 用 rvcpu_pipeline_reg 连接四组阶段 payload；
//   2. 在 ID 加入 RAW 检测，在 EX 的预留端口接入 MEM/WB 前推；
//   3. 分支成立时 flush IF/ID、ID/EX；
//   4. 将内部存储器替换为带 valid/ready 的总线或缓存接口。
//==============================================================================
module rvcpu_top #(
    parameter IMEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] debug_pc,       // 调试：当前 PC
    output wire [2:0]  debug_stage,    // 调试：当前节拍序号 (0~4)
    output wire        debug_wb_we,    // 调试：写回使能
    output wire [4:0]  debug_wb_rd,    // 调试：写回目标寄存器
    output wire [31:0] debug_wb_data,  // 调试：写回数据
    output wire        periph_led_we,  // LED 外设写使能
    output wire [31:0] periph_led_wdata// LED 外设写数据
);
    //======== 节拍与 PC（sequencer 驱动全局）========
    wire [`RVC_STAGE_WIDTH-1:0] cycle_cnt;  // 当前节拍：IF/ID/EX/MEM/WB
    wire [31:0] pc;                          // 当前 PC

    //======== 阶段间连线 + 流水寄存器 ========
    // IF 阶段输出：从 IMEM 取指令
    wire [`RVC_IMEM_AW-1:0] imem_addr = pc[`RVC_IMEM_AW+1:2]; // 字节地址→字地址
    wire [31:0] imem_rdata;
    wire [31:0] if_ir = imem_rdata;    // 取到的指令
    wire [31:0] if_pc = pc;            // 当前 PC 值

    // IF/ID 流水寄存器：锁存指令和 PC，供 ID 阶段译码
    reg [31:0] if_id_ir, if_id_pc;

    // ID 阶段输出：译码 + 读寄存器堆
    // dec_info 是唯一的控制载体，其公共字段已包含本条指令的 PC/立即数；
    // ID/EX、EX/MEM、MEM/WB 因此不再平行保存 PC、IMM 或 IR 的副本。
    wire [`RVC_DECINFO_WIDTH-1:0] id_dec_info;  // 译码结果控制总线
    wire [31:0] id_rs1, id_rs2;                  // 从寄存器堆读出的操作数
    // ID/EX 流水寄存器：锁存译码结果和操作数，供 EX 阶段执行
    reg [`RVC_DECINFO_WIDTH-1:0] id_ex_dec_info;
    reg [31:0] id_ex_rs1, id_ex_rs2;

    // EX 阶段输出：ALU 运算 + 分支判定
    wire ex_branch_taken;                        // 分支是否成立
    wire [31:0] ex_branch_target;                // 跳转目标地址
    wire [`RVC_DECINFO_WIDTH-1:0] ex_dec_info;   // 直通的 dec_info
    wire [31:0] ex_alu_result;                   // ALU 计算结果 / 访存地址
    wire [31:0] ex_store_data;                   // Store 要写入 DMEM 的数据
    // EX/MEM 流水寄存器：锁存 ALU 结果和 Store 数据，供 MEM 阶段访存
    reg [`RVC_DECINFO_WIDTH-1:0] ex_mem_dec_info;
    reg [31:0] ex_mem_alu_result, ex_mem_store_data;

    // MEM 阶段输出：数据存储器读写
    wire [`RVC_DMEM_AW-1:0] dmem_addr;           // DMEM 字地址
    wire [31:0] dmem_wdata, dmem_rdata;          // DMEM 写/读数据
    wire [3:0] dmem_wmask;                       // 字节写掩码
    wire dmem_wen;                                // DMEM 写使能
    // 只有完整地址命中 LED 寄存器才访问外设；不能只比较 dmem_addr，
    // 否则 0x4000_0000 会因地址截断而误写 DMEM[0]。
    wire led_sel = (ex_mem_alu_result == `RVC_LED_ADDR);
    wire dmem_wen_to_ram = dmem_wen && !led_sel;
    wire [`RVC_DECINFO_WIDTH-1:0] mem_dec_info;   // 直通的 dec_info
    wire [31:0] mem_alu_result;                   // 直通的 ALU 结果
    wire [31:0] mem_mem_result;                   // DMEM 读出数据（Load 结果）
    // MEM/WB 流水寄存器：锁存写回所需数据，供 WB 阶段写回寄存器堆
    reg [`RVC_DECINFO_WIDTH-1:0] mem_wb_dec_info;
    reg [31:0] mem_wb_alu_result, mem_wb_mem_result;

    // WB 阶段：写回寄存器堆
    wire wb_we_raw;                              // WB 阶段输出的原始写使能
    wire wb_we = wb_we_raw && (cycle_cnt == `RVC_STAGE_WB); // 叠加节拍闸门
    wire [`RVC_RFIDX_WIDTH-1:0] wb_wa;           // 写回目标寄存器地址 (rd)
    wire [31:0] wb_wd;                           // 写回数据

    //======== 调试信号：直连 Vivado ILA，不参与核心控制 ========
    assign debug_pc      = pc;
    assign debug_stage   = cycle_cnt;
    assign debug_wb_we   = wb_we;
    assign debug_wb_rd   = wb_wa;
    assign debug_wb_data = wb_wd;
    assign periph_led_we    = dmem_wen && led_sel;
    assign periph_led_wdata = dmem_wdata;

    //======== 模块例化（共 7 个子模块）========

    // ① 节拍与 PC 控制器
    //  产生 IF/ID/EX/MEM/WB 五节拍序列，在 WB 节拍统一更新 PC
    rvcpu_sequencer u_sequencer(
        .clk(clk), .rst_n(rst_n), .ex_branch_taken(ex_branch_taken),
        .ex_branch_target(ex_branch_target), .mem_ready(1'b1), .cycle_cnt(cycle_cnt), .pc(pc));

    // ② 流水寄存器组
    //   在每个节拍锁存上一阶段的输出到本级；复位时清零并插入 NOP
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_ir<=`RVC_NOP_INSTR; if_id_pc<=0;
            id_ex_dec_info<=0; id_ex_rs1<=0; id_ex_rs2<=0;
            ex_mem_dec_info<=0; ex_mem_alu_result<=0; ex_mem_store_data<=0;
            mem_wb_dec_info<=0; mem_wb_alu_result<=0; mem_wb_mem_result<=0;
        end else begin
            if (cycle_cnt==`RVC_STAGE_IF) begin if_id_ir<=if_ir; if_id_pc<=if_pc; end
            if (cycle_cnt==`RVC_STAGE_ID) begin
                id_ex_dec_info<=id_dec_info; id_ex_rs1<=id_rs1; id_ex_rs2<=id_rs2;
            end
            if (cycle_cnt==`RVC_STAGE_EX) begin
                ex_mem_dec_info<=ex_dec_info; ex_mem_alu_result<=ex_alu_result;
                ex_mem_store_data<=ex_store_data;
            end
            if (cycle_cnt==`RVC_STAGE_MEM) begin
                mem_wb_dec_info<=mem_dec_info; mem_wb_alu_result<=mem_alu_result;
                mem_wb_mem_result<=mem_mem_result;
            end
        end
    end

    // ③ ID 阶段：译码 + 读寄存器堆（含 rvcpu_decode + rvcpu_regfile）
    //   输入：if_id_ir（指令）、if_id_pc（地址）
    //   输出：id_dec_info（控制总线）、id_rs1/id_rs2（操作数）
    //   wb_we/wa/wd 是 WB 阶段回来的写回信号（register file 的写口）
    rvcpu_id_stage u_id_stage(.clk(clk),.rst_n(rst_n),.i_valid(1'b1),.i_ready(),
        .i_ir(if_id_ir),.i_pc(if_id_pc),.wb_we(wb_we),.wb_wa(wb_wa),.wb_wd(wb_wd),
        .o_valid(),.o_ready(1'b1),.o_dec_info(id_dec_info),.o_rs1(id_rs1),.o_rs2(id_rs2));

    // ④ EX 阶段：ALU 运算 + 分支判定
    //   前推端口 (fwd_*) 预留供五级流水使用，多周期模式下全部接地
    rvcpu_ex_stage u_ex_stage(.i_valid(1'b1),.i_ready(),.i_dec_info(id_ex_dec_info),
        .i_rs1(id_ex_rs1),.i_rs2(id_ex_rs2),
        .o_pc_sel(),.o_pc_next(),.o_branch_taken(ex_branch_taken),.o_branch_target(ex_branch_target),
        .fwd_mem_result(32'b0),.fwd_wb_result(32'b0),
        .fwd_rs1_sel(2'b00),.fwd_rs2_sel(2'b00),
        .o_valid(),.o_ready(1'b1),.o_dec_info(ex_dec_info),.o_alu_result(ex_alu_result),
        .o_store_data(ex_store_data));

    // ⑤ MEM 阶段：数据存储器读写
    //   i_valid 只在 MEM 节拍有效，确保 DMEM 不会在其他节拍被误写入
    //   DMEM 的 clk/rst_n 已删除（组合读模块无需时钟）
    rvcpu_mem_stage u_mem_stage(
        .i_valid(cycle_cnt==`RVC_STAGE_MEM),.i_ready(),.i_dec_info(ex_mem_dec_info),
        .i_alu_result(ex_mem_alu_result),.i_store_data(ex_mem_store_data),
        .dmem_addr(dmem_addr),.dmem_wdata(dmem_wdata),.dmem_wmask(dmem_wmask),.dmem_wen(dmem_wen),
        .dmem_rdata(dmem_rdata),.o_valid(),.o_ready(1'b1),.o_dec_info(mem_dec_info),
        .o_alu_result(mem_alu_result),.o_mem_result(mem_mem_result));

    // ⑥ WB 阶段：三选一（ALU 结果 / MEM 读出数据 / PC+4）写回寄存器堆
    rvcpu_wb_stage u_wb_stage(.i_valid(1'b1),.i_ready(),.i_dec_info(mem_wb_dec_info),
        .i_alu_result(mem_wb_alu_result),.i_mem_result(mem_wb_mem_result),
        .wb_we(wb_we_raw),.wb_wa(wb_wa),.wb_wd(wb_wd));

    // ⑦ 存储器：指令存储器（组合读，.hex 文件初始化）+ 数据存储器（组合读、字节掩码写）
    rvcpu_imem #(.INIT_FILE(IMEM_INIT_FILE)) u_imem(.addr(imem_addr),.rdata(imem_rdata));
    rvcpu_dmem u_dmem(.clk(clk),.addr(dmem_addr),.wdata(dmem_wdata),
        .wmask(dmem_wmask),.wen(dmem_wen_to_ram),.rdata(dmem_rdata));
endmodule
