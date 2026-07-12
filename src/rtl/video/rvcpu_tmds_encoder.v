// DVI/HDMI TMDS 8b/10b 编码器：活动区控制直流平衡，消隐区输出四种控制码。
module rvcpu_tmds_encoder(
    input wire clk,input wire rst,
    input wire [7:0] data,input wire c0,input wire c1,input wire de,
    output reg [9:0] symbol
);
    integer i;reg[3:0]ones_data;reg[8:0]qm;reg[3:0]ones_qm;
    reg signed[5:0]disparity;reg signed[5:0]balance;
    always @(*)begin
        ones_data=data[0]+data[1]+data[2]+data[3]+data[4]+data[5]+data[6]+data[7];
        qm[0]=data[0];
        if((ones_data>4)||((ones_data==4)&&!data[0]))begin
            for(i=1;i<8;i=i+1)qm[i]=~(qm[i-1]^data[i]);qm[8]=0;
        end else begin
            for(i=1;i<8;i=i+1)qm[i]=qm[i-1]^data[i];qm[8]=1;
        end
        ones_qm=qm[0]+qm[1]+qm[2]+qm[3]+qm[4]+qm[5]+qm[6]+qm[7];
        balance=$signed({1'b0,ones_qm,1'b0})-6'sd8;
    end
    always @(posedge clk or posedge rst)begin
        if(rst)begin symbol<=0;disparity<=0;end
        else if(!de)begin
            case({c1,c0})
                2'b00:symbol<=10'b1101010100;2'b01:symbol<=10'b0010101011;
                2'b10:symbol<=10'b0101010100;default:symbol<=10'b1010101011;
            endcase disparity<=0;
        end else if((disparity==0)||(ones_qm==4))begin
            symbol<={~qm[8],qm[8],qm[8]?qm[7:0]:~qm[7:0]};
            disparity<=qm[8]?balance:-balance;
        end else if((!disparity[5]&&balance>0)||(disparity[5]&&balance<0))begin
            symbol<={1'b1,qm[8],~qm[7:0]};
            disparity<=disparity-balance+(qm[8]?6'sd2:0);
        end else begin
            symbol<={1'b0,qm[8],qm[7:0]};
            disparity<=disparity+balance-(qm[8]?0:6'sd2);
        end
    end
endmodule
