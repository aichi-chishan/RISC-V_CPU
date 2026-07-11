`include "./defines.v"

// 五级流水冒险控制单元（当前多周期模式暂不例化）
//
// 检测 RAW（先读后写）冲突，生成前推选择信号和 Load-Use 暂停信号。
// 优先从距离最近的 EX/MEM 前推（fwd_rs1_sel=01），其次从 MEM/WB 前推（=10）。
// Load 的数据到 MEM 末尾才有效，因此紧随 Load 的消费者必须暂停一个周期（load_use_stall）。
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

    // Load-Use 暂停：EX 阶段正在执行 Load，且 ID 需要其结果
    assign load_use_stall = ex_is_load && (ex_hits_rs1 || ex_hits_rs2);

    // 前推选择：00=无前推（取寄存器堆），01=从 EX/MEM 前推，10=从 MEM/WB 前推
    // 注意：Load 结果不能从 EX/MEM 前推（数据还没到），必须暂停等待 MEM/WB
    always @(*) begin
        fwd_rs1_sel = 2'b00;
        fwd_rs2_sel = 2'b00;
        if (ex_hits_rs1 && !ex_is_load) fwd_rs1_sel = 2'b01;   // EX/MEM 前推
        else if (mem_hits_rs1)          fwd_rs1_sel = 2'b10;   // MEM/WB 前推
        if (ex_hits_rs2 && !ex_is_load) fwd_rs2_sel = 2'b01;
        else if (mem_hits_rs2)          fwd_rs2_sel = 2'b10;
    end
endmodule
