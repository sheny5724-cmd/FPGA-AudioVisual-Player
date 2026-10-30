// Streaming BI_RGB24 BMP scaler, 1..2048 pixels per dimension.
// Aspect-fit nearest neighbor, one row RAM, complete aligned canvas rows.
module bmp24_loader(input clk,input reset,input byte_valid,input [7:0] byte_data,
 input frame_bank,output reg pixel_valid,output reg [20:0] pixel_addr,
 output reg [31:0] pixel_data,output reg done,output reg [3:0] error,
 input throttle,output byte_ready);
 localparam HEADER=0,GEOMETRY=1,DIVIDE=2,SETUP=3,PREFIX=4,
 READ_ROW=5,PADDING=6,CHECK_ROW=7,START_ROW=8,FETCH=9,
 EMIT=10,STEP_X=11,END_ROW=12,STEP_Y=13,NEXT_ROW=14;
 reg [3:0] state;
 reg [31:0] pos,offset,dib,width,height,compression;
 reg [15:0] signature,planes,bpp;
 wire [31:0] abs_height=height[31] ? (~height+32'd1) : height;
 reg top_down,width_limited;
 reg [11:0] source_w,source_h,source_row,wanted_row,source_x;
 reg [9:0] dest_w,dest_h,left_margin,leading_rows,canvas_row,image_row,column;
 reg [18:0] rowbase;
 reg [1:0] component,pad_left;
 reg [11:0] input_x;
 reg [7:0] b,g;
 reg [23:0] row_ram[0:2047];
 reg [23:0] row_pixel;
 reg [12:0] x_acc,y_acc;
 // Geometry uses a 21-cycle divider, not a combinational divider.
 reg [20:0] dividend,quotient;
 reg [12:0] remainder;
 reg [11:0] divisor;
 reg [4:0] div_count;
 wire [12:0] trial={remainder[11:0],dividend[20]};
 wire [20:0] next_q={quotient[19:0],trial>={1'b0,divisor}};
 wire [20:0] fit_w_product={9'b0,source_w}*21'd480;
 wire [20:0] fit_h_product={9'b0,source_h}*21'd640;
 wire image_column=column>=left_margin && column<left_margin+dest_w;
 wire image_line=canvas_row>=leading_rows && canvas_row<leading_rows+dest_h;
 assign byte_ready=!done && error==0 &&
 (state==HEADER || state==PREFIX || state==READ_ROW || state==PADDING);
 always @(posedge clk) begin
  if(byte_valid && byte_ready && state==READ_ROW && component==2)
   row_ram[input_x[10:0]]<={byte_data,g,b};
  if(state==FETCH) row_pixel<=row_ram[source_x[10:0]];
 end
 always @(posedge clk) begin
  pixel_valid<=0;
  if(reset) begin
   state<=HEADER;pos<=0;offset<=0;dib<=0;width<=0;height<=0;compression<=0;
   signature<=0;planes<=0;bpp<=0;top_down<=0;width_limited<=0;
   source_w<=0;source_h<=0;source_row<=0;wanted_row<=0;source_x<=0;
   dest_w<=0;dest_h<=0;left_margin<=0;leading_rows<=0;canvas_row<=0;
   image_row<=0;column<=0;rowbase<=0;component<=0;pad_left<=0;
   input_x<=0;b<=0;g<=0;x_acc<=0;y_acc<=0;
   dividend<=0;quotient<=0;remainder<=0;divisor<=0;div_count<=0;
   done<=0;error<=0;pixel_addr<=0;pixel_data<=0;
  end else if(!done && error==0) begin
   if(byte_valid && byte_ready) pos<=pos+1'b1;
   case(state)
    HEADER:if(byte_valid) begin
     case(pos)
      0:signature[7:0]<=byte_data;1:signature[15:8]<=byte_data;
      10:offset[7:0]<=byte_data;11:offset[15:8]<=byte_data;
      12:offset[23:16]<=byte_data;13:offset[31:24]<=byte_data;
      14:dib[7:0]<=byte_data;15:dib[15:8]<=byte_data;
      16:dib[23:16]<=byte_data;17:dib[31:24]<=byte_data;
      18:width[7:0]<=byte_data;19:width[15:8]<=byte_data;
      20:width[23:16]<=byte_data;21:width[31:24]<=byte_data;
      22:height[7:0]<=byte_data;23:height[15:8]<=byte_data;
      24:height[23:16]<=byte_data;25:height[31:24]<=byte_data;
      26:planes[7:0]<=byte_data;27:planes[15:8]<=byte_data;
      28:bpp[7:0]<=byte_data;29:bpp[15:8]<=byte_data;
      30:compression[7:0]<=byte_data;31:compression[15:8]<=byte_data;
      32:compression[23:16]<=byte_data;33:compression[31:24]<=byte_data;
      53:begin
       if(signature!=16'h4d42 || dib<40 || dib>4042 || offset<14+dib || offset>4096) error<=1;
       else if(width==0 || width>2048 || abs_height==0 || abs_height>2048) error<=2;
       else if(planes!=1 || bpp!=24 || compression!=0) error<=3;
       else begin
        source_w<=width[11:0];source_h<=abs_height[11:0];
        top_down<=height[31];state<=GEOMETRY;
       end
      end
     endcase
    end
    GEOMETRY:begin
     width_limited<=fit_w_product>=fit_h_product;
     if(fit_w_product>=fit_h_product) begin
      dest_w<=640;dividend<=fit_h_product;divisor<=source_w;
     end else begin
      dest_h<=480;dividend<=fit_w_product;divisor<=source_h;
     end
     quotient<=0;remainder<=0;div_count<=20;state<=DIVIDE;
    end
    DIVIDE:begin
     dividend<={dividend[19:0],1'b0};quotient<=next_q;
     remainder<=trial>={1'b0,divisor} ? trial-{1'b0,divisor} : trial;
     if(div_count==0) begin
      if(width_limited) dest_h<=next_q==0 ? 10'd1 : next_q[9:0];
      else dest_w<=next_q==0 ? 10'd1 : next_q[9:0];
      state<=SETUP;
     end else div_count<=div_count-1'b1;
    end
    SETUP:begin
     left_margin<=(640-dest_w)>>1;
     leading_rows<=top_down ? ((480-dest_h)>>1) : 480-dest_h-((480-dest_h)>>1);
     rowbase<=top_down ? 19'd0 : 19'd306560;
     source_row<=0;wanted_row<=0;image_row<=0;canvas_row<=0;
     y_acc<=0;state<=NEXT_ROW;
    end
    PREFIX:begin
     if(pos==offset) state<=READ_ROW;
     if(byte_valid && pos+1'b1==offset) state<=READ_ROW;
    end
    READ_ROW:if(byte_valid) begin
     case(component)
      0:begin b<=byte_data;component<=1;end
      1:begin g<=byte_data;component<=2;end
      2:begin
       component<=0;
       if(input_x==source_w-1'b1) begin
        input_x<=0;
        // (-3*width) mod 4 == width mod 4.
        pad_left<=source_w[1:0];
        state<=source_w[1:0]==0 ? CHECK_ROW : PADDING;
       end else input_x<=input_x+1'b1;
      end
     endcase
    end
    PADDING:if(byte_valid) begin
     pad_left<=pad_left-1'b1;
     if(pad_left==1) state<=CHECK_ROW;
    end
    CHECK_ROW:begin
     if(source_row==wanted_row) state<=START_ROW;
     else begin source_row<=source_row+1'b1;state<=READ_ROW;end
    end
    NEXT_ROW:begin
     if(!image_line) state<=START_ROW;
     else if(pos<offset) state<=PREFIX;
     else state<=READ_ROW;
    end
    START_ROW:begin
     column<=0;source_x<=0;x_acc<=0;state<=FETCH;
    end
    FETCH:state<=EMIT;
    EMIT:if(!throttle) begin
     pixel_valid<=1;
     pixel_addr<={frame_bank,20'b0}+rowbase+column;
     pixel_data<=image_line && image_column ? {8'b0,row_pixel} : 32'b0;
     if(column==639) state<=END_ROW;
     else begin
      column<=column+1'b1;
      if(image_line && image_column && column<left_margin+dest_w-1'b1) begin
       x_acc<=x_acc+source_w;state<=STEP_X;
      end else state<=FETCH;
     end
    end
    STEP_X:begin
     if(x_acc>=dest_w) begin
      x_acc<=x_acc-dest_w;source_x<=source_x+1'b1;
     end else state<=FETCH;
    end
    END_ROW:begin
     if(canvas_row==479) done<=1;
     else begin
      canvas_row<=canvas_row+1'b1;
      rowbase<=top_down ? rowbase+640 : rowbase-640;
      if(image_line && image_row<dest_h-1'b1) begin
       image_row<=image_row+1'b1;y_acc<=y_acc+source_h;state<=STEP_Y;
      end else state<=NEXT_ROW;
     end
    end
    STEP_Y:begin
     if(y_acc>=dest_h) begin
      y_acc<=y_acc-dest_h;wanted_row<=wanted_row+1'b1;
     end else if(wanted_row==source_row) state<=START_ROW;
     else begin source_row<=source_row+1'b1;state<=READ_ROW;end
    end
    default:error<=1;
   endcase
  end
 end
endmodule
