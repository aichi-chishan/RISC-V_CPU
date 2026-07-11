`include "./defines.v"

//==============================================================================
// 多周期五节拍控制器
// EX 保存控制转移结果，WB 完成后统一更新 PC，保证一条指令完整提交后才
// 开始下一条。未来五级流水启用后，本模块将由各级 valid/ready 和 flush
// 网络取代，PC 更新信号仍可复用 EX 的 branch_taken/target。
//==============================================================================
module rvcpu_sequencer (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    ex_branch_taken,
    input  wire [`RVC_PC_WIDTH-1:0] ex_branch_target,
    output reg  [`RVC_STAGE_WIDTH-1:0] cycle_cnt,
    output reg  [`RVC_PC_WIDTH-1:0] pc
);
    reg branch_taken_r;
    reg [`RVC_PC_WIDTH-1:0] branch_target_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_cnt      <= `RVC_STAGE_IF;
            pc             <= `RVC_RESET_PC;
            branch_taken_r <= 1'b0;
            branch_target_r<= 32'b0;
        end else begin
            if (cycle_cnt == `RVC_STAGE_EX) begin
                branch_taken_r  <= ex_branch_taken;
                branch_target_r <= ex_branch_target;
            end
            if (cycle_cnt == `RVC_STAGE_WB) begin
                pc <= branch_taken_r ? branch_target_r : (pc + 32'd4);
                cycle_cnt <= `RVC_STAGE_IF;
                branch_taken_r <= 1'b0;
            end else begin
                cycle_cnt <= cycle_cnt + 1'b1;
            end
        end
    end
endmodule
