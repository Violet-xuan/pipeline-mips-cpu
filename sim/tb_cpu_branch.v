`timescale 1ns/1ps
module tb_cpu_branch;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #400;
		if(cpu.rf.RF_data[3]!==32'd111) begin errors=errors+1; $display("FAIL $3=%0d exp 111",cpu.rf.RF_data[3]); end
		if(cpu.rf.RF_data[4]!==32'd444) begin errors=errors+1; $display("FAIL $4=%0d exp 444 (jal/jr)",cpu.rf.RF_data[4]); end
		if(cpu.rf.RF_data[7]!==32'd0)   begin errors=errors+1; $display("FAIL $7=%0d exp 0 (flushed)",cpu.rf.RF_data[7]); end
		if(cpu.rf.RF_data[31]!==32'h0000001c) begin errors=errors+1; $display("FAIL $31=%h exp 1c",cpu.rf.RF_data[31]); end
		if(errors==0) $display("PASS tb_cpu_branch");
		$finish;
	end
endmodule
