`timescale 1ns/1ps
module tb_cpu_mmio;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	wire [11:0] digi;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	MemBus bus(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.WriteData(MemWriteData),.ReadData(MemReadData),.digi(digi));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #200;
		if(digi!==12'h15b) begin errors=errors+1; $display("FAIL digi=%h exp 15b",digi); end
		if(errors==0) $display("PASS tb_cpu_mmio");
		$finish;
	end
endmodule
