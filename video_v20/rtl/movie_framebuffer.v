// Two 160x90 indexed images, each with its own 256-entry RGB palette.
// Writes target the back bank; scanout switches banks only in vertical blank.
module movie_framebuffer(input core,input pixel_we,input palette_we,input write_bank,
 input [13:0] pixel_address,input [7:0] pixel_data,
 input [7:0] palette_address,input [23:0] palette_data,
 input fast,input [2:0] phase,input display_bank,input [13:0] display_address,
 output [23:0] rgb);
 reg [7:0] pixels0[0:14399],pixels1[0:14399];
 reg [23:0] palette0[0:255],palette1[0:255];
 reg [7:0] index0_q,index1_q;reg bank_q,palette_bank_q;
 reg [23:0] color0_q,color1_q;
 wire [7:0] index_q=bank_q ? index1_q : index0_q;
 assign rgb=palette_bank_q ? color1_q : color0_q;
 always @(posedge core) begin
  if(pixel_we) begin
   if(write_bank) pixels1[pixel_address]<=pixel_data;
   else pixels0[pixel_address]<=pixel_data;
  end
  if(palette_we) begin
   if(write_bank) palette1[palette_address]<=palette_data;
   else palette0[palette_address]<=palette_data;
  end
 end
 always @(posedge fast) begin
  if(phase==0) begin
   bank_q<=display_bank;
   index0_q<=pixels0[display_address];
   index1_q<=pixels1[display_address];
  end
  if(phase==1) begin
   palette_bank_q<=bank_q;
   color0_q<=palette0[index_q];
   color1_q<=palette1[index_q];
  end
 end
endmodule
