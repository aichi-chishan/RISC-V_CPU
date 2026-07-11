//==============================================================================
// RV32M 乘除法执行单元
//
// 乘法使用 FPGA DSP 友好的组合乘积并寄存一拍；除法采用 32 拍 restoring
// 迭代器，不推导面积和关键路径都很差的单周期“/”组合网络。start 只接受一次，
// busy 期间操作数保持在模块内部，done 精确脉冲一拍。
//==============================================================================
module rvcpu_mdu (
    input wire clk, input wire rst_n,
    input wire start, input wire [2:0] op,
    input wire [31:0] a, input wire [31:0] b,
    output reg busy, output reg done, output reg [31:0] result
);
    wire signed [63:0] mul_ss = $signed(a) * $signed(b);
    wire [63:0] mul_uu = a * b;
    wire signed [65:0] mul_su = $signed({a[31],a}) * $signed({1'b0,b});

    reg fast_pending;
    reg [31:0] dividend_mag, divisor_mag, quotient;
    reg [32:0] remainder;
    reg [5:0] div_count;
    reg negate_q, negate_r, want_remainder;
    wire [5:0] div_bit_index = 6'd31-div_count;
    wire [32:0] remainder_shift = {remainder[31:0],dividend_mag[div_bit_index]};
    wire div_subtract = remainder_shift >= {1'b0,divisor_mag};
    wire [32:0] remainder_next = div_subtract ?
        remainder_shift-{1'b0,divisor_mag} : remainder_shift;
    wire [31:0] quotient_next = div_subtract ?
        (quotient | (32'b1 << div_bit_index)) : quotient;
    wire [31:0] signed_quotient = negate_q ? (~quotient_next+1'b1) : quotient_next;
    wire [31:0] unsigned_remainder = remainder_next[31:0];
    wire [31:0] signed_remainder = negate_r ? (~unsigned_remainder+1'b1) : unsigned_remainder;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;result<=0;fast_pending<=0;dividend_mag<=0;divisor_mag<=0;
            quotient<=0;remainder<=0;div_count<=0;negate_q<=0;negate_r<=0;want_remainder<=0;
        end else begin
            done<=1'b0;
            if(start && !busy) begin
                busy<=1'b1;
                if(op[2]==1'b0) begin
                    fast_pending<=1'b1;
                    case(op)
                        3'b000:result<=mul_uu[31:0];
                        3'b001:result<=mul_ss[63:32];
                        3'b010:result<=mul_su[63:32];
                        default:result<=mul_uu[63:32];
                    endcase
                end else if(b==0) begin
                    // 规范规定除零不异常：DIV 商全 1，REM 返回被除数。
                    fast_pending<=1'b1;
                    result<=op[1] ? a : 32'hffff_ffff;
                end else begin
                    fast_pending<=1'b0;
                    dividend_mag<=(!op[0] && a[31]) ? (~a+1'b1) : a;
                    divisor_mag<=(!op[0] && b[31]) ? (~b+1'b1) : b;
                    quotient<=0;remainder<=0;div_count<=0;
                    negate_q<=!op[0] && (a[31]^b[31]);
                    negate_r<=!op[0] && a[31];
                    want_remainder<=op[1];
                end
            end else if(busy) begin
                if(fast_pending) begin
                    busy<=0;done<=1;fast_pending<=0;
                end else begin
                    quotient<=quotient_next;
                    remainder<=remainder_next;
                    if(div_count==31) begin
                        result<=want_remainder ? signed_remainder : signed_quotient;
                        busy<=0;done<=1;
                    end else div_count<=div_count+1'b1;
                end
            end
        end
    end
endmodule
