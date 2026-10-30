// Digital music gain; settings survive song reloads. No analog volume control.
// V11 arithmetic retained: Q8, symmetric rounding, 1/256 ramp per 8 samples.
module audio_volume(input clk,reset,sample_toggle,input [31:0] music_pcm,
 input [4:0] volume_level,input muted,output reg [31:0] pcm);
 reg [2:0] sample_sync,ramp_div;
 reg [8:0] gain,volume_gain;
 wire tick=sample_sync[2]^sample_sync[1];
 always @* begin case(volume_level)
   5'd0:volume_gain=9'd0;
   5'd1:volume_gain=9'd13;
   5'd2:volume_gain=9'd26;
   5'd3:volume_gain=9'd38;
   5'd4:volume_gain=9'd51;
   5'd5:volume_gain=9'd64;
   5'd6:volume_gain=9'd77;
   5'd7:volume_gain=9'd90;
   5'd8:volume_gain=9'd102;
   5'd9:volume_gain=9'd115;
   5'd10:volume_gain=9'd128;
   5'd11:volume_gain=9'd141;
   5'd12:volume_gain=9'd154;
   5'd13:volume_gain=9'd166;
   5'd14:volume_gain=9'd179;
   5'd15:volume_gain=9'd192;
   5'd16:volume_gain=9'd205;
   5'd17:volume_gain=9'd218;
   5'd18:volume_gain=9'd230;
   5'd19:volume_gain=9'd243;
   5'd20:volume_gain=9'd256;
   default:volume_gain=0;
 endcase end
 wire [8:0] target_gain=muted ? 9'd0 : volume_gain;
 wire signed [15:0] source_l=$signed(music_pcm[15:0]);
 wire signed [15:0] source_r=$signed(music_pcm[31:16]);
 reg signed [25:0] product_l,product_r;
 wire signed [25:0] rounded_l=product_l+(product_l[25] ? 26'sd127 : 26'sd128);
 wire signed [25:0] rounded_r=product_r+(product_r[25] ? 26'sd127 : 26'sd128);
 always @(posedge clk) begin
  if(reset) begin
   sample_sync<=0;ramp_div<=0;gain<=0;product_l<=0;product_r<=0;pcm<=0;
  end else begin
   sample_sync<={sample_sync[1:0],sample_toggle};
   product_l<=source_l*$signed({1'b0,gain});
   product_r<=source_r*$signed({1'b0,gain});
   pcm<={rounded_r[23:8],rounded_l[23:8]};
   if(tick) begin
    ramp_div<=ramp_div+1'b1;
    if(ramp_div==7) begin
     if(gain<target_gain) gain<=gain+1'b1;
     else if(gain>target_gain) gain<=gain-1'b1;
    end
   end
  end
 end
endmodule
