// V20 isolated video experiment. V19 remains in the board's Flash.
module competition(input clk,input [3:0] key_n,input [3:0] sw,input sd_miso,
 output sd_cs,output sd_clk,output sd_mosi,
 output [2:0] hdmi_p,output hdmi_clk_p,output [3:0] led);
 wire [4:0] clocks;wire locked,fast,feedback,core;
 EG_LOGIC_BUFG clock_buffer(.i(clocks[1]),.o(fast));
 EG_LOGIC_BUFG feedback_buffer(.i(clocks[0]),.o(feedback));
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
 reg [3:0] reset_pipe=15,core_reset_pipe=15;
 always @(posedge fast or negedge locked)
  if(!locked) reset_pipe<=15;else reset_pipe<={reset_pipe[2:0],1'b0};
 always @(posedge core or negedge locked)
  if(!locked) core_reset_pipe<=15;else core_reset_pipe<={core_reset_pipe[2:0],1'b0};
 wire reset=reset_pipe[3],core_reset=core_reset_pipe[3];
 wire [3:0] pressed,held,video_keys,switch_state;
 wire adjust_mode,wave_visible,volume_muted;wire [1:0] parameter_select;
 wire [4:0] volume_level;wire signed [3:0] brightness;wire [3:0] contrast;
 wire [3:0] movie_error;
 key_controls controls(core,core_reset,key_n,pressed,held);
 key_controls switch_inputs(core,core_reset,~sw,,switch_state);
 display_controls settings(core,core_reset,pressed,held,switch_state,movie_error!=0,video_keys,
  adjust_mode,parameter_select,brightness,contrast,wave_visible,volume_level,volume_muted);

 reg [2:0] phase;reg [9:0] x,y;
 reg vblank_toggle;reg [2:0] vblank_sync;
 always @(posedge fast) begin
  if(reset) vblank_toggle<=0;
  else if(phase==0 && x==0 && y==480) vblank_toggle<=~vblank_toggle;
 end
 always @(posedge core)
  if(core_reset) vblank_sync<=0;else vblank_sync<={vblank_sync[1:0],vblank_toggle};
 wire vblank=vblank_sync[2]^vblank_sync[1];
 wire reader_reset,clip_index,front_bank,front_valid,parser_ready;
 wire pixel_we,palette_we,write_bank,loading,finished;
 wire [13:0] pixel_address;wire [7:0] pixel_data,palette_address;
 wire [23:0] palette_data;
 wire [31:0] music_pcm,output_pcm,played_samples,shown_frames;
 wire sample_toggle,audio_underrun,audio_overflow;wire [4:0] debug_state;
 reg [1:0] sd_reset_sync=3;
 always @(posedge feedback or posedge reset)
  if(reset) sd_reset_sync<=3;else sd_reset_sync<={sd_reset_sync[0],reader_reset};
 wire sd_reset=sd_reset_sync[1];
 wire [7:0] file_digit=clip_index ? 8'd50 : 8'd49;
 wire [415:0] filename={"VIDEO0",file_digit,".FPV"};
 wire [1:0] card_type,fs_type;wire [3:0] card_status;wire [2:0] fs_status;
 wire file_found,sd_byte_valid,sd_pause;wire [7:0] sd_byte;wire [23:0] sd_session;
 sd_spi_file_reader #(.FILE_NAME_LEN(11),.SPI_CLK_DIV(49)) reader(
  .rstn(!sd_reset),.clk(feedback),.pause(sd_pause),.requested_name(filename),
  .spi_ssn(sd_cs),.spi_sck(sd_clk),.spi_mosi(sd_mosi),.spi_miso(sd_miso),
  .card_type(card_type),.card_stat(card_status),.debug_session(sd_session),.filesystem_type(fs_type),
  .filesystem_stat(fs_status),.file_found(file_found),.outen(sd_byte_valid),.outbyte(sd_byte));
 wire byte_full,byte_empty,byte_overflow;wire [7:0] byte_data;reg byte_valid;
 wire pop_byte=!byte_empty && parser_ready && !byte_valid && !reader_reset;
 always @(posedge core)
  if(core_reset || reader_reset) byte_valid<=0;else byte_valid<=pop_byte;
 async_bytes byte_queue(feedback,sd_reset,sd_byte_valid&&!sd_pause,sd_byte,byte_full,byte_overflow,
  core,core_reset||reader_reset,pop_byte,byte_data,byte_empty,sd_pause);
 reg [1:0] overflow_sync,found_sync,fsdone_sync;
 always @(posedge core) begin
  if(core_reset || reader_reset) begin overflow_sync<=0;found_sync<=0;fsdone_sync<=0;end
  else begin
   overflow_sync<={overflow_sync[0],byte_overflow};found_sync<={found_sync[0],file_found};
   fsdone_sync<={fsdone_sync[0],fs_status==6};
  end
 end
 movie_stream movie(core,core_reset,video_keys,switch_state[0],vblank,
  byte_valid,byte_data,parser_ready,reader_reset,fsdone_sync[1],found_sync[1],byte_empty,overflow_sync[1],sample_toggle,
  clip_index,front_bank,front_valid,pixel_we,palette_we,write_bank,pixel_address,pixel_data,palette_address,palette_data,
  music_pcm,loading,finished,movie_error,audio_underrun,audio_overflow,played_samples,shown_frames,debug_state);
 audio_volume volume(core,core_reset,sample_toggle,music_pcm,volume_level,volume_muted,output_pcm);

 reg [1:0] front_meta1,front_meta2;
 always @(posedge fast) begin
  if(reset) begin front_meta1<=0;front_meta2<=0;end
  else begin front_meta1<={front_valid,front_bank};front_meta2<=front_meta1;end
 end
 // Prepare the next raster coordinate at phase 0. Palette read is phase 1;
 // RGB register 2, contrast 3, offset 4, output on the following phase 0.
 wire [9:0] next_x=x==799 ? 10'd0 : x+1'b1;
 wire [9:0] next_y=x==799 ? (y==524 ? 10'd0 : y+1'b1) : y;
 // Compute addresses during the four intervening serializer ticks. This
 // removes the raster increment/subtract/multiply/RAM cascade from 125 MHz.
 reg [9:0] fetch_x,fetch_y;
 reg [6:0] fetch_row;reg [7:0] fetch_column;reg fetch_active;
 reg [13:0] row_base,display_address;
 always @(posedge fast) begin
  if(reset) begin fetch_x<=0;fetch_y<=0;fetch_row<=0;fetch_column<=0;fetch_active<=0;row_base<=0;display_address<=0;end
  else begin
   if(phase==1) begin fetch_x<=next_x;fetch_y<=next_y;end
   if(phase==2) begin
    fetch_row<=(fetch_y-10'd60)>>2;fetch_column<=fetch_x[9:2];
    fetch_active<=fetch_x<640 && fetch_y>=60 && fetch_y<420;
   end
   if(phase==3) row_base<=({7'd0,fetch_row}<<7)+({7'd0,fetch_row}<<5);
   if(phase==4) display_address<=fetch_active ? row_base+{6'd0,fetch_column} : 14'd0;
  end
 end
 wire [23:0] rgb;
 movie_framebuffer frames(core,pixel_we,palette_we,write_bank,pixel_address,pixel_data,
  palette_address,palette_data,fast,phase,front_meta2[0],display_address,rgb);
 reg active_q,hs_q,vs_q,picture_q;
 always @(posedge fast) begin
  if(reset) begin phase<=0;x<=0;y<=0;active_q<=0;hs_q<=1;vs_q<=1;picture_q<=0;end
  else begin
   phase<=phase==4 ? 0 : phase+1'b1;
   if(phase==0) begin
    active_q<=x<640 && y<480;hs_q<=!(x>=656 && x<752);vs_q<=!(y>=490 && y<492);
    picture_q<=front_meta2[1] && x<640 && y>=60 && y<420;
    x<=next_x;y<=next_y;
   end
  end
 end
 wire [1:0] audio_state=movie_error!=0 ? 2'd3 : front_valid && !finished ? 2'd2 : 2'd0;
 reg [19:0] settings_core,settings_sync1,settings_sync2;
 always @(posedge core)
  if(core_reset) settings_core<=20'h22004;
  else settings_core<={audio_state,volume_muted,volume_level,wave_visible,adjust_mode,parameter_select,brightness,contrast};
 reg wave_frame;reg signed [3:0] brightness_frame;reg [3:0] contrast_frame;
 always @(posedge fast) begin
  if(reset) begin
   settings_sync1<=20'h22004;settings_sync2<=20'h22004;brightness_frame<=0;contrast_frame<=4;wave_frame<=0;
  end else begin
   settings_sync1<=settings_core;settings_sync2<=settings_sync1;
   if(phase==0 && x==0 && y==480) begin
    brightness_frame<=settings_sync2[7:4];contrast_frame<=settings_sync2[3:0];wave_frame<=settings_sync2[11];
   end
  end
 end
 wire overlay_panel,overlay_ink,overlay_logo;wire [23:0] overlay_color;
 // V20 overlay reuses the proven text renderer, with video-specific fault labels.
 wire [2:0] work_stage=movie_error!=0 ? 3'd6 : loading ? 3'd1 : finished ? 3'd7 : 3'd0;
 wire [12:0] work_info={work_stage,2'b0,clip_index,1'b0,3'b0,2'b0,clip_index};
 wire [14:0] fault_info={movie_error!=0,10'b0,movie_error};
 video_overlay overlay(fast,reset,phase,x,y,{2'b0,clip_index},switch_state[0],loading,front_valid,
  settings_sync2,work_info,front_valid&&!finished,fault_info,overlay_panel,overlay_ink,overlay_logo,overlay_color);
 wire [23:0] adjusted_rgb;reg [23:0] palette_rgb,picture_rgb;
 picture_adjust transfer(fast,reset,phase,palette_rgb,brightness_frame,contrast_frame,adjusted_rgb);
 always @(posedge fast) begin
  if(reset) begin palette_rgb<=0;picture_rgb<=0;end
  else begin
   if(phase==2) palette_rgb<=rgb;
   if(phase==0) picture_rgb<=adjusted_rgb;
  end
 end
 wire [23:0] base_rgb=picture_q ? picture_rgb : 24'h001020;
 wire [23:0] dim_rgb={1'b0,base_rgb[23:17],1'b0,base_rgb[15:9],1'b0,base_rgb[7:1]};
 wire visual_ce,visual_panel,visual_ink;wire signed [15:0] visual_left,visual_right;
 wire [23:0] visual_color;
 audio_visualizer visualizer(fast,reset,phase,x,y,visual_ce,visual_left,visual_right,wave_frame,
  visual_panel,visual_ink,visual_color);
 wire [23:0] visual_rgb=visual_panel ? (visual_ink ? visual_color : dim_rgb) : base_rgb;
 wire [23:0] output_rgb=overlay_panel ? ((overlay_ink || overlay_logo) ? overlay_color : dim_rgb) : visual_rgb;
 wire [9:0] symbols[0:2];wire audio_packet_fault,av_override;wire [29:0] av_symbols;
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
 assign led={movie_error!=0 || audio_underrun || audio_overflow || audio_packet_fault,switch_state[0],loading,front_valid};
endmodule
