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
    output wire [31:0] debug_pc,
    output wire [2:0]  debug_stage,
    output wire        debug_wb_we,
    output wire [4:0]  debug_wb_rd,
    output wire [31:0] debug_wb_data
);
    wire [`RVC_STAGE_WIDTH-1:0] cycle_cnt;
    wire [31:0] pc;

    wire [`RVC_IMEM_AW-1:0] imem_addr = pc[`RVC_IMEM_AW+1:2];
    wire [31:0] imem_rdata;
    wire [31:0] if_ir = imem_rdata;
    wire [31:0] if_pc = pc;

    reg [31:0] if_id_ir, if_id_pc;
    wire [`RVC_DECINFO_WIDTH-1:0] id_dec_info;
    wire [31:0] id_rs1, id_rs2, id_imm, id_pc, id_ir;
    reg [`RVC_DECINFO_WIDTH-1:0] id_ex_dec_info;
    reg [31:0] id_ex_rs1, id_ex_rs2, id_ex_imm, id_ex_pc, id_ex_ir;

    wire ex_branch_taken;
    wire [31:0] ex_branch_target;
    wire [`RVC_DECINFO_WIDTH-1:0] ex_dec_info;
    wire [31:0] ex_alu_result, ex_store_data, ex_pc, ex_ir;
    reg [`RVC_DECINFO_WIDTH-1:0] ex_mem_dec_info;
    reg [31:0] ex_mem_alu_result, ex_mem_store_data, ex_mem_pc, ex_mem_ir;

    wire [`RVC_DMEM_AW-1:0] dmem_addr;
    wire [31:0] dmem_wdata, dmem_rdata;
    wire [3:0] dmem_wmask;
    wire dmem_wen;
    wire [`RVC_DECINFO_WIDTH-1:0] mem_dec_info;
    wire [31:0] mem_alu_result, mem_mem_result, mem_pc, mem_ir;
    reg [`RVC_DECINFO_WIDTH-1:0] mem_wb_dec_info;
    reg [31:0] mem_wb_alu_result, mem_wb_mem_result, mem_wb_pc;

    wire wb_we_raw;
    wire wb_we = wb_we_raw && (cycle_cnt == `RVC_STAGE_WB);
    wire [`RVC_RFIDX_WIDTH-1:0] wb_wa;
    wire [31:0] wb_wd;

    // 这些信号可直接连接 Vivado ILA；不会参与核心控制，也不影响时序功能。
    assign debug_pc      = pc;
    assign debug_stage   = cycle_cnt;
    assign debug_wb_we   = wb_we;
    assign debug_wb_rd   = wb_wa;
    assign debug_wb_data = wb_wd;

    rvcpu_sequencer u_sequencer(
        .clk(clk), .rst_n(rst_n), .ex_branch_taken(ex_branch_taken),
        .ex_branch_target(ex_branch_target), .cycle_cnt(cycle_cnt), .pc(pc));

    // 阶段数据寄存器：现在由节拍使能；未来可换成 valid/ready 弹性寄存器。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_ir<=`RVC_NOP_INSTR; if_id_pc<=0;
            id_ex_dec_info<=0; id_ex_rs1<=0; id_ex_rs2<=0; id_ex_imm<=0; id_ex_pc<=0; id_ex_ir<=`RVC_NOP_INSTR;
            ex_mem_dec_info<=0; ex_mem_alu_result<=0; ex_mem_store_data<=0; ex_mem_pc<=0; ex_mem_ir<=`RVC_NOP_INSTR;
            mem_wb_dec_info<=0; mem_wb_alu_result<=0; mem_wb_mem_result<=0; mem_wb_pc<=0;
        end else begin
            if (cycle_cnt==`RVC_STAGE_IF) begin if_id_ir<=if_ir; if_id_pc<=if_pc; end
            if (cycle_cnt==`RVC_STAGE_ID) begin
                id_ex_dec_info<=id_dec_info; id_ex_rs1<=id_rs1; id_ex_rs2<=id_rs2;
                id_ex_imm<=id_imm; id_ex_pc<=id_pc; id_ex_ir<=id_ir;
            end
            if (cycle_cnt==`RVC_STAGE_EX) begin
                ex_mem_dec_info<=ex_dec_info; ex_mem_alu_result<=ex_alu_result;
                ex_mem_store_data<=ex_store_data; ex_mem_pc<=ex_pc; ex_mem_ir<=ex_ir;
            end
            if (cycle_cnt==`RVC_STAGE_MEM) begin
                mem_wb_dec_info<=mem_dec_info; mem_wb_alu_result<=mem_alu_result;
                mem_wb_mem_result<=mem_mem_result; mem_wb_pc<=mem_pc;
            end
        end
    end

    rvcpu_id_stage u_id_stage(.clk(clk),.rst_n(rst_n),.i_valid(1'b1),.i_ready(),
        .i_ir(if_id_ir),.i_pc(if_id_pc),.wb_we(wb_we),.wb_wa(wb_wa),.wb_wd(wb_wd),
        .o_valid(),.o_ready(1'b1),.o_dec_info(id_dec_info),.o_rs1(id_rs1),.o_rs2(id_rs2),
        .o_imm(id_imm),.o_pc(id_pc),.o_ir(id_ir));

    rvcpu_ex_stage u_ex_stage(.i_valid(1'b1),.i_ready(),.i_dec_info(id_ex_dec_info),
        .i_rs1(id_ex_rs1),.i_rs2(id_ex_rs2),.i_imm(id_ex_imm),.i_pc(id_ex_pc),.i_ir(id_ex_ir),
        .o_pc_sel(),.o_pc_next(),.o_branch_taken(ex_branch_taken),.o_branch_target(ex_branch_target),
        .fwd_mem_result(32'b0),.fwd_wb_result(32'b0),
        .fwd_rs1_sel(2'b00),.fwd_rs2_sel(2'b00),
        .o_valid(),.o_ready(1'b1),.o_dec_info(ex_dec_info),.o_alu_result(ex_alu_result),
        .o_store_data(ex_store_data),.o_pc(ex_pc),.o_ir(ex_ir));

    rvcpu_mem_stage u_mem_stage(.clk(clk),.rst_n(rst_n),
        .i_valid(cycle_cnt==`RVC_STAGE_MEM),.i_ready(),.i_dec_info(ex_mem_dec_info),
        .i_alu_result(ex_mem_alu_result),.i_store_data(ex_mem_store_data),.i_pc(ex_mem_pc),.i_ir(ex_mem_ir),
        .dmem_addr(dmem_addr),.dmem_wdata(dmem_wdata),.dmem_wmask(dmem_wmask),.dmem_wen(dmem_wen),
        .dmem_rdata(dmem_rdata),.o_valid(),.o_ready(1'b1),.o_dec_info(mem_dec_info),
        .o_alu_result(mem_alu_result),.o_mem_result(mem_mem_result),.o_pc(mem_pc),.o_ir(mem_ir));

    rvcpu_wb_stage u_wb_stage(.i_valid(1'b1),.i_ready(),.i_dec_info(mem_wb_dec_info),
        .i_alu_result(mem_wb_alu_result),.i_mem_result(mem_wb_mem_result),.i_pc(mem_wb_pc),
        .wb_we(wb_we_raw),.wb_wa(wb_wa),.wb_wd(wb_wd));

    rvcpu_imem #(.INIT_FILE(IMEM_INIT_FILE)) u_imem(.addr(imem_addr),.rdata(imem_rdata));
    rvcpu_dmem u_dmem(.clk(clk),.addr(dmem_addr),.wdata(dmem_wdata),
        .wmask(dmem_wmask),.wen(dmem_wen),.rdata(dmem_rdata));
endmodule
