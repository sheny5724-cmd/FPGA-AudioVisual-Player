// Single-clock HDMI packet queue. Packet payload is latched at packet start.
// Packet encoders below are the attributed hdl-util reference implementations.
module audio_packet_queue(
 input logic clk, reset, pixel_ce, audio_ce, packet_enable, video_field_end,
 input logic [31:0] stereo,
 output logic [23:0] header,
 output logic [55:0] sub [3:0],
 output logic fault
);
 // Flat stereo words, one producer/consumer clock, no multi-dimensional RAM.
 logic [31:0] fifo [0:15];
 logic [3:0] wp, rp;
 logic [4:0] count;
 logic [5:0] acr_samples;
 logic acr_pending, avi_sent, audio_sent, spd_sent;
 logic [7:0] frame_counter;
 wire select_packet=pixel_ce && packet_enable && !reset;
 wire take_audio=select_packet && !acr_pending && count>=4;
 wire push=audio_ce && (count<16 || take_audio) && !reset;
 wire acr_tick=audio_ce && acr_samples==47;
 wire [23:0] audio_header, avi_header, info_header, spd_header;
 wire [55:0] audio_sub [3:0], avi_sub [3:0], info_sub [3:0], spd_sub [3:0];
 wire [23:0] samples [3:0][1:0];
 genvar g;
 generate for(g=0;g<4;g=g+1) begin: gather
  wire [3:0] index=rp+g;
  assign samples[g][0]={fifo[index][15:0],8'd0};
  assign samples[g][1]={fifo[index][31:16],8'd0};
 end endgenerate
 audio_sample_packet #(.SAMPLING_FREQUENCY(4'b0010),.WORD_LENGTH(4'b0010)) sample_packet(
  .frame_counter(frame_counter),.valid_bit('{2'd0,2'd0,2'd0,2'd0}),
  .user_data_bit('{2'd0,2'd0,2'd0,2'd0}),.audio_sample_word(samples),
  .audio_sample_word_present(4'b1111),.header(audio_header),.sub(audio_sub));
 audio_info_frame info(.header(info_header),.sub(info_sub));
 auxiliary_video_information_info_frame #(.VIDEO_ID_CODE(7'd1),.IT_CONTENT(1'b1)) avi(
  .header(avi_header),.sub(avi_sub));
 source_product_description_info_frame #(.VENDOR_NAME({"HX4S20C",8'd0}),
  .PRODUCT_DESCRIPTION({"FPGA PLAYER",40'd0}),.SOURCE_DEVICE_INFORMATION(0)) spd(
  .header(spd_header),.sub(spd_sub));
 integer i;
 always @(posedge clk) begin
  if(reset) begin
   wp<=0;rp<=0;count<=0;acr_samples<=0;acr_pending<=1;
   avi_sent<=0;audio_sent<=0;spd_sent<=0;frame_counter<=0;fault<=0;
   header<=0;for(i=0;i<4;i=i+1) sub[i]<=0;
  end else begin
   if(push) begin fifo[wp]<=stereo;wp<=wp+1'b1;end
   if(audio_ce && !push) fault<=1;
   case({push,take_audio})
    2'b10:count<=count+1'b1;
    2'b01:count<=count-5'd4;
    2'b11:count<=count-5'd3;
   endcase
   if(audio_ce) acr_samples<=acr_tick ? 0 : acr_samples+1'b1;
   if(pixel_ce && video_field_end) begin avi_sent<=0;audio_sent<=0;spd_sent<=0;end
   if(select_packet) begin
    if(acr_pending) begin
     // Both rates derive from the same 125MHz PLL output:
     // 25MHz * 6144 / (128 * 25000) = 48000Hz.
     header<=24'h000001;
     for(i=0;i<4;i=i+1) sub[i]<=56'h001800a8610000;
     acr_pending<=0;
    end else if(take_audio) begin
     header<=audio_header;for(i=0;i<4;i=i+1) sub[i]<=audio_sub[i];
     rp<=rp+4'd4;
     frame_counter<=frame_counter==188 ? 0 : frame_counter+8'd4;
    end else if(!audio_sent) begin
     header<=info_header;for(i=0;i<4;i=i+1) sub[i]<=info_sub[i];audio_sent<=1;
    end else if(!avi_sent) begin
     header<=avi_header;for(i=0;i<4;i=i+1) sub[i]<=avi_sub[i];avi_sent<=1;
    end else if(!spd_sent) begin
     header<=spd_header;for(i=0;i<4;i=i+1) sub[i]<=spd_sub[i];spd_sent<=1;
    end else begin header<=0;for(i=0;i<4;i=i+1) sub[i]<=0;end
   end
   if(acr_tick) acr_pending<=1;
  end
 end
endmodule
