module InstructionMemory(
	input  [31:0] Address,
	output [31:0] Instruction
);
`ifndef IMEM_FILE
 `define IMEM_FILE "sim/prog_basic.hex"
`endif
	reg [31:0] rom [0:1023];          // 1024-instruction space
	initial $readmemh(`IMEM_FILE, rom);
	assign Instruction = rom[Address[31:2]];
endmodule
