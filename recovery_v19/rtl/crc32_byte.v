// CRC32/ISO-HDLC byte update. Start at FFFFFFFF, complement at the end.
module crc32_byte(input [31:0] crc,input [7:0] data,output [31:0] next_crc);
 wire [31:0] c[0:8];
 assign c[0]=crc^{24'b0,data};
 genvar bit_index;
 generate for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin:bits
  assign c[bit_index+1]=(c[bit_index]>>1)^(c[bit_index][0] ? 32'hedb88320 : 32'd0);
 end endgenerate
 assign next_crc=c[8];
endmodule
