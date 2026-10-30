// V19: retry twice, quarantine bad tracks, retain circular-arena safety.
module music_playlist(input clk,input reset,input enabled,input [3:0] song_count,input image_idle,
 input [20:0] words0,input [20:0] words1,input [20:0] next_words,output [2:0] next_index,
 input load_finished,input load_ok,input load_error,input [3:0] load_reason,
 input [1:0] calibrated,input [1:0] verified,
 input [20:0] consumed_words,input song_done,input player_idle,input retry,
 output reg active_slot,output reg load_slot,output reg [1:0] slot_loaded,
 output reg [20:0] base0,output reg [20:0] base1,
 output reg [2:0] song0,output reg [2:0] song1,
 output reg restart,output reader_claim,output start_claim,output verify_busy,
 output failed,output playback_ready,output reg switching,output [3:0] debug_state,
 output reg startup_done,output reg fault_event,output reg [14:0] fault_info);
 localparam FIRST_LOAD=0,FIRST_VERIFY=1,PLAYING=2,NEXT_LOAD=3,NEXT_VERIFY=4,NEXT_READY=5,
            FAILED=6,WAIT_CATALOG=7,RECOVER=8,SEEK=9;
 localparam [21:0] ARENA_WORDS=22'd1482752;
 reg [3:0] state;
 reg retry_queued;
 reg [1:0] retries;
 reg [25:0] recovery_wait;
 reg [7:0] bad_mask;
 reg [2:0] candidate;
 wire [2:0] current_song=active_slot ? song1 : song0;
 wire [2:0] loading_song=load_slot ? song1 : song0;
 wire [8:0] active_mask_w=(9'd1<<song_count)-9'd1;
 wire [7:0] active_mask=active_mask_w[7:0];
 wire all_bad=(bad_mask & active_mask)==active_mask;
 wire last_failure=((bad_mask | (8'd1<<loading_song)) & active_mask)==active_mask;
 function [2:0] following;
  input [2:0] song;
  begin following=({1'b0,song}+4'd1==song_count) ? 3'd0 : song+3'd1;end
 endfunction
 assign next_index=candidate;
 wire [20:0] current_words=active_slot ? words1 : words0;
 reg [21:0] combined_words,safe_consumed;
 reg [2:0] metadata_valid,candidate_q;
 reg active_slot_q;
 // Length lookup, overlap arithmetic, and reader arbitration are separate
 // core cycles. Invalidate the pipeline whenever its descriptor changes.
 always @(posedge clk) begin
  if(reset) begin combined_words<=0;safe_consumed<=0;metadata_valid<=0;candidate_q<=0;active_slot_q<=0;end
  else begin
   candidate_q<=candidate;active_slot_q<=active_slot;
   combined_words<={1'b0,current_words}+{1'b0,next_words};
   safe_consumed<=combined_words>ARENA_WORDS ? combined_words-22'd1480704 : 22'd2048;
   if(state==SEEK && candidate==candidate_q && active_slot==active_slot_q)
    metadata_valid<={metadata_valid[1:0],1'b1};
   else metadata_valid<=0;
  end
 end
 wire [20:0] current_base=active_slot ? base1 : base0;
 wire [21:0] end_sum={1'b0,current_base}+{1'b0,current_words};
 wire [21:0] next_base=end_sum>=ARENA_WORDS ? end_sum-ARENA_WORDS : end_sum;
 wire next_calibrated=active_slot ? calibrated[0] : calibrated[1];
 wire next_verified=active_slot ? verified[0] : verified[1];
 wire load_calibrated=load_slot ? calibrated[1] : calibrated[0];
 wire load_verified=load_slot ? verified[1] : verified[0];
 assign playback_ready=active_slot ? (slot_loaded[1] && calibrated[1] && verified[1]) :
                                    (slot_loaded[0] && calibrated[0] && verified[0]);
 // Every replacement candidate gets its own overlap check before writing.
 wire safe_to_load=!playback_ready || ({1'b0,consumed_words}>=safe_consumed || (song_done && player_idle));
 wire seek_due=state==SEEK && metadata_valid[2] && !retry_queued && !switching && image_idle && !all_bad && !bad_mask[candidate] && safe_to_load;
 wire retry_due=state==RECOVER && retries<2 && recovery_wait>=26'd24999999 && image_idle && !retry_queued;
 assign start_claim=seek_due || retry_due;
 assign reader_claim=state==FIRST_LOAD || state==NEXT_LOAD;
 assign verify_busy=state==FIRST_VERIFY || state==NEXT_VERIFY;
 assign failed=state==FAILED;
 assign debug_state=state;
 task fail_song;
  input [3:0] reason;
  begin
   startup_done<=1;state<=RECOVER;recovery_wait<=0;fault_event<=1;
   fault_info<={1'b1,2'd3,loading_song,reason,(retries<2 ? 3'd1 : last_failure ? 3'd3 : 3'd2),
                (retries<2 ? retries+2'd1 : 2'd2)};
   if(load_slot) slot_loaded[1]<=0;else slot_loaded[0]<=0;
   if(retries==2) begin bad_mask[loading_song]<=1;candidate<=following(loading_song);end
  end
 endtask
 always @(posedge clk) begin
  if(reset) begin
   state<=WAIT_CATALOG;active_slot<=0;load_slot<=0;slot_loaded<=0;
   base0<=0;base1<=0;song0<=0;song1<=0;restart<=0;switching<=0;retry_queued<=0;
   retries<=0;bad_mask<=0;candidate<=0;recovery_wait<=0;startup_done<=0;fault_event<=0;fault_info<=0;
  end else begin
   restart<=0;switching<=0;fault_event<=0;
   if(retry) retry_queued<=1;
   case(state)
    WAIT_CATALOG:if(enabled) state<=FIRST_LOAD;
    FIRST_LOAD,NEXT_LOAD:if(!restart && load_finished) begin
     if(load_ok && !load_error) begin
      if(load_slot) slot_loaded[1]<=1;else slot_loaded[0]<=1;
      state<=state==FIRST_LOAD ? FIRST_VERIFY : NEXT_VERIFY;
     end else fail_song(load_reason);
    end
    FIRST_VERIFY,NEXT_VERIFY:if(load_calibrated) begin
     if(load_verified) begin
      startup_done<=1;retries<=0;bad_mask[loading_song]<=0;
      state<=state==FIRST_VERIFY ? PLAYING : NEXT_READY;
     end else fail_song(4'd3);
    end
    PLAYING:begin candidate<=following(current_song);state<=SEEK;end
    SEEK:begin
     if(retry_queued) begin bad_mask<=0;retry_queued<=0;end
     else if(all_bad) state<=FAILED;
     else if(bad_mask[candidate]) candidate<=following(candidate);
     else if(seek_due) begin
      retries<=0;
      if(playback_ready) begin
       load_slot<=~active_slot;
       if(active_slot) begin base0<=next_base[20:0];song0<=candidate;slot_loaded[0]<=0;end
       else begin base1<=next_base[20:0];song1<=candidate;slot_loaded[1]<=0;end
       state<=NEXT_LOAD;
      end else begin
       load_slot<=active_slot;
       if(active_slot) begin base1<=0;song1<=candidate;slot_loaded[1]<=0;end
       else begin base0<=0;song0<=candidate;slot_loaded[0]<=0;end
       state<=FIRST_LOAD;
      end
      restart<=1;
     end
    end
    NEXT_READY:if(song_done && player_idle && next_calibrated && next_verified) begin
     if(active_slot) slot_loaded[1]<=0;else slot_loaded[0]<=0;
     active_slot<=~active_slot;switching<=1;state<=PLAYING;
    end
    RECOVER:begin
     if(recovery_wait<26'd25000000) recovery_wait<=recovery_wait+1'b1;
     if(retry_queued) begin retries<=0;bad_mask<=0;retry_queued<=0;end
     else if(retry_due) begin
      retries<=retries+1'b1;restart<=1;state<=load_slot==active_slot ? FIRST_LOAD : NEXT_LOAD;
     end else if(retries==2 && recovery_wait>=26'd24999999) begin
      if(all_bad) state<=FAILED;else begin retries<=0;state<=SEEK;end
     end
    end
    FAILED:if(retry_queued) begin
     bad_mask<=0;retries<=0;retry_queued<=0;candidate<=0;state<=SEEK;
     fault_event<=1;fault_info<={1'b1,2'd3,3'd0,4'd0,3'd4,2'd0};
    end
    default:state<=FAILED;
   endcase
  end
 end
endmodule
