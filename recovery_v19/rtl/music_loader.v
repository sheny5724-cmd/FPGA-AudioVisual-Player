// V18: validate FPA header against catalog, then load probe + mu-law payload.
module music_loader(input clk,input reset,input ready,input restart,
 input [20:0] song_words,input [20:0] base_word,
 input [31:0] expected_full,input [31:0] expected_probe,
 input byte_valid,input [7:0] byte_data,input byte_empty,
 input drained,input overflow,input filesystem_done,input file_found,
 output reader_reset,output active,output finished,output reg loaded,
 output clear_load,output reg error,output byte_ready,
 output reg word_valid,output reg [20:0] word_addr,output reg [31:0] word_data,output reg [3:0] failure_reason);
 localparam WAIT_INIT=0,PREPARE=1,HEADER=2,CHECK_HEADER=3,LOAD=4,DRAIN=5,DONE=6,FAIL=7;
 reg [2:0] state;
 reg [8:0] hold_reset,header_position;
 reg [30:0] inactivity;
 reg [20:0] offset;
 wire [20:0] mapped_address;
 audio_buffer_map address_map(base_word,offset,mapped_address);
 reg [1:0] byte_index;
 reg [23:0] pack;
 reg [63:0] magic;
 reg [31:0] crc,header_crc,header_words,header_full,header_probe,rate,probe_words,payload_bytes;
 wire [31:0] crc_next,assembled;
 assign assembled={byte_data,pack};
 crc32_byte header_crc_step(crc,byte_data,crc_next);
 assign finished=state==DONE || state==FAIL;
 assign active=!finished;
 assign reader_reset=state!=HEADER && state!=CHECK_HEADER && state!=LOAD;
 assign clear_load=state==PREPARE;
 assign byte_ready=state==HEADER || state==LOAD;
 always @(posedge clk) begin
  if(reset) begin
   state<=WAIT_INIT;hold_reset<=0;inactivity<=0;offset<=0;
   byte_index<=0;pack<=0;loaded<=0;error<=0;failure_reason<=0;header_position<=0;
   word_valid<=0;word_addr<=0;word_data<=0;magic<=0;crc<=32'hffffffff;
   header_crc<=0;header_words<=0;header_full<=0;header_probe<=0;rate<=0;probe_words<=0;payload_bytes<=0;
  end else if(restart && finished) begin
   state<=PREPARE;hold_reset<=0;inactivity<=0;offset<=0;
   byte_index<=0;pack<=0;loaded<=0;error<=0;failure_reason<=0;header_position<=0;
   word_valid<=0;word_addr<=0;word_data<=0;magic<=0;crc<=32'hffffffff;
   header_crc<=0;header_words<=0;header_full<=0;header_probe<=0;rate<=0;probe_words<=0;payload_bytes<=0;
  end else begin
   word_valid<=0;
   case(state)
    WAIT_INIT:if(ready) state<=PREPARE;
    PREPARE:begin
     if(hold_reset==255) begin state<=HEADER;inactivity<=0;end
     else hold_reset<=hold_reset+1'b1;
    end
    HEADER:begin
     if(byte_valid) begin
      inactivity<=0;header_position<=header_position+1'b1;
      if(header_position<508) crc<=crc_next;
      if(header_position<8) magic<={magic[55:0],byte_data};
      case(header_position[1:0])
       0:pack[7:0]<=byte_data;1:pack[15:8]<=byte_data;2:pack[23:16]<=byte_data;
       default:;
      endcase
      case(header_position)
       11:header_words<=assembled;15:header_full<=assembled;19:header_probe<=assembled;
       23:rate<=assembled;27:probe_words<=assembled;31:payload_bytes<=assembled;
       511:begin header_crc<=assembled;state<=CHECK_HEADER;end
       default:;
      endcase
     end else inactivity<=inactivity+1'b1;
     if(overflow) begin error<=1;failure_reason<=5;state<=FAIL;end
     else if(filesystem_done && !file_found) begin error<=1;failure_reason<=1;state<=FAIL;end
     else if(filesystem_done && byte_empty && !byte_valid && inactivity>500000) begin error<=1;failure_reason<=6;state<=FAIL;end
     else if(inactivity==499999999) begin error<=1;failure_reason<=4;state<=FAIL;end
    end
    CHECK_HEADER:begin
     if(magic!="HXAU0001" || ~crc!=header_crc || header_words!={11'd0,song_words} ||
        header_full!=expected_full || header_probe!=expected_probe || rate!=24000 || probe_words!=1024 ||
        payload_bytes!=(({11'd0,song_words}-32'd1024)<<2)) begin error<=1;failure_reason<=(~crc!=header_crc) ? 4'd3 : 4'd2;state<=FAIL;end
     else begin state<=LOAD;byte_index<=0;pack<=0;inactivity<=0;end
    end
    LOAD:begin
     if(byte_valid) begin
      inactivity<=0;byte_index<=byte_index+1'b1;
      case(byte_index)
       0:pack[7:0]<=byte_data;1:pack[15:8]<=byte_data;2:pack[23:16]<=byte_data;
       3:begin
        word_valid<=1;word_data<=assembled;word_addr<=mapped_address;offset<=offset+1'b1;
        if(offset==song_words-1'b1) begin state<=DRAIN;inactivity<=0;end
       end
      endcase
     end else inactivity<=inactivity+1'b1;
     if(overflow) begin error<=1;failure_reason<=5;state<=FAIL;end
     else if(filesystem_done && !file_found) begin error<=1;failure_reason<=1;state<=FAIL;end
     else if(filesystem_done && byte_empty && !byte_valid && inactivity>500000) begin error<=1;failure_reason<=6;state<=FAIL;end
     else if(inactivity==499999999) begin error<=1;failure_reason<=4;state<=FAIL;end
    end
    DRAIN:begin
     inactivity<=inactivity+1'b1;
     if(drained && inactivity>64) begin loaded<=1;state<=DONE;end
     else if(inactivity==499999999) begin error<=1;failure_reason<=7;state<=FAIL;end
    end
    default:;
   endcase
  end
 end
endmodule
