`include "./defines.v"

//==============================================================================
// Machine 模式 CSR、异常与中断状态单元
//
// 设计遵循“单一提交点”：普通 CSR 指令、陷阱进入和 MRET 都只在 EX 边界更新
// 状态，优先级为 trap > mret > CSR。这样不会出现同一周期多个 always 块分别
// 改写 mstatus/mepc 的多驱动问题，也便于以后把提交点后移到独立 Commit 级。
//==============================================================================
module rvcpu_csr_file #(
    parameter RESET_MTVEC = 32'h0000_0100
) (
    input wire clk, input wire rst_n,
    input wire [11:0] csr_addr,
    input wire [1:0] csr_cmd,          // 01=CSRRW，10=CSRRS，11=CSRRC
    input wire csr_write_intent,
    input wire [31:0] csr_wdata,
    output reg [31:0] csr_rdata,
    output reg csr_addr_valid,
    output reg csr_writable,

    input wire trap_enter,
    input wire [31:0] trap_epc,
    input wire [31:0] trap_cause,
    input wire [31:0] trap_tval,
    input wire mret,
    input wire retire,
    input wire irq_software,
    input wire irq_timer,
    input wire irq_external,
    output wire irq_request,
    output wire [31:0] irq_cause,
    output wire [31:0] trap_vector,
    output wire [31:0] mret_pc
);
    reg [31:0] mstatus, mie, mtvec, mscratch, mepc, mcause, mtval;
    reg [63:0] mcycle, minstret;
    wire [31:0] mip = {20'b0, irq_external, 3'b0, irq_timer, 3'b0,
                       irq_software, 3'b0};
    wire [31:0] enabled_pending = mie & mip;

    // Machine external > software > timer。优先级固定且集中编码，避免中断原因
    // 与实际选中的请求源不一致。全局 MIE 清零后所有可屏蔽中断被抑制。
    assign irq_request = mstatus[3] &&
                         (enabled_pending[11] || enabled_pending[3] || enabled_pending[7]);
    assign irq_cause = enabled_pending[11] ? 32'h8000_000b :
                       enabled_pending[3]  ? 32'h8000_0003 : 32'h8000_0007;
    assign trap_vector = {mtvec[31:2], 2'b00}; // 当前只实现 Direct 模式。
    assign mret_pc = {mepc[31:2], 2'b00};

    always @(*) begin
        csr_rdata = 32'b0;
        csr_addr_valid = 1'b1;
        csr_writable = 1'b1;
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h304: csr_rdata = mie;
            12'h305: csr_rdata = mtvec;
            12'h340: csr_rdata = mscratch;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'h343: csr_rdata = mtval;
            12'h344: begin csr_rdata = mip; csr_writable = 1'b0; end
            12'hb00: csr_rdata = mcycle[31:0];
            12'hb80: csr_rdata = mcycle[63:32];
            12'hb02: csr_rdata = minstret[31:0];
            12'hb82: csr_rdata = minstret[63:32];
            12'hf11: begin csr_rdata = 32'b0; csr_writable = 1'b0; end // mvendorid
            12'hf12: begin csr_rdata = 32'b0; csr_writable = 1'b0; end // marchid
            12'hf13: begin csr_rdata = 32'b0; csr_writable = 1'b0; end // mimpid
            12'hf14: begin csr_rdata = 32'b0; csr_writable = 1'b0; end // mhartid
            default: begin csr_addr_valid = 1'b0; csr_writable = 1'b0; end
        endcase
    end

    reg [31:0] csr_new_value;
    always @(*) begin
        case (csr_cmd)
            2'b01: csr_new_value = csr_wdata;
            2'b10: csr_new_value = csr_rdata | csr_wdata;
            default: csr_new_value = csr_rdata & ~csr_wdata;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 仅实现 M-mode：MPP 固定初始化为 M，MIE/MPIE 初始关闭。
            mstatus <= 32'h0000_1800;
            mie <= 32'b0; mtvec <= RESET_MTVEC; mscratch <= 32'b0;
            mepc <= 32'b0; mcause <= 32'b0; mtval <= 32'b0;
            mcycle <= 64'b0; minstret <= 64'b0;
        end else begin
            mcycle <= mcycle + 64'd1;
            if (retire) minstret <= minstret + 64'd1;

            if (trap_enter) begin
                mepc <= {trap_epc[31:2], 2'b00};
                mcause <= trap_cause;
                mtval <= trap_tval;
                mstatus[7] <= mstatus[3]; // MPIE 保存进入陷阱前的 MIE。
                mstatus[3] <= 1'b0;
                mstatus[12:11] <= 2'b11;
            end else if (mret) begin
                mstatus[3] <= mstatus[7];
                mstatus[7] <= 1'b1;
                mstatus[12:11] <= 2'b11;
            end else if (csr_write_intent && csr_addr_valid && csr_writable) begin
                case (csr_addr)
                    // WARL 掩码：只实现真正存在的状态位，保留位读回为零。
                    12'h300: begin
                        mstatus[3] <= csr_new_value[3];
                        mstatus[7] <= csr_new_value[7];
                        mstatus[12:11] <= 2'b11;
                    end
                    12'h304: begin
                        mie[3] <= csr_new_value[3];
                        mie[7] <= csr_new_value[7];
                        mie[11] <= csr_new_value[11];
                    end
                    12'h305: mtvec <= {csr_new_value[31:2], 2'b00};
                    12'h340: mscratch <= csr_new_value;
                    12'h341: mepc <= {csr_new_value[31:2], 2'b00};
                    12'h342: mcause <= csr_new_value;
                    12'h343: mtval <= csr_new_value;
                    12'hb00: mcycle[31:0] <= csr_new_value;
                    12'hb80: mcycle[63:32] <= csr_new_value;
                    12'hb02: minstret[31:0] <= csr_new_value;
                    12'hb82: minstret[63:32] <= csr_new_value;
                    default: begin end
                endcase
            end
        end
    end
endmodule
