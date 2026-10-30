// V13 maintained switches: SW1 auto (player), SW2 sound, SW3 wave, SW4 SET.
// All inputs here have already passed the 50 MHz synchronizer/debouncer.
// VIEW: KEY1 next, KEY2 previous, KEY3 volume -, KEY4 volume +.
// SET: KEY1 +, KEY2 -, KEY3 VOL/BRT/CON; SW4 down exits.
// A media error gives KEY4 retry priority in either mode, without changing gain.
module display_controls(
 input clk,input reset,input [3:0] pressed,input [3:0] held,
 input [3:0] switches,input recovery_needed,
 output reg [3:0] image_keys,output adjust_mode,output reg [1:0] parameter_select,
 output reg signed [3:0] brightness,output reg [3:0] contrast,
 output wave_visible,output reg [4:0] volume_level,output muted);
 assign adjust_mode=switches[3];
 assign wave_visible=switches[2];
 assign muted=!switches[1];
 reg previous_set;
 reg [3:0] blocked_keys;
 wire [3:0] events=pressed & ~blocked_keys;
 always @(posedge clk) begin
  if(reset) begin
   image_keys<=0;parameter_select<=2;brightness<=0;contrast<=4;
   volume_level<=5'd2;previous_set<=0;blocked_keys<=0;
  end else begin
   image_keys<=0;
   previous_set<=switches[3];
   blocked_keys<=blocked_keys & held;
   if(previous_set!=switches[3]) begin
    // Keys held across a mode change must be released before reusing them.
    blocked_keys<=held | pressed;
    if(switches[3]) parameter_select<=2;
   end else begin
    if(recovery_needed && events[3]) image_keys[3]<=1;
    if(switches[3]) begin
     if(events[2]) parameter_select<=parameter_select==2 ? 0 : parameter_select+1'b1;
     else if(events[0] != events[1]) begin
      if(parameter_select==0) begin
       if(events[0] && brightness<4'sd4) brightness<=brightness+1'b1;
       else if(events[1] && brightness>-4'sd4) brightness<=brightness-1'b1;
      end else if(parameter_select==1) begin
       if(events[0] && contrast<6) contrast<=contrast+1'b1;
       else if(events[1] && contrast>2) contrast<=contrast-1'b1;
      end else begin
       if(events[0] && volume_level<20) volume_level<=volume_level+1'b1;
       else if(events[1] && volume_level>0) volume_level<=volume_level-1'b1;
      end
     end
    end else begin
     // Opposite keys pressed together cancel, rather than favoring one.
     if(events[0] != events[1]) image_keys[1:0]<=events[1:0];
     if(recovery_needed) begin
      if(events[2] && volume_level>0) volume_level<=volume_level-1'b1;
     end else if(events[2] != events[3]) begin
      if(events[2] && volume_level>0) volume_level<=volume_level-1'b1;
      else if(events[3] && volume_level<20) volume_level<=volume_level+1'b1;
     end
    end
   end
  end
 end
endmodule
