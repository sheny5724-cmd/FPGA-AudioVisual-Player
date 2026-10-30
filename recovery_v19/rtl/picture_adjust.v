// RAM read at phase 1, contrast at 2, offset/clamp at 3, fade capture at 4.
// Clamp((component-128)*contrast/4 + 128 + brightness*16, 0, 255).
// Default brightness=0, contrast=4 is bit-exact identity.
module picture_adjust(input clk,input reset,input [2:0] phase,
 input [23:0] rgb,input signed [3:0] brightness,
 input [3:0] contrast,output reg [23:0] adjusted);
 function signed [10:0] contrast_product;
 input [7:0] component;
 input [3:0] gain;
 reg signed [10:0] centered;
 reg signed [10:0] base_term,extra_term;
 begin
  // Subtracting 128 flips the MSB of an eight-bit signed value. The five
  // gains only need shifts and adds, avoiding a DSP in the RAM read path.
  centered=$signed({{3{~component[7]}},~component[7],component[6:0]});
  // Select operands before one shared adder. Selecting between separately
  // computed products would put two more muxes after the carry chain.
  base_term=(gain==4'd2 || gain==4'd3) ? centered<<<1 : centered<<<2;
  case(gain)
   4'd3,4'd5: extra_term=centered;
   4'd6: extra_term=centered<<<1;
   default: extra_term=0;
  endcase
  contrast_product=base_term+extra_term;
 end endfunction
 function [7:0] channel;
 input signed [10:0] product;
 input signed [3:0] offset;
 reg signed [10:0] result,wide_offset;
 begin
  wide_offset=$signed({{7{offset[3]}},offset});
  result=(product>>>2)+11'sd128+(wide_offset<<<4);
  if(result<0) channel=0;
  else if(result>255) channel=255;
  else channel=result[7:0];
 end endfunction
 reg signed [10:0] red_product,green_product,blue_product;
 reg signed [3:0] offset_q;
 always @(posedge clk) begin
  if(reset) begin
   red_product<=0;green_product<=0;blue_product<=0;offset_q<=0;adjusted<=0;
  end else begin
   if(phase==2) begin
    red_product<=contrast_product(rgb[23:16],contrast);
    green_product<=contrast_product(rgb[15:8],contrast);
    blue_product<=contrast_product(rgb[7:0],contrast);
    offset_q<=brightness;
   end
   if(phase==3) adjusted<={channel(red_product,offset_q),
                          channel(green_product,offset_q),
                          channel(blue_product,offset_q)};
  end
 end
endmodule
