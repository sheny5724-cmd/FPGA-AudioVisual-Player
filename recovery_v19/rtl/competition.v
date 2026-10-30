// V19: bounded media recovery, quarantine and readable fault notices.
// HX4S20C EG4S20BG256: TF BMP -> embedded SDRAM -> HDMI B.
module competition(input clk,input [3:0] key_n,input [3:0] sw,input sd_miso,
 output sd_cs,output sd_clk,output sd_mosi,
 output [2:0] hdmi_p,output hdmi_clk_p,output [3:0] led);
 wire [4:0] clocks;wire locked,fast,feedback,shifted,core;
 EG_LOGIC_BUFG clock_buffer(.i(clocks[1]),.o(fast));
 EG_LOGIC_BUFG feedback_buffer(.i(clocks[0]),.o(feedback));
 EG_LOGIC_BUFG sdram_clock_buffer(.i(clocks[2]),.o(shifted));
 EG_LOGIC_BUFG core_clock_buffer(.i(clocks[3]),.o(core));
 EG_PHY_PLL #(.FIN("50.0000"),.REFCLK_DIV(2),.FBCLK_DIV(1),
 .CLKC0_DIV(40),.CLKC0_CPHASE(39),.CLKC0_ENABLE("ENABLE"),
 .CLKC1_DIV(8),.CLKC1_CPHASE(7),.CLKC1_ENABLE("ENABLE"),
 .CLKC2_DIV(20),.CLKC2_CPHASE(7),.CLKC2_ENABLE("ENABLE"),
 .CLKC3_DIV(20),.CLKC3_CPHASE(19),.CLKC3_ENABLE("ENABLE"),
 .FEEDBK_MODE("NORMAL"),.FEEDBK_PATH("CLKC0_EXT"),
 .GMC_GAIN(0),.ICP_CURRENT(9),.KVCO(2),
 .LPF_CAPACITOR(2),.LPF_RESISTOR(8),.STDBY_ENABLE("DISABLE")) pll(
 .refclk(clk),.clkc(clocks),.extlock(locked),.reset(1'b0),.stdby(1'b0),
 .fbclk(feedback),.load_reg(1'b0),.psclk(1'b0),.psdown(1'b0),.psstep(1'b0),
 .psclksel(3'b0),.dclk(1'b0),.dcs(1'b0),.dwe(1'b0),.di(8'b0),.daddr(6'b0),
 .psdone(),.do());
 reg [3:0] reset_pipe=15;
 always @(posedge fast or negedge locked)
  if(!locked) reset_pipe<=15;else reset_pipe<={reset_pipe[2:0],1'b0};
 wire reset=reset_pipe[3];
 reg [3:0] core_reset_pipe=15;
 always @(posedge core or negedge locked)
  if(!locked) core_reset_pipe<=15;else core_reset_pipe<={core_reset_pipe[2:0],1'b0};
 wire core_reset=core_reset_pipe[3];
 wire [3:0] pressed,held,image_keys;
 wire [3:0] switch_state;
 wire adjust_mode,wave_visible;
 wire [1:0] parameter_select;
 wire [4:0] volume_level;wire volume_muted;
 wire recovery_needed;wire [1:0] audio_state;
 wire catalog_fault_event,image_fault_event,music_fault_event,image_stopped,music_startup_done;
 wire [14:0] catalog_fault_info,image_fault_info,music_fault_info,recovery_info;
 wire [3:0] music_failure_reason;
 wire [3:0] picture_keys={image_keys[3] && recovery_info[13:12]==2'd2,image_keys[2:0]};
 wire music_retry=image_keys[3] && recovery_info[13:12]==2'd3;
 wire signed [3:0] brightness;
 wire [3:0] contrast;
 key_controls controls(core,core_reset,key_n,pressed,held);
 // Board switches are active high. Reuse the 2-flop/20 ms input filter;
 // invert at its active-low input, then held is the stable switch level.
 key_controls switch_inputs(.clk(core),.reset(core_reset),.keys_n(~sw),
  .pressed(),.held(switch_state));
 display_controls settings(core,core_reset,pressed,held,switch_state,recovery_needed,image_keys,
  adjust_mode,parameter_select,brightness,contrast,wave_visible,volume_level,volume_muted);

 reg [2:0] phase;reg [9:0] x,y;
 reg vblank_toggle,line_toggle;
 reg [8:0] requested_line,line_number_sync1,line_number_sync2;
 reg [2:0] vblank_sync,line_sync;
 reg [25:0] video_meta1,video_meta2;
 always @(posedge fast) begin
  if(reset) begin vblank_toggle<=0;line_toggle<=0;requested_line<=0;end
  else if(phase==0 && x==0) begin
   if(y==480) vblank_toggle<=~vblank_toggle;
   if(video_meta2[25] && (y<479 || y==524)) begin
    line_toggle<=~line_toggle;requested_line<=y==524 ? 0 : y[8:0]+1'b1;
   end
  end
 end
 always @(posedge core) begin
  if(core_reset) begin vblank_sync<=0;line_sync<=0;line_number_sync1<=0;line_number_sync2<=0;end
  else begin
   vblank_sync<={vblank_sync[1:0],vblank_toggle};line_sync<={line_sync[1:0],line_toggle};
   line_number_sync1<=requested_line;line_number_sync2<=line_number_sync1;
  end
 end
 wire vblank=vblank_sync[2]^vblank_sync[1];
 wire front_bank,front_valid,back_bank;
 wire reader_reset,image_reader_reset,parser_reset,clear_load,auto_mode,loading,image_loading;
 wire music_active,music_finished,music_loaded,music_reader_reset,music_clear,music_error;
 wire music_word_valid;wire [20:0] music_word_addr;wire [31:0] music_word_data;
 wire audio_request,audio_accept,audio_valid,audio_underrun;
 wire player_audio_request,player_audio_accept,player_audio_valid;
 wire [20:0] player_audio_address;
 wire [31:0] player_audio_data;
 wire [31:0] music_pcm;wire sample_toggle;
 wire [20:0] audio_address;wire [31:0] read_data;
 wire [2:0] selected,requested,pending_target;wire request_pending;
 wire [3:0] image_error;
 wire [2:0] debug_stage;
 wire commit_allowed,transition_busy,requested_reverse,wipe_active,wipe_reverse;
 wire [9:0] wipe_boundary;
 wire song_done,audio_memory_idle;
 wire [20:0] consumed_words;
 wire active_slot,load_slot;
 wire [2:0] slot_song0,slot_song1,next_song;
 wire [3:0] image_count,song_count;
 wire [20:0] next_words;
 wire [31:0] full_crc0,full_crc1,probe_crc0,probe_crc1;
 wire catalog_reset,catalog_clear,catalog_byte_ready,catalog_claim,catalog_ready,catalog_error;
 wire music_byte_ready;
 wire [20:0] slot_base0,slot_base1,slot_words0,slot_words1;
 wire [1:0] slot_loaded,slot_calibrated,slot_verified;
 wire music_claim,music_start,music_restart,music_verify,music_failed,playback_ready,switching;
 wire [3:0] playlist_stage;
 wire [2:0] song_index=active_slot ? slot_song1 : slot_song0;
 wire [2:0] load_song_index=load_slot ? slot_song1 : slot_song0;
 wire [20:0] song_words=active_slot ? slot_words1 : slot_words0;
 wire [20:0] song_base=active_slot ? slot_base1 : slot_base0;
 wire [20:0] load_words=load_slot ? slot_words1 : slot_words0;
 wire [20:0] load_base=load_slot ? slot_base1 : slot_base0;
 wire [3:0] load_error=catalog_error ? 4'd11 : image_stopped ? image_error : music_failed ? (music_error ? 4'd9 : 4'd10) : 4'd0;
 assign recovery_needed=recovery_info[14];
 assign audio_state=playback_ready ? 2'd2 : music_failed ? 2'd3 : music_claim ? 2'd0 : 2'd1;
 assign reader_reset=catalog_claim ? catalog_reset : music_claim ? music_reader_reset : image_reader_reset;
 assign loading=(catalog_claim && !catalog_error) || music_claim || image_loading;
 transition_control transition(core,core_reset,vblank,debug_stage==4,
  front_valid,front_bank,requested_reverse,commit_allowed,transition_busy,
  wipe_active,wipe_reverse,wipe_boundary);
 wire init_done,refresh,busy;
 wire parser_done;wire [3:0] parser_error;
 wire pixel_valid;wire [20:0] pixel_addr;wire [31:0] pixel_data;
 wire throttle,drained,write_idle,write_overflow,dma_error;
 wire [1:0] card_type,fs_type;wire [3:0] card_status;wire [2:0] fs_status;
 wire file_found,sd_byte_valid;wire [7:0] sd_byte;
 wire sd_pause,parser_ready;
 wire image_bus_idle=(debug_stage==0 || debug_stage==5 || debug_stage==6) &&
                     !transition_busy &&
                     (drained || ((music_failed || music_error || debug_stage==6) && write_idle));
 music_playlist playlist(core,core_reset,catalog_ready,song_count,image_bus_idle,
  slot_words0,slot_words1,next_words,next_song,music_finished,music_loaded,music_error,music_failure_reason,
  slot_calibrated,slot_verified,consumed_words+21'd1024,song_done,audio_memory_idle,music_retry,
  active_slot,load_slot,slot_loaded,slot_base0,slot_base1,slot_song0,slot_song1,
  music_restart,music_claim,music_start,music_verify,music_failed,playback_ready,switching,playlist_stage,
  music_startup_done,music_fault_event,music_fault_info);
 recovery_notice notice(core,core_reset,catalog_fault_event,catalog_fault_info,catalog_error,
  image_fault_event,image_fault_info,image_stopped,music_fault_event,music_fault_info,music_failed,recovery_info);
 reg byte_valid;
 wire [23:0] sd_session;
 reg [1:0] sd_reset_sync=3;
 always @(posedge feedback or posedge reset)
  if(reset) sd_reset_sync<=3;
  else sd_reset_sync<={sd_reset_sync[0],reader_reset};
 wire sd_reset=sd_reset_sync[1];
 wire [7:0] picture_file_digit=8'd49+{5'd0,requested};
 wire [7:0] song_file_digit=8'd49+{5'd0,load_song_index};
 wire [415:0] filename=catalog_claim ? "PLAYLST.BIN" :
  music_claim ? {"MUSIC0",song_file_digit,".FPA"} : {"PIC000",picture_file_digit,".BMP"};
 sd_spi_file_reader #(.FILE_NAME_LEN(11),.SPI_CLK_DIV(49)) reader(
 .rstn(!sd_reset),.clk(feedback),.pause(sd_pause),.requested_name(filename),
 .spi_ssn(sd_cs),.spi_sck(sd_clk),.spi_mosi(sd_mosi),.spi_miso(sd_miso),
 .card_type(card_type),.card_stat(card_status),.debug_session(sd_session),.filesystem_type(fs_type),
 .filesystem_stat(fs_status),.file_found(file_found),.outen(sd_byte_valid),.outbyte(sd_byte));
 wire byte_full,byte_empty,byte_overflow;wire [7:0] byte_data;
 // Allow only one outstanding synchronous FIFO read. A row-ending byte
 // may make the parser busy; the next byte must remain in the FIFO.
 wire pop_byte=!byte_empty && (catalog_claim ? catalog_byte_ready : music_claim ? (music_byte_ready && !throttle) : parser_ready) && !byte_valid && !reader_reset;
 always @(posedge core)
  if(core_reset || reader_reset) byte_valid<=0;else byte_valid<=pop_byte;
 async_bytes byte_queue(feedback,sd_reset,sd_byte_valid&&!sd_pause,sd_byte,byte_full,byte_overflow,
                       core,core_reset||reader_reset,pop_byte,byte_data,byte_empty,sd_pause);
 reg [1:0] overflow_sync,found_sync,fsdone_sync;
 always @(posedge core) begin
  if(core_reset || reader_reset) begin overflow_sync<=0;found_sync<=0;fsdone_sync<=0;end
  else begin
   overflow_sync<={overflow_sync[0],byte_overflow};
   found_sync<={found_sync[0],file_found};
   fsdone_sync<={fsdone_sync[0],fs_status==6};
  end
 end
 media_catalog catalog(core,core_reset,init_done,pressed[3] && catalog_claim,
  byte_valid&&catalog_claim,byte_data,byte_empty,fsdone_sync[1],found_sync[1],overflow_sync[1],
  slot_song0,slot_song1,next_song,catalog_reset,catalog_clear,catalog_byte_ready,catalog_claim,
  catalog_ready,catalog_error,image_count,song_count,slot_words0,slot_words1,next_words,
  full_crc0,full_crc1,probe_crc0,probe_crc1,catalog_fault_event,catalog_fault_info);
 bmp24_loader parser(core,core_reset||parser_reset||music_claim||catalog_claim,byte_valid&&!music_claim&&!catalog_claim,byte_data,back_bank,
                    pixel_valid,pixel_addr,pixel_data,parser_done,parser_error,throttle,parser_ready);
 player_control player(core,core_reset||!catalog_ready,init_done&&catalog_ready&&music_startup_done,
 music_claim||music_start||catalog_claim||(adjust_mode && debug_stage==5),switch_state[0],image_count,picture_keys,vblank,commit_allowed,transition_busy,parser_done,parser_error,
 drained,write_idle,write_overflow||overflow_sync[1],byte_valid,fsdone_sync[1],found_sync[1],byte_empty,parser_ready,
 image_reader_reset,parser_reset,clear_load,front_bank,front_valid,back_bank,
 selected,requested,auto_mode,image_loading,image_error,debug_stage,request_pending,pending_target,requested_reverse,
 image_fault_event,image_fault_info,image_stopped);
 music_loader music_load(core,core_reset,init_done&&catalog_ready,music_restart,load_words,load_base,
  load_slot ? full_crc1 : full_crc0,load_slot ? probe_crc1 : probe_crc0,
  byte_valid&&music_claim,byte_data,byte_empty,
  drained,write_overflow||overflow_sync[1],fsdone_sync[1],found_sync[1],
  music_reader_reset,music_active,music_finished,music_loaded,music_clear,music_error,music_byte_ready,
  music_word_valid,music_word_addr,music_word_data,music_failure_reason);
 wire [21:0] playable_sum={1'b0,song_base}+22'd1024;
 wire [20:0] playable_base=playable_sum>=22'd1482752 ? playable_sum-22'd1482752 : playable_sum[20:0];
 music_player music_play(core,core_reset,playback_ready&&!switching,front_valid||image_stopped,song_words-21'd1024,playable_base,
  sample_toggle,player_audio_accept,player_audio_valid,player_audio_data,
  player_audio_request,player_audio_address,music_pcm,audio_underrun,song_done,audio_memory_idle,
  consumed_words);
 // Playback requests take priority over the next song's alignment/CRC reads.
 audio_slots slots(core,core_reset,active_slot,slot_loaded,full_crc0,full_crc1,probe_crc0,probe_crc1,
  slot_words0,slot_words1,slot_base0,slot_base1,read_data,audio_valid,audio_accept,
  player_audio_request,player_audio_address,audio_request,audio_address,
  player_audio_accept,player_audio_valid,player_audio_data,slot_calibrated,slot_verified);
 wire [31:0] output_pcm;
 audio_volume volume(core,core_reset,sample_toggle,music_pcm,volume_level,volume_muted,output_pcm);

 reg [7:0] sd_info1,sd_info2,sd_snapshot;
 reg [23:0] response_sync1,response_sync2,response_snapshot;
 reg [19:0] bytes_received;
 always @(posedge core) begin
  if(core_reset) begin
   sd_info1<=0;sd_info2<=0;sd_snapshot<=0;bytes_received<=0;
   response_sync1<=24'hffff00;response_sync2<=24'hffff00;response_snapshot<=24'hffff00;
  end
  else begin
   sd_info1<={card_status,fs_status,file_found};sd_info2<=sd_info1;
   response_sync1<=sd_session;response_sync2<=response_sync1;
   if(catalog_claim ? catalog_clear : music_claim ? music_clear : parser_reset) begin sd_snapshot<=0;bytes_received<=0;response_snapshot<=24'hffff00;end
   else if(!reader_reset) begin
    sd_snapshot<=sd_info2;
    response_snapshot<=response_sync2;
    if(byte_valid) bytes_received<=bytes_received+1'b1;
   end
  end
 end
 wire [31:0] debug_codes=auto_mode && load_error!=0 ?
 {4'hC,sd_snapshot[7:4],response_snapshot} :
 {4'hE,load_error!=0 ? load_error : (dma_error ? 4'd8 : 4'd0),
 sd_snapshot[7:4],{1'b0,sd_snapshot[3:1]},
 {3'b0,sd_snapshot[0]},{1'b0,debug_stage},bytes_received[19:12]};
 reg [31:0] debug_codes1,debug_codes2;
 always @(posedge fast) begin
  if(reset) begin debug_codes1<=0;debug_codes2<=0;end
  else begin debug_codes1<=debug_codes;debug_codes2<=debug_codes1;end
 end

 wire wr_en,rd_en,read_valid;
 wire [20:0] wr_addr,rd_addr;
 wire [31:0] wr_data;
 wire [23:0] rgb;wire [1:0] line_valid;wire [8:0] tag0,tag1;
 wire line_request=line_sync[2]^line_sync[1];
 // Claim and clear the old write queue on the SAME edge, so an incomplete
 // failed file cannot block retry or launch an obsolete write during retry.
 frame_store store(core,core_reset,catalog_clear || music_start || (music_claim ? music_clear : clear_load),
 !catalog_claim && (music_claim ? music_word_valid : pixel_valid),
 music_claim ? music_word_addr : pixel_addr,music_claim ? music_word_data : pixel_data,
 throttle,drained,write_overflow,line_request,line_number_sync2,front_bank,
 {y[0],x},phase==1,fast,rgb,line_valid,tag0,tag1,dma_error,
 init_done,refresh,busy,wr_en,wr_addr,wr_data,rd_en,rd_addr,read_valid,read_data,
 audio_request,audio_address,audio_accept,audio_valid,write_idle,
 wipe_active,wipe_reverse,wipe_boundary);
 wire memory_clk,ras_n,cas_n,we_n;wire [1:0] ba;wire [10:0] addr;
 wire [3:0] dm;wire [31:0] dq;
 sdr_as_ram #(.self_refresh_open(1)) memory_controller(
 .Sdr_clk(core),.Sdr_clk_sft(shifted),.Rst(core_reset),.Sdr_init_done(init_done),
 .Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_ref_req(1'b0),
 .App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_dm(4'b0),.App_wr_din(wr_data),
 .App_rd_en(rd_en),.App_rd_addr(rd_addr),.Sdr_rd_en(read_valid),.Sdr_rd_dout(read_data),
 .SDRAM_CLK(memory_clk),.SDR_RAS(ras_n),.SDR_CAS(cas_n),.SDR_WE(we_n),
 .SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(dm),.SDR_DQ(dq));
 EG_PHY_SDRAM_2M_32 memory(.clk(memory_clk),.ras_n(ras_n),.cas_n(cas_n),
 .we_n(we_n),.addr(addr),.ba(ba),.dq(dq),.cs_n(1'b0),
 .dm0(dm[0]),.dm1(dm[1]),.dm2(dm[2]),.dm3(dm[3]),.cke(1'b1));

 reg active_q,hs_q,vs_q,picture_q,status_q;reg [23:0] diagnostic;
 wire status_lit;
 status_display screen_status(x,y,debug_codes2,status_lit);
 // Bundled line metadata is held stable during display; valid rises only
 // after the last RAM write. Two sampling stages precede pixel selection.
 reg [25:0] video_metadata_core;
 reg loading_status;
 always @(posedge core) begin
  if(core_reset) begin video_metadata_core<=0;loading_status<=0;end
  else begin video_metadata_core<={front_valid,loading,load_error,line_valid,tag1,tag0};loading_status<=loading;end
 end
 always @(posedge fast) begin
  if(reset) begin video_meta1<=0;video_meta2<=0;end
  else begin
   video_meta1<=video_metadata_core;
   video_meta2<=video_meta1;
  end
 end
 always @(posedge fast) begin
  if(reset) begin phase<=0;x<=0;y<=0;active_q<=0;hs_q<=1;vs_q<=1;picture_q<=0;status_q<=0;diagnostic<=0;end
  else begin
   phase<=phase==4 ? 0 : phase+1'b1;
   if(phase==0) begin
    // Startup uses readable work status; retain numeric diagnostics for errors.
    status_q<=1'b0; // V19 shows compact readable notices, preserving the full picture.
    active_q<=x<640 && y<480;hs_q<=!(x>=656 && x<752);vs_q<=!(y>=490 && y<492);
    picture_q<=video_meta2[25] && (y[0] ? video_meta2[19] : video_meta2[18]) &&
                  ((y[0] ? video_meta2[17:9] : video_meta2[8:0])==y[8:0]);
    // Diagnostic screen only before a frame is ready or on a missing line.
    diagnostic<=video_meta2[23:20]!=0 ? {8'h90,4'b0,video_meta2[23:20],8'h00} :
                 video_meta2[24] ? {8'h00,x[7:0],y[7:0]} : 24'h001040;
    if(x==799) begin x<=0;y<=y==524 ? 0 : y+1'b1;end
    else x<=x+1'b1;
   end
  end
 end
 wire overlay_panel,overlay_ink,overlay_logo;wire [23:0] overlay_color;
 // Bundled settings settle through two stages. Picture and OSD take the
 // same snapshot in vertical blank, so labels match the whole next frame.
 reg [19:0] settings_core,settings_sync1,settings_sync2;
 always @(posedge core)
  if(core_reset) settings_core<=20'h22004;
  else settings_core<={audio_state,volume_muted,volume_level,wave_visible,adjust_mode,parameter_select,brightness,contrast};
 reg wave_frame;
 reg signed [3:0] brightness_frame;
 reg [3:0] contrast_frame;
 always @(posedge fast) begin
  if(reset) begin
   settings_sync1<=20'h22004;settings_sync2<=20'h22004;brightness_frame<=0;contrast_frame<=4;wave_frame<=0;
  end else begin
   settings_sync1<=settings_core;
   settings_sync2<=settings_sync1;
   if(phase==0 && x==0 && y==480) begin
    brightness_frame<=settings_sync2[7:4];contrast_frame<=settings_sync2[3:0];
    wave_frame<=settings_sync2[11];
   end
  end
 end
 // Stable stage/target information; the overlay synchronizes then latches at vblank.
 wire [2:0] work_stage=load_error!=0 ? 3'd6 : (!init_done || catalog_claim) ? 3'd1 :
  music_claim ? 3'd2 : music_verify ? 3'd3 :
  (transition_busy || debug_stage==4) ? 3'd5 : image_loading ? 3'd4 :
  request_pending ? 3'd7 : 3'd0;
 reg [12:0] work_info;
 always @(posedge core)
  if(core_reset) work_info<=13'd1024;
  else work_info<={work_stage,requested,request_pending,pending_target,load_song_index};
 video_overlay overlay(fast,reset,phase,x,y,selected,auto_mode,loading_status,front_valid,settings_sync2,work_info,playback_ready,recovery_info,
                        overlay_panel,overlay_ink,overlay_logo,overlay_color);
 // Row selection composes the wipe before the existing display pipeline.
 // Keep RAM phase 1, contrast 2, clamp 3, capture 4, output 0, TMDS 1.
 // There is no frame-wide fade or brightness dip during a transition.
 reg [23:0] picture_sample,picture_rgb;
 wire [23:0] adjusted_rgb;
 picture_adjust transfer(fast,reset,phase,rgb,brightness_frame,contrast_frame,adjusted_rgb);
 always @(posedge fast) begin
  if(reset) begin picture_sample<=0;picture_rgb<=0;end
  else begin
   if(phase==4) picture_sample<=adjusted_rgb;
   if(phase==0) picture_rgb<=picture_sample;
  end
 end
 // Status remains visible during startup as well as over a loaded picture.
 wire [23:0] base_rgb=picture_q ? picture_rgb : diagnostic;
 wire [23:0] dim_rgb={1'b0,base_rgb[23:17],1'b0,base_rgb[15:9],1'b0,base_rgb[7:1]};
 wire visual_ce,visual_panel,visual_ink;
 wire signed [15:0] visual_left,visual_right;
 wire [23:0] visual_color;
 audio_visualizer visualizer(fast,reset,phase,x,y,visual_ce,visual_left,visual_right,wave_frame,
  visual_panel,visual_ink,visual_color);
 wire [23:0] visual_rgb=(visual_panel && picture_q) ? (visual_ink ? visual_color : dim_rgb) : base_rgb;
 wire [23:0] layered_rgb=overlay_panel ?
  ((overlay_ink || overlay_logo) ? overlay_color : dim_rgb) : visual_rgb;
 wire [23:0] output_rgb=status_q ? 24'hffffff : layered_rgb;
 wire [9:0] symbols[0:2];
 wire audio_packet_fault;wire av_override;wire [29:0] av_symbols;
 hdmi_audio_bridge av(fast,reset,phase,x,y,hs_q,vs_q,output_pcm,sample_toggle,
  audio_packet_fault,av_override,av_symbols,visual_ce,visual_left,visual_right);
 tmds_encode enc_b(fast,reset,phase,output_rgb[7:0],active_q,{vs_q,hs_q},symbols[0]);
 tmds_encode enc_g(fast,reset,phase,output_rgb[15:8],active_q,2'b00,symbols[1]);
 tmds_encode enc_r(fast,reset,phase,output_rgb[23:16],active_q,2'b00,symbols[2]);
 genvar lane;
 generate for(lane=0;lane<3;lane=lane+1) begin:data_lanes
  tmds_serialize ser(fast,reset,phase,av_override ? av_symbols[lane*10+:10] : symbols[lane],hdmi_p[lane]);
 end endgenerate
 tmds_serialize ser_clk(fast,reset,phase,10'b1111100000,hdmi_clk_p);
 assign led={recovery_info[14] || load_error!=0 || dma_error || audio_underrun || audio_packet_fault,auto_mode,loading,init_done};
endmodule
