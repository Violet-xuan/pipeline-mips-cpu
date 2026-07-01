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
	reg [31:0] RAM [0:32767];         // 128KB — fits DFS memo for grids up to ~30×30
	initial $readmemh(`DMEM_FILE, RAM);
	// Registered read — removes async LUTRAM read from critical path.
	// Loads now see 1 extra cycle of latency in MEM (handled by the
	// dmem_stall mechanism in PipelineCPU.v).
	reg [31:0] Read_data;
	always @(posedge clk)
		Read_data <= MemRead ? RAM[Address[16:2]] : 32'd0;
	always @(posedge clk)
		if (MemWrite) RAM[Address[16:2]] <= Write_data;
endmodule
