// V16: each resident descriptor retains its own alignment and whole-song CRC.
// Current playback wins over background audit at each 32-word burst boundary.
// owner is latched on accept and remains fixed through all returned data.
module audio_slots(input clk,input reset,input active_slot,input [1:0] loaded,
 input [31:0] full_crc0,input [31:0] full_crc1,input [31:0] probe_crc0,input [31:0] probe_crc1,
 input [20:0] words0,input [20:0] words1,
 input [20:0] base0,input [20:0] base1,
 input [31:0] memory_data,input memory_valid,input memory_accept,
 input player_request,input [20:0] player_address,
 output memory_request,output [20:0] memory_address,
 output player_accept,output player_valid,output [31:0] player_data,
 output [1:0] calibrated,output [1:0] verified);
 wire [1:0] request,accept,valid;
 wire [20:0] address0,address1;
 wire [31:0] data0,data1;
 reg owner;
 wire active_request=active_slot ? request[1] : request[0];
 wire chosen=active_request ? active_slot : ~active_slot;
 assign memory_request=|request;
 assign memory_address=chosen ? address1 : address0;
 assign player_accept=active_slot ? accept[1] : accept[0];
 assign player_valid=active_slot ? valid[1] : valid[0];
 assign player_data=active_slot ? data1 : data0;
 always @(posedge clk)
  if(reset) owner<=0;else if(memory_accept) owner<=chosen;
 audio_read_align slot0(
  .clk(clk),.reset(reset),.loaded(loaded[0]),.expected(probe_crc0),.expected_full(full_crc0),.song_words(words0),.base_word(base0),
  .memory_data(memory_data),.memory_valid(memory_valid && !owner),.memory_accept(memory_accept && !chosen),
  .player_request(player_request && !active_slot),.player_address(player_address),
  .memory_request(request[0]),.memory_address(address0),
  .player_accept(accept[0]),.player_valid(valid[0]),.player_data(data0),
  .calibrated(calibrated[0]),.status(),.observed_normal(),.observed_early(),.observed_late(),
  .verified(verified[0]));
 audio_read_align slot1(
  .clk(clk),.reset(reset),.loaded(loaded[1]),.expected(probe_crc1),.expected_full(full_crc1),.song_words(words1),.base_word(base1),
  .memory_data(memory_data),.memory_valid(memory_valid && owner),.memory_accept(memory_accept && chosen),
  .player_request(player_request && active_slot),.player_address(player_address),
  .memory_request(request[1]),.memory_address(address1),
  .player_accept(accept[1]),.player_valid(valid[1]),.player_data(data1),
  .calibrated(calibrated[1]),.status(),.observed_normal(),.observed_early(),.observed_late(),
  .verified(verified[1]));
endmodule
