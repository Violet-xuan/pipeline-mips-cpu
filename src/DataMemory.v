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
	reg [31:0] RAM [0:4095];          // 16KB (enlarged from 2KB so the DFS memo table fits realistic grids)
	initial $readmemh(`DMEM_FILE, RAM);
	assign Read_data = MemRead ? RAM[Address[13:2]] : 32'd0;
	always @(posedge clk)
		if (MemWrite) RAM[Address[13:2]] <= Write_data;
endmodule
