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
	// ---- clock divider: cpu_clk = clk100 / 2 = 50 MHz ----
	// The async distributed-RAM IMEM/DMEM read paths + single-cycle DSP multiply
	// give a ~11.3 ns critical path (~88 MHz true Fmax), so 100 MHz can't close,
	// but a clean /2 (20 ns budget) leaves ~8 ns slack. cpu_clk is a named toggle
	// FF so the create_generated_clock in welog1.xdc can pin its Q for STA.
	reg cpu_clk_r = 1'b0;
	always @(posedge clk100) cpu_clk_r <= ~cpu_clk_r;
	wire cpu_clk = cpu_clk_r;

	wire        MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(cpu_clk),.reset(rst_btn),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	// cpu_clk = 50 MHz drives the UART baud divider (DIV = 50e6/9600 = 5208)
	MemBus #(.CLK_FREQ(50_000_000),.BAUD(9600)) bus(
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
