`timescale 1ns/1ps

//==============================================================================
// 通用弹性流水寄存器
//
// valid/ready 规则与 E203 功能单元接口一致：
//   - i_valid && i_ready：接收一拍新数据；
//   - o_valid && o_ready：下游消费当前数据；
//   - flush：分支跳转或异常时丢弃本级数据；
//   - 下游阻塞时保持 payload 和 valid 不变。
//
// 当前多周期核由 sequencer 保证每级不会阻塞；未来改成真正五级流水时，
// 可直接用本模块替换顶层的阶段寄存器，并接入 hazard/flush 控制。
//==============================================================================
module rvcpu_pipeline_reg #(
    parameter WIDTH = 1
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             flush,
    input  wire             i_valid,
    output wire             i_ready,
    input  wire [WIDTH-1:0] i_payload,
    output reg              o_valid,
    input  wire             o_ready,
    output reg  [WIDTH-1:0] o_payload
);
    // 本级为空，或当前数据本拍会被下游取走时，可以接收新数据。
    assign i_ready = (~o_valid) | o_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o_valid   <= 1'b0;
            o_payload <= {WIDTH{1'b0}};
        end else if (flush) begin
            o_valid <= 1'b0;
        end else if (i_ready) begin
            o_valid <= i_valid;
            if (i_valid)
                o_payload <= i_payload;
        end
    end
endmodule
