`include "./defines.v"

//==============================================================================
// 五级流水冒险控制单元（当前多周期模式暂不例化）
//
// 优先从距离最近的 EX/MEM 前推，其次从 MEM/WB 前推。Load 的数据要到
// MEM 末尾才有效，因此紧随 Load 的消费者必须暂停一个周期。
// 后续启用 RVC_CFG_PIPELINE_5STAGE 时，可把输出直接接到 EX 的前推 MUX，
// 并用 load_use_stall 冻结 PC、IF/ID，同时向 ID/EX 注入 bubble。
//==============================================================================
module rvcpu_hazard_unit (
    input  wire       id_rs1_en,
    input  wire       id_rs2_en,
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       ex_rd_we,
    input  wire       ex_is_load,
    input  wire [4:0] ex_rd,
    input  wire       mem_rd_we,
    input  wire [4:0] mem_rd,
    output reg  [1:0] fwd_rs1_sel,
    output reg  [1:0] fwd_rs2_sel,
    output wire       load_use_stall
);
    wire ex_hits_rs1  = id_rs1_en && ex_rd_we  && (ex_rd  != 0) && (ex_rd  == id_rs1);
    wire ex_hits_rs2  = id_rs2_en && ex_rd_we  && (ex_rd  != 0) && (ex_rd  == id_rs2);
    wire mem_hits_rs1 = id_rs1_en && mem_rd_we && (mem_rd != 0) && (mem_rd == id_rs1);
    wire mem_hits_rs2 = id_rs2_en && mem_rd_we && (mem_rd != 0) && (mem_rd == id_rs2);

    assign load_use_stall = ex_is_load && (ex_hits_rs1 || ex_hits_rs2);

    always @(*) begin
        fwd_rs1_sel = 2'b00;
        fwd_rs2_sel = 2'b00;
        if (ex_hits_rs1 && !ex_is_load) fwd_rs1_sel = 2'b01;
        else if (mem_hits_rs1)          fwd_rs1_sel = 2'b10;
        if (ex_hits_rs2 && !ex_is_load) fwd_rs2_sel = 2'b01;
        else if (mem_hits_rs2)          fwd_rs2_sel = 2'b10;
    end
endmodule
