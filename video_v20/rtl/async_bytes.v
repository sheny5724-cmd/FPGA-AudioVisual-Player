// Dual-clock FIFO. Gray pointers cross domains; RAM uses synchronous read.
module async_bytes(input wc,input wrst,input we,input [7:0] wd,
                   output full,output reg overflow,
                   input rc,input rrst,input re,output reg [7:0] rd,
                   output empty,output almost_full);
    reg [7:0] mem[0:1023];
    reg [10:0] wp,wg,rp,rg;
    reg [10:0] rg1,rg2,wg1,wg2;
    wire [10:0] wn=wp+1'b1;
    wire [10:0] wgn=(wn>>1)^wn;
    assign full = wg == {~rg2[10:9],rg2[8:0]};
    assign empty = rg == wg2;
    wire [10:0] read_binary;
    genvar bit_index;
    generate for(bit_index=0;bit_index<11;bit_index=bit_index+1) begin:gray_decode
        assign read_binary[bit_index]=^(rg2>>bit_index);
    end endgenerate
    wire [10:0] used=wp-read_binary;
    assign almost_full=used>=11'd768;
    always @(posedge wc) begin
        if(wrst) begin wp<=0;wg<=0;rg1<=0;rg2<=0;overflow<=0;end
        else begin
            rg1<=rg;rg2<=rg1;
            if(we && !full) begin mem[wp[9:0]]<=wd;wp<=wn;wg<=wgn;end
            if(we && full) overflow<=1;
        end
    end
    always @(posedge rc) begin
        if(rrst) begin rp<=0;rg<=0;wg1<=0;wg2<=0;rd<=0;end
        else begin
            wg1<=wg;wg2<=wg1;
            if(re && !empty) begin
                rd<=mem[rp[9:0]];rp<=rp+1'b1;
                rg<=((rp+1'b1)>>1)^(rp+1'b1);
            end
        end
    end
endmodule
