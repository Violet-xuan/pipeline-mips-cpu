`timescale 1ns/1ps
module tb_cpu_loaduse;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #200;
		if(cpu.rf.RF_data[1]!==32'd100) begin errors=errors+1; $display("FAIL $1=%0d exp 100",cpu.rf.RF_data[1]); end
		if(cpu.rf.RF_data[2]!==32'd200) begin errors=errors+1; $display("FAIL $2=%0d exp 200",cpu.rf.RF_data[2]); end
		if(dmem.RAM[1]!==32'd200) begin errors=errors+1; $display("FAIL MEM[1]=%0d exp 200",dmem.RAM[1]); end
		if(errors==0) $display("PASS tb_cpu_loaduse");
		$finish;
	end
endmodule
