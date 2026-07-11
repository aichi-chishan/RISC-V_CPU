`include "./defines.v"

// 多周期五节拍控制器
//
// 产生 IF(0)→ID(1)→EX(2)→MEM(3)→WB(4) 五拍序列，循环往复。
// EX 节拍锁存分支判定结果，WB 节拍统一更新 PC：
//  - 分支跳转 → PC = branch_target
//  - 顺序执行 → PC = PC + 4
//
// 保证一条指令完整提交后才开始下一条，所以当前不存在数据冒险。
// 未来启用五级流水后，本模块将由 valid/ready 和 flush 网络取代。
module rvcpu_sequencer (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    ex_branch_taken,      // EX 送来的分支是否成立
    input  wire [`RVC_PC_WIDTH-1:0] ex_branch_target,    // EX 算出的跳转目标地址
    input  wire                    mem_ready,             // 外部总线响应完成；片内 RAM 时恒为 1
    output reg  [`RVC_STAGE_WIDTH-1:0] cycle_cnt,         // 当前节拍序号 0~4
    output reg  [`RVC_PC_WIDTH-1:0] pc                    // 当前 PC
);
    // EX 节拍锁存的分支信息（下一拍 EX 结果可能被覆盖，所以暂存起来）
    reg branch_taken_r;
    reg [`RVC_PC_WIDTH-1:0] branch_target_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt      <= `RVC_STAGE_IF;      // 复位后从 IF 开始
            pc             <= `RVC_RESET_PC;      // PC 回到 0
            branch_taken_r <= 1'b0;
            branch_target_r<= 32'b0;
        end else if ((cycle_cnt == `RVC_STAGE_MEM) && !mem_ready) begin
            // 保持在 MEM，直到单未完成事务桥收到响应。PC 与其它节拍状态均冻结。
            cycle_cnt <= cycle_cnt;
        end else begin
            // EX 节拍：锁存分支判决结果（此时 ex_branch_taken/target 已稳定）
            if (cycle_cnt == `RVC_STAGE_EX) begin
                branch_taken_r  <= ex_branch_taken;
                branch_target_r <= ex_branch_target;
            end
            // WB 节拍：指令提交完成，更新 PC
            if (cycle_cnt == `RVC_STAGE_WB) begin
                pc <= branch_taken_r ? branch_target_r : (pc + 32'd4);
                cycle_cnt <= `RVC_STAGE_IF;       // 回到 IF，开始下一条
                branch_taken_r <= 1'b0;
            end else begin
                cycle_cnt <= cycle_cnt + 1'b1;    // 前进到下一节拍
            end
        end
    end
endmodule
