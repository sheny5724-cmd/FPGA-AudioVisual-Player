module tmds_encode(input clk, input reset, input [2:0] phase,
                   input [7:0] data, input active, input [1:0] control,
                   output reg [9:0] symbol);
    function [3:0] ones;
        input [7:0] v;
        integer j;
        begin
            ones = 0;
            for (j=0;j<8;j=j+1) ones = ones + v[j];
        end
    endfunction
    reg [7:0] data0;
    reg active0;
    reg [1:0] control0;
    wire use_xnor = (ones(data0)>4) || ((ones(data0)==4) && !data0[0]);
    reg [8:0] qm_next;
    integer k;
    always @* begin
        qm_next[0] = data0[0];
        for (k=1;k<8;k=k+1)
            qm_next[k] = qm_next[k-1] ^ data0[k] ^ use_xnor;
        qm_next[8] = !use_xnor;
    end
    reg [8:0] qm1, qm2;
    reg active1, active2;
    reg [1:0] control1, control2;
    reg signed [5:0] balance, disparity;
    always @(posedge clk) begin
        if (reset) begin
            data0 <= 0; active0 <= 0; control0 <= 0;
            qm1 <= 0; qm2 <= 0; active1 <= 0; active2 <= 0;
            control1 <= 0; control2 <= 0;
            balance <= 0; disparity <= 0; symbol <= 10'b1101010100;
        end else begin
            // Line RAM read at phase 0; RGB at 1, qm1 at 2, qm2 at 3.
            // Symbol at 4, serializer load at phase 0.
            data0 <= data; active0 <= active; control0 <= control;
            qm1 <= qm_next; active1 <= active0; control1 <= control0;
            qm2 <= qm1; active2 <= active1; control2 <= control1;
            balance <= $signed({1'b0,ones(qm1[7:0]),1'b0}) - 6'sd8;
            if (phase == 4) begin
                if (!active2) begin
                    disparity <= 0;
                    case (control2)
                        0: symbol <= 10'b1101010100;
                        1: symbol <= 10'b0010101011;
                        2: symbol <= 10'b0101010100;
                        3: symbol <= 10'b1010101011;
                    endcase
                end else if (disparity == 0 || balance == 0) begin
                    symbol <= {~qm2[8],qm2[8],qm2[8] ? qm2[7:0] : ~qm2[7:0]};
                    disparity <= disparity + (qm2[8] ? balance : -balance);
                end else if ((disparity > 0 && balance > 0) ||
                             (disparity < 0 && balance < 0)) begin
                    symbol <= {1'b1,qm2[8],~qm2[7:0]};
                    disparity <= disparity - balance + (qm2[8] ? 6'sd2 : 6'sd0);
                end else begin
                    symbol <= {1'b0,qm2[8],qm2[7:0]};
                    disparity <= disparity + balance - (qm2[8] ? 6'sd0 : 6'sd2);
                end
            end
        end
    end
endmodule

module tmds_serialize(input clk, input reset, input [2:0] phase,
                      input [9:0] symbol, output serial);
    reg [9:0] shift;
    wire [1:0] pair = phase == 0 ? symbol[1:0] : shift[1:0];
    always @(posedge clk)
        if (reset) shift <= 0;
        else if (phase == 0) shift <= {2'b0,symbol[9:2]};
        else shift <= {2'b0,shift[9:2]};
    EG_LOGIC_ODDR #(.ASYNCRST("ENABLE")) ddr (
        .clk(clk), .rst(reset), .d0(pair[0]), .d1(pair[1]), .q(serial));
endmodule
