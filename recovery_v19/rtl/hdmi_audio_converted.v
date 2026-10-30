// Converted using sv2v v0.0.13. Original .sv and licenses accompany this file.
module hdmi_audio_bridge (
	clk,
	reset,
	phase,
	x,
	y,
	hs,
	vs,
	music_pcm,
	sample_toggle,
	audio_fault,
	override_video,
	symbols,
	visual_ce,
	visual_left,
	visual_right
);
	input wire clk;
	input wire reset;
	input wire [2:0] phase;
	input wire [9:0] x;
	input wire [9:0] y;
	input wire hs;
	input wire vs;
	input wire [31:0] music_pcm;
	output reg sample_toggle;
	output wire audio_fault;
	output reg override_video;
	output reg [29:0] symbols;
	output wire visual_ce;
	output wire signed [15:0] visual_left;
	output wire signed [15:0] visual_right;
	reg [9:0] px;
	reg [9:0] py;
	always @(posedge clk)
		if (reset) begin
			px <= 0;
			py <= 0;
		end
		else if (phase == 0) begin
			px <= x;
			py <= y;
		end
	reg [26:0] audio_acc = 0;
	wire [27:0] audio_sum = {1'b0, audio_acc} + 28'd48000;
	wire audio_ce = !reset && (audio_sum >= 28'd125000000);
	reg [31:0] pcm_sync1;
	reg [31:0] pcm_sync2;
	assign visual_ce = audio_ce;
	assign visual_left = pcm_sync2[15:0];
	assign visual_right = pcm_sync2[31:16];
	always @(posedge clk)
		if (reset) begin
			audio_acc <= 0;
			sample_toggle <= 0;
			pcm_sync1 <= 0;
			pcm_sync2 <= 0;
		end
		else begin
			audio_acc <= (audio_ce ? audio_sum - 28'd125000000 : audio_sum);
			if (audio_ce)
				sample_toggle <= ~sample_toggle;
			pcm_sync1 <= music_pcm;
			pcm_sync2 <= pcm_sync1;
		end
	wire island = (px >= 654) && (px < 782);
	wire choose_packet = island && (px[4:0] == 5'd14);
	wire island_guard = ((px >= 652) && (px < 654)) || ((px >= 782) && (px < 784));
	wire island_pre = (px >= 644) && (px < 652);
	wire video_line = (py < 479) || (py == 524);
	wire video_guard = video_line && (px >= 798);
	wire video_pre = (video_line && (px >= 790)) && (px < 798);
	wire [23:0] header;
	wire [223:0] sub;
	wire [4:0] packet_counter;
	wire [8:0] packet_bits;
	audio_packet_queue picker(
		.clk(clk),
		.reset(reset),
		.pixel_ce(phase == 1),
		.audio_ce(audio_ce),
		.stereo(pcm_sync2),
		.packet_enable(choose_packet),
		.video_field_end((px == 639) && (py == 479)),
		.header(header),
		.sub(sub),
		.fault(audio_fault)
	);
	packet_assembler assembler(
		.clk_pixel(clk),
		.pixel_ce(reset || (phase == 3)),
		.reset(reset),
		.data_island_period(island),
		.header(header),
		.sub(sub),
		.packet_data(packet_bits),
		.counter(packet_counter)
	);
	reg [8:0] bits_q;
	always @(posedge clk)
		if (reset)
			bits_q <= 0;
		else if (phase == 2)
			bits_q <= packet_bits;
	function [9:0] control_code;
		input [1:0] c;
		case (c)
			0: control_code = 10'b1101010100;
			1: control_code = 10'b0010101011;
			2: control_code = 10'b0101010100;
			3: control_code = 10'b1010101011;
		endcase
	endfunction
	function [9:0] terc4;
		input [3:0] c;
		case (c)
			0: terc4 = 10'b1010011100;
			1: terc4 = 10'b1001100011;
			2: terc4 = 10'b1011100100;
			3: terc4 = 10'b1011100010;
			4: terc4 = 10'b0101110001;
			5: terc4 = 10'b0100011110;
			6: terc4 = 10'b0110001110;
			7: terc4 = 10'b0100111100;
			8: terc4 = 10'b1011001100;
			9: terc4 = 10'b0100111001;
			10: terc4 = 10'b0110011100;
			11: terc4 = 10'b1011000110;
			12: terc4 = 10'b1010001110;
			13: terc4 = 10'b1001110001;
			14: terc4 = 10'b0101100011;
			15: terc4 = 10'b1011000011;
		endcase
	endfunction
	always @(posedge clk)
		if (reset) begin
			override_video <= 0;
			symbols <= 0;
		end
		else if (phase == 4) begin
			override_video <= !((px < 640) && (py < 480));
			if (island_guard)
				symbols <= {20'b01001100110100110011, terc4({2'b11, vs, hs})};
			else if (island)
				symbols <= {terc4(bits_q[8:5]), terc4(bits_q[4:1]), terc4({1'b1, bits_q[0], vs, hs})};
			else if (video_guard)
				symbols <= 30'b101100110001001100111011001100;
			else
				symbols <= {control_code({1'b0, island_pre}), control_code({1'b0, island_pre || video_pre}), control_code({vs, hs})};
		end
endmodule
module audio_packet_queue (
	clk,
	reset,
	pixel_ce,
	audio_ce,
	packet_enable,
	video_field_end,
	stereo,
	header,
	sub,
	fault
);
	input wire clk;
	input wire reset;
	input wire pixel_ce;
	input wire audio_ce;
	input wire packet_enable;
	input wire video_field_end;
	input wire [31:0] stereo;
	output reg [23:0] header;
	output reg [223:0] sub;
	output reg fault;
	reg [31:0] fifo [0:15];
	reg [3:0] wp;
	reg [3:0] rp;
	reg [4:0] count;
	reg [5:0] acr_samples;
	reg acr_pending;
	reg avi_sent;
	reg audio_sent;
	reg spd_sent;
	reg [7:0] frame_counter;
	wire select_packet = (pixel_ce && packet_enable) && !reset;
	wire take_audio = (select_packet && !acr_pending) && (count >= 4);
	wire push = (audio_ce && ((count < 16) || take_audio)) && !reset;
	wire acr_tick = audio_ce && (acr_samples == 47);
	wire [23:0] audio_header;
	wire [23:0] avi_header;
	wire [23:0] info_header;
	wire [23:0] spd_header;
	wire [223:0] audio_sub;
	wire [223:0] avi_sub;
	wire [223:0] info_sub;
	wire [223:0] spd_sub;
	wire [191:0] samples;
	genvar _gv_g_1;
	generate
		for (_gv_g_1 = 0; _gv_g_1 < 4; _gv_g_1 = _gv_g_1 + 1) begin : gather
			localparam g = _gv_g_1;
			wire [3:0] index = rp + g;
			assign samples[(g * 2) * 24+:24] = {fifo[index][15:0], 8'd0};
			assign samples[((g * 2) + 1) * 24+:24] = {fifo[index][31:16], 8'd0};
		end
	endgenerate
	audio_sample_packet #(
		.SAMPLING_FREQUENCY(4'b0010),
		.WORD_LENGTH(4'b0010)
	) sample_packet(
		.frame_counter(frame_counter),
		.valid_bit(8'h00),
		.user_data_bit(8'h00),
		.audio_sample_word(samples),
		.audio_sample_word_present(4'b1111),
		.header(audio_header),
		.sub(audio_sub)
	);
	audio_info_frame info(
		.header(info_header),
		.sub(info_sub)
	);
	auxiliary_video_information_info_frame #(
		.VIDEO_ID_CODE(7'd1),
		.IT_CONTENT(1'b1)
	) avi(
		.header(avi_header),
		.sub(avi_sub)
	);
	source_product_description_info_frame #(
		.VENDOR_NAME({"HX4S20C", 8'd0}),
		.PRODUCT_DESCRIPTION({"FPGA PLAYER", 40'd0}),
		.SOURCE_DEVICE_INFORMATION(0)
	) spd(
		.header(spd_header),
		.sub(spd_sub)
	);
	integer i;
	always @(posedge clk)
		if (reset) begin
			wp <= 0;
			rp <= 0;
			count <= 0;
			acr_samples <= 0;
			acr_pending <= 1;
			avi_sent <= 0;
			audio_sent <= 0;
			spd_sent <= 0;
			frame_counter <= 0;
			fault <= 0;
			header <= 0;
			for (i = 0; i < 4; i = i + 1)
				sub[i * 56+:56] <= 0;
		end
		else begin
			if (push) begin
				fifo[wp] <= stereo;
				wp <= wp + 1'b1;
			end
			if (audio_ce && !push)
				fault <= 1;
			case ({push, take_audio})
				2'b10: count <= count + 1'b1;
				2'b01: count <= count - 5'd4;
				2'b11: count <= count - 5'd3;
			endcase
			if (audio_ce)
				acr_samples <= (acr_tick ? 0 : acr_samples + 1'b1);
			if (pixel_ce && video_field_end) begin
				avi_sent <= 0;
				audio_sent <= 0;
				spd_sent <= 0;
			end
			if (select_packet) begin
				if (acr_pending) begin
					header <= 24'h000001;
					for (i = 0; i < 4; i = i + 1)
						sub[i * 56+:56] <= 56'h001800a8610000;
					acr_pending <= 0;
				end
				else if (take_audio) begin
					header <= audio_header;
					for (i = 0; i < 4; i = i + 1)
						sub[i * 56+:56] <= audio_sub[i * 56+:56];
					rp <= rp + 4'd4;
					frame_counter <= (frame_counter == 188 ? 0 : frame_counter + 8'd4);
				end
				else if (!audio_sent) begin
					header <= info_header;
					for (i = 0; i < 4; i = i + 1)
						sub[i * 56+:56] <= info_sub[i * 56+:56];
					audio_sent <= 1;
				end
				else if (!avi_sent) begin
					header <= avi_header;
					for (i = 0; i < 4; i = i + 1)
						sub[i * 56+:56] <= avi_sub[i * 56+:56];
					avi_sent <= 1;
				end
				else if (!spd_sent) begin
					header <= spd_header;
					for (i = 0; i < 4; i = i + 1)
						sub[i * 56+:56] <= spd_sub[i * 56+:56];
					spd_sent <= 1;
				end
				else begin
					header <= 0;
					for (i = 0; i < 4; i = i + 1)
						sub[i * 56+:56] <= 0;
				end
			end
			if (acr_tick)
				acr_pending <= 1;
		end
endmodule
module packet_assembler (
	clk_pixel,
	pixel_ce,
	reset,
	data_island_period,
	header,
	sub,
	packet_data,
	counter
);
	input wire clk_pixel;
	input wire pixel_ce;
	input wire reset;
	input wire data_island_period;
	input wire [23:0] header;
	input wire [223:0] sub;
	output wire [8:0] packet_data;
	output reg [4:0] counter = 5'd0;
	always @(posedge clk_pixel)
		if (pixel_ce) begin
			if (reset)
				counter <= 5'd0;
			else if (data_island_period)
				counter <= counter + 5'd1;
		end
	wire [5:0] counter_t2 = {counter, 1'b0};
	wire [5:0] counter_t2_p1 = {counter, 1'b1};
	reg [39:0] parity = 40'h0000000000;
	wire [63:0] bch [3:0];
	assign bch[0] = {parity[0+:8], sub[0+:56]};
	assign bch[1] = {parity[8+:8], sub[56+:56]};
	assign bch[2] = {parity[16+:8], sub[112+:56]};
	assign bch[3] = {parity[24+:8], sub[168+:56]};
	wire [31:0] bch4 = {parity[32+:8], header};
	assign packet_data = {bch[3][counter_t2_p1], bch[2][counter_t2_p1], bch[1][counter_t2_p1], bch[0][counter_t2_p1], bch[3][counter_t2], bch[2][counter_t2], bch[1][counter_t2], bch[0][counter_t2], bch4[counter]};
	function automatic [7:0] next_ecc;
		input [7:0] ecc;
		input [7:0] next_bch_bit;
		next_ecc = (ecc >> 1) ^ (ecc[0] ^ next_bch_bit ? 8'b10000011 : 8'd0);
	endfunction
	wire [7:0] parity_next [4:0];
	wire [31:0] parity_next_next;
	genvar _gv_i_1;
	generate
		for (_gv_i_1 = 0; _gv_i_1 < 5; _gv_i_1 = _gv_i_1 + 1) begin : parity_calc
			localparam i = _gv_i_1;
			if (i == 4) begin : genblk1
				assign parity_next[i] = next_ecc(parity[i * 8+:8], header[counter]);
			end
			else begin : genblk1
				assign parity_next[i] = next_ecc(parity[i * 8+:8], sub[(i * 56) + counter_t2]);
				assign parity_next_next[i * 8+:8] = next_ecc(parity_next[i], sub[(i * 56) + counter_t2_p1]);
			end
		end
	endgenerate
	always @(posedge clk_pixel)
		if (pixel_ce) begin
			if (reset)
				parity <= 40'h0000000000;
			else if (data_island_period) begin
				if (counter < 5'd28) begin
					parity[0+:32] <= parity_next_next;
					if (counter < 5'd24)
						parity[32+:8] <= parity_next[4];
				end
				else if (counter == 5'd31)
					parity <= 40'h0000000000;
			end
			else
				parity <= 40'h0000000000;
		end
endmodule
module audio_sample_packet (
	frame_counter,
	valid_bit,
	user_data_bit,
	audio_sample_word,
	audio_sample_word_present,
	header,
	sub
);
	reg _sv2v_0;
	parameter [0:0] GRADE = 1'b0;
	parameter [0:0] SAMPLE_WORD_TYPE = 1'b0;
	parameter [0:0] COPYRIGHT_NOT_ASSERTED = 1'b1;
	parameter [2:0] PRE_EMPHASIS = 3'b000;
	parameter [1:0] MODE = 2'b00;
	parameter [7:0] CATEGORY_CODE = 8'd0;
	parameter [3:0] SOURCE_NUMBER = 4'd0;
	parameter [3:0] SAMPLING_FREQUENCY = 4'b0000;
	parameter [1:0] CLOCK_ACCURACY = 2'b00;
	parameter [3:0] WORD_LENGTH = 0;
	parameter [3:0] ORIGINAL_SAMPLING_FREQUENCY = 4'b0000;
	parameter [0:0] LAYOUT = 1'b0;
	input wire [7:0] frame_counter;
	input wire [7:0] valid_bit;
	input wire [7:0] user_data_bit;
	input wire [191:0] audio_sample_word;
	input wire [3:0] audio_sample_word_present;
	output wire [23:0] header;
	output reg [223:0] sub;
	reg [3:0] CHANNEL_LEFT = 4'd1;
	reg [3:0] CHANNEL_RIGHT = 4'd2;
	localparam [7:0] CHANNEL_STATUS_LENGTH = 8'd192;
	wire [191:0] channel_status_left;
	assign channel_status_left = {152'd0, ORIGINAL_SAMPLING_FREQUENCY, WORD_LENGTH, 2'b00, CLOCK_ACCURACY, SAMPLING_FREQUENCY, CHANNEL_LEFT, SOURCE_NUMBER, CATEGORY_CODE, MODE, PRE_EMPHASIS, COPYRIGHT_NOT_ASSERTED, SAMPLE_WORD_TYPE, GRADE};
	wire [CHANNEL_STATUS_LENGTH - 1:0] channel_status_right;
	assign channel_status_right = {152'd0, ORIGINAL_SAMPLING_FREQUENCY, WORD_LENGTH, 2'b00, CLOCK_ACCURACY, SAMPLING_FREQUENCY, CHANNEL_RIGHT, SOURCE_NUMBER, CATEGORY_CODE, MODE, PRE_EMPHASIS, COPYRIGHT_NOT_ASSERTED, SAMPLE_WORD_TYPE, GRADE};
	assign header[19:12] = {7'b0000000, LAYOUT};
	assign header[7:0] = 8'd2;
	wire [1:0] parity_bit [3:0];
	reg [7:0] aligned_frame_counter [3:0];
	genvar _gv_i_2;
	function automatic [7:0] sv2v_cast_8;
		input reg [7:0] inp;
		sv2v_cast_8 = inp;
	endfunction
	generate
		for (_gv_i_2 = 0; _gv_i_2 < 4; _gv_i_2 = _gv_i_2 + 1) begin : sample_based_assign
			localparam i = _gv_i_2;
			always @(*) begin
				if (_sv2v_0)
					;
				if (sv2v_cast_8(frame_counter + i) >= CHANNEL_STATUS_LENGTH)
					aligned_frame_counter[i] = sv2v_cast_8((frame_counter + i) - CHANNEL_STATUS_LENGTH);
				else
					aligned_frame_counter[i] = sv2v_cast_8(frame_counter + i);
			end
			assign header[20 + i] = (aligned_frame_counter[i] == 8'd0) && audio_sample_word_present[i];
			assign header[8 + i] = audio_sample_word_present[i];
			assign parity_bit[i][0] = ^{channel_status_left[aligned_frame_counter[i]], user_data_bit[i * 2], valid_bit[i * 2], audio_sample_word[(i * 2) * 24+:24]};
			assign parity_bit[i][1] = ^{channel_status_right[aligned_frame_counter[i]], user_data_bit[(i * 2) + 1], valid_bit[(i * 2) + 1], audio_sample_word[((i * 2) + 1) * 24+:24]};
			always @(*) begin
				if (_sv2v_0)
					;
				if (audio_sample_word_present[i])
					sub[i * 56+:56] = {parity_bit[i][1], channel_status_right[aligned_frame_counter[i]], user_data_bit[(i * 2) + 1], valid_bit[(i * 2) + 1], parity_bit[i][0], channel_status_left[aligned_frame_counter[i]], user_data_bit[i * 2], valid_bit[i * 2], audio_sample_word[((i * 2) + 1) * 24+:24], audio_sample_word[(i * 2) * 24+:24]};
				else
					sub[i * 56+:56] = 56'd0;
			end
		end
	endgenerate
	initial _sv2v_0 = 0;
endmodule
module audio_info_frame (
	header,
	sub
);
	parameter [2:0] AUDIO_CHANNEL_COUNT = 3'd1;
	parameter [7:0] CHANNEL_ALLOCATION = 8'h00;
	parameter [0:0] DOWN_MIX_INHIBITED = 1'b0;
	parameter [3:0] LEVEL_SHIFT_VALUE = 4'd0;
	parameter [1:0] LOW_FREQUENCY_EFFECTS_PLAYBACK_LEVEL = 2'b00;
	output wire [23:0] header;
	output wire [223:0] sub;
	localparam [3:0] AUDIO_CODING_TYPE = 4'd0;
	localparam [2:0] SAMPLING_FREQUENCY = 3'd0;
	localparam [1:0] SAMPLE_SIZE = 2'd0;
	localparam [4:0] LENGTH = 5'd10;
	localparam [7:0] VERSION = 8'd1;
	localparam [6:0] TYPE = 7'd4;
	assign header = {3'b000, LENGTH, VERSION, 1'b1, TYPE};
	wire [7:0] packet_bytes [27:0];
	assign packet_bytes[0] = 8'd1 + ~(((((((header[23:16] + header[15:8]) + header[7:0]) + packet_bytes[5]) + packet_bytes[4]) + packet_bytes[3]) + packet_bytes[2]) + packet_bytes[1]);
	assign packet_bytes[1] = {AUDIO_CODING_TYPE, 1'b0, AUDIO_CHANNEL_COUNT};
	assign packet_bytes[2] = {3'd0, SAMPLING_FREQUENCY, SAMPLE_SIZE};
	assign packet_bytes[3] = 8'd0;
	assign packet_bytes[4] = CHANNEL_ALLOCATION;
	assign packet_bytes[5] = {DOWN_MIX_INHIBITED, LEVEL_SHIFT_VALUE, 1'b0, LOW_FREQUENCY_EFFECTS_PLAYBACK_LEVEL};
	genvar _gv_i_3;
	generate
		for (_gv_i_3 = 6; _gv_i_3 < 28; _gv_i_3 = _gv_i_3 + 1) begin : pb_reserved
			localparam i = _gv_i_3;
			assign packet_bytes[i] = 8'd0;
		end
		for (_gv_i_3 = 0; _gv_i_3 < 4; _gv_i_3 = _gv_i_3 + 1) begin : pb_to_sub
			localparam i = _gv_i_3;
			assign sub[i * 56+:56] = {packet_bytes[6 + (i * 7)], packet_bytes[5 + (i * 7)], packet_bytes[4 + (i * 7)], packet_bytes[3 + (i * 7)], packet_bytes[2 + (i * 7)], packet_bytes[1 + (i * 7)], packet_bytes[0 + (i * 7)]};
		end
	endgenerate
endmodule
module auxiliary_video_information_info_frame (
	header,
	sub
);
	parameter [1:0] VIDEO_FORMAT = 2'b00;
	parameter [0:0] ACTIVE_FORMAT_INFO_PRESENT = 1'b0;
	parameter [1:0] BAR_INFO = 2'b00;
	parameter [1:0] SCAN_INFO = 2'b00;
	parameter [1:0] COLORIMETRY = 2'b00;
	parameter [1:0] PICTURE_ASPECT_RATIO = 2'b00;
	parameter [3:0] ACTIVE_FORMAT_ASPECT_RATIO = 4'b1000;
	parameter [0:0] IT_CONTENT = 1'b0;
	parameter [2:0] EXTENDED_COLORIMETRY = 3'b000;
	parameter [1:0] RGB_QUANTIZATION_RANGE = 2'b00;
	parameter [1:0] NON_UNIFORM_PICTURE_SCALING = 2'b00;
	parameter signed [31:0] VIDEO_ID_CODE = 4;
	parameter [1:0] YCC_QUANTIZATION_RANGE = 2'b00;
	parameter [1:0] CONTENT_TYPE = 2'b00;
	parameter [3:0] PIXEL_REPETITION = 4'b0000;
	output wire [23:0] header;
	output wire [223:0] sub;
	localparam [4:0] LENGTH = 5'd13;
	localparam [7:0] VERSION = 8'd2;
	localparam [6:0] TYPE = 7'd2;
	assign header = {3'b000, LENGTH, VERSION, 1'b1, TYPE};
	wire [7:0] packet_bytes [27:0];
	assign packet_bytes[0] = 8'd1 + ~(((((((((((((((header[23:16] + header[15:8]) + header[7:0]) + packet_bytes[13]) + packet_bytes[12]) + packet_bytes[11]) + packet_bytes[10]) + packet_bytes[9]) + packet_bytes[8]) + packet_bytes[7]) + packet_bytes[6]) + packet_bytes[5]) + packet_bytes[4]) + packet_bytes[3]) + packet_bytes[2]) + packet_bytes[1]);
	assign packet_bytes[1] = {1'b0, VIDEO_FORMAT, ACTIVE_FORMAT_INFO_PRESENT, BAR_INFO, SCAN_INFO};
	assign packet_bytes[2] = {COLORIMETRY, PICTURE_ASPECT_RATIO, ACTIVE_FORMAT_ASPECT_RATIO};
	assign packet_bytes[3] = {IT_CONTENT, EXTENDED_COLORIMETRY, RGB_QUANTIZATION_RANGE, NON_UNIFORM_PICTURE_SCALING};
	function automatic signed [6:0] sv2v_cast_7_signed;
		input reg signed [6:0] inp;
		sv2v_cast_7_signed = inp;
	endfunction
	assign packet_bytes[4] = {1'b0, sv2v_cast_7_signed(VIDEO_ID_CODE)};
	assign packet_bytes[5] = {YCC_QUANTIZATION_RANGE, CONTENT_TYPE, PIXEL_REPETITION};
	genvar _gv_i_4;
	generate
		if (BAR_INFO != 2'b00) begin : genblk1
			assign packet_bytes[6] = 8'hff;
			assign packet_bytes[7] = 8'hff;
			assign packet_bytes[8] = 8'h00;
			assign packet_bytes[9] = 8'h00;
			assign packet_bytes[10] = 8'hff;
			assign packet_bytes[11] = 8'hff;
			assign packet_bytes[12] = 8'h00;
			assign packet_bytes[13] = 8'h00;
		end
		else begin : genblk1
			assign packet_bytes[6] = 8'h00;
			assign packet_bytes[7] = 8'h00;
			assign packet_bytes[8] = 8'h00;
			assign packet_bytes[9] = 8'h00;
			assign packet_bytes[10] = 8'h00;
			assign packet_bytes[11] = 8'h00;
			assign packet_bytes[12] = 8'h00;
			assign packet_bytes[13] = 8'h00;
		end
		for (_gv_i_4 = 14; _gv_i_4 < 28; _gv_i_4 = _gv_i_4 + 1) begin : pb_reserved
			localparam i = _gv_i_4;
			assign packet_bytes[i] = 8'd0;
		end
		for (_gv_i_4 = 0; _gv_i_4 < 4; _gv_i_4 = _gv_i_4 + 1) begin : pb_to_sub
			localparam i = _gv_i_4;
			assign sub[i * 56+:56] = {packet_bytes[6 + (i * 7)], packet_bytes[5 + (i * 7)], packet_bytes[4 + (i * 7)], packet_bytes[3 + (i * 7)], packet_bytes[2 + (i * 7)], packet_bytes[1 + (i * 7)], packet_bytes[0 + (i * 7)]};
		end
	endgenerate
endmodule
module source_product_description_info_frame (
	header,
	sub
);
	parameter [63:0] VENDOR_NAME = 0;
	parameter [127:0] PRODUCT_DESCRIPTION = 0;
	parameter [7:0] SOURCE_DEVICE_INFORMATION = 0;
	output wire [23:0] header;
	output wire [223:0] sub;
	localparam [4:0] LENGTH = 5'd25;
	localparam [7:0] VERSION = 8'd1;
	localparam [6:0] TYPE = 7'd3;
	assign header = {3'b000, LENGTH, VERSION, 1'b1, TYPE};
	wire [7:0] packet_bytes [27:0];
	assign packet_bytes[0] = 8'd1 + ~(((((((((((((((((((((((((((header[23:16] + header[15:8]) + header[7:0]) + packet_bytes[25]) + packet_bytes[24]) + packet_bytes[23]) + packet_bytes[22]) + packet_bytes[21]) + packet_bytes[20]) + packet_bytes[19]) + packet_bytes[18]) + packet_bytes[17]) + packet_bytes[16]) + packet_bytes[15]) + packet_bytes[14]) + packet_bytes[13]) + packet_bytes[12]) + packet_bytes[11]) + packet_bytes[10]) + packet_bytes[9]) + packet_bytes[8]) + packet_bytes[7]) + packet_bytes[6]) + packet_bytes[5]) + packet_bytes[4]) + packet_bytes[3]) + packet_bytes[2]) + packet_bytes[1]);
	wire signed [7:0] vendor_name [0:7];
	wire signed [7:0] product_description [0:15];
	genvar _gv_i_5;
	generate
		for (_gv_i_5 = 0; _gv_i_5 < 8; _gv_i_5 = _gv_i_5 + 1) begin : vendor_to_bytes
			localparam i = _gv_i_5;
			assign vendor_name[i] = VENDOR_NAME[((8 - i) * 8) - 1:(7 - i) * 8];
		end
		for (_gv_i_5 = 0; _gv_i_5 < 16; _gv_i_5 = _gv_i_5 + 1) begin : product_to_bytes
			localparam i = _gv_i_5;
			assign product_description[i] = PRODUCT_DESCRIPTION[((16 - i) * 8) - 1:(15 - i) * 8];
		end
		for (_gv_i_5 = 1; _gv_i_5 < 9; _gv_i_5 = _gv_i_5 + 1) begin : pb_vendor
			localparam i = _gv_i_5;
			assign packet_bytes[i] = (vendor_name[i - 1] == 8'h30 ? 8'h00 : vendor_name[i - 1]);
		end
		for (_gv_i_5 = 9; _gv_i_5 < LENGTH; _gv_i_5 = _gv_i_5 + 1) begin : pb_product
			localparam i = _gv_i_5;
			assign packet_bytes[i] = (product_description[i - 9] == 8'h30 ? 8'h00 : product_description[i - 9]);
		end
	endgenerate
	assign packet_bytes[LENGTH] = SOURCE_DEVICE_INFORMATION;
	generate
		for (_gv_i_5 = 26; _gv_i_5 < 28; _gv_i_5 = _gv_i_5 + 1) begin : pb_reserved
			localparam i = _gv_i_5;
			assign packet_bytes[i] = 8'd0;
		end
		for (_gv_i_5 = 0; _gv_i_5 < 4; _gv_i_5 = _gv_i_5 + 1) begin : pb_to_sub
			localparam i = _gv_i_5;
			assign sub[i * 56+:56] = {packet_bytes[6 + (i * 7)], packet_bytes[5 + (i * 7)], packet_bytes[4 + (i * 7)], packet_bytes[3 + (i * 7)], packet_bytes[2 + (i * 7)], packet_bytes[1 + (i * 7)], packet_bytes[0 + (i * 7)]};
		end
	endgenerate
endmodule
