`include "./defines.v"

//==============================================================================
// MEM 阶段：生成 Store 字节掩码，完成 Load 数据抽取和符号扩展。
// 地址在 EX 已算好；这里把字节地址拆成“字地址 + 字内偏移”。未来接同步
// BRAM 时，可用 valid/ready 将 o_valid 延后一拍，无需修改译码格式。
//==============================================================================
module rvcpu_mem_stage (
    input wire i_valid, output wire i_ready,
    input wire [`RVC_DECINFO_WIDTH-1:0] i_dec_info,
    input wire [31:0] i_alu_result,        // EX 算出的访存地址（字节地址）
    input wire [31:0] i_store_data,        // 要写入 Store 的数据（来自 rs2）
    output wire [`RVC_DMEM_AW-1:0] dmem_addr,  // DMEM 字地址
    output reg [31:0] dmem_wdata,          // 写入 DMEM 的数据（字节对齐后）
    output reg [3:0] dmem_wmask,           // 字节写掩码（逐 bit 对应一个字节：bit0=byte0...）
    output wire dmem_wen,                  // DMEM 写使能
    input wire [31:0] dmem_rdata,          // 从 DMEM 读出的原始 32 位数据
    output wire o_valid, input wire o_ready,
    output wire [`RVC_DECINFO_WIDTH-1:0] o_dec_info,
    output wire [31:0] o_alu_result,
    output reg [31:0] o_mem_result         // Load 的结果（已抽取和符号/零扩展）
);
    //-------- 提取 dec_info 中的 LSU 控制字段 --------
    wire is_lsu  = i_dec_info[`RVC_DECINFO_GRP] == `RVC_DECINFO_GRP_LSU;
    wire is_store= is_lsu && i_dec_info[`RVC_DECINFO_LSU_STORE];
    wire [1:0] size   = i_dec_info[`RVC_DECINFO_LSU_SIZE];        // 字长：00=byte,01=half,10=word
    wire unsign = i_dec_info[`RVC_DECINFO_LSU_USIGN];             // 无符号扩展：仅 Load 有效

    //-------- 字节地址拆字 --------
    // ALU 算出的 i_alu_result 是字节地址（如 0x1003）
    // DMEM 按 32 位字编址：dmem_addr = 字节地址 >> 2
    // off = 字节地址低 2 位，指示目标字节在字内的偏移（0~3）
    wire [1:0] off = i_alu_result[1:0];

    assign dmem_addr = i_alu_result[`RVC_DMEM_AW+1:2];  // 字节地址 → 字地址

    //-------- Store：字节掩码生成 + 写数据对齐 --------
    // DMEM 总是按 32 位读写，通过 wmask 控制哪些字节真正写入
    // 例：SB rs2, 1(rs1) → off=1, 只写 byte1, wmask=0010
    //     SH rs2, 2(rs1) → off=2, 写 half 在 byte2~3, wmask=1100
    //     SW rs2, 0(rs1) → 写全部 4 字节, wmask=1111
    reg [7:0] byte_v; reg [15:0] half_v;
    always @(*) begin
        dmem_wmask = 4'b0;
        dmem_wdata = 32'b0;
        case (size)
            // SB：只写 1 个字节，wmask 左移 off 位到对应字节位置
            2'b00: begin dmem_wmask=4'b0001 << off;   dmem_wdata=i_store_data << {off, 3'b000}; end
            // SH：写 2 个字节（半字），wmask 左移 off[1]*2 位
            // off[1] 指示半字偏移：0=低半字(word0~1), 1=高半字(word2~3)
            2'b01: begin dmem_wmask=4'b0011 << {off[1],1'b0}; dmem_wdata=i_store_data << {off[1], 4'b0000}; end
            // SW：写满 4 字节
            default: begin dmem_wmask=4'b1111; dmem_wdata=i_store_data; end
        endcase
    end

    //-------- Load：从读出数据中抽取目标字节/半字 + 符号/零扩展 --------
    always @(*) begin
        // 从 dmem_rdata 的 32 位中，用部分位选抽取目标字节/半字
        byte_v = dmem_rdata[{off, 3'b000} +: 8];        // 从 off*8 位置取 8 位
        half_v = dmem_rdata[{off[1], 4'b0000} +: 16];  // 从 off[1]*16 位置取 16 位

        case (size)
            // LB / LBU：抽取 1 字节
            //   unsign=1（LBU）→ 零扩展：高 24 位补 0
            //   unsign=0（LB） → 符号扩展：高 24 位按 byte[7] 复制
            2'b00: o_mem_result = unsign ? {24'b0, byte_v}    : {{24{byte_v[7]}}, byte_v};
            // LH / LHU：抽取 2 字节
            2'b01: o_mem_result = unsign ? {16'b0, half_v}    : {{16{half_v[15]}}, half_v};
            // LW：32 位直接输出
            default: o_mem_result = dmem_rdata;
        endcase
    end

    //-------- 控制输出 --------
    assign dmem_wen = i_valid && is_store;   // 仅在 MEM 节拍且是 Store 指令时写 DMEM
    assign i_ready=o_ready; assign o_valid=i_valid; assign o_dec_info=i_dec_info;
    assign o_alu_result=i_alu_result;
endmodule
