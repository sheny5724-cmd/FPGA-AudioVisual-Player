module key_controls(input clk,input reset,input [3:0] keys_n,output reg [3:0] pressed,
                    output [3:0] held);
    reg [3:0] k1,k2,stable;
    assign held=~stable;
    reg [16:0] tick;
    reg [4:0] c0,c1,c2,c3;
    always @(posedge clk) begin
        k1<=keys_n;k2<=k1;pressed<=0;
        if(reset) begin stable<=15;tick<=0;c0<=0;c1<=0;c2<=0;c3<=0;k1<=15;k2<=15;end
        else if(tick==49999) begin
            tick<=0;
            if(k2[0]==stable[0])c0<=0;else if(c0==19)begin stable[0]<=k2[0];c0<=0;pressed[0]<=!k2[0];end else c0<=c0+1'b1;
            if(k2[1]==stable[1])c1<=0;else if(c1==19)begin stable[1]<=k2[1];c1<=0;pressed[1]<=!k2[1];end else c1<=c1+1'b1;
            if(k2[2]==stable[2])c2<=0;else if(c2==19)begin stable[2]<=k2[2];c2<=0;pressed[2]<=!k2[2];end else c2<=c2+1'b1;
            if(k2[3]==stable[3])c3<=0;else if(c3==19)begin stable[3]<=k2[3];c3<=0;pressed[3]<=!k2[3];end else c3<=c3+1'b1;
        end else tick<=tick+1'b1;
    end
endmodule
