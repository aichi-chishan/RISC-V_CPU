`include "./defines.v"

//==============================================================================
// RV32I 五级流水处理器顶层
//
// 流水级为 IF、ID、EX、MEM、WB，每一级均带 valid 位。分支采用简单、可综合
// 且容易验证的 BTFNT 静态预测：条件分支的立即数为负（后向）时预测跳转，
// 为正（前向）时预测不跳转；JAL 在 IF 级直接预测跳转，JALR 因目标依赖
// 寄存器值而预测不跳转，在 EX 级统一比较“预测下一 PC”和“实际下一 PC”。
//
// 控制优先级严格规定为：复位 > 预测失败冲刷 > Load-Use 停顿 > 正常流动。
// 这种写法避免多个控制源同时修改流水寄存器，也是工程中常用的可审计风格。
//==============================================================================
module rvcpu_core (
    input  wire        clk,
    input  wire        rst_n,
    // IFU 只读命令/响应通道，地址采用统一的 32 位字节地址。
    output wire        ifu_cmd_valid,
    input  wire        ifu_cmd_ready,
    output wire [31:0] ifu_cmd_addr,
    input  wire        ifu_rsp_valid,
    output wire        ifu_rsp_ready,
    input  wire [31:0] ifu_rsp_rdata,
    input  wire        ifu_rsp_err,
    // LSU 命令携带读写方向、写掩码和写数据，响应与命令相互解耦。
    output wire        lsu_cmd_valid,
    input  wire        lsu_cmd_ready,
    output wire        lsu_cmd_read,
    output wire [31:0] lsu_cmd_addr,
    output wire [31:0] lsu_cmd_wdata,
    output wire [3:0]  lsu_cmd_wmask,
    input  wire        lsu_rsp_valid,
    output wire        lsu_rsp_ready,
    input  wire [31:0] lsu_rsp_rdata,
    input  wire        lsu_rsp_err,
    output wire [31:0] debug_pc,
    output wire [2:0]  debug_stage,
    output wire        debug_wb_we,
    output wire [4:0]  debug_wb_rd,
    output wire [31:0] debug_wb_data,
    output wire        periph_led_we,
    output wire [31:0] periph_led_wdata
);
    // -------------------------------------------------------------------------
    // IF：组合读指令存储器，并用指令低成本预译码产生静态预测结果。
    // -------------------------------------------------------------------------
    reg  [31:0] pc;
    wire [31:0] if_instr = ifu_rsp_rdata;
    wire [6:0] if_opcode = if_instr[6:0];
    wire if_is_branch = (if_opcode == 7'b1100011);
    wire if_is_jal    = (if_opcode == 7'b1101111);
    wire [31:0] if_b_imm = {{19{if_instr[31]}}, if_instr[31], if_instr[7],
                             if_instr[30:25], if_instr[11:8], 1'b0};
    wire [31:0] if_j_imm = {{11{if_instr[31]}}, if_instr[31], if_instr[19:12],
                             if_instr[20], if_instr[30:21], 1'b0};
    wire if_pred_taken = if_is_jal || (if_is_branch && if_instr[31]);
    wire [31:0] if_pred_target = pc + (if_is_jal ? if_j_imm : if_b_imm);
    wire [31:0] if_pred_next = if_pred_taken ? if_pred_target : (pc + 32'd4);

    // IF/ID 流水寄存器同时保存预测元数据。执行级必须拿同一条指令当时的预测
    // 进行核对，不能用当前 IF 级的组合预测值，否则连续分支时会错配。
    reg if_id_valid;
    reg [31:0] if_id_ir, if_id_pc;
    reg if_id_pred_taken;
    reg [31:0] if_id_pred_target;

    // -------------------------------------------------------------------------
    // ID：完整 RV32I 译码、寄存器堆读取。
    // -------------------------------------------------------------------------
    wire [`RVC_DECINFO_WIDTH-1:0] id_dec_info;
    wire [31:0] id_rs1, id_rs2;
    wire [4:0] id_rs1_idx = id_dec_info[`RVC_DECINFO_RS1IDX];
    wire [4:0] id_rs2_idx = id_dec_info[`RVC_DECINFO_RS2IDX];
    wire id_rs1_en = id_dec_info[`RVC_DECINFO_RS1EN];
    wire id_rs2_en = id_dec_info[`RVC_DECINFO_RS2EN];

    reg id_ex_valid;
    reg [`RVC_DECINFO_WIDTH-1:0] id_ex_dec_info;
    reg [31:0] id_ex_rs1, id_ex_rs2;
    reg id_ex_pred_taken;
    reg [31:0] id_ex_pred_target;

    // -------------------------------------------------------------------------
    // EX：ALU、条件比较、跳转解析和数据前推。
    // -------------------------------------------------------------------------
    wire [4:0] ex_rs1_idx = id_ex_dec_info[`RVC_DECINFO_RS1IDX];
    wire [4:0] ex_rs2_idx = id_ex_dec_info[`RVC_DECINFO_RS2IDX];
    wire ex_rs1_en = id_ex_dec_info[`RVC_DECINFO_RS1EN];
    wire ex_rs2_en = id_ex_dec_info[`RVC_DECINFO_RS2EN];
    wire [4:0] ex_rd_idx = id_ex_dec_info[`RVC_DECINFO_RDIDX];
    wire ex_rd_we = id_ex_valid && id_ex_dec_info[`RVC_DECINFO_RDWEN];
    wire ex_is_load = id_ex_valid &&
                      (id_ex_dec_info[`RVC_DECINFO_GRP] == `RVC_DECINFO_GRP_LSU) &&
                      id_ex_dec_info[`RVC_DECINFO_LSU_LOAD];

    wire ex_branch_taken;
    wire [31:0] ex_branch_target;
    wire [`RVC_DECINFO_WIDTH-1:0] ex_dec_info;
    wire [31:0] ex_alu_result, ex_store_data;
    wire [1:0] fwd_rs1_sel, fwd_rs2_sel;

    reg ex_mem_valid;
    reg [`RVC_DECINFO_WIDTH-1:0] ex_mem_dec_info;
    reg [31:0] ex_mem_alu_result, ex_mem_store_data;

    wire [4:0] mem_rd_idx = ex_mem_dec_info[`RVC_DECINFO_RDIDX];
    wire mem_rd_we = ex_mem_valid && ex_mem_dec_info[`RVC_DECINFO_RDWEN];
    wire mem_is_load = ex_mem_valid &&
                       (ex_mem_dec_info[`RVC_DECINFO_GRP] == `RVC_DECINFO_GRP_LSU) &&
                       ex_mem_dec_info[`RVC_DECINFO_LSU_LOAD];
    wire [31:0] mem_forward_value =
        (ex_mem_dec_info[`RVC_DECINFO_WB_SEL] == `RVC_WB_SEL_PC4) ?
        (ex_mem_dec_info[`RVC_DECINFO_PC] + 32'd4) : ex_mem_alu_result;

    // 实际下一 PC 与预测下一 PC 不同才冲刷。这样既覆盖分支方向预测错误，
    // 也覆盖目标错误，并自然支持 JALR 的执行级重定向。
    wire [31:0] ex_pc = id_ex_dec_info[`RVC_DECINFO_PC];
    wire [31:0] ex_actual_next = ex_branch_taken ? ex_branch_target : (ex_pc + 32'd4);
    wire [31:0] ex_pred_next = id_ex_pred_taken ? id_ex_pred_target : (ex_pc + 32'd4);
    wire ex_mispredict = id_ex_valid && (ex_actual_next != ex_pred_next);

    // -------------------------------------------------------------------------
    // MEM/WB：数据存储器访问与最终写回。
    // -------------------------------------------------------------------------
    wire [`RVC_DMEM_AW-1:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [31:0] dmem_rdata = lsu_rsp_rdata;
    wire [3:0] dmem_wmask;
    wire dmem_wen;
    wire led_sel = (ex_mem_alu_result == `RVC_LED_ADDR);
    wire mem_is_lsu = ex_mem_dec_info[`RVC_DECINFO_GRP] == `RVC_DECINFO_GRP_LSU;
    wire mem_is_store = mem_is_lsu && ex_mem_dec_info[`RVC_DECINFO_LSU_STORE];
    wire [`RVC_DECINFO_WIDTH-1:0] mem_dec_info;
    wire [31:0] mem_alu_result, mem_mem_result;

    reg mem_wb_valid;
    reg [`RVC_DECINFO_WIDTH-1:0] mem_wb_dec_info;
    reg [31:0] mem_wb_alu_result, mem_wb_mem_result;
    wire wb_we;
    wire [4:0] wb_wa;
    wire [31:0] wb_wd;

    // ID 检测紧随 Load 的消费者；仅需停一拍。下一拍 Load 已到 MEM，消费者
    // 随后进入 EX 时可从 MEM/WB 前推已经扩展完成的读取结果。
    wire load_use_stall = if_id_valid && ex_is_load && (ex_rd_idx != 5'd0) &&
        ((id_rs1_en && (id_rs1_idx == ex_rd_idx)) ||
         (id_rs2_en && (id_rs2_idx == ex_rd_idx)));

    // 这些计数器仅用于仿真和板上 ILA 观察，不参与功能控制。保留稳定名字，
    // 方便测试平台用层次路径确认预测器和冒险单元确实被覆盖。
    reg [31:0] branch_predict_count;
    reg [31:0] branch_mispredict_count;
    reg [31:0] load_stall_count;

    // -------------------------------------------------------------------------
    // 流水状态更新。EX 指令在预测失败时仍正常进入 EX/MEM；只杀死比它年轻的
    // IF/ID 与 ID/EX 指令，因此已完成的旧指令和当前控制转移都不会丢失。
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'b0;
            if_id_valid <= 1'b0; id_ex_valid <= 1'b0;
            ex_mem_valid <= 1'b0; mem_wb_valid <= 1'b0;
            if_id_ir <= `RVC_NOP_INSTR; if_id_pc <= 32'b0;
            if_id_pred_taken <= 1'b0; if_id_pred_target <= 32'b0;
            id_ex_dec_info <= {`RVC_DECINFO_WIDTH{1'b0}};
            id_ex_rs1 <= 32'b0; id_ex_rs2 <= 32'b0;
            id_ex_pred_taken <= 1'b0; id_ex_pred_target <= 32'b0;
            ex_mem_dec_info <= {`RVC_DECINFO_WIDTH{1'b0}};
            ex_mem_alu_result <= 32'b0; ex_mem_store_data <= 32'b0;
            mem_wb_dec_info <= {`RVC_DECINFO_WIDTH{1'b0}};
            mem_wb_alu_result <= 32'b0; mem_wb_mem_result <= 32'b0;
            branch_predict_count <= 32'b0;
            branch_mispredict_count <= 32'b0;
            load_stall_count <= 32'b0;
        end else begin
            // 较老阶段始终前进，不应被年轻指令的停顿或冲刷阻塞。
            mem_wb_valid <= ex_mem_valid;
            mem_wb_dec_info <= mem_dec_info;
            mem_wb_alu_result <= mem_alu_result;
            mem_wb_mem_result <= mem_mem_result;
            ex_mem_valid <= id_ex_valid;
            ex_mem_dec_info <= ex_dec_info;
            ex_mem_alu_result <= ex_alu_result;
            ex_mem_store_data <= ex_store_data;

            if (if_is_branch || if_is_jal)
                branch_predict_count <= branch_predict_count + 32'd1;
            if (ex_mispredict)
                branch_mispredict_count <= branch_mispredict_count + 32'd1;
            if (load_use_stall && !ex_mispredict)
                load_stall_count <= load_stall_count + 32'd1;

            if (ex_mispredict) begin
                pc <= ex_actual_next;
                if_id_valid <= 1'b0;
                id_ex_valid <= 1'b0;
            end else if (load_use_stall) begin
                // 保持 PC 与 IF/ID，向 ID/EX 插入气泡，让 Load 继续前进。
                pc <= pc;
                if_id_valid <= if_id_valid;
                id_ex_valid <= 1'b0;
            end else begin
                pc <= if_pred_next;
                if_id_valid <= 1'b1;
                if_id_ir <= if_instr;
                if_id_pc <= pc;
                if_id_pred_taken <= if_pred_taken;
                if_id_pred_target <= if_pred_target;
                id_ex_valid <= if_id_valid;
                id_ex_dec_info <= id_dec_info;
                id_ex_rs1 <= id_rs1;
                id_ex_rs2 <= id_rs2;
                id_ex_pred_taken <= if_id_pred_taken;
                id_ex_pred_target <= if_id_pred_target;
            end
        end
    end

    // 前推单元面向 EX 级消费者。EX/MEM 中的 Load 尚无数据，不能前推；
    // 其余结果优先从最近的 EX/MEM 获取，再退到 MEM/WB。
    rvcpu_hazard_unit u_hazard_unit(
        .id_rs1_en(ex_rs1_en), .id_rs2_en(ex_rs2_en),
        .id_rs1(ex_rs1_idx), .id_rs2(ex_rs2_idx),
        .ex_rd_we(mem_rd_we), .ex_is_load(mem_is_load), .ex_rd(mem_rd_idx),
        .mem_rd_we(wb_we), .mem_rd(wb_wa),
        .fwd_rs1_sel(fwd_rs1_sel), .fwd_rs2_sel(fwd_rs2_sel),
        .load_use_stall());

    rvcpu_id_stage u_id_stage(
        .clk(clk), .rst_n(rst_n), .i_valid(if_id_valid), .i_ready(),
        .i_ir(if_id_ir), .i_pc(if_id_pc),
        .wb_we(wb_we), .wb_wa(wb_wa), .wb_wd(wb_wd),
        .o_valid(), .o_ready(1'b1), .o_dec_info(id_dec_info),
        .o_rs1(id_rs1), .o_rs2(id_rs2));

    rvcpu_ex_stage u_ex_stage(
        .i_valid(id_ex_valid), .i_ready(), .i_dec_info(id_ex_dec_info),
        .i_rs1(id_ex_rs1), .i_rs2(id_ex_rs2),
        .o_pc_sel(), .o_pc_next(), .o_branch_taken(ex_branch_taken),
        .o_branch_target(ex_branch_target),
        .fwd_mem_result(mem_forward_value), .fwd_wb_result(wb_wd),
        .fwd_rs1_sel(fwd_rs1_sel), .fwd_rs2_sel(fwd_rs2_sel),
        .o_valid(), .o_ready(1'b1), .o_dec_info(ex_dec_info),
        .o_alu_result(ex_alu_result), .o_store_data(ex_store_data));

    rvcpu_mem_stage u_mem_stage(
        .i_valid(ex_mem_valid), .i_ready(), .i_dec_info(ex_mem_dec_info),
        .i_alu_result(ex_mem_alu_result), .i_store_data(ex_mem_store_data),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_wmask(dmem_wmask), .dmem_wen(dmem_wen), .dmem_rdata(dmem_rdata),
        .o_valid(), .o_ready(1'b1), .o_dec_info(mem_dec_info),
        .o_alu_result(mem_alu_result), .o_mem_result(mem_mem_result));

    rvcpu_wb_stage u_wb_stage(
        .i_valid(mem_wb_valid), .i_ready(), .i_dec_info(mem_wb_dec_info),
        .i_alu_result(mem_wb_alu_result), .i_mem_result(mem_wb_mem_result),
        .wb_we(wb_we), .wb_wa(wb_wa), .wb_wd(wb_wd));

    // 本阶段先提供零等待 ICB 从设备契约，端口完整保留 valid/ready 和 err。
    // 下一步加入取指队列和 LSU outstanding 状态机时，模块边界无需再次变化。
    assign ifu_cmd_valid = 1'b1;
    assign ifu_cmd_addr  = pc;
    assign ifu_rsp_ready = 1'b1;
    // Store 还必须通过 MEM 级的对齐检查；否则一个未对齐 Store 虽然不会拉高
    // 原 dmem_wen，却可能被接口包装层误认为合法命令并产生总线副作用。
    assign lsu_cmd_valid = ex_mem_valid && mem_is_lsu &&
                           (!mem_is_store || dmem_wen) &&
                           !(mem_is_store && led_sel);
    assign lsu_cmd_read  = !mem_is_store;
    assign lsu_cmd_addr  = ex_mem_alu_result;
    assign lsu_cmd_wdata = dmem_wdata;
    assign lsu_cmd_wmask = dmem_wmask;
    assign lsu_rsp_ready = 1'b1;

    assign debug_pc = pc;
    // 三位分别表示 ID/EX、EX/MEM、MEM/WB 是否有效，比旧多周期阶段号更适合 ILA。
    assign debug_stage = {mem_wb_valid, ex_mem_valid, id_ex_valid};
    assign debug_wb_we = wb_we;
    assign debug_wb_rd = wb_wa;
    assign debug_wb_data = wb_wd;
    assign periph_led_we = dmem_wen && led_sel;
    assign periph_led_wdata = dmem_wdata;
endmodule

//==============================================================================
// 兼容顶层：在 ICB 风格核心外连接零等待片内存储器。
// FPGA 顶层和既有软件无需感知接口重构；以后接 AXI、缓存或总线矩阵时，
// 可直接实例化 rvcpu_core 并替换本包装层，不必修改流水数据通路。
//==============================================================================
module rvcpu_top #(
    parameter IMEM_INIT_FILE = ""
) (
    input wire clk, input wire rst_n,
    output wire [31:0] debug_pc, output wire [2:0] debug_stage,
    output wire debug_wb_we, output wire [4:0] debug_wb_rd,
    output wire [31:0] debug_wb_data,
    output wire periph_led_we, output wire [31:0] periph_led_wdata
);
    wire ifu_cmd_valid, ifu_cmd_ready, ifu_rsp_valid, ifu_rsp_ready;
    wire [31:0] ifu_cmd_addr, ifu_rsp_rdata;
    wire lsu_cmd_valid, lsu_cmd_ready, lsu_cmd_read;
    wire [31:0] lsu_cmd_addr, lsu_cmd_wdata, lsu_rsp_rdata;
    wire [3:0] lsu_cmd_wmask;
    wire lsu_rsp_valid, lsu_rsp_ready;

    // 零等待 ROM：命令握手的同一周期给出响应。只在边界处把字节地址
    // 转换为存储宏所需的字地址，核心内部地址语义保持一致。
    assign ifu_cmd_ready = 1'b1;
    assign ifu_rsp_valid = ifu_cmd_valid && ifu_cmd_ready;
    rvcpu_imem #(.INIT_FILE(IMEM_INIT_FILE)) u_imem(
        .addr(ifu_cmd_addr[`RVC_IMEM_AW+1:2]), .rdata(ifu_rsp_rdata));

    // 写副作用严格发生在 cmd_valid && cmd_ready 的握手周期。
    assign lsu_cmd_ready = 1'b1;
    assign lsu_rsp_valid = lsu_cmd_valid && lsu_cmd_ready;
    rvcpu_dmem u_dmem(
        .clk(clk), .addr(lsu_cmd_addr[`RVC_DMEM_AW+1:2]),
        .wdata(lsu_cmd_wdata), .wmask(lsu_cmd_wmask),
        .wen(lsu_cmd_valid && lsu_cmd_ready && !lsu_cmd_read),
        .rdata(lsu_rsp_rdata));

    rvcpu_core u_core(
        .clk(clk), .rst_n(rst_n),
        .ifu_cmd_valid(ifu_cmd_valid), .ifu_cmd_ready(ifu_cmd_ready),
        .ifu_cmd_addr(ifu_cmd_addr), .ifu_rsp_valid(ifu_rsp_valid),
        .ifu_rsp_ready(ifu_rsp_ready), .ifu_rsp_rdata(ifu_rsp_rdata), .ifu_rsp_err(1'b0),
        .lsu_cmd_valid(lsu_cmd_valid), .lsu_cmd_ready(lsu_cmd_ready),
        .lsu_cmd_read(lsu_cmd_read), .lsu_cmd_addr(lsu_cmd_addr),
        .lsu_cmd_wdata(lsu_cmd_wdata), .lsu_cmd_wmask(lsu_cmd_wmask),
        .lsu_rsp_valid(lsu_rsp_valid), .lsu_rsp_ready(lsu_rsp_ready),
        .lsu_rsp_rdata(lsu_rsp_rdata), .lsu_rsp_err(1'b0),
        .debug_pc(debug_pc), .debug_stage(debug_stage),
        .debug_wb_we(debug_wb_we), .debug_wb_rd(debug_wb_rd),
        .debug_wb_data(debug_wb_data), .periph_led_we(periph_led_we),
        .periph_led_wdata(periph_led_wdata));
endmodule
