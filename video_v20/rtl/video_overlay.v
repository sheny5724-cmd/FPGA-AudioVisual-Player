// V20 video experiment: compact status and on-demand settings.
module video_overlay(input clk,reset,input [2:0] phase,input [9:0] x,y,
 input [2:0] selected,input auto_mode,loading,front_valid,input [19:0] settings,input [12:0] work_info,input playback_ready,input [14:0] recovery_info,
 output reg panel_q,ink_q,logo_q,output reg [23:0] ink_color_q);
 reg [5:0] meta1,meta2,display_meta;
 reg [14:0] fault_s1,fault_s2,display_fault;
 reg [19:0] display_settings;
 reg [12:0] work_sync1,work_sync2,display_work;
 reg playing_s1,playing_s2,display_playing;
 reg [26:0] ticks;
 reg [3:0] mt,mu,st,su;reg [15:0] time_display;
 reg [9:0] scroll;reg [1:0] scroll_div;
 always @(posedge clk) begin
  if(reset) begin
   fault_s1<=0;fault_s2<=0;display_fault<=0;
   work_sync1<=13'd1024;work_sync2<=13'd1024;display_work<=13'd1024;
   playing_s1<=0;playing_s2<=0;display_playing<=0;
   meta1<=0;meta2<=0;display_meta<=0;display_settings<=20'h22004;ticks<=0;
   mt<=0;mu<=0;st<=0;su<=0;time_display<=0;scroll<=0;scroll_div<=0;
  end else begin
   fault_s1<=recovery_info;fault_s2<=fault_s1;
   meta1<={selected,auto_mode,loading,front_valid};meta2<=meta1;
   work_sync1<=work_info;work_sync2<=work_sync1;
   playing_s1<=playback_ready;playing_s2<=playing_s1;
   if(ticks==27'd124999999) begin
    ticks<=0;
    if(su==9) begin su<=0;
     if(st==5) begin st<=0;
      if(mu==9) begin mu<=0;mt<=mt==9 ? 0 : mt+1'b1;end
      else mu<=mu+1'b1;
     end else st<=st+1'b1;
    end else su<=su+1'b1;
   end else ticks<=ticks+1'b1;
   if(phase==0 && x==0 && y==480) begin
    display_fault<=fault_s2;display_playing<=playing_s2;display_work<=work_sync2;display_meta<=meta2;display_settings<=settings;time_display<={mt,mu,st,su};scroll_div<=scroll_div+1'b1;
    if(scroll_div==3) scroll<=scroll+1'b1;
   end
  end
 end
 wire [2:0] activity=display_work[12:10];
 wire work_visible=activity!=0 || display_fault[14];
 wire [7:0] picture_digit=8'd49+{5'b0,display_work[9:7]};
 wire [7:0] pending_digit=8'd49+{5'b0,display_work[5:3]};
 wire [7:0] song_digit=8'd49+{5'b0,display_work[2:0]};
 wire set_mode=display_settings[10];
 wire [1:0] chosen=display_settings[9:8];
 wire top_panel=y>=8 && y<40;
 wire parameter_panel=set_mode && y>=40 && y<72;
 wire bottom_panel=y>=440 && y<472;
 wire fixed_text=top_panel || parameter_panel || (bottom_panel && work_visible);
 wire [9:0] scroll_x=x+scroll,top_x=x-16;
 reg [5:0] index;reg [2:0] column,row;
 reg [1:0] row_id;
 reg text_row,panel_pre;reg [23:0] color_pre;
 wire chosen_field=(chosen==0 && top_x[9:4]<=6) ||
                   (chosen==1 && top_x[9:4]>=8 && top_x[9:4]<=15) ||
                   (chosen==2 && top_x[9:4]>=17 && top_x[9:4]<=24);
 always @(posedge clk) begin
  if(reset) begin
   index<=0;column<=0;row<=0;row_id<=0;text_row<=0;panel_pre<=0;color_pre<=0;
  end else if(phase==1) begin
   index<=fixed_text ? top_x[9:4] : scroll_x[9:4];
   column<=fixed_text ? top_x[3:1] : scroll_x[3:1];row<=y[3:1];
   row_id<=top_panel ? 0 : parameter_panel ? 1 : work_visible ? 3 : set_mode ? 2 : 3;
   text_row<=(top_panel && y>=16 && y<32 && x>=16) ||
             (parameter_panel && y>=48 && y<64 && x>=16) ||
             (bottom_panel && y>=448 && y<464 && (!work_visible || x>=16));
   panel_pre<=(top_panel || parameter_panel || bottom_panel) && x<640;
   color_pre<=(bottom_panel && work_visible) ? ((activity==6 || display_fault[14]) ? 24'hff8080 : 24'hffcc40) : parameter_panel ? (chosen_field ? 24'hffcc40 : 24'hd0e8ff) :
               display_meta[1] ? 24'hffcc40 : display_meta[2] ? 24'h40ff90 : 24'h70d8ff;
  end
 end
 wire [3:0] brightness_abs=display_settings[7] ? -display_settings[7:4] : display_settings[7:4];
 reg [7:0] brightness_bcd;reg [11:0] contrast_bcd,volume_digits;
 always @* begin
  case(brightness_abs)
   1:brightness_bcd=8'h16;2:brightness_bcd=8'h32;3:brightness_bcd=8'h48;4:brightness_bcd=8'h64;
   default:brightness_bcd=0;
  endcase
  case(display_settings[3:0])
   2:contrast_bcd=12'h050;3:contrast_bcd=12'h075;5:contrast_bcd=12'h125;6:contrast_bcd=12'h150;
   default:contrast_bcd=12'h100;
  endcase
  case(display_settings[16:12])
  5'd0:volume_digits=12'h000;
  5'd1:volume_digits=12'h005;
  5'd2:volume_digits=12'h010;
  5'd3:volume_digits=12'h015;
  5'd4:volume_digits=12'h020;
  5'd5:volume_digits=12'h025;
  5'd6:volume_digits=12'h030;
  5'd7:volume_digits=12'h035;
  5'd8:volume_digits=12'h040;
  5'd9:volume_digits=12'h045;
  5'd10:volume_digits=12'h050;
  5'd11:volume_digits=12'h055;
  5'd12:volume_digits=12'h060;
  5'd13:volume_digits=12'h065;
  5'd14:volume_digits=12'h070;
  5'd15:volume_digits=12'h075;
  5'd16:volume_digits=12'h080;
  5'd17:volume_digits=12'h085;
  5'd18:volume_digits=12'h090;
  5'd19:volume_digits=12'h095;
  5'd20:volume_digits=12'h100;
   default:volume_digits=0;
  endcase
 end
 wire [1:0] audio_state=display_settings[19:18];
 wire muted=display_settings[17];
 reg [7:0] character_0;
 always @* begin
  case(index)
   6'd0:character_0=70;
   6'd1:character_0=80;
   6'd2:character_0=71;
   6'd3:character_0=65;
   6'd4:character_0=32;
   6'd5:character_0=86;
   6'd6:character_0=50;
   6'd7:character_0=48;
   6'd8:character_0=32;
   6'd9:character_0=86;
   6'd10:character_0=73;
   6'd11:character_0=68;
   6'd12:character_0=32;
   6'd13:character_0=8'd49+{5'b0,display_meta[5:3]};
   6'd14:character_0=32;
   6'd15:character_0=display_meta[2] ? 8'd65 : 8'd77;
   6'd16:character_0=display_meta[2] ? 8'd85 : 8'd65;
   6'd17:character_0=display_meta[2] ? 8'd84 : 8'd78;
   6'd18:character_0=32;
   6'd19:character_0=8'd48+time_display[15:12];
   6'd20:character_0=8'd48+time_display[11:8];
   6'd21:character_0=58;
   6'd22:character_0=8'd48+time_display[7:4];
   6'd23:character_0=8'd48+time_display[3:0];
   6'd24:character_0=32;
   6'd25:character_0=86;
   6'd26:character_0=8'd48+volume_digits[11:8];
   6'd27:character_0=8'd48+volume_digits[7:4];
   6'd28:character_0=8'd48+volume_digits[3:0];
   6'd29:character_0=37;
   6'd30:character_0=32;
   6'd31:character_0=audio_state==3 ? 8'd70 : audio_state!=2 ? 8'd87 : muted ? 8'd77 : 8'd80;
   6'd32:character_0=audio_state==3 ? 8'd65 : audio_state!=2 ? 8'd65 : muted ? 8'd85 : 8'd76;
   6'd33:character_0=audio_state==3 ? 8'd73 : audio_state!=2 ? 8'd73 : muted ? 8'd84 : 8'd65;
   6'd34:character_0=audio_state==3 ? 8'd76 : audio_state!=2 ? 8'd84 : muted ? 8'd69 : 8'd89;
   default:character_0=32;
  endcase
 end
 reg [7:0] character_1;
 always @* begin
  case(index)
   6'd0:character_1=66;
   6'd1:character_1=82;
   6'd2:character_1=84;
   6'd3:character_1=chosen==0 ? 8'd62 : 8'd32;
   6'd4:character_1=display_settings[7] ? 8'd45 : 8'd43;
   6'd5:character_1=8'd48+brightness_bcd[7:4];
   6'd6:character_1=8'd48+brightness_bcd[3:0];
   6'd7:character_1=32;
   6'd8:character_1=67;
   6'd9:character_1=79;
   6'd10:character_1=78;
   6'd11:character_1=chosen==1 ? 8'd62 : 8'd32;
   6'd12:character_1=8'd48+contrast_bcd[11:8];
   6'd13:character_1=8'd48+contrast_bcd[7:4];
   6'd14:character_1=8'd48+contrast_bcd[3:0];
   6'd15:character_1=37;
   6'd16:character_1=32;
   6'd17:character_1=86;
   6'd18:character_1=79;
   6'd19:character_1=76;
   6'd20:character_1=chosen==2 ? 8'd62 : 8'd32;
   6'd21:character_1=8'd48+volume_digits[11:8];
   6'd22:character_1=8'd48+volume_digits[7:4];
   6'd23:character_1=8'd48+volume_digits[3:0];
   6'd24:character_1=37;
   6'd25:character_1=32;
   6'd26:character_1=83;
   6'd27:character_1=87;
   6'd28:character_1=52;
   6'd29:character_1=32;
   6'd30:character_1=69;
   6'd31:character_1=88;
   6'd32:character_1=73;
   6'd33:character_1=84;
   default:character_1=32;
  endcase
 end
 reg [7:0] character_2;
 always @* begin
  case(index)
   6'd0:character_2=32;
   6'd1:character_2=83;
   6'd2:character_2=69;
   6'd3:character_2=84;
   6'd4:character_2=32;
   6'd5:character_2=75;
   6'd6:character_2=49;
   6'd7:character_2=32;
   6'd8:character_2=43;
   6'd9:character_2=32;
   6'd10:character_2=75;
   6'd11:character_2=50;
   6'd12:character_2=32;
   6'd13:character_2=45;
   6'd14:character_2=32;
   6'd15:character_2=75;
   6'd16:character_2=51;
   6'd17:character_2=32;
   6'd18:character_2=86;
   6'd19:character_2=79;
   6'd20:character_2=76;
   6'd21:character_2=45;
   6'd22:character_2=66;
   6'd23:character_2=82;
   6'd24:character_2=84;
   6'd25:character_2=45;
   6'd26:character_2=67;
   6'd27:character_2=79;
   6'd28:character_2=78;
   6'd29:character_2=32;
   6'd30:character_2=83;
   6'd31:character_2=87;
   6'd32:character_2=52;
   6'd33:character_2=32;
   6'd34:character_2=69;
   6'd35:character_2=88;
   6'd36:character_2=73;
   6'd37:character_2=84;
   6'd38:character_2=32;
   6'd39:character_2=32;
   6'd40:character_2=69;
   6'd41:character_2=82;
   6'd42:character_2=82;
   6'd43:character_2=79;
   6'd44:character_2=82;
   6'd45:character_2=32;
   6'd46:character_2=75;
   6'd47:character_2=52;
   6'd48:character_2=32;
   6'd49:character_2=82;
   6'd50:character_2=69;
   6'd51:character_2=84;
   6'd52:character_2=82;
   6'd53:character_2=89;
   6'd54:character_2=32;
   default:character_2=32;
  endcase
 end
 reg [7:0] character_3;
 always @* begin
  case(index)
   6'd0:character_3=32;
   6'd1:character_3=75;
   6'd2:character_3=49;
   6'd3:character_3=32;
   6'd4:character_3=78;
   6'd5:character_3=69;
   6'd6:character_3=88;
   6'd7:character_3=84;
   6'd8:character_3=32;
   6'd9:character_3=75;
   6'd10:character_3=50;
   6'd11:character_3=32;
   6'd12:character_3=80;
   6'd13:character_3=82;
   6'd14:character_3=69;
   6'd15:character_3=86;
   6'd16:character_3=32;
   6'd17:character_3=75;
   6'd18:character_3=51;
   6'd19:character_3=45;
   6'd20:character_3=32;
   6'd21:character_3=75;
   6'd22:character_3=52;
   6'd23:character_3=43;
   6'd24:character_3=32;
   6'd25:character_3=83;
   6'd26:character_3=87;
   6'd27:character_3=49;
   6'd28:character_3=32;
   6'd29:character_3=65;
   6'd30:character_3=85;
   6'd31:character_3=84;
   6'd32:character_3=79;
   6'd33:character_3=32;
   6'd34:character_3=83;
   6'd35:character_3=87;
   6'd36:character_3=50;
   6'd37:character_3=32;
   6'd38:character_3=83;
   6'd39:character_3=79;
   6'd40:character_3=85;
   6'd41:character_3=78;
   6'd42:character_3=68;
   6'd43:character_3=32;
   6'd44:character_3=83;
   6'd45:character_3=87;
   6'd46:character_3=51;
   6'd47:character_3=32;
   6'd48:character_3=87;
   6'd49:character_3=65;
   6'd50:character_3=86;
   6'd51:character_3=69;
   6'd52:character_3=32;
   6'd53:character_3=83;
   6'd54:character_3=87;
   6'd55:character_3=52;
   6'd56:character_3=32;
   6'd57:character_3=83;
   6'd58:character_3=69;
   6'd59:character_3=84;
   6'd60:character_3=32;
   default:character_3=32;
  endcase
 end
 reg [7:0] character_work;
 always @* begin
  character_work=32;
  if(index<16) begin
   case(activity)
    3'd1:case(index)
     6'd0:character_work=8'd83;
     6'd1:character_work=8'd84;
     6'd2:character_work=8'd65;
     6'd3:character_work=8'd82;
     6'd4:character_work=8'd84;
     6'd5:character_work=8'd73;
     6'd6:character_work=8'd78;
     6'd7:character_work=8'd71;
     default:character_work=32;
    endcase
    3'd2:case(index)
     6'd0:character_work=(display_playing ? 8'd80 : 8'd76);
     6'd1:character_work=(display_playing ? 8'd82 : 8'd79);
     6'd2:character_work=(display_playing ? 8'd69 : 8'd65);
     6'd3:character_work=(display_playing ? 8'd76 : 8'd68);
     6'd4:character_work=(display_playing ? 8'd79 : 8'd73);
     6'd5:character_work=(display_playing ? 8'd65 : 8'd78);
     6'd6:character_work=(display_playing ? 8'd68 : 8'd71);
     6'd7:character_work=8'd32;
     6'd8:character_work=8'd77;
     6'd9:character_work=8'd85;
     6'd10:character_work=8'd83;
     6'd11:character_work=8'd73;
     6'd12:character_work=8'd67;
     6'd13:character_work=8'd32;
     6'd14:character_work=song_digit;
     default:character_work=32;
    endcase
    3'd3:case(index)
     6'd0:character_work=8'd67;
     6'd1:character_work=8'd72;
     6'd2:character_work=8'd69;
     6'd3:character_work=8'd67;
     6'd4:character_work=8'd75;
     6'd5:character_work=8'd73;
     6'd6:character_work=8'd78;
     6'd7:character_work=8'd71;
     6'd8:character_work=8'd32;
     6'd9:character_work=8'd77;
     6'd10:character_work=8'd85;
     6'd11:character_work=8'd83;
     6'd12:character_work=8'd73;
     6'd13:character_work=8'd67;
     6'd14:character_work=8'd32;
     6'd15:character_work=song_digit;
     default:character_work=32;
    endcase
    3'd4:case(index)
     6'd0:character_work=8'd76;
     6'd1:character_work=8'd79;
     6'd2:character_work=8'd65;
     6'd3:character_work=8'd68;
     6'd4:character_work=8'd73;
     6'd5:character_work=8'd78;
     6'd6:character_work=8'd71;
     6'd7:character_work=8'd32;
     6'd8:character_work=8'd80;
     6'd9:character_work=8'd73;
     6'd10:character_work=8'd67;
     6'd11:character_work=8'd32;
     6'd12:character_work=picture_digit;
     default:character_work=32;
    endcase
    3'd5:case(index)
     6'd0:character_work=8'd83;
     6'd1:character_work=8'd87;
     6'd2:character_work=8'd73;
     6'd3:character_work=8'd84;
     6'd4:character_work=8'd67;
     6'd5:character_work=8'd72;
     6'd6:character_work=8'd73;
     6'd7:character_work=8'd78;
     6'd8:character_work=8'd71;
     6'd9:character_work=8'd32;
     6'd10:character_work=8'd80;
     6'd11:character_work=8'd73;
     6'd12:character_work=8'd67;
     6'd13:character_work=8'd32;
     6'd14:character_work=picture_digit;
     default:character_work=32;
    endcase
    3'd6:case(index)
     6'd0:character_work=8'd69;
     6'd1:character_work=8'd82;
     6'd2:character_work=8'd82;
     6'd3:character_work=8'd79;
     6'd4:character_work=8'd82;
     6'd5:character_work=8'd32;
     6'd6:character_work=8'd45;
     6'd7:character_work=8'd32;
     6'd8:character_work=8'd75;
     6'd9:character_work=8'd52;
     6'd10:character_work=8'd32;
     6'd11:character_work=8'd82;
     6'd12:character_work=8'd69;
     6'd13:character_work=8'd84;
     6'd14:character_work=8'd82;
     6'd15:character_work=8'd89;
     default:character_work=32;
    endcase
    3'd7:case(index)
     6'd0:character_work=8'd69;
     6'd1:character_work=8'd78;
     6'd2:character_work=8'd68;
     6'd3:character_work=8'd69;
     6'd4:character_work=8'd68;
     6'd5:character_work=8'd32;
     6'd6:character_work=8'd45;
     6'd7:character_work=8'd32;
     6'd8:character_work=8'd75;
     6'd9:character_work=8'd49;
     6'd10:character_work=8'd32;
     6'd11:character_work=8'd78;
     6'd12:character_work=8'd69;
     6'd13:character_work=8'd88;
     6'd14:character_work=8'd84;
     default:character_work=32;
    endcase
    default:character_work=32;
   endcase
  end else if(index>=17 && index<=19) begin
   if(activity!=6 && activity!=7 && {4'd0,scroll[3:2]}>(index-6'd17)) character_work=8'd46;
  end else if(display_work[6] && activity!=7) begin
   case(index)
    6'd20:character_work=8'd78;
    6'd21:character_work=8'd69;
    6'd22:character_work=8'd88;
    6'd23:character_work=8'd84;
    6'd24:character_work=8'd32;
    6'd25:character_work=8'd80;
    6'd26:character_work=8'd73;
    6'd27:character_work=8'd67;
    6'd28:character_work=8'd32;
    6'd29:character_work=pending_digit;
    default:character_work=32;
   endcase
  end
 end
 wire [7:0] character_fault;
 recovery_text recovery_label(display_fault,index,character_fault);
 reg [7:0] row_char[0:3];reg [7:0] fault_char_q,char_q;reg [63:0] bitmap;
 always @(posedge clk) begin
  if(reset) begin row_char[0]<=32;row_char[1]<=32;row_char[2]<=32;row_char[3]<=32;fault_char_q<=32;char_q<=32;bitmap<=0;end
  else begin
   if(phase==2) begin row_char[0]<=character_0;row_char[1]<=character_1;row_char[2]<=character_2;row_char[3]<=activity!=0 ? character_work : character_3;fault_char_q<=character_fault;end
   if(phase==3) char_q<=(row_id==3 && display_fault[14]) ? fault_char_q : row_char[row_id];
   if(phase==4) bitmap<=glyph(char_q);
  end
 end
 function [63:0] glyph;
 input [7:0] c;
 begin case(c)
8'd65: glyph=64'h0000111f110a0a04;
8'd66: glyph=64'h00000e12120e121e;
8'd67: glyph=64'h00001e030101031e;
8'd68: glyph=64'h00000e121212120e;
8'd69: glyph=64'h00001e02021e021e;
8'd70: glyph=64'h00000202021e021e;
8'd71: glyph=64'h00001e131119031e;
8'd72: glyph=64'h00001212121e1212;
8'd73: glyph=64'h00000e040404040e;
8'd74: glyph=64'h00000e101010101e;
8'd75: glyph=64'h0000120a06060a12;
8'd76: glyph=64'h00001e0202020202;
8'd77: glyph=64'h00002121252d2a12;
8'd78: glyph=64'h0000121a1a161612;
8'd79: glyph=64'h00000e111111110e;
8'd80: glyph=64'h000002020e12120e;
8'd81: glyph=64'h18040e111111110e;
8'd82: glyph=64'h000012120e12120e;
8'd83: glyph=64'h00000e101806021c;
8'd84: glyph=64'h000004040404041f;
8'd85: glyph=64'h00001c2222222222;
8'd86: glyph=64'h0000081414222222;
8'd87: glyph=64'h000022322e2a2222;
8'd88: glyph=64'h000031120c040a13;
8'd89: glyph=64'h0000080808141422;
8'd90: glyph=64'h00001e040408081e;
8'd48: glyph=64'h00000e11171d110e;
8'd49: glyph=64'h00001e0808080a0c;
8'd50: glyph=64'h00001e040810121c;
8'd51: glyph=64'h00000e10100c101e;
8'd52: glyph=64'h0000081f090a0c0c;
8'd53: glyph=64'h00000e10100e021e;
8'd54: glyph=64'h00001c22221e061c;
8'd55: glyph=64'h000004040808101e;
8'd56: glyph=64'h00000e12120c121e;
8'd57: glyph=64'h00000f101e11110e;
8'd58: glyph=64'h0000040400040400;
8'd43: glyph=64'h000004040e040400;
8'd37: glyph=64'h0000110204081111;
8'd62: glyph=64'h0000020408040200;
8'd45: glyph=64'h000000000e000000;
8'd46: glyph=64'h00000c0c00000000;
8'd47: glyph=64'h0000010204081020;
  default: glyph=0;
 endcase end
 endfunction

 always @(posedge clk) begin
  if(reset) begin panel_q<=0;ink_q<=0;logo_q<=0;ink_color_q<=0;end
  else if(phase==0) begin
   panel_q<=panel_pre;ink_q<=text_row && bitmap[{row,column}];logo_q<=0;ink_color_q<=color_pre;
  end
 end
endmodule
