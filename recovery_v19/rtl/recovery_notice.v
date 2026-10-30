// Core-domain notices: brief recoverable messages, persistent stopped status.
// info: valid[14], kind[13:12], file index[11:9], reason[8:5], action[4:2], retry[1:0].
module recovery_notice(input clk,reset,
 input catalog_event,input [14:0] catalog_info,input catalog_stopped,
 input image_event,input [14:0] image_info,input image_stopped,
 input music_event,input [14:0] music_info,input music_stopped,
 output reg [14:0] info);
 reg [27:0] duration;
 always @(posedge clk) begin
  if(reset) begin info<=0;duration<=0;end
  else if(catalog_event || image_event || music_event) begin
   info<=catalog_event ? catalog_info : image_event ? image_info : music_info;
   duration<=28'd199999999;
  end else if(duration!=0) duration<=duration-1'b1;
  else if(catalog_stopped) info<=catalog_info;
  else if(image_stopped) info<=image_info;
  else if(music_stopped) info<=music_info;
  else info<=0;
 end
endmodule
