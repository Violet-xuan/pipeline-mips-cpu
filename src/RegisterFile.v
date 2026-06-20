module RegisterFile(
	input  reset,
	input  clk,
	input  RegWrite,
	input  [4:0]  Read_register1,
	input  [4:0]  Read_register2,
	input  [4:0]  Write_register,
	input  [31:0] Write_data,
	output [31:0] Read_data1,
	output [31:0] Read_data2
);
	reg [31:0] RF_data[31:1];

	assign Read_data1 = (Read_register1 == 5'd0)? 32'd0 : RF_data[Read_register1];
	assign Read_data2 = (Read_register2 == 5'd0)? 32'd0 : RF_data[Read_register2];

	integer i;
	// write on negedge so WB result is visible to ID read in the same cycle
	always @(negedge clk or posedge reset)
		if (reset)
			for (i = 1; i < 32; i = i + 1) RF_data[i] <= 32'd0;
		else if (RegWrite && (Write_register != 5'd0))
			RF_data[Write_register] <= Write_data;
endmodule
