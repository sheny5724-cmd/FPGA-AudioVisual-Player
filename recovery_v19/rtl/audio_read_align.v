// V18: calibrate using a 4 KiB prefix that is never played, then read back
// the entire loaded song before enabling the music player. Three candidates
// must produce exactly ONE CRC match; ambiguous silence is never accepted.
// Core clock, SDRAM phase/refresh, and video arbitration remain unchanged.
module audio_read_align(input clk,reset,loaded,
 input [31:0] expected,input [31:0] expected_full,
 input [20:0] song_words,input [20:0] base_word,
 input [31:0] memory_data,input memory_valid,memory_accept,
 input player_request,input [20:0] player_address,
 output memory_request,output [20:0] memory_address,
 output player_accept,player_valid,output [31:0] player_data,
 output reg calibrated,output reg [2:0] status,
 output reg [31:0] observed_normal,observed_early,observed_late,
 output reg verified);
 reg [31:0] data_q,data_qq;
 reg valid_q,pending,audit;
 reg [20:0] count;
 reg [31:0] crc_normal,crc_early,crc_late,crc_full;
 wire [31:0] next_normal,next_early,next_late,next_full;
 audio_align_crc_step step_n(crc_normal,data_q,next_normal);
 audio_align_crc_step step_e(crc_early,data_qq,next_early);
 audio_align_crc_step step_l(crc_late,memory_data,next_late);
 audio_align_crc_step step_full(crc_full,player_data,next_full);
 wire [2:0] matches={(~next_late==expected),(~next_early==expected),(~next_normal==expected)};
 wire [20:0] offset={count[20:5],5'b00000};
 wire [20:0] scan_address;
 audio_buffer_map scan_map(base_word,offset,scan_address);
 assign memory_request=loaded && (calibrated ? (verified && player_request) : !pending);
 assign memory_address=calibrated ? player_address : scan_address;
 assign player_accept=calibrated && verified && memory_accept;
 assign player_valid=calibrated && verified && valid_q;
 assign player_data=status==2 ? data_qq : status==3 ? memory_data : data_q;
 always @(posedge clk) begin
  if(reset || !loaded) begin
   data_q<=0;data_qq<=0;valid_q<=0;pending<=0;count<=0;audit<=0;
   calibrated<=0;verified<=0;status<=0;
   crc_normal<=32'hffffffff;crc_early<=32'hffffffff;crc_late<=32'hffffffff;
   crc_full<=32'hffffffff;
   observed_normal<=0;observed_early<=0;observed_late<=0;
  end else begin
   data_q<=memory_data;data_qq<=data_q;valid_q<=memory_valid;
   if(!calibrated) begin
    if(memory_accept) pending<=1;
    if(valid_q) begin
     count<=count+1'b1;
     if(count[4:0]==31) pending<=0;
     if(!audit) begin
      crc_normal<=next_normal;crc_early<=next_early;crc_late<=next_late;
      if(count==21'd1023) begin
       observed_normal<=~next_normal;observed_early<=~next_early;observed_late<=~next_late;
       count<=0;
       case(matches)
        3'b001:begin status<=1;audit<=1;end
        3'b010:begin status<=2;audit<=1;end
        3'b100:begin status<=3;audit<=1;end
        default:begin status<=4;calibrated<=1;verified<=0;end
       endcase
      end
     end else begin
      crc_full<=next_full;
      if(count==song_words-1'b1) begin
       calibrated<=1;verified<=(~next_full==expected_full);
      end
     end
    end
   end
  end
 end
endmodule

// CRC32/ISO-HDLC, reflected input, byte order low byte first.
module audio_align_crc_step(input [31:0] crc,word,output [31:0] next_crc);
 wire [63:0] crc_inputs={word,crc};
 assign next_crc[0]=^(crc_inputs & 64'h04d101df04d101df);
 assign next_crc[1]=^(crc_inputs & 64'h09a203be09a203be);
 assign next_crc[2]=^(crc_inputs & 64'h1344077d1344077d);
 assign next_crc[3]=^(crc_inputs & 64'h26880efa26880efa);
 assign next_crc[4]=^(crc_inputs & 64'h4d101df44d101df4);
 assign next_crc[5]=^(crc_inputs & 64'h9a203be99a203be9);
 assign next_crc[6]=^(crc_inputs & 64'h3091760d3091760d);
 assign next_crc[7]=^(crc_inputs & 64'h6122ec1a6122ec1a);
 assign next_crc[8]=^(crc_inputs & 64'hc245d835c245d835);
 assign next_crc[9]=^(crc_inputs & 64'h805ab1b5805ab1b5);
 assign next_crc[10]=^(crc_inputs & 64'h046462b5046462b5);
 assign next_crc[11]=^(crc_inputs & 64'h08c8c56a08c8c56a);
 assign next_crc[12]=^(crc_inputs & 64'h11918ad411918ad4);
 assign next_crc[13]=^(crc_inputs & 64'h232315a9232315a9);
 assign next_crc[14]=^(crc_inputs & 64'h46462b5346462b53);
 assign next_crc[15]=^(crc_inputs & 64'h8c8c56a68c8c56a6);
 assign next_crc[16]=^(crc_inputs & 64'h1dc9ac921dc9ac92);
 assign next_crc[17]=^(crc_inputs & 64'h3b9359243b935924);
 assign next_crc[18]=^(crc_inputs & 64'h7726b2497726b249);
 assign next_crc[19]=^(crc_inputs & 64'hee4d6493ee4d6493);
 assign next_crc[20]=^(crc_inputs & 64'hd84bc8f9d84bc8f9);
 assign next_crc[21]=^(crc_inputs & 64'hb446902db446902d);
 assign next_crc[22]=^(crc_inputs & 64'h6c5c21846c5c2184);
 assign next_crc[23]=^(crc_inputs & 64'hd8b84309d8b84309);
 assign next_crc[24]=^(crc_inputs & 64'hb5a187ccb5a187cc);
 assign next_crc[25]=^(crc_inputs & 64'h6f920e466f920e46);
 assign next_crc[26]=^(crc_inputs & 64'hdf241c8cdf241c8c);
 assign next_crc[27]=^(crc_inputs & 64'hba9938c7ba9938c7);
 assign next_crc[28]=^(crc_inputs & 64'h71e3705171e37051);
 assign next_crc[29]=^(crc_inputs & 64'he3c6e0a3e3c6e0a3);
 assign next_crc[30]=^(crc_inputs & 64'hc35cc098c35cc098);
 assign next_crc[31]=^(crc_inputs & 64'h826880ef826880ef);
endmodule
