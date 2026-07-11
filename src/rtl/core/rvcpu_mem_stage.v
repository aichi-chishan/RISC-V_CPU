`include "./defines.v"

//==============================================================================
// MEM 阶段：完成 RV32I Load/Store 的字节选通、对齐和数据扩展。
//
// 片内 DMEM 按 32 位字组织，而 CPU 访存地址是字节地址。该模块负责把
// CPU 地址拆为“字地址 + 字内偏移”，并根据 LB/LH/LW/SB/SH/SW 的大小
// 生成正确的读写数据。所有 Load 结果只在本模块的唯一组合块中产生，避免
// 多个 always 块同时驱动同一个寄存器而造成仿真/综合结果不一致。
//==============================================================================
module rvcpu_mem_stage (
    input  wire i_valid,
    output wire i_ready,
    input  wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,
    input  wire [31:0] i_alu_result,
    input  wire [31:0] i_store_data,
    output wire [`RVC_DMEM_AW-1:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg  [3:0]  dmem_wmask,
    output wire dmem_wen,
    input  wire [31:0] dmem_rdata,
    output wire o_valid,
    input  wire o_ready,
    output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,
    output wire [31:0] o_alu_result,
    output reg  [31:0] o_mem_result
);
    // 从统一译码总线中取出 LSU 控制字段。
    wire is_lsu   = (i_dec_info[`RVC_DECINFO_GRP] == `RVC_DECINFO_GRP_LSU);
    wire is_load  = is_lsu && i_dec_info[`RVC_DECINFO_LSU_LOAD];
    wire is_store = is_lsu && i_dec_info[`RVC_DECINFO_LSU_STORE];
    wire [1:0] size = i_dec_info[`RVC_DECINFO_LSU_SIZE]; // 00=B，01=H，10=W
    wire unsign = i_dec_info[`RVC_DECINFO_LSU_USIGN];

    // ALU 输出为字节地址。DMEM 的地址端口只接收字地址。
    wire [1:0] off = i_alu_result[1:0];
    assign dmem_addr = i_alu_result[`RVC_DMEM_AW+1:2];

    // Phase 1 暂无异常提交通路，暂行策略是：非对齐半字/字 Store 不得产生
    // 写副作用；非对齐 Load 返回 0。Phase 3 增加异常后，应在此处产生
    // load/store-address-misaligned trap，并取消异常指令的写回。
    wire access_aligned = (size == 2'b00) ? 1'b1 :
                          (size == 2'b01) ? !off[0] :
                                             (off == 2'b00);

    // Store 写掩码和写数据的对齐。虽然非法/非对齐 Store 最终不会拉高
    // dmem_wen，仍给出确定的组合值，方便波形查看且不会推导锁存器。
    always @(*) begin
        dmem_wmask = 4'b0000;
        dmem_wdata = 32'b0;
        case (size)
            2'b00: begin // SB：把 rs2[7:0] 放入目标字节通道。
                dmem_wmask = 4'b0001 << off;
                dmem_wdata = i_store_data << {off, 3'b000};
            end
            2'b01: begin // SH：合法位置只能是 byte0 或 byte2。
                dmem_wmask = 4'b0011 << {off[1], 1'b0};
                dmem_wdata = i_store_data << {off[1], 4'b0000};
            end
            default: begin // SW：完整覆盖整个 32 位字。
                dmem_wmask = 4'b1111;
                dmem_wdata = i_store_data;
            end
        endcase
    end

    // Load 数据选择与符号/零扩展。o_mem_result 的所有赋值集中在此块，
    // 防止后来增加 Store 逻辑时意外覆盖 Load 的保护结果。
    reg [7:0]  byte_v;
    reg [15:0] half_v;
    always @(*) begin
        if (is_load && !access_aligned) begin
            byte_v       = 8'b0;
            half_v       = 16'b0;
            o_mem_result = 32'b0;
        end else begin
            byte_v = dmem_rdata[{off, 3'b000} +: 8];
            half_v = dmem_rdata[{off[1], 4'b0000} +: 16];
            case (size)
                2'b00: o_mem_result = unsign ? {24'b0, byte_v} : {{24{byte_v[7]}}, byte_v};
                2'b01: o_mem_result = unsign ? {16'b0, half_v} : {{16{half_v[15]}}, half_v};
                default: o_mem_result = dmem_rdata;
            endcase
        end
    end

    // 唯一的 DMEM 写许可。is_store 确保 Load 不会写，access_aligned 确保
    // 奇地址 SH 或非字对齐 SW 不会被静默变形成附近地址的写操作。
    assign dmem_wen    = i_valid && is_store && access_aligned;
    assign i_ready     = o_ready;
    assign o_valid     = i_valid;
    assign o_dec_info  = i_dec_info;
    assign o_alu_result = i_alu_result;
endmodule
