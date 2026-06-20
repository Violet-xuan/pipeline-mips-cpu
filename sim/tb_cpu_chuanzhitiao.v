`timescale 1ns/1ps
// 传纸条 full-program integration test.
// 3x3 example: m=n=3, grid {0 3 9 / 2 8 5 / 5 7 0}, expected answer 34 (0x22).
// Program stores result to scratch word 0x3FF8 (RAM index 4094) before the display loop.
module tb_cpu_chuanzhitiao;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	MemBus bus(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi),
		.uart_txd(),.uart_rxd(1'b1));
	always #5 clk=~clk;
	integer errors=0;

	// cycle counter + completion detection (C for CPI = C/N)
	integer cycles=0; integer done_cycle=-1;
	always @(posedge clk) if(!reset) begin
		cycles = cycles + 1;
		// scratch write at 0x3FF8 marks algorithm completion
		if (done_cycle<0 && MemWrite && MemAddr==32'h00003FF8) done_cycle = cycles;
	end

	initial begin
		#12 reset=0;
		#400000;  // run long enough for init + DFS to finish and store the result
		$display("completion cycle C = %0d (algorithm done; excludes display loop)", done_cycle);
		$display("scratch[0x3FF8] = %0d (0x%h)", bus.dmem.RAM[4094], bus.dmem.RAM[4094]);
		$display("digi = 0x%h (display loop active)", digi);
		if (bus.dmem.RAM[4094]!==32'd34) begin errors=errors+1;
			$display("FAIL: result=%0d exp 34", bus.dmem.RAM[4094]); end
		// display loop must have written a real pattern (one AN selected, segments lit)
		if (digi===12'd0) begin errors=errors+1;
			$display("FAIL: digi=0, display loop did not run"); end
		if (errors==0) $display("PASS tb_cpu_chuanzhitiao");
		$finish;
	end
endmodule
