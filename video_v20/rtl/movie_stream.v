// HXVD0001 / FRM1: fixed 160x90, 15 fps, per-frame palette and 1600 audio bytes.
// Back frames and staged audio are published only after a complete CRC match.
module movie_stream(input clk,reset,input [3:0] keys,input auto_next,input vblank,
 input byte_valid,input [7:0] byte_data,output byte_ready,output reader_reset,
 input file_done,file_found,byte_empty,byte_overflow,input sample_toggle,
 output reg clip_index,output reg front_bank,front_valid,
 output pixel_we,palette_we,write_bank,output [13:0] pixel_address,
 output [7:0] pixel_data,palette_address,output [23:0] palette_data,
 output [31:0] pcm,output loading,finished,output reg [3:0] error,
 output audio_underrun,audio_overflow,output [31:0] played_samples,
 output [31:0] shown_frames,output [4:0] debug_state);
 localparam RESET_HOLD=0,HEADER=1,HEADER_CHECK=2,FRAME_HEAD=3,FRAME_CHECK=4,
 PALETTE=5,PIXELS=6,AUDIO=7,PADDING=8,CRC_CHECK=9,SPACE=10,
 COPY_READ=11,COPY_WRITE=12,READY=13,LAST_FRAME=14,STOP=15,FAIL=16;
 reg [4:0] state;
 reg [10:0] reset_count;
 reg [8:0] head_pos;
 reg [5:0] frame_head_pos;
 reg [63:0] signature;
 reg [15:0] width,height,rate_fps,encoding;
 reg [31:0] frame_total,audio_rate,samples_per_frame,packet_size,pixel_total,sample_total;
 reg [31:0] head_crc,crc,frame_magic,packet_index,expected_crc,payload_size;
 reg [31:0] frame_index,next_deadline,presented;
 reg [7:0] palette_index,pal_r,pal_g;
 reg [1:0] component;
 reg [13:0] pixel_index;
 reg [10:0] audio_index,copy_index;
 reg [6:0] pad_index;
 reg [7:0] audio_stage[0:1599];reg [7:0] staged_q;
 reg [29:0] inactivity;
 wire [31:0] crc_next;
 wire audio_space,audio_ended;
 wire stream_accept=byte_valid && byte_ready;
 assign reader_reset=reset || state==RESET_HOLD;
 assign byte_ready=state==HEADER || state==FRAME_HEAD || state==PALETTE ||
                   state==PIXELS || state==AUDIO || state==PADDING;
 assign write_bank=~front_bank;
 assign pixel_we=stream_accept && state==PIXELS;
 assign pixel_address=pixel_index;
 assign pixel_data=byte_data;
 assign palette_we=stream_accept && state==PALETTE && component==2;
 assign palette_address=palette_index;
 assign palette_data={pal_r,pal_g,byte_data};
 assign loading=!front_valid && state!=FAIL;
 assign finished=state==STOP;
 assign shown_frames=presented;
 assign debug_state=state;
 crc32_byte crc_step(crc,byte_data,crc_next);
 movie_audio sound(clk,reader_reset,state==COPY_WRITE,staged_q,
  front_valid && error==0 && state!=STOP,sample_toggle,sample_total,
  pcm,played_samples,audio_space,audio_ended,audio_underrun,audio_overflow);
 always @(posedge clk) begin
  if(stream_accept && state==AUDIO) audio_stage[audio_index]<=byte_data;
  if(state==COPY_READ) staged_q<=audio_stage[copy_index];
 end
 always @(posedge clk) begin
  if(reset) begin
   state<=RESET_HOLD;reset_count<=0;clip_index<=0;front_bank<=0;front_valid<=0;
   error<=0;head_pos<=0;frame_head_pos<=0;signature<=0;width<=0;height<=0;
   rate_fps<=0;encoding<=0;frame_total<=0;audio_rate<=0;samples_per_frame<=0;
   packet_size<=0;pixel_total<=0;sample_total<=0;head_crc<=0;crc<=32'hffffffff;
   frame_magic<=0;packet_index<=0;expected_crc<=0;payload_size<=0;
   frame_index<=0;next_deadline<=1600;presented<=0;palette_index<=0;pal_r<=0;pal_g<=0;
   component<=0;pixel_index<=0;audio_index<=0;copy_index<=0;pad_index<=0;inactivity<=0;
  end else if((keys[0]^keys[1]) || (keys[3] && error!=0) || (state==STOP && auto_next)) begin
   if((keys[0]^keys[1]) || (state==STOP && auto_next)) clip_index<=~clip_index;
   state<=RESET_HOLD;reset_count<=0;front_valid<=0;error<=0;inactivity<=0;
  end else begin
   if(byte_ready && !stream_accept) inactivity<=inactivity+1'b1;
   else inactivity<=0;
   case(state)
    RESET_HOLD:begin
     front_bank<=0;front_valid<=0;head_pos<=0;signature<=0;head_crc<=0;
     width<=0;height<=0;rate_fps<=0;encoding<=0;frame_total<=0;audio_rate<=0;
     samples_per_frame<=0;packet_size<=0;pixel_total<=0;sample_total<=0;
     crc<=32'hffffffff;frame_index<=0;presented<=0;next_deadline<=1600;
     if(reset_count==1023) state<=HEADER;else reset_count<=reset_count+1'b1;
    end
    HEADER:if(stream_accept) begin
     head_pos<=head_pos+1'b1;
     if(head_pos<508) crc<=crc_next;
     case(head_pos)
      0,1,2,3,4,5,6,7:signature<={byte_data,signature[63:8]};
      8:width[7:0]<=byte_data;9:width[15:8]<=byte_data;
      10:height[7:0]<=byte_data;11:height[15:8]<=byte_data;
      12:rate_fps[7:0]<=byte_data;13:rate_fps[15:8]<=byte_data;
      14:encoding[7:0]<=byte_data;15:encoding[15:8]<=byte_data;
      16,17,18,19:frame_total<={byte_data,frame_total[31:8]};
      20,21,22,23:audio_rate<={byte_data,audio_rate[31:8]};
      24,25,26,27:samples_per_frame<={byte_data,samples_per_frame[31:8]};
      28,29,30,31:packet_size<={byte_data,packet_size[31:8]};
      32,33,34,35:pixel_total<={byte_data,pixel_total[31:8]};
      36,37,38,39:sample_total<={byte_data,sample_total[31:8]};
      508,509,510,511:head_crc<={byte_data,head_crc[31:8]};
     endcase
     if(head_pos==511) state<=HEADER_CHECK;
    end
    HEADER_CHECK:begin
     if(signature!=64'h3130303044565848 || width!=160 || height!=90 || rate_fps!=15 ||
        encoding!=1 || frame_total==0 || frame_total>60000 || audio_rate!=24000 ||
        samples_per_frame!=1600 || packet_size!=16896 || pixel_total!=14400 ||
        sample_total!=frame_total*32'd1600) begin error<=2;state<=FAIL;end
     else if(~crc!=head_crc) begin error<=3;state<=FAIL;end
     else begin state<=FRAME_HEAD;frame_head_pos<=0;end
    end
    FRAME_HEAD:if(stream_accept) begin
     frame_head_pos<=frame_head_pos+1'b1;
     case(frame_head_pos)
      0,1,2,3:frame_magic<={byte_data,frame_magic[31:8]};
      4,5,6,7:packet_index<={byte_data,packet_index[31:8]};
      8,9,10,11:expected_crc<={byte_data,expected_crc[31:8]};
      12,13,14,15:payload_size<={byte_data,payload_size[31:8]};
     endcase
     if(frame_head_pos==31) state<=FRAME_CHECK;
    end
    FRAME_CHECK:begin
     if(frame_magic!=32'h314d5246 || packet_index!=frame_index || payload_size!=16768) begin error<=2;state<=FAIL;end
     else begin state<=PALETTE;palette_index<=0;component<=0;crc<=32'hffffffff;end
    end
    PALETTE:if(stream_accept) begin
     crc<=crc_next;
     if(component==0) begin pal_r<=byte_data;component<=1;end
     else if(component==1) begin pal_g<=byte_data;component<=2;end
     else begin
      component<=0;palette_index<=palette_index+1'b1;
      if(palette_index==255) begin pixel_index<=0;state<=PIXELS;end
     end
    end
    PIXELS:if(stream_accept) begin
     crc<=crc_next;pixel_index<=pixel_index+1'b1;
     if(pixel_index==14399) begin audio_index<=0;state<=AUDIO;end
    end
    AUDIO:if(stream_accept) begin
     crc<=crc_next;audio_index<=audio_index+1'b1;
     if(audio_index==1599) begin pad_index<=0;state<=PADDING;end
    end
    PADDING:if(stream_accept) begin
     pad_index<=pad_index+1'b1;
     if(pad_index==95) state<=CRC_CHECK;
    end
    CRC_CHECK:if(~crc!=expected_crc) begin error<=3;state<=FAIL;end else state<=SPACE;
    SPACE:if(audio_space) begin copy_index<=0;state<=COPY_READ;end
    COPY_READ:state<=COPY_WRITE;
    COPY_WRITE:begin
     copy_index<=copy_index+1'b1;
     state<=copy_index==1599 ? READY : COPY_READ;
    end
    READY:if(vblank && (!front_valid || played_samples>=next_deadline)) begin
     front_bank<=~front_bank;front_valid<=1;presented<=frame_index+1'b1;
     if(front_valid) next_deadline<=next_deadline+32'd1600;
     if(frame_index==frame_total-1'b1) state<=LAST_FRAME;
     else begin frame_index<=frame_index+1'b1;frame_head_pos<=0;state<=FRAME_HEAD;end
    end
    LAST_FRAME:if(audio_ended) state<=STOP;
    STOP:begin end
    FAIL:begin end
    default:begin error<=7;state<=FAIL;end
   endcase
   // Only the states requesting input participate in the file watchdog.
   if(state!=RESET_HOLD && state!=FAIL && state!=STOP) begin
    if(byte_overflow || audio_overflow) begin error<=5;state<=FAIL;end
    else if(byte_ready && !stream_accept && byte_empty && inactivity>500000 && file_done) begin
     error<=file_found ? 4'd6 : 4'd1;state<=FAIL;
    end else if(byte_ready && !stream_accept && inactivity==30'd499999999) begin error<=4;state<=FAIL;end
   end
  end
 end
endmodule
