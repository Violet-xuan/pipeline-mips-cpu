module MemBus(
	input         clk,
	input         reset,
	input         MemRead,
	input         MemWrite,
	input  [31:0] Address,
	input  [31:0] WriteData,
	output [31:0] ReadData,
	output reg [11:0] digi
);
	wire is_periph = (Address[30]);            // 0x4xxxxxxx
	wire dmem_we = MemWrite & ~is_periph;
	wire dmem_re = MemRead  & ~is_periph;
	wire [31:0] dmem_rd;
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(dmem_re),.MemWrite(dmem_we),
		.Address(Address),.Write_data(WriteData),.Read_data(dmem_rd));

	always @(posedge clk or posedge reset)
		if (reset) digi <= 12'd0;
		else if (MemWrite & is_periph && Address==32'h40000010)
			digi <= WriteData[11:0];

	// peripheral read: 0x40000010 reads back digi; otherwise 0
	wire [31:0] periph_rd = (Address==32'h40000010)? {20'd0,digi} : 32'd0;
	assign ReadData = is_periph ? periph_rd : dmem_rd;
endmodule
