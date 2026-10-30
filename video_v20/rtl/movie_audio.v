// Validated frame audio -> synchronous FIFO -> 24 kHz mu-law -> 48 kHz PCM.
// The consumed sample counter is the video presentation clock.
module movie_audio(input clk,reset,input write_enable,input [7:0] write_data,
 input run,input sample_toggle,input [31:0] sample_limit,
 output reg [31:0] pcm,output reg [31:0] played_samples,
 output space_for_frame,output ended,output reg underrun,overflow);
 reg [7:0] memory[0:8191];
 reg [12:0] wp,rp;
 reg [13:0] count;
 reg [7:0] read_q,code;
 reg pending,have_code,half;
 reg [2:0] sync_tick;
 reg signed [15:0] previous;
 wire tick=sync_tick[2]^sync_tick[1];
 wire pop=!reset && !have_code && !pending && count!=0;
 wire push=!reset && write_enable && count<8192;
 assign space_for_frame=count<=14'd6592;
 assign ended=run && sample_limit!=0 && played_samples>=sample_limit && !half;
 function signed [15:0] decode;
 input [7:0] data;
 reg [7:0] u;reg [15:0] magnitude;
 begin u=~data;magnitude=({9'b0,u[3:0],3'b0}+16'd132)<<u[6:4];
 decode=u[7] ? 16'd132-magnitude : magnitude-16'd132;end
 endfunction
 wire signed [15:0] decoded=decode(code);
 wire signed [16:0] mixed=$signed({previous[15],previous})+$signed({decoded[15],decoded});
 wire signed [15:0] interpolated=mixed>>>1;
 always @(posedge clk) begin
  if(push) memory[wp]<=write_data;
  if(pop) read_q<=memory[rp];
  if(reset) begin
   wp<=0;rp<=0;count<=0;pending<=0;have_code<=0;half<=0;sync_tick<=0;
   code<=8'hff;previous<=0;pcm<=0;played_samples<=0;underrun<=0;overflow<=0;
  end else begin
   sync_tick<={sync_tick[1:0],sample_toggle};
   pending<=pop;
   if(write_enable && !push) overflow<=1;
   case({push,pop})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-1'b1;
   endcase
   if(push) wp<=wp+1'b1;
   if(pop) rp<=rp+1'b1;
   if(pending) begin code<=read_q;have_code<=1;end
   if(!run) begin pcm<=0;previous<=0;half<=0;end
   else if(tick) begin
    if(half) begin pcm<={previous,previous};half<=0;end
    else if(played_samples>=sample_limit) begin pcm<=0;previous<=0;end
    else if(have_code) begin
     pcm<={interpolated,interpolated};previous<=decoded;half<=1;
     have_code<=0;played_samples<=played_samples+1'b1;
    end else begin pcm<=0;previous<=0;underrun<=1;end
   end
  end
 end
endmodule
