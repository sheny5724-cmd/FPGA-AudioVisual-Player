// V16 audio arena: concatenate the two gaps between the RGB32 frame buffers.
// Physical words [0,307199] and [1048576,1355775] remain image-only.
// Each caller supplies base < 1482752 and offset < 1482752, so one wrap suffices.
// All read bursts begin at multiples of 32; both gap boundaries are aligned.
module audio_buffer_map(input [20:0] base_word,input [20:0] offset,
 output [20:0] physical_word);
 wire [21:0] sum={1'b0,base_word}+{1'b0,offset};
 wire [21:0] wrapped=sum>=22'd1482752 ? sum-22'd1482752 : sum;
 assign physical_word=wrapped[20:0]+(wrapped<22'd741376 ? 21'd307200 : 21'd614400);
endmodule
