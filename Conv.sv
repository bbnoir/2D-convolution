module Conv(
	// Input signals
	clk,
	rst_n,
	filter_valid,
	image_valid,
	filter_size,
	image_size,
	pad_mode,
	act_mode,
	in_data,
	// Output signals
	out_valid,
	out_data
);

//---------------------------------------------------------------------
//   INPUT AND OUTPUT DECLARATION                         
//---------------------------------------------------------------------
input clk, rst_n, image_valid, filter_valid, filter_size, pad_mode, act_mode;
input [3:0] image_size;
input signed [7:0] in_data;
output logic out_valid;
output logic signed [15:0] out_data;

//---------------------------------------------------------------------
//   Your design                       
//---------------------------------------------------------------------
logic signed [7:0] filter [0:24];
logic signed [7:0] filter_nxt [0:24];
logic signed [7:0] image [0:11][0:11];
logic signed [7:0] image_nxt [0:11][0:11];
logic signed [15:0] out_data_nxt;
logic out_valid_nxt;
logic out_done;
logic [4:0] filter_cnt, filter_cnt_nxt;
logic [6:0] image_cnt, image_cnt_nxt;
logic filter_size_reg, filter_size_nxt;
logic [2:0] filter_size_num;
logic [3:0] image_size_reg, image_size_nxt;
logic pad_mode_reg, pad_mode_nxt, act_mode_reg, act_mode_nxt;
typedef enum logic [1:0] {IDLE, FILT_IN, IMG_IN} STATE;
STATE cs, ns;
logic signed [15:0] mul_result [0:24];
logic signed [15:0] mul_result_nxt [0:24];
logic signed [16:0] add_result_1 [0:12];
logic signed [16:0] add_result_1_nxt [0:12];
logic signed [17:0] add_result_2 [0:6];
logic signed [17:0] add_result_2_nxt [0:6];
logic signed [18:0] add_result_3 [0:3];
logic signed [18:0] add_result_3_nxt [0:3];
logic signed [19:0] add_result_4 [0:1];
logic signed [19:0] add_result_4_nxt [0:1];
logic signed [20:0] add_result_5;
logic signed [20:0] add_result_5_nxt;

always_ff @( posedge clk, negedge rst_n ) begin : FSM_FF
	if ( !rst_n ) cs <= IDLE;
	else cs <= ns; 
end

always_comb begin : FSM_COMB
	ns = IDLE;
	case(cs)
		IDLE: begin
			if ( filter_valid ) ns = FILT_IN;
			else if ( image_valid ) ns = IMG_IN;
			else ns = IDLE;
		end
		FILT_IN: begin
			if ( filter_valid ) ns = FILT_IN;
			else ns = IDLE;
		end
		IMG_IN: begin
			if ( !out_done ) ns = IMG_IN;
			else ns = IDLE;
		end
	endcase
end


assign filter_size_nxt = (cs == IDLE && ns == FILT_IN) ? filter_size : filter_size_reg;
assign filter_size_num = (filter_size_reg)? 5 : 3;
assign image_size_nxt = (cs == IDLE && ns == FILT_IN) ? image_size : image_size_reg;
assign pad_mode_nxt = (cs == IDLE && ns == FILT_IN) ? pad_mode : pad_mode_reg;
assign act_mode_nxt = (cs == IDLE && ns == FILT_IN) ? act_mode : act_mode_reg;

always_comb begin : FILTER_COMB
	for(int i = 0; i < 25; i = i+1) begin
		filter_nxt[i] = filter[i];
	end
	if(~filter_size_reg) begin
		filter_nxt[0] = 0;
		filter_nxt[1] = 0;
		filter_nxt[2] = 0;
		filter_nxt[3] = 0;
		filter_nxt[4] = 0;
		filter_nxt[5] = 0;
		filter_nxt[9] = 0;
		filter_nxt[10] = 0;
		filter_nxt[14] = 0;
		filter_nxt[15] = 0;
		filter_nxt[19] = 0;
		filter_nxt[20] = 0;
		filter_nxt[21] = 0;
		filter_nxt[22] = 0;
		filter_nxt[23] = 0;
		filter_nxt[24] = 0;
	end
	if(filter_valid) begin
		filter_cnt_nxt = filter_cnt + 1;
		if(filter_size_nxt) begin
			filter_nxt[filter_cnt] = in_data;
		end else begin
			filter_nxt[5*(1+filter_cnt/3)+1+filter_cnt%3] = in_data;
		end
	end
	else begin
		filter_cnt_nxt = 0;
	end
end

always_comb begin : IMG_IN_COMB
	for(int i = 0; i < 12; i = i+1) begin
		for(int j = 0; j < 12; j = j+1) begin
			image_nxt[i][j] = (cs == IDLE)? 0 : image[i][j];
		end
	end
	if(image_valid) begin
		image_nxt[2+image_cnt/image_size_reg][2+image_cnt%image_size_reg] = in_data;
	end
	if(ns == IMG_IN) begin
		image_cnt_nxt = image_cnt + 1;
	end
	else begin
		image_cnt_nxt = 0;
	end
end

logic [15:0] conv_result;
logic conv_done;
logic [5:0] conv_idx;
logic [2:0] conv_row, conv_col;
logic [2:0] conv_row_nxt, conv_col_nxt;
logic [5:0] cal_start_num;
always_comb begin
	if(filter_size_num == 5) begin
		cal_start_num = 2*image_size_reg + 2 + 1;
	end else begin
		cal_start_num = image_size_reg + 1 + 1;
	end
end
always_comb begin
	if(filter_size_num == 5) begin
		conv_idx = image_cnt - 2*image_size_reg - 2;
	end else begin
		conv_idx = image_cnt - image_size_reg - 1;
	end
end
assign conv_row_nxt = conv_idx / image_size_reg;
assign conv_col_nxt = conv_idx % image_size_reg;

always_comb begin
	for(integer i = 0; i < 25; i = i+1) begin
		mul_result_nxt[i] = filter[i] * image[conv_row+i/5][conv_col+i%5];
	end
end

always_comb begin
	for(int i = 0; i < 12; i = i+1) begin
		add_result_1_nxt[i] = mul_result[2*i] + mul_result[2*i+1];
	end
	add_result_1_nxt[12] = mul_result[24];
	for(int i = 0; i < 6; i = i+1) begin
		add_result_2_nxt[i] = add_result_1[2*i] + add_result_1[2*i+1];
	end
	add_result_2_nxt[6] = add_result_1[12];
	for(int i = 0; i < 3; i = i+1) begin
		add_result_3_nxt[i] = add_result_2[2*i] + add_result_2[2*i+1];
	end
	add_result_3_nxt[3] = add_result_2[6];
	add_result_4_nxt[0] = add_result_3[0] + add_result_3[1];
	add_result_4_nxt[1] = add_result_3[2] + add_result_3[3];
	add_result_5_nxt = add_result_4[0] + add_result_4[1];
end



logic signed [15:0] leaky_out;
assign leaky_out = {1'b1, conv_result[14:0]/10};

always_comb begin : OUT_COMB
	out_done = 0;
	out_valid_nxt = 0;
	out_data_nxt = 0;
	conv_done = 0;
	//convolution
	if(add_result_5 > 0) begin
		if(add_result_5 > 32767) begin
			conv_result = 32767;
		end else begin
			conv_result = add_result_5;
		end
	end else if(act_mode_reg) begin
		if(add_result_5/10 < -32768) begin
			conv_result = -32768;
		end else begin
			conv_result = add_result_5/10;
		end
	end
	else begin
		conv_result = 0;
	end
	if(image_cnt > cal_start_num+5) begin
		conv_done = 1;
	end
	if(conv_done) begin
		out_valid_nxt = 1;
		out_data_nxt = conv_result;
	end
	if(image_cnt-cal_start_num == image_size_reg*image_size_reg+5) begin
		out_done = 1;
	end
end

always_ff @( posedge clk, negedge rst_n ) begin : REG_FF
	if ( !rst_n ) begin
		filter_size_reg <= 0;
		image_size_reg <= 0;
		pad_mode_reg <= 0;
		act_mode_reg <= 0;
		for(int i = 0; i < 25; i = i+1) begin
			filter[i] <= 0;
			mul_result[i] <= 0;
		end
		for(int i = 0; i < 12; i = i+1) begin
			for(int j = 0; j < 12; j = j+1) begin
				image[i][j] <= 0;
			end
		end
		filter_cnt <= 0;
		image_cnt <= 0;
		out_valid <= 0;
		out_data <= 0;
		for(int i = 0; i < 13; i = i+1) begin
			add_result_1[i] <= 0;
		end
		for(int i = 0; i < 7; i = i+1) begin
			add_result_2[i] <= 0;
		end
		for(int i = 0; i < 4; i = i+1) begin
			add_result_3[i] <= 0;
		end
		for(int i = 0; i < 2; i = i+1) begin
			add_result_4[i] <= 0;
		end
		add_result_5 <= 0;
		conv_row <= 0;
		conv_col <= 0;
	end
	else begin
		filter_size_reg <= filter_size_nxt;
		image_size_reg <= image_size_nxt;
		pad_mode_reg <= pad_mode_nxt;
		act_mode_reg <= act_mode_nxt;
		for(int i = 0; i < 25; i = i+1) begin
			filter[i] <= filter_nxt[i];
			mul_result[i] <= mul_result_nxt[i];
		end
		for(int i = 0; i < 12; i = i+1) begin
			for(int j = 0; j < 12; j = j+1) begin
				image[i][j] <= image_nxt[i][j];
			end
		end
		filter_cnt <= filter_cnt_nxt;
		image_cnt <= image_cnt_nxt;
		out_valid <= out_valid_nxt;
		out_data <= out_data_nxt;
		for(int i = 0; i < 13; i = i+1) begin
			add_result_1[i] <= add_result_1_nxt[i];
		end
		for(int i = 0; i < 7; i = i+1) begin
			add_result_2[i] <= add_result_2_nxt[i];
		end
		for(int i = 0; i < 4; i = i+1) begin
			add_result_3[i] <= add_result_3_nxt[i];
		end
		for(int i = 0; i < 2; i = i+1) begin
			add_result_4[i] <= add_result_4_nxt[i];
		end
		add_result_5 <= add_result_5_nxt;
		conv_row <= conv_row_nxt;
		conv_col <= conv_col_nxt;
	end
end

endmodule
