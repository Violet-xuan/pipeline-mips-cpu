module top(
	input         clk100,        // R4 100MHz
	input         rst_btn,       // KEY1 (B22) high when pressed
	// 7-seg (common cathode, segments/sels active high)
	output        seg_a,seg_b,seg_c,seg_d,seg_e,seg_f,seg_g,seg_dp,
	output        sel1,sel2,sel3,sel4,
	// UART
	output        uart_txd,
	input         uart_rxd
);
	// ---- MMCM: 100 MHz → 80 MHz ----
	// Fout = Fin * CLKFBOUT_MULT / (DIVCLK_DIVIDE * CLKOUT0_DIVIDE)
	//      = 100 * 8 / (1 * 10) = 80 MHz   (Fvco = 800 MHz, within 600-1200)
	wire cpu_clk, mmcm_locked, mmcm_fb;
	MMCME2_BASE #(
		.BANDWIDTH("OPTIMIZED"),
		.CLKIN1_PERIOD(10.0),           // 100 MHz
		.CLKFBOUT_MULT_F(8.0),          // Fvco = 100 * 8 = 800 MHz
		.DIVCLK_DIVIDE(1),
		.CLKOUT0_DIVIDE_F(10.0),        // 800 / 10 = 80 MHz
		.STARTUP_WAIT("FALSE")
	) mmcm (
		.CLKIN1(clk100), .CLKFBIN(mmcm_fb), .CLKFBOUT(mmcm_fb),
		.CLKOUT0(cpu_clk), .LOCKED(mmcm_locked),
		.RST(1'b0), .PWRDWN(1'b0)
	);

	// Reset: hold while MMCM locks (or button pressed)
	wire reset = rst_btn | ~mmcm_locked;

	wire        MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(cpu_clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	// cpu_clk = 80 MHz drives the UART baud divider (DIV = 80e6/9600 = 8333)
	MemBus #(.CLK_FREQ(80_000_000),.BAUD(9600)) bus(
		.clk(cpu_clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi),
		.uart_txd(uart_txd),.uart_rxd(uart_rxd));

	// digi[6:0]=g..a (digi[0]=a), digi[7]=dp, digi[11:8]=AN3..AN0
	assign {seg_g,seg_f,seg_e,seg_d,seg_c,seg_b,seg_a} = digi[6:0];
	assign seg_dp = digi[7];
	assign {sel1,sel2,sel3,sel4} = digi[11:8];
endmodule
