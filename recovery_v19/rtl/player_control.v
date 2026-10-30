// V19: bounded retries, session-local bad-image mask, intact front frame.
module player_control(input clk,input reset,input ready,input media_pause,input auto_enable,input [3:0] image_count,input [3:0] keys,
 input vblank,input commit_allowed,input transition_busy,input parser_done,input [3:0] parser_error,
 input drained,input write_idle,input overflow,input byte_activity,
 input filesystem_done,input file_found,input byte_empty,input parser_ready,
 output reader_reset,output parser_reset,output clear_load,
 output reg front_bank,output reg front_valid,output back_bank,
 output reg [2:0] selected,output reg [2:0] requested,
 output auto_mode,output loading,output reg [3:0] error,
 output [2:0] debug_stage,output reg request_pending,output reg [2:0] pending_target,
 output reg requested_reverse,output reg fault_event,output reg [14:0] fault_info,output stopped);
 localparam BOOT=0,PREPARE=1,LOAD=2,FLUSH=3,COMMIT=4,IDLE=5,FAIL=6,SEEK=7;
 reg [2:0] state;
 reg [8:0] hold_reset;
 reg [30:0] inactivity;
 reg [29:0] slideshow;
 reg [1:0] cached_valid,retries;
 reg [7:0] bad_mask;
 reg pending_reverse,retry_queued;
 reg [2:0] cached_picture0,cached_picture1;
 wire [2:0] last_picture=image_count[2:0]-3'd1;
 wire [8:0] active_mask_w=(9'd1<<image_count)-9'd1;
 wire [7:0] active_mask=active_mask_w[7:0];
 wire all_bad=(bad_mask & active_mask)==active_mask;
 wire last_failure=((bad_mask | (8'd1<<requested)) & active_mask)==active_mask;
 wire back_cached=back_bank ? cached_valid[1] : cached_valid[0];
 wire [2:0] back_picture=back_bank ? cached_picture1 : cached_picture0;
 wire [2:0] next_target=requested_reverse ? (requested==0 ? last_picture : requested-3'd1) :
                                                        (requested==last_picture ? 3'd0 : requested+3'd1);
 assign debug_stage=state;
 assign auto_mode=auto_enable;
 assign stopped=state==FAIL && retries==2 && all_bad;
 assign loading=state==PREPARE || state==LOAD || state==FLUSH || state==COMMIT || state==SEEK || (state==FAIL && !stopped);
 assign reader_reset=state!=LOAD;
 assign parser_reset=state==BOOT || state==PREPARE;
 // Finish an already-issued write burst before clearing its queue. While
 // idle, clear_load also prevents the arbiter from starting another burst.
 assign clear_load=state==PREPARE && write_idle;
 assign back_bank=~front_bank;
 wire navigation_press=keys[0]^keys[1];
 wire [2:0] navigation_base=request_pending ? pending_target :
                            (loading || transition_busy || state==FAIL) ? requested : selected;
 wire [2:0] navigation_target=keys[0] ? (navigation_base==last_picture ? 3'd0 : navigation_base+3'd1) :
                                                      (navigation_base==0 ? last_picture : navigation_base-3'd1);
 wire have_request=navigation_press || request_pending;
 wire [2:0] wanted=navigation_press ? navigation_target : pending_target;
 wire wanted_reverse=navigation_press ? keys[1] : pending_reverse;
 wire consume_request=have_request && !media_pause && !transition_busy &&
                      !(state==SEEK && (retry_queued || keys[3])) &&
                      (state==IDLE || state==FAIL || state==SEEK || (state==BOOT && ready));
 always @(posedge clk) begin
  if(reset) begin request_pending<=0;pending_target<=0;pending_reverse<=0;end
  else if(navigation_press) begin
   pending_target<=navigation_target;pending_reverse<=keys[1];request_pending<=!consume_request;
  end else if(consume_request) request_pending<=0;
 end
 task fail_picture;
  input [3:0] code,reason;
  begin
   error<=code;state<=FAIL;inactivity<=0;fault_event<=1;
   fault_info<={1'b1,2'd2,requested,reason,(retries<2 ? 3'd1 : last_failure ? 3'd3 : 3'd2),
                (retries<2 ? retries+2'd1 : 2'd2)};
   if(retries==2) bad_mask[requested]<=1;
  end
 endtask
 always @(posedge clk) begin
  if(reset) begin
   state<=BOOT;hold_reset<=0;front_bank<=0;front_valid<=0;selected<=0;requested<=0;
   error<=0;inactivity<=0;slideshow<=0;cached_valid<=0;cached_picture0<=0;cached_picture1<=0;
   requested_reverse<=0;retries<=0;bad_mask<=0;fault_event<=0;fault_info<=0;retry_queued<=0;
  end else begin
   fault_event<=0;
   if(keys[3]) retry_queued<=1;
   if(!auto_enable) slideshow<=0;
   if(!media_pause) begin
    case(state)
     BOOT:if(ready) begin
      if(have_request) begin requested<=wanted;requested_reverse<=wanted_reverse;end
      state<=PREPARE;hold_reset<=0;
     end
     PREPARE:begin
      if(back_bank) cached_valid[1]<=0;else cached_valid[0]<=0;
      error<=0;slideshow<=0;
      if(!write_idle) begin
       hold_reset<=0;inactivity<=inactivity+1'b1;
       if(inactivity==31'd499999999) fail_picture(4'd7,4'd7);
      end else begin
       inactivity<=0;
       if(hold_reset==255) state<=LOAD;else hold_reset<=hold_reset+1'b1;
      end
     end
     LOAD:begin
      if(byte_activity) inactivity<=0;else inactivity<=inactivity+1'b1;
      if(parser_error!=0) fail_picture(parser_error,parser_error==1 ? 4'd2 : 4'd8);
      else if(overflow) fail_picture(4'd4,4'd5);
      else if(parser_done) begin state<=FLUSH;inactivity<=0;end
      else if(filesystem_done && !file_found) fail_picture(4'd5,4'd1);
      else if(filesystem_done && byte_empty && parser_ready && !byte_activity && inactivity>500000) fail_picture(4'd6,4'd6);
      else if(inactivity==31'd499999999) fail_picture(4'd6,4'd4);
     end
     FLUSH:begin
      inactivity<=inactivity+1'b1;
      if(drained && inactivity>64) begin
       if(back_bank) begin cached_valid[1]<=1;cached_picture1<=requested;end
       else begin cached_valid[0]<=1;cached_picture0<=requested;end
       state<=COMMIT;
      end else if(inactivity==31'd499999999) fail_picture(4'd7,4'd7);
     end
     COMMIT:if(vblank && commit_allowed) begin
      front_bank<=~front_bank;front_valid<=1;selected<=requested;
      bad_mask[requested]<=0;retries<=0;error<=0;slideshow<=0;state<=IDLE;
     end
     IDLE:if(!transition_busy) begin
      if(auto_mode) slideshow<=slideshow+1'b1;else slideshow<=0;
      if(have_request) begin
       slideshow<=0;
       if(wanted!=selected) begin
        requested<=wanted;requested_reverse<=wanted_reverse;hold_reset<=0;retries<=0;state<=SEEK;
       end
      end else if(retry_queued || keys[3]) begin
       bad_mask<=0;requested<=selected;state<=PREPARE;hold_reset<=0;retries<=0;retry_queued<=0;
      end else if(auto_mode && slideshow==30'd249999999) begin
       requested<=selected==last_picture ? 3'd0 : selected+3'd1;requested_reverse<=0;
       state<=SEEK;hold_reset<=0;retries<=0;
      end
     end
     FAIL:begin
      if(inactivity<31'd25000000) inactivity<=inactivity+1'b1;
      if(have_request || retry_queued || keys[3]) begin
       if(have_request) begin
        requested<=wanted;requested_reverse<=wanted_reverse;bad_mask[wanted]<=0;
       end else bad_mask<=0;
       state<=PREPARE;hold_reset<=0;retries<=0;retry_queued<=0;
       fault_event<=1;fault_info<={1'b1,2'd2,(have_request ? wanted : requested),4'd0,3'd4,2'd0};
      end else if(inactivity>=31'd24999999 && !stopped) begin
       if(retries<2) begin retries<=retries+1'b1;state<=PREPARE;hold_reset<=0;end
       else begin requested<=next_target;state<=SEEK;retries<=0;end
      end
     end
     SEEK:begin
      error<=0;hold_reset<=0;slideshow<=0;
      if(retry_queued || keys[3]) begin bad_mask<=0;retries<=0;retry_queued<=0;state<=PREPARE;end
      else if(have_request) begin requested<=wanted;requested_reverse<=wanted_reverse;end
      else if(all_bad) begin state<=FAIL;retries<=2;end
      else if(bad_mask[requested]) requested<=next_target;
      else if(front_valid && requested==selected) state<=IDLE;
      else if(back_cached && back_picture==requested) state<=COMMIT;
      else state<=PREPARE;
     end
     default:state<=BOOT;
    endcase
   end
  end
 end
endmodule
