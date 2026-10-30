// One compact ASCII row: e.g. MUSIC 2 MISSING      RETRY 1/2 K4.
module recovery_text(input [14:0] info,input [5:0] index,output reg [7:0] character);
 reg [63:0] name_text;
 reg [95:0] reason_text;
 reg [127:0] action_text;
 always @* begin
  case(info[13:12])
   1:name_text="CATALOG ";2:name_text={"PIC ",8'd49+{5'd0,info[11:9]},"   "};
   default:name_text={"MUSIC ",8'd49+{5'd0,info[11:9]}," "};
  endcase
  case(info[8:5])
   1:reason_text="MISSING     ";2:reason_text="BAD HEADER  ";3:reason_text="CRC ERROR   ";
   4:reason_text="READ TIMEOUT";5:reason_text="BUFFER FULL ";6:reason_text="SHORT FILE  ";
   7:reason_text="MEM STALL   ";8:reason_text="UNSUPPORTED ";
   default:reason_text="            ";
  endcase
  case(info[4:2])
   1:action_text={"RETRY ",8'd48+{6'd0,info[1:0]},"/2 K4    "};
   2:action_text="SKIPPED K4 RETRY";
   3:action_text="STOPPED K4 RETRY";
   4:action_text="RESTARTING      ";
   default:action_text="                ";
  endcase
  character=8'd32;
  if(index<8) character=name_text[(7-index)*8 +:8];
  else if(index<20) character=reason_text[(19-index)*8 +:8];
  else if(index<36) character=action_text[(35-index)*8 +:8];
 end
endmodule
