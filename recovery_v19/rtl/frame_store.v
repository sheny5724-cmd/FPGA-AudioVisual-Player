// 50 MHz SDRAM arbiter. Four-word aligned writes and thirty-two-word reads.
// Two 640-pixel line buffers decouple the raster from SDRAM refresh.
// V17: select old/new bank once per row; no extra SDRAM read bandwidth.
module frame_store(input clk,input reset,input clear_load,
 input pixel_valid,input [20:0] pixel_addr,input [31:0] pixel_data,
 output throttle,output drained,output reg overflow,
 input line_request,input [8:0] line_number,input front_bank,
 input [10:0] display_addr,input display_read,input display_clk,
 output reg [23:0] display_data,output [1:0] line_valid,
 output [8:0] tag0,output [8:0] tag1,output reg dma_error,
 input init_done,input ref_valid,input busy,
 output wr_en,output [20:0] wr_addr,output [31:0] wr_data,
 output rd_en,output [20:0] rd_addr,input read_valid,input [31:0] read_data,
 input audio_request,input [20:0] audio_address,output audio_accept,output audio_valid,
 output write_idle,
 input wipe_active,input wipe_reverse,input [9:0] wipe_boundary);
 reg [52:0] writes[0:63];
 reg [5:0] wp,rp;
 reg [6:0] count;
 reg [3:0] state;
 reg [20:0] audio_addr;
 reg [5:0] issue,received;
 reg [7:0] guard;
 reg [15:0] watchdog;
 reg active_line;
 reg [8:0] row, tags[0:1];
 reg bank;
 reg [9:0] column;
 reg [1:0] valid;
 reg [23:0] lines[0:2047];
 localparam IDLE=0, WRITE=1, WRITE_WAIT=2, READ=3, READ_WAIT=4, READ_GUARD=5,
 AUDIO_READ=6,AUDIO_WAIT=7,AUDIO_GUARD=8;
 wire pop=state==WRITE;
 wire reveal_row=wipe_reverse ? ({1'b0,line_number}>=wipe_boundary) :
                                   ({1'b0,line_number}<wipe_boundary);
 assign wr_en=pop;
 assign wr_addr=writes[rp][52:32];
 assign wr_data=writes[rp][31:0];
 assign rd_en=state==READ || state==AUDIO_READ;
 wire [20:0] row_address={bank,20'b0}+({12'b0,row}<<9)+({12'b0,row}<<7);
 assign rd_addr=(state==AUDIO_READ ? audio_addr : row_address+column)+issue;
 assign audio_accept=state==IDLE && init_done && !ref_valid && !busy &&
 !clear_load && !active_line && !line_request && audio_request;
 assign audio_valid=read_valid && (state==AUDIO_READ || state==AUDIO_WAIT);
 assign throttle=count>=48;
 assign drained=count==0 && state!=WRITE && state!=WRITE_WAIT;
 // A failed/truncated load can leave fewer than four queued words. The owner
 // may discard those only after the current four-word write has finished.
 assign write_idle=state!=WRITE && state!=WRITE_WAIT;
 assign line_valid=valid;
 assign tag0=tags[0];assign tag1=tags[1];
 always @(posedge display_clk) if(display_read) display_data<=lines[display_addr];
 always @(posedge clk) begin
   if(reset) begin
     wp<=0;rp<=0;count<=0;state<=IDLE;issue<=0;received<=0;guard<=0;
     active_line<=0;row<=0;bank<=0;column<=0;valid<=0;tags[0]<=0;tags[1]<=0;audio_addr<=0;
     overflow<=0;dma_error<=0;watchdog<=0;
   end else begin
     if(clear_load) begin wp<=0;rp<=0;count<=0;overflow<=0;end
     else begin
       case({pixel_valid,pop})
         2'b10:if(count<64) count<=count+1'b1;
         2'b01:count<=count-1'b1;
       endcase
       if(pixel_valid) begin
         if(count<64) begin writes[wp]<={pixel_addr,pixel_data};wp<=wp+1'b1;end
         else overflow<=1;
       end
       if(pop) rp<=rp+1'b1;
     end
     if(line_request) begin
       if(!active_line) begin
         active_line<=1;row<=line_number;
         bank<=front_bank ^ (wipe_active && reveal_row);column<=0;
         valid[line_number[0]]<=0;
       end else dma_error<=1;
     end
     if(active_line) begin
       watchdog<=watchdog+1'b1;
       if(watchdog==16'hffff) dma_error<=1;
     end else watchdog<=0;
     if(read_valid && (state==READ || state==READ_WAIT)) begin
       lines[{row[0],10'b0}+column+received]<={read_data[23:0]};
       received<=received+1'b1;
     end
     if(audio_valid) received<=received+1'b1;
     case(state)
       IDLE:if(init_done && !ref_valid && !busy && !clear_load) begin
         issue<=0;received<=0;
         if(active_line) state<=READ;
         else if(line_request) state<=IDLE;
         else if(audio_request) begin audio_addr<=audio_address;state<=AUDIO_READ;end
         else if(count>=4) state<=WRITE;
       end
       WRITE:begin
         if(issue==3) begin state<=WRITE_WAIT;guard<=0;end
         else issue<=issue+1'b1;
       end
       WRITE_WAIT:begin
         guard<=guard+1'b1;
         if(guard==23 && !busy) state<=IDLE;
       end
       READ:begin
         if(issue==31) state<=READ_WAIT;
         else issue<=issue+1'b1;
       end
       READ_WAIT:if(received==32) begin state<=READ_GUARD;guard<=0;end
       READ_GUARD:begin
         guard<=guard+1'b1;
         if(guard==7 && !busy) begin
           if(column==608) begin
             active_line<=0;valid[row[0]]<=1;tags[row[0]]<=row;state<=IDLE;
           end else begin
             column<=column+32;issue<=0;received<=0;
             // Finish all twenty bursts of the requested display row before
             // servicing background writes. Scaling can saturate the write
             // queue; interleaving a write after every read burst consumes
             // the next-line prefetch deadline and exposes diagnostic pixels.
             // IDLE prioritizes active_line; writes resume after the full row.
             state<=IDLE;
           end
         end
       end
       AUDIO_READ:begin
         if(issue==31) state<=AUDIO_WAIT;else issue<=issue+1'b1;
       end
       AUDIO_WAIT:if(received==32) begin state<=AUDIO_GUARD;guard<=0;end
       AUDIO_GUARD:begin
         guard<=guard+1'b1;
         if(guard==7 && !busy) state<=IDLE;
       end
       default:state<=IDLE;
     endcase
   end
 end
endmodule
