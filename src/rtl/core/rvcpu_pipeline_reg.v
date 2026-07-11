`timescale 1ns/1ps

// 通用弹性流水寄存器（valid/ready 握手）
//
// valid/ready 规则：
//   - i_valid && i_ready：接收一拍新数据
//   - o_valid && o_ready：下游消费当前数据
//   - flush：分支跳转或异常时丢弃本级数据（o_valid 拉低）
//   - 下游阻塞（o_ready=0）时保持 payload 和 valid 不变
//
// 当前多周期核由 sequencer 保证每级不会阻塞；未来改为五级流水时可直接
// 用本模块替换顶层手写的阶段寄存器。
module rvcpu_pipeline_reg #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             flush,
    input  wire             i_valid,
    output wire             i_ready,
    input  wire [WIDTH-1:0] i_payload,
    output wire             o_valid,
    input  wire             o_ready,
    output wire [WIDTH-1:0] o_payload
);
    // 本级为空，或当前数据本拍会被下游取走时，可以接收新数据。
    assign i_ready = (~o_valid) | o_ready;

    // 使用统一的 DFF 库，明确“复位到 0 + 时钟使能”的时序语义。
    // flush 的优先级高于握手；无有效输入时保留 payload，避免无意义翻转。
    wire load_en = flush | i_ready;
    wire valid_nxt = flush ? 1'b0 : i_valid;
    wire [WIDTH-1:0] payload_nxt = flush ? {WIDTH{1'b0}} :
                                   (i_valid ? i_payload : o_payload);

    rvcpu_dfflr #(.DW(1)) u_valid_dff (
        .clk(clk), .rst_n(rst_n), .lden(load_en), .dnxt(valid_nxt), .qout(o_valid)
    );
    rvcpu_dfflr #(.DW(WIDTH)) u_payload_dff (
        .clk(clk), .rst_n(rst_n), .lden(load_en), .dnxt(payload_nxt), .qout(o_payload)
    );
endmodule
