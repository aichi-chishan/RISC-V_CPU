`timescale 1ns/1ps

//==============================================================================
// rvcpu_dff.v：通用 D 触发器库
//
// 参考 E203 的 sirv_gnrl_dffs.v，将时序基本单元统一成四类常用形式：
//   1. dffl   ：带时钟使能、无复位（只用于复位后无需定义值的数据路径）
//   2. dffr   ：异步低有效复位、每拍更新
//   3. dfflr  ：异步低有效复位 + 时钟使能，复位值为全 0
//   4. dfflrs ：异步低有效复位 + 时钟使能，复位值为全 1
//
// 禁止在本文件加入 #delay；这样 RTL 行为与综合后的 FPGA/ASIC 一致。
//==============================================================================

// 带时钟使能、无复位的 DFF
module rvcpu_dffl #(
    parameter DW = 1
) (
    input wire clk,
    input wire lden,
    input wire [DW-1:0] dnxt,
    output reg [DW-1:0] qout
);
    always @(posedge clk) begin
        if (lden)
            qout <= dnxt;
    end
endmodule

// 每拍更新、异步低有效复位到全 0 的 DFF
module rvcpu_dffr #(
    parameter DW = 1
) (
    input wire clk,
    input wire rst_n,
    input wire [DW-1:0] dnxt,
    output reg [DW-1:0] qout
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            qout <= {DW{1'b0}};
        else
            qout <= dnxt;
    end
endmodule

// 带时钟使能、异步低有效复位到全 0 的 DFF：控制状态与流水寄存器默认使用该型。
module rvcpu_dfflr #(
    parameter DW = 1
) (
    input wire clk,
    input wire rst_n,
    input wire lden,
    input wire [DW-1:0] dnxt,
    output reg [DW-1:0] qout
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            qout <= {DW{1'b0}};
        else if (lden)
            qout <= dnxt;
    end
endmodule

// 带时钟使能、异步低有效复位到全 1 的 DFF：适合 active-low 掩码等极性信号。
module rvcpu_dfflrs #(
    parameter DW = 1
) (
    input wire clk,
    input wire rst_n,
    input wire lden,
    input wire [DW-1:0] dnxt,
    output reg [DW-1:0] qout
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            qout <= {DW{1'b1}};
        else if (lden)
            qout <= dnxt;
    end
endmodule
