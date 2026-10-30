// Read PLAYLST.BIN before granting the shared reader. KEY4 retries failures.
module media_catalog(input clk,input reset,input init_done,input retry,
 input byte_valid,input [7:0] byte_data,input byte_empty,input filesystem_done,input file_found,input overflow,
 input [2:0] index0,input [2:0] index1,input [2:0] next_index,
 output reader_reset,output clear_load,output byte_ready,output claim,
 output ready,output failed,output reg [3:0] image_count,output reg [3:0] song_count,
 output [20:0] words0,words1,next_words,
 output [31:0] full_crc0,full_crc1,probe_crc0,probe_crc1,output reg fault_event,output reg [14:0] fault_info);
 localparam WAIT_INIT=0,PREPARE=1,READ=2,CHECK=3,SCAN=4,DONE=5,FAIL=6,CAPTURE=7;
 reg [2:0] state,scan_index;
 reg [8:0] position,hold_reset;
 reg [29:0] inactivity;
 reg [63:0] magic;
 reg [31:0] crc,expected_crc,rate,header_bytes,probe_words,scan_length,scan_payload;
 reg [23:0] pack;
 reg invalid;
 reg [1:0] retries;
 reg [25:0] recovery_wait;
 reg [31:0] lengths[0:7],full_crcs[0:7],probe_crcs[0:7],payload_bytes[0:7];
 wire [31:0] next_crc;
 crc32_byte crc_step(crc,byte_data,next_crc);
 wire [31:0] assembled={byte_data,pack};
 wire [2:0] entry=position[7:5]-3'd1;
 assign reader_reset=state!=READ;
 assign clear_load=state==PREPARE;
 assign byte_ready=state==READ;
 assign ready=state==DONE;
 assign failed=state==FAIL && retries==2;
 assign claim=state!=DONE;
 assign words0=lengths[index0][20:0];assign words1=lengths[index1][20:0];
 assign next_words=lengths[next_index][20:0];
 assign full_crc0=full_crcs[index0];assign full_crc1=full_crcs[index1];
 assign probe_crc0=probe_crcs[index0];assign probe_crc1=probe_crcs[index1];
 task fail_catalog;
  input [3:0] reason;
  begin
   state<=FAIL;recovery_wait<=0;fault_event<=1;
   fault_info<={1'b1,2'd1,3'd0,reason,(retries<2 ? 3'd1 : 3'd3),(retries<2 ? retries+2'd1 : 2'd2)};
  end
 endtask
 integer i;
 always @(posedge clk) begin
  if(reset) begin
   state<=WAIT_INIT;retries<=0;recovery_wait<=0;fault_event<=0;fault_info<=0;position<=0;hold_reset<=0;inactivity<=0;scan_index<=0;
   magic<=0;crc<=32'hffffffff;expected_crc<=0;pack<=0;invalid<=0;
   image_count<=0;song_count<=0;rate<=0;header_bytes<=0;probe_words<=0;scan_length<=0;scan_payload<=0;
   for(i=0;i<8;i=i+1) begin lengths[i]<=0;full_crcs[i]<=0;probe_crcs[i]<=0;payload_bytes[i]<=0;end
  end else begin
   fault_event<=0;
   case(state)
   WAIT_INIT:if(init_done) state<=PREPARE;
   PREPARE:begin
    position<=0;inactivity<=0;scan_index<=0;magic<=0;crc<=32'hffffffff;
    expected_crc<=0;pack<=0;invalid<=0;image_count<=0;song_count<=0;
    rate<=0;header_bytes<=0;probe_words<=0;
    if(hold_reset==255) begin hold_reset<=0;state<=READ;end
    else hold_reset<=hold_reset+1'b1;
   end
   READ:begin
    if(byte_valid) begin
     inactivity<=0;position<=position+1'b1;
     if(position<508) crc<=next_crc;
     if(position<8) magic<={magic[55:0],byte_data};
     case(position[1:0])
      0:pack[7:0]<=byte_data;1:pack[15:8]<=byte_data;2:pack[23:16]<=byte_data;
      default:;
     endcase
     case(position)
      8:begin image_count<=byte_data[3:0];if(byte_data==0 || byte_data>8) invalid<=1;end
      9:begin song_count<=byte_data[3:0];if(byte_data==0 || byte_data>8) invalid<=1;end
      10,11:if(byte_data!=0) invalid<=1;
      15:rate<=assembled;19:header_bytes<=assembled;23:probe_words<=assembled;
      511:begin expected_crc<=assembled;state<=CHECK;end
      default:;
     endcase
     if(position>=32 && position<288 && position[1:0]==3) begin
      case(position[4:2])
       0:lengths[entry]<=assembled;
       1:full_crcs[entry]<=assembled;
       2:probe_crcs[entry]<=assembled;
       3:if({1'b0,entry}<song_count && assembled!=24000) invalid<=1;
       4:payload_bytes[entry]<=assembled;
       5:if({1'b0,entry}<song_count && assembled!=1) invalid<=1;
       6:if({1'b0,entry}<song_count && assembled!={29'd0,entry}+32'd1) invalid<=1;
       7:if(assembled!=0) invalid<=1;
      endcase
     end
    end else inactivity<=inactivity+1'b1;
    if(overflow) fail_catalog(4'd5);
    else if(filesystem_done && !file_found) fail_catalog(4'd1);
    else if(filesystem_done && byte_empty && !byte_valid && inactivity>500000) fail_catalog(4'd6);
    else if(inactivity==499999999) fail_catalog(4'd4);
   end
   CHECK:begin
    if(invalid || magic!="HXPL0001" || ~crc!=expected_crc || rate!=24000 ||
       header_bytes!=512 || probe_words!=1024 || image_count==0 || image_count>8 || song_count==0 || song_count>8) fail_catalog(~crc!=expected_crc ? 4'd3 : 4'd2);
    else begin scan_index<=0;state<=CAPTURE;end
   end
   CAPTURE:begin scan_length<=lengths[scan_index];scan_payload<=payload_bytes[scan_index];state<=SCAN;end
   SCAN:begin
    // Prefix=1024 words; payload>=128 words, aligned to 32 words.
    if(scan_length<1152 || scan_length>1480704 || scan_length[4:0]!=0 ||
       scan_payload!=((scan_length-32'd1024)<<2)) fail_catalog(4'd8);
    else if({1'b0,scan_index}+4'd1==song_count) state<=DONE;
    else begin scan_index<=scan_index+1'b1;state<=CAPTURE;end
   end
   FAIL:begin
    if(recovery_wait<26'd25000000) recovery_wait<=recovery_wait+1'b1;
    if(retry) begin retries<=0;state<=PREPARE;hold_reset<=0;end
    else if(retries<2 && recovery_wait>=26'd24999999) begin retries<=retries+1'b1;state<=PREPARE;hold_reset<=0;end
   end
   default:;
  endcase
  end
 end
endmodule
