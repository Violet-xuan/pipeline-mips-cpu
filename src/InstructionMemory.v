module InstructionMemory(
	input         reset,
	input         clk,
	input         hold,        // freeze output during pipeline stalls/holds
	input  [31:0] Address,
	output [31:0] Instruction
);
`ifndef IMEM_FILE
 `define IMEM_FILE "sim/prog_basic.hex"
`endif
	reg [31:0] rom [0:1023];          // 1024-instruction space
	initial $readmemh(`IMEM_FILE, rom);
	// Registered read — removes async LUTRAM read from critical path.
	// 'hold' freezes the output register when the pipeline is stalled
	// so that the instruction waiting to enter IF/ID is not overwritten
	// by garbage from the stalled PC.
	reg [31:0] Instruction;
	always @(posedge clk)
		if (reset) Instruction <= 32'h00000000;
		else if (!hold) Instruction <= rom[Address[11:2]];
endmodule
