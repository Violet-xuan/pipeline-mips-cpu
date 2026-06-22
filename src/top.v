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
	// ---- CPU runs directly on the buffered 100 MHz input clock ----
	// The CPU logic critical path is short (~6.6 ns), so we drop the fabric
	// clock divider and clock the CPU at the full 100 MHz sys_clk (constrained
	// at 10 ns in welog1.xdc); timing closure is checked by the build report.
	wire cpu_clk = clk100;

	wire        MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	// cpu_clk = 100 MHz drives the UART baud divider (DIV = 100e6/9600 = 10416)
	MemBus #(.CLK_FREQ(100_000_000),.BAUD(9600)) bus(
		.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi),
		.uart_txd(uart_txd),.uart_rxd(uart_rxd));

	// digi[6:0]=g..a (digi[0]=a), digi[7]=dp, digi[11:8]=AN3..AN0
	// Board's leftmost physical digit is sel1, so MSB nibble (AN3=digi[11])
	// must drive sel1 to read MSB..LSB left-to-right (e.g. 0x0022 -> "0022").
	assign {seg_g,seg_f,seg_e,seg_d,seg_c,seg_b,seg_a} = digi[6:0];
	assign seg_dp = digi[7];
	assign {sel1,sel2,sel3,sel4} = digi[11:8];
endmodule
