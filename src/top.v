module top(
	input         clk100,        // R4 100MHz
	input         rst_btn,       // KEY1 (B22) high when pressed
	// 7-seg (common cathode, segments/sels active high)
	output        seg_a,seg_b,seg_c,seg_d,seg_e,seg_f,seg_g,seg_dp,
	output        sel1,sel2,sel3,sel4,
	// UART (interface only; wired in Phase 8)
	output        uart_txd,
	input         uart_rxd
);
	// ---- clock divider (example: 100MHz/4 = 25MHz; conservative, tune by timing report) ----
	reg [1:0] divcnt = 2'd0;
	always @(posedge clk100) divcnt <= divcnt + 2'd1;
	wire cpu_clk = divcnt[1];

	wire        MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	MemBus bus(.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi));

	// digi[6:0]=g..a (digi[0]=a), digi[7]=dp, digi[11:8]=AN3..AN0
	assign {seg_g,seg_f,seg_e,seg_d,seg_c,seg_b,seg_a} = digi[6:0];
	assign seg_dp = digi[7];
	assign {sel4,sel3,sel2,sel1} = digi[11:8];
	assign uart_txd = 1'b1;   // placeholder (replaced in Phase 8)
endmodule
