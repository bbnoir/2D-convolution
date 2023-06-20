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
logic signed [7:0] image [0:36];
logic signed [7:0] image_nxt [0:36]; //0 not used
logic signed [15:0] out_data_nxt;
logic out_valid_in;
logic out_valid_buf [0:4];
logic out_done, out_start;
logic [3:0] row, row_nxt;
logic [3:0] col, col_nxt;
logic filter_size_reg, filter_size_nxt;
logic [3:0] image_size_reg, image_size_nxt;
logic pad_mode_reg, pad_mode_nxt, act_mode_reg, act_mode_nxt;
logic signed [15:0] mul_result [0:24];
logic signed [15:0] mul_result_nxt [0:24];
logic signed [17:0] add_mid [0:6];
logic signed [17:0] add_mid_nxt [0:6];
logic signed [20:0] add_result;
logic signed [20:0] add_result_nxt;

typedef enum logic [1:0] {IDLE, FILT_IN, IMG_IN, OUT} STATE;
STATE cs, ns;

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
			if ( !out_start ) ns = IMG_IN;
			else ns = OUT;
		end
		OUT: begin
			if( !out_done ) ns = OUT;
			else ns = IDLE;
		end
	endcase
end

always_comb begin : MODE_COMB
	if(cs == IDLE && ns == FILT_IN) begin
		filter_size_nxt =  filter_size;
		image_size_nxt =  image_size;
		pad_mode_nxt =  pad_mode;
		act_mode_nxt =  act_mode;
	end else begin
		filter_size_nxt =  filter_size_reg;
		image_size_nxt =  image_size_reg;
		pad_mode_nxt =  pad_mode_reg;
		act_mode_nxt =  act_mode_reg;
	end
end

always_comb begin : FILTER_SHIFT_COMB
	if(filter_valid) begin
		filter_nxt[0] = in_data;
		for(int i = 1; i < 25; i = i+1) begin
			filter_nxt[i] = filter[i-1];
		end
		if(!filter_size_reg) begin
			for(int i = 9; i < 25; i = i+1) begin
				filter_nxt[i] = 0;
			end
		end
	end else begin
		for(int i = 0; i < 25; i = i+1) begin
			filter_nxt[i] = filter[i];
		end
	end
end

always_comb begin : IMG_SHIFT_COMB
	for(int i = 0; i < 37; i = i+1) begin
		image_nxt[i] = 0;
	end
	if(ns == IMG_IN || ns == OUT) begin
		image_nxt[0] = in_data;
		for(int i = 1; i < 37; i = i+1) begin
			image_nxt[i] = image[i-1];
		end
	end
end

logic [2:0] row_start, col_start;
assign row_start = (filter_size_reg)? 2:1;
assign col_start = (filter_size_reg)? 1:0;

always_comb begin : CNT_COMB
	row_nxt = 0;
	col_nxt = 0;
	out_start = 0;
	out_done = 0;
	case(cs)
		IMG_IN: begin
			if(row == row_start && col == col_start) begin
				row_nxt = 0;
				col_nxt = 0;
				out_start = 1;
			end else if(col == image_size_reg-1) begin
				row_nxt = row+1;
				col_nxt = 0;
			end else begin
				row_nxt = row;
				col_nxt = col+1;
			end
		end
		OUT: begin
			if(col == image_size_reg-1 && row == image_size_reg-1) begin
				row_nxt = 0;
				col_nxt = 0;
				out_done = 1;
			end else if(col == image_size_reg-1) begin
				row_nxt = row+1;
				col_nxt = 0;
			end else begin
				row_nxt = row;
				col_nxt = col+1;
			end
		end
	endcase
end

logic [15:0] conv_result;
logic signed [7:0] mul_opr[0:24];
logic signed [7:0] mul_opr_nxt[0:24];

logic [4:0] n;
assign n = image_size_reg;


always_comb begin : MUL_OPR_COMB
	for(int i = 0; i < 25; i = i+1) begin
		mul_opr_nxt[i] = 0;
	end
	if(!filter_size_reg) begin
		mul_opr_nxt[4] = image[n+1];
		mul_opr_nxt[1] = (row==n-1)? (pad_mode_reg? image[n+1] : 0) : image[1];
		mul_opr_nxt[3] = (col==n-1)? (pad_mode_reg? image[n+1] : 0) : image[n];
		mul_opr_nxt[5] = (col==0)? (pad_mode_reg? image[n+1] : 0) : image[n+2];
		mul_opr_nxt[7] = (row==0)? (pad_mode_reg? image[n+1] : 0) : image[2*n+1];
		mul_opr_nxt[0] = (row==n-1 && col==n-1)? (pad_mode_reg? image[n+1] : 0) :
			(row==n-1)? (pad_mode_reg? image[n] : 0) : (col==n-1)? (pad_mode_reg? image[1] : 0) : image[0];
		mul_opr_nxt[2] = (row==n-1 && col==0)? (pad_mode_reg? image[n+1] : 0) :
			(row==n-1)? (pad_mode_reg? image[n+2] : 0) : (col==0)? (pad_mode_reg? image[1] : 0) : image[2];
		mul_opr_nxt[6] = (row==0 && col==n-1)? (pad_mode_reg? image[n+1] : 0) :
			(row==0)? (pad_mode_reg? image[n] : 0) : (col==n-1)? (pad_mode_reg? image[2*n+1] : 0) : image[2*n];
		mul_opr_nxt[8] = (row==0 && col==0)? (pad_mode_reg? image[n+1] : 0) :
			(row==0)? (pad_mode_reg? image[n+2] : 0) : (col==0)? (pad_mode_reg? image[2*n+1] : 0) : image[2*n+2];
	end else begin
		mul_opr_nxt[12] = image[2*n+2];
		mul_opr_nxt[7] = (row==n-1)? (pad_mode_reg? image[2*n+2] : 0) : image[n+2];
		mul_opr_nxt[11] = (col==n-1)? (pad_mode_reg? image[2*n+2] : 0) : image[2*n+1];
		mul_opr_nxt[13] = (col==0)? (pad_mode_reg? image[2*n+2] : 0) : image[2*n+3];
		mul_opr_nxt[17] = (row==0)? (pad_mode_reg? image[2*n+2] : 0) : image[3*n+2];
		mul_opr_nxt[6] = (row==n-1 && col==n-1)? (pad_mode_reg? image[2*n+2] : 0) :
			(row==n-1)? (pad_mode_reg? image[2*n+1] : 0) : (col==n-1)? (pad_mode_reg? image[n+2] : 0) : image[n+1];
		mul_opr_nxt[8] = (row==n-1 && col==0)? (pad_mode_reg? image[2*n+2] : 0) :
			(row==n-1)? (pad_mode_reg? image[2*n+3] : 0) : (col==0)? (pad_mode_reg? image[n+2] : 0) : image[n+3];
		mul_opr_nxt[16] = (row==0 && col==n-1)? (pad_mode_reg? image[2*n+2] : 0) :
			(row==0)? (pad_mode_reg? image[2*n+1] : 0) : (col==n-1)? (pad_mode_reg? image[3*n+2] : 0) : image[3*n+1];
		mul_opr_nxt[18] = (row==0 && col==0)? (pad_mode_reg? image[2*n+2] : 0) :
			(row==0)? (pad_mode_reg? image[2*n+3] : 0) : (col==0)? (pad_mode_reg? image[3*n+2] : 0) : image[3*n+3];
		mul_opr_nxt[2] = (row==n-1)? (pad_mode_reg? image[2*n+2] : 0) : (row==n-2)? (pad_mode_reg? image[n+2] : 0) : image[2];
		mul_opr_nxt[10] = (col==n-1)? (pad_mode_reg? image[2*n+2] : 0) : (col==n-2)? (pad_mode_reg? image[2*n+1] : 0) : image[2*n];
		mul_opr_nxt[14] = (col==0)? (pad_mode_reg? image[2*n+2] : 0) : (col==1)? (pad_mode_reg? image[2*n+3] : 0) : image[2*n+4];
		mul_opr_nxt[22] = (row==0)? (pad_mode_reg? image[2*n+2] : 0) : (row==1)? (pad_mode_reg? image[3*n+2] : 0) : image[4*n+2];

		mul_opr_nxt[1] = (col==n-1)? (pad_mode_reg? mul_opr_nxt[2] : 0) : (row==n-2)? (pad_mode_reg? image[n+1] : 0) :
			(row==n-1)? (pad_mode_reg? image[2*n+1] : 0) : image[1];
		mul_opr_nxt[3] = (col==0)? (pad_mode_reg? mul_opr_nxt[2] : 0) : (row==n-2)? (pad_mode_reg? image[n+3] : 0) :
			(row==n-1)? (pad_mode_reg? image[2*n+3] : 0) : image[3];
		mul_opr_nxt[5] = (row==n-1)? (pad_mode_reg? mul_opr_nxt[10] : 0) : (col==n-2)? (pad_mode_reg? image[n+1] : 0) :
			(col==n-1)? (pad_mode_reg? image[n+2] : 0) : image[n];
		mul_opr_nxt[15] = (row==0)? (pad_mode_reg? mul_opr_nxt[10] : 0) : (col==n-2)? (pad_mode_reg? image[3*n+1] : 0) :
			(col==n-1)? (pad_mode_reg? image[3*n+2] : 0) : image[3*n];
		mul_opr_nxt[21] = (col==n-1)? (pad_mode_reg? mul_opr_nxt[22] : 0) : (row==1)? (pad_mode_reg? image[3*n+1] : 0) :
			(row==0)? (pad_mode_reg? image[2*n+1] : 0) : image[4*n+1];
		mul_opr_nxt[23] = (col==0)? (pad_mode_reg? mul_opr_nxt[22] : 0) : (row==1)? (pad_mode_reg? image[3*n+3] : 0) :
			(row==0)? (pad_mode_reg? image[2*n+3] : 0) : image[4*n+3];
		mul_opr_nxt[9] = (row==n-1)? (pad_mode_reg? mul_opr_nxt[14] : 0) : (col==1)? (pad_mode_reg? image[n+3] : 0) :
			(col==0)? (pad_mode_reg? image[n+2] : 0) : image[n+4];
		mul_opr_nxt[19] = (row==0)? (pad_mode_reg? mul_opr_nxt[14] : 0) : (col==1)? (pad_mode_reg? image[3*n+3] : 0) :
			(col==0)? (pad_mode_reg? image[3*n+2] : 0) : image[3*n+4];

		mul_opr_nxt[0] = (col >= n-2)? (pad_mode_reg? mul_opr_nxt[1] : 0) :
			 (row >= n-2)? (pad_mode_reg? mul_opr_nxt[5] : 0) : image[0];
		mul_opr_nxt[4] = (col <= 1)? (pad_mode_reg? mul_opr_nxt[3] : 0) :
			 (row >= n-2)? (pad_mode_reg? mul_opr_nxt[9] : 0) : image[4];
		mul_opr_nxt[20] = (col >= n-2)? (pad_mode_reg? mul_opr_nxt[21] : 0) :
			 (row <= 1)? (pad_mode_reg? mul_opr_nxt[15] : 0) : image[4*n];
		mul_opr_nxt[24] = (col <= 1)? (pad_mode_reg? mul_opr_nxt[23] : 0) :
			 (row <= 1)? (pad_mode_reg? mul_opr_nxt[19] : 0) : image[4*n+4];
	end
end

always_comb begin : MUL_COMB
	for(integer i = 0; i < 25; i = i+1) begin
		mul_result_nxt[i] = filter[i] * mul_opr[i];
	end
end

always_comb begin : ADD_MID_COMB
	add_mid_nxt[0] = mul_result[0];
	for(int i = 1; i < 7; i = i+1) begin
		add_mid_nxt[i] = mul_result[4*i] + mul_result[4*i-1] + mul_result[4*i-2] + mul_result[4*i-3];
	end
end

always_comb begin : ADD_COMB
	add_result_nxt = add_mid[0];
	for(int i = 1; i < 7; i = i+1) begin
		add_result_nxt = add_result_nxt + add_mid[i];
	end
end

always_comb begin : RELU_COMB
	if(add_result > 0) begin
		if(add_result > 32767) begin
			conv_result = 32767;
		end else begin
			conv_result = add_result;
		end
	end else if(act_mode_reg) begin
		if(add_result/10 < -32768) begin
			conv_result = -32768;
		end else begin
			conv_result = add_result/10;
		end
	end
	else begin
		conv_result = 0;
	end
end

assign out_valid_in = (cs==OUT)? 1 : 0;
assign out_valid = out_valid_buf[4];
assign out_data_nxt = (out_valid_buf[3])? conv_result : 0;


always_ff @( posedge clk, negedge rst_n ) begin : REG_FF
	if ( !rst_n ) begin
		for(int i = 0; i < 5; i = i+1) begin
			out_valid_buf[i] <= 0;
		end
		out_data <= 0;
	end else begin
		out_valid_buf[0] <= out_valid_in;
		for(int i = 1; i < 5; i = i+1) begin
			out_valid_buf[i] <= out_valid_buf[i-1];
		end
		out_data <= out_data_nxt;
	end
end

always_ff @( posedge clk) begin : REG_FF2
		filter_size_reg <= filter_size_nxt;
		image_size_reg <= image_size_nxt;
		pad_mode_reg <= pad_mode_nxt;
		act_mode_reg <= act_mode_nxt;
		for(int i = 0; i < 25; i = i+1) begin
			filter[i] <= filter_nxt[i];
			mul_opr[i] <= mul_opr_nxt[i];
			mul_result[i] <= mul_result_nxt[i];
		end
		for(int i = 0; i < 37; i = i+1) begin
			image[i] <= image_nxt[i];
		end
		for(int i = 0; i < 7; i = i+1) begin
			add_mid[i] <= add_mid_nxt[i];
		end
		add_result <= add_result_nxt;
		row <= row_nxt;
		col <= col_nxt;
end

endmodule
