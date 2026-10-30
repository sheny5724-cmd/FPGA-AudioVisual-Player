// HDMI packet integration for the existing 25MHz video / 125MHz serializer.
// Reference packet modules retain hdl-util/hdmi attribution and licenses.
module hdmi_audio_bridge(
 input wire clk,input wire reset,input wire [2:0] phase,
 input wire [9:0] x,input wire [9:0] y,
 input wire hs,input wire vs,
 input wire [31:0] music_pcm,output reg sample_toggle,
 output wire audio_fault,output reg override_video,output reg [29:0] symbols,
 output wire visual_ce,output wire signed [15:0] visual_left,visual_right
);
 reg [9:0] px,py;
 always @(posedge clk) begin
  if(reset) begin px<=0;py<=0;end
  else if(phase==0) begin px<=x;py<=y;end
 end
 // Exact long-term 48kHz rate from 125MHz, without a generated fabric clock.
 reg [26:0] audio_acc=0;
 wire [27:0] audio_sum={1'b0,audio_acc}+28'd48000;
 wire audio_ce=!reset && audio_sum>=28'd125000000;
 reg [31:0] pcm_sync1,pcm_sync2;
 // Observe the exact words/enable presented to the HDMI audio queue.
 assign visual_ce=audio_ce;
 assign visual_left=pcm_sync2[15:0];
 assign visual_right=pcm_sync2[31:16];
 always @(posedge clk) begin
  if(reset) begin audio_acc<=0;sample_toggle<=0;pcm_sync1<=0;pcm_sync2<=0;end
  else begin
   audio_acc<=audio_ce ? audio_sum-28'd125000000 : audio_sum;
   if(audio_ce) sample_toggle<=~sample_toggle;
   // PCM updates shortly after the previous sample_toggle in the core
   // domain, and remains stable for almost the entire 20.8us sample period.
   pcm_sync1<=music_pcm;pcm_sync2<=pcm_sync1;
  end
 end
 // Four 32-pixel packets fit the 160-pixel horizontal blank.
 wire island=px>=654 && px<782;
 wire choose_packet=island && (px[4:0]==5'd14);
 wire island_guard=(px>=652 && px<654) || (px>=782 && px<784);
 wire island_pre=px>=644 && px<652;
 wire video_line=py<479 || py==524;
 wire video_guard=video_line && px>=798;
 wire video_pre=video_line && px>=790 && px<798;
 wire [23:0] header;
 wire [55:0] sub [3:0];
 wire [4:0] packet_counter;
 wire [8:0] packet_bits;
 audio_packet_queue picker(.clk(clk),.reset(reset),.pixel_ce(phase==1),
 .audio_ce(audio_ce),.stereo(pcm_sync2),.packet_enable(choose_packet),
 .video_field_end(px==639 && py==479),.header(header),.sub(sub),.fault(audio_fault));
 packet_assembler assembler(.clk_pixel(clk),.pixel_ce(reset || phase==3),
 .reset(reset),.data_island_period(island),.header(header),.sub(sub),
 .packet_data(packet_bits),.counter(packet_counter));
 // Capture serialized packet bits before assembler advances its counter.
 reg [8:0] bits_q;
 always @(posedge clk)
  if(reset) bits_q<=0;
  else if(phase==2) bits_q<=packet_bits;
 function [9:0] control_code;
 input [1:0] c;
 begin case(c)
  0:control_code=10'b1101010100;
  1:control_code=10'b0010101011;
  2:control_code=10'b0101010100;
  3:control_code=10'b1010101011;
 endcase end
 endfunction
 function [9:0] terc4;
 input [3:0] c;
 begin case(c)
  0:terc4=10'b1010011100;1:terc4=10'b1001100011;
  2:terc4=10'b1011100100;3:terc4=10'b1011100010;
  4:terc4=10'b0101110001;5:terc4=10'b0100011110;
  6:terc4=10'b0110001110;7:terc4=10'b0100111100;
  8:terc4=10'b1011001100;9:terc4=10'b0100111001;
  10:terc4=10'b0110011100;11:terc4=10'b1011000110;
  12:terc4=10'b1010001110;13:terc4=10'b1001110001;
  14:terc4=10'b0101100011;15:terc4=10'b1011000011;
 endcase end
 endfunction
 always @(posedge clk) begin
  if(reset) begin override_video<=0;symbols<=0;end
  else if(phase==4) begin
   override_video<=!(px<640 && py<480);
   if(island_guard) begin
    symbols<={10'b0100110011,10'b0100110011,terc4({2'b11,vs,hs})};
   end else if(island) begin
    symbols<={terc4(bits_q[8:5]),terc4(bits_q[4:1]),
              terc4({1'b1,bits_q[0],vs,hs})};
   end else if(video_guard) begin
    symbols<={10'b1011001100,10'b0100110011,10'b1011001100};
   end else begin
    symbols<={control_code({1'b0,island_pre}),
              control_code({1'b0,island_pre||video_pre}),control_code({vs,hs})};
   end
  end
 end
endmodule

