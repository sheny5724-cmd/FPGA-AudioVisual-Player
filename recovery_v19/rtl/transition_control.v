// V17: frame-synchronous vertical reveal with cubic ease-in/ease-out.
// Both full frames remain immutable until the new picture covers all rows.
// Scanout needs only one source frame per row, so its DMA budget is unchanged.
module transition_control(input clk,input reset,input vblank,
 input commit_pending,input front_valid,input front_bank,input requested_reverse,
 output commit_allowed,output transition_busy,output wipe_active,
 output reg wipe_reverse,output reg [9:0] wipe_boundary);
 localparam IDLE=2'd0,REVEAL=2'd1,WAIT_SWAP=2'd2;
 reg [1:0] state;
 reg old_bank;
 reg [5:0] step;
 function [9:0] reveal;
 input [5:0] position;
 begin
  case(position)
    6'd0: reveal=10'd0;
    6'd1: reveal=10'd1;
    6'd2: reveal=10'd2;
    6'd3: reveal=10'd5;
    6'd4: reveal=10'd9;
    6'd5: reveal=10'd15;
    6'd6: reveal=10'd21;
    6'd7: reveal=10'd28;
    6'd8: reveal=10'd36;
    6'd9: reveal=10'd44;
    6'd10: reveal=10'd54;
    6'd11: reveal=10'd64;
    6'd12: reveal=10'd75;
    6'd13: reveal=10'd87;
    6'd14: reveal=10'd99;
    6'd15: reveal=10'd111;
    6'd16: reveal=10'd124;
    6'd17: reveal=10'd138;
    6'd18: reveal=10'd152;
    6'd19: reveal=10'd166;
    6'd20: reveal=10'd181;
    6'd21: reveal=10'd195;
    6'd22: reveal=10'd210;
    6'd23: reveal=10'd225;
    6'd24: reveal=10'd240;
    6'd25: reveal=10'd255;
    6'd26: reveal=10'd270;
    6'd27: reveal=10'd285;
    6'd28: reveal=10'd299;
    6'd29: reveal=10'd314;
    6'd30: reveal=10'd328;
    6'd31: reveal=10'd342;
    6'd32: reveal=10'd356;
    6'd33: reveal=10'd369;
    6'd34: reveal=10'd381;
    6'd35: reveal=10'd393;
    6'd36: reveal=10'd405;
    6'd37: reveal=10'd416;
    6'd38: reveal=10'd426;
    6'd39: reveal=10'd436;
    6'd40: reveal=10'd444;
    6'd41: reveal=10'd452;
    6'd42: reveal=10'd459;
    6'd43: reveal=10'd465;
    6'd44: reveal=10'd471;
    6'd45: reveal=10'd475;
    6'd46: reveal=10'd478;
    6'd47: reveal=10'd479;
    6'd48: reveal=10'd480;
    default: reveal=10'd480;
  endcase
 end endfunction
 wire [5:0] next_step=step+6'd1;
 wire [9:0] next_reveal=reveal(next_step);
 assign commit_allowed=!front_valid || state==WAIT_SWAP;
 assign transition_busy=state!=IDLE;
 // Suppress the bank XOR on the actual swap edge. Waiting for the FSM to
 // observe that edge would otherwise briefly select the retired framebuffer.
 assign wipe_active=state!=IDLE && front_bank==old_bank;
 always @(posedge clk) begin
  if(reset) begin
   state<=IDLE;old_bank<=0;step<=0;wipe_reverse<=0;wipe_boundary<=0;
  end else case(state)
   IDLE:if(commit_pending && front_valid) begin
    old_bank<=front_bank;step<=0;wipe_reverse<=requested_reverse;
    wipe_boundary<=requested_reverse ? 10'd480 : 10'd0;
    state<=REVEAL;
   end
   REVEAL:if(vblank) begin
    step<=next_step;
    wipe_boundary<=wipe_reverse ? 10'd480-next_reveal : next_reveal;
    if(step==6'd47) state<=WAIT_SWAP;
   end
   WAIT_SWAP:if(front_bank!=old_bank) state<=IDLE;
   default:begin state<=IDLE;step<=0;wipe_boundary<=0;end
  endcase
 end
endmodule
