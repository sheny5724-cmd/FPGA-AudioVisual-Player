// Eight large hexadecimal digits on the HDMI diagnostic screen.
// Each cell is 64 pixels wide; strokes form a 32x64 seven-segment glyph.
module status_display(input [9:0] x,input [9:0] y,
 input [31:0] codes,output lit);
 wire [2:0] cell_index=x[8:6]-1'b1;
 reg [3:0] value;reg [6:0] segments;
 wire [5:0] xx=x[5:0];wire [6:0] yy=y-180;
 always @* begin
  case(cell_index)
   0:value=codes[31:28];1:value=codes[27:24];
   2:value=codes[23:20];3:value=codes[19:16];
   4:value=codes[15:12];5:value=codes[11:8];
   6:value=codes[7:4];default:value=codes[3:0];
  endcase
  case(value)
   0:segments=7'h3f;1:segments=7'h06;2:segments=7'h5b;3:segments=7'h4f;
   4:segments=7'h66;5:segments=7'h6d;6:segments=7'h7d;7:segments=7'h07;
   8:segments=7'h7f;9:segments=7'h6f;10:segments=7'h77;11:segments=7'h7c;
   12:segments=7'h39;13:segments=7'h5e;14:segments=7'h79;default:segments=7'h71;
  endcase
 end
 assign lit=x>=64 && x<576 && y>=180 && y<244 && (
  (xx>=4 && xx<28 && yy<4 && segments[0]) ||
  (xx>=28 && xx<32 && yy>=4 && yy<30 && segments[1]) ||
  (xx>=28 && xx<32 && yy>=34 && yy<60 && segments[2]) ||
  (xx>=4 && xx<28 && yy>=60 && segments[3]) ||
  (xx<4 && yy>=34 && yy<60 && segments[4]) ||
  (xx<4 && yy>=4 && yy<30 && segments[5]) ||
  (xx>=4 && xx<28 && yy>=30 && yy<34 && segments[6]));
endmodule
