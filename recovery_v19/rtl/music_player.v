// V18: runtime length/base; playback starts after the calibration prefix.
`define MUSIC_PLAYLIST

// 24kHz mu-law -> linearly interpolated 48kHz PCM, same sample both channels.
// 256-word prefetch FIFO and 32-word memory bursts decouple playback from video.
module music_player(input clk,input reset,input loaded,input play_enable,input [20:0] song_words,input [20:0] base_word,
 input sample_toggle,input memory_accept,input memory_valid,input [31:0] memory_data,
 output memory_request,output [20:0] memory_address,
 output reg [31:0] pcm,output reg underrun,output reg song_done,output memory_idle,output [20:0] consumed_words);
 reg [2:0] sample_sync;
 wire tick=sample_sync[2]^sample_sync[1];
 always @(posedge clk)
  if(reset) sample_sync<=0;else sample_sync<={sample_sync[1:0],sample_toggle};
 reg [31:0] fifo[0:255];reg [7:0] wp,rp;reg [8:0] count;
 reg pending,have_word,started,half;
 reg [4:0] received;
 reg [31:0] word;
 reg [1:0] byte_index;
 reg [20:0] fetch_index;
 reg [20:0] played_words;
 reg end_pending,fetch_done;
 assign consumed_words=played_words;
 reg signed [15:0] previous;
 wire pop_word=!have_word && count!=0;
 assign memory_request=loaded && !pending && !song_done && !end_pending && !fetch_done && count<=192;
 assign memory_idle=!pending;
 audio_buffer_map address_map(base_word,fetch_index,memory_address);
 function signed [15:0] decode;
 input [7:0] code;
 reg [7:0] u;reg [15:0] magnitude;
 begin
  u=~code;
  magnitude=({9'b0,u[3:0],3'b0}+16'd132)<<u[6:4];
  decode=u[7] ? 16'd132-magnitude : magnitude-16'd132;
 end endfunction
 wire signed [15:0] decoded=decode(word[7:0]);
 wire signed [16:0] mixed=$signed({previous[15],previous})+$signed({decoded[15],decoded});
 wire signed [15:0] interpolated=mixed>>>1;
 always @(posedge clk) begin
  if(reset || !loaded) begin
   wp<=0;rp<=0;count<=0;pending<=0;received<=0;have_word<=0;
   started<=0;half<=0;word<=0;byte_index<=0;fetch_index<=0;
   previous<=0;pcm<=0;underrun<=0;song_done<=0;played_words<=0;end_pending<=0;fetch_done<=0;
  end else begin
   case({memory_valid,pop_word})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
   endcase
   if(memory_accept) begin
    pending<=1;received<=0;
    // Never wrap the fetch pointer into a prefix reclaimed by the next song.
    if(fetch_index==song_words-21'd32) fetch_done<=1;
    else fetch_index<=fetch_index+21'd32;
   end
   if(memory_valid) begin
    fifo[wp]<=memory_data;wp<=wp+1'b1;received<=received+1'b1;
    if(received==31) pending<=0;
   end
   if(pop_word) begin word<=fifo[rp];rp<=rp+1'b1;have_word<=1;byte_index<=0;end
   if(!started && play_enable && count>=64 && have_word) started<=1;
   if(started && tick && !song_done) begin
`ifdef MUSIC_PCM_STEREO
    if(have_word) begin pcm<=word;have_word<=0;end
    else begin pcm<=0;underrun<=1;end
`else
    if(half) begin
     pcm<={previous,previous};half<=0;
`ifdef MUSIC_PLAYLIST
     if(end_pending) begin song_done<=1;pcm<=0;end
`endif
    end
    else if(have_word) begin
     pcm<={interpolated,interpolated};previous<=decoded;half<=1;
     word<=word>>8;byte_index<=byte_index+1'b1;
     if(byte_index==3) begin
      have_word<=0;
`ifdef MUSIC_PLAYLIST
      played_words<=played_words+1'b1;
      if(played_words==song_words-1'b1) end_pending<=1;
`endif
     end
    end else begin pcm<=0;previous<=0;underrun<=1;end
`endif
   end
  end
 end
endmodule
