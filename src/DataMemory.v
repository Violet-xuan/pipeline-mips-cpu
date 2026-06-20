module DataMemory(
	input  reset,
	input  clk,
	input  MemRead,
	input  MemWrite,
	input  [31:0] Address,
	input  [31:0] Write_data,
	output [31:0] Read_data
);
`ifndef DMEM_FILE
 `define DMEM_FILE "sim/data_zero.hex"
`endif
	reg [31:0] RAM [0:511];           // 2KB
	initial $readmemh(`DMEM_FILE, RAM);
	assign Read_data = MemRead ? RAM[Address[10:2]] : 32'd0;
	always @(posedge clk)
		if (MemWrite) RAM[Address[10:2]] <= Write_data;
endmodule
