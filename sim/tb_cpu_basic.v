`timescale 1ns/1ps
module tb_cpu_basic;
	reg clk=0, reset=1;
	wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk;
	integer errors=0;
	initial begin
		#12 reset=0;
		#300;  // run enough cycles
		if (dmem.RAM[0]!==32'd12) begin errors=errors+1; $display("FAIL: MEM[0]=%0d exp 12",dmem.RAM[0]); end
		if (cpu.rf.RF_data[1]!==32'd5)  begin errors=errors+1; $display("FAIL: $1=%0d exp 5",cpu.rf.RF_data[1]); end
		if (cpu.rf.RF_data[2]!==32'd7)  begin errors=errors+1; $display("FAIL: $2=%0d exp 7",cpu.rf.RF_data[2]); end
		if (cpu.rf.RF_data[3]!==32'd12) begin errors=errors+1; $display("FAIL: $3=%0d exp 12",cpu.rf.RF_data[3]); end
		if (errors==0) $display("PASS tb_cpu_basic");
		$finish;
	end
endmodule
