// Actual HDMI PCM samples, 48 samples per 1ms min/max column.
// 512 columns show the last 512ms, oldest at left and newest at right.
// Copy after a bin completes in vertical blank: 513 clocks (4.104us).
// The next history write is 1ms later, so the displayed snapshot is stable.
module audio_visualizer(input clk,input reset,input [2:0] phase,
 input [9:0] x,y,input sample_ce,
 input signed [15:0] sample_left,input signed [15:0] sample_right,
 input visible,
 output reg panel_q,ink_q,output reg [23:0] color_q);
 wire frame_blank=phase==0 && x==0 && y==480;
 // Register the sample strobe and its matching values together. This
 // separates HDMI rate-accumulator arithmetic from the peak-meter path.
 // Visualization is delayed by one 125 MHz clock; HDMI audio is unchanged.
 reg sample_ce_q;
 reg signed [6:0] left_level,right_level;
 always @(posedge clk) begin
  if(reset) begin sample_ce_q<=0;left_level<=0;right_level<=0;end
  else begin
   sample_ce_q<=sample_ce;
   if(sample_ce) begin left_level<=sample_left[15:9];right_level<=sample_right[15:9];end
  end
 end
 wire [6:0] left_abs=left_level[6] ? -left_level : left_level;
 wire [6:0] right_abs=right_level[6] ? -right_level : right_level;
 wire [6:0] sample_peak=left_abs>right_abs ? left_abs : right_abs;
 reg [5:0] bin_samples;
 reg signed [6:0] bin_min,bin_max;
 wire signed [6:0] next_min=(bin_samples==0 || left_level<bin_min) ? left_level : bin_min;
 wire signed [6:0] next_max=(bin_samples==0 || left_level>bin_max) ? left_level : bin_max;
 wire bin_complete=sample_ce_q && bin_samples==6'd47;
 function [7:0] plot_position;
 input signed [6:0] amplitude;
 begin plot_position=8'd128-{1'b0,~amplitude[6],amplitude[5:0]};end
 endfunction
 reg [15:0] history[0:511];
 reg [8:0] write_ptr;
 reg [9:0] history_count;
 always @(posedge clk) begin
  if(reset) begin
   bin_samples<=0;bin_min<=0;bin_max<=0;write_ptr<=0;history_count<=0;
  end else if(sample_ce_q) begin
   if(bin_samples==6'd47) begin
    history[write_ptr]<={plot_position(next_max),plot_position(next_min)};
    write_ptr<=write_ptr+1'b1;
    if(history_count<10'd512) history_count<=history_count+1'b1;
    bin_samples<=0;bin_min<=0;bin_max<=0;
   end else begin
    bin_samples<=bin_samples+1'b1;bin_min<=next_min;bin_max<=next_max;
   end
  end
 end

 // Frame peak uses both channels. Fast attack and a two-step/frame release.
 reg [6:0] frame_peak,meter_level;
 wire [6:0] peak_including_sample=sample_ce_q && sample_peak>frame_peak ? sample_peak : frame_peak;
 wire [6:0] released_level=meter_level>7'd2 ? meter_level-7'd2 : 7'd0;
 always @(posedge clk) begin
  if(reset) begin frame_peak<=0;meter_level<=0;end
  else if(frame_blank) begin
   meter_level<=peak_including_sample>released_level ? peak_including_sample : released_level;
   frame_peak<=0;
  end else if(sample_ce_q) frame_peak<=peak_including_sample;
 end

 // Two small on-chip memories keep capture independent of SDRAM/TF access.
 // Unfilled history is copied as silence; neither RAM needs power-up data.
 reg [15:0] display_history[0:511];
 reg snapshot_requested,copy_running,copy_pending,copy_valid,display_ready;
 reg [8:0] snapshot_head,copy_index,copy_destination;
 reg [9:0] snapshot_padding;
 reg [15:0] history_read;
 wire [8:0] copy_address=snapshot_head+copy_index;
 always @(posedge clk) begin
  if(reset) begin
   snapshot_requested<=0;copy_running<=0;copy_pending<=0;copy_valid<=0;
   display_ready<=0;snapshot_head<=0;copy_index<=0;copy_destination<=0;
   snapshot_padding<=512;
  end else begin
   copy_pending<=copy_running;
   if(frame_blank) snapshot_requested<=1;
   if(bin_complete && snapshot_requested && !copy_running && !copy_pending) begin
    snapshot_requested<=0;copy_running<=1;copy_index<=0;
    snapshot_head<=write_ptr+1'b1;
    snapshot_padding<=history_count==10'd512 ? 10'd0 : 10'd511-history_count;
   end
   if(copy_running) begin
    history_read<=history[copy_address];
    copy_valid<={1'b0,copy_index}>=snapshot_padding;
    copy_destination<=copy_index;
    if(copy_index==9'd511) copy_running<=0;
    else copy_index<=copy_index+1'b1;
   end
   if(copy_pending) begin
    display_history[copy_destination]<=copy_valid ? history_read : 16'h4040;
    if(copy_destination==9'd511) display_ready<=1;
   end
  end
 end

 // Coordinate/RAM at 1, waveform comparisons/font at 2, header bit at 3,
 // output at 0, matching the existing picture and subtitle pipeline.
 wire [9:0] plot_x=x-10'd64;
 wire [9:0] header_y=y-10'd280;
 wire [9:0] meter_width={meter_level,3'b0};
 reg [15:0] display_column;
 always @(posedge clk)
  if(phase==1) display_column<=display_history[plot_x[8:0]];
 reg panel_pre,plot_pre,grid_pre,meter_pre,ready_pre,header_pre;
 reg [7:0] plot_y,header_character;
 reg [5:0] header_bit;
 reg [23:0] meter_color;
 function [7:0] header_char;
 input [3:0] index;
 begin case(index)
  0:header_char="P";1:header_char="C";2:header_char="M";
  4:header_char="W";5:header_char="A";6:header_char="V";7:header_char="E";
  11:header_char="4";12:header_char="8";13:header_char="K";
  default:header_char=8'd32;
 endcase end
 endfunction
 always @(posedge clk) begin
  if(reset) begin
   panel_pre<=0;plot_pre<=0;grid_pre<=0;meter_pre<=0;ready_pre<=0;
   header_pre<=0;plot_y<=0;header_character<=32;header_bit<=0;meter_color<=0;
  end else if(phase==1) begin
   // Visibility is frame-latched in the top. Capture remains live while
   // hidden, so revealing the panel shows the newest complete snapshot.
   panel_pre<=visible && x>=48 && x<592 && y>=272 && y<440;
   plot_pre<=x>=64 && x<576 && y>=296 && y<=424;
   plot_y<=y[7:0]-8'd40;
   ready_pre<=display_ready;
   grid_pre<=x>=64 && x<576 && y>=296 && y<=424 &&
             (x[5:0]==0 || y==296 || y==328 || y==360 || y==392 || y==424);
   meter_pre<=x>=64 && x<576 && y>=428 && y<436 && plot_x<meter_width;
   meter_color<=plot_x>=448 ? 24'hff6060 : plot_x>=320 ? 24'hffd050 : 24'h50ff90;
   header_pre<=x>=64 && x<288 && y>=280 && y<296;
   header_character<=header_char(plot_x[7:4]);
   header_bit<={header_y[3:1],plot_x[3:1]};
  end
 end
 function [63:0] glyph;
 input [7:0] c;
 begin case(c)
  "A":glyph=64'h0000111f110a0a04;
  "C":glyph=64'h00001e030101031e;
  "E":glyph=64'h00001e02021e021e;
  "K":glyph=64'h0000120a06060a12;
  "M":glyph=64'h00002121252d2a12;
  "P":glyph=64'h000002020e12120e;
  "V":glyph=64'h0000081414222222;
  "W":glyph=64'h000022322e2a2222;
  "4":glyph=64'h0000081f090a0c0c;
  "8":glyph=64'h00000e12120c121e;
  default:glyph=0;
 endcase end
 endfunction
 reg wave_ink,grid_ink,meter_ink,header_ink;
 reg [63:0] header_bitmap;
 always @(posedge clk) begin
  if(reset) begin wave_ink<=0;grid_ink<=0;meter_ink<=0;header_ink<=0;header_bitmap<=0;end
  else begin
   if(phase==2) begin
    wave_ink<=plot_pre && (ready_pre ?
      (plot_y>=display_column[15:8] && plot_y<=display_column[7:0]) : plot_y==8'd64);
    grid_ink<=grid_pre;meter_ink<=meter_pre;header_bitmap<=glyph(header_character);
   end
   if(phase==3) header_ink<=header_pre && header_bitmap[header_bit];
  end
 end
 always @(posedge clk) begin
  if(reset) begin panel_q<=0;ink_q<=0;color_q<=0;end
  else if(phase==0) begin
   panel_q<=panel_pre;ink_q<=header_ink || wave_ink || grid_ink || meter_ink;
   color_q<=header_ink ? 24'hd0e8ff : wave_ink ? 24'h50ffe0 :
            meter_ink ? meter_color : 24'h385568;
  end
 end
endmodule
