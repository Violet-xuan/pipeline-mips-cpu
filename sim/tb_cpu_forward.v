`timescale 1ns/1ps
module tb_cpu_forward;
	reg clk=0,reset=1; wire MemRead,MemWrite; wire [31:0] MemAddr,MemWriteData,MemReadData;
	PipelineCPU cpu(.clk(clk),.reset(reset),.MemRead(MemRead),.MemWrite(MemWrite),
		.MemAddr(MemAddr),.MemWriteData(MemWriteData),.MemReadData(MemReadData));
	DataMemory dmem(.reset(reset),.clk(clk),.MemRead(MemRead),.MemWrite(MemWrite),
		.Address(MemAddr),.Write_data(MemWriteData),.Read_data(MemReadData));
	always #5 clk=~clk; integer errors=0;
	initial begin
		#12 reset=0; #200;
		// expect: $1=5 $2=8 $3=13 $4=5
		if(cpu.rf.RF_data[2]!==32'd8)  begin errors=errors+1; $display("FAIL $2=%0d exp 8",cpu.rf.RF_data[2]); end
		if(cpu.rf.RF_data[3]!==32'd13) begin errors=errors+1; $display("FAIL $3=%0d exp 13",cpu.rf.RF_data[3]); end
		if(cpu.rf.RF_data[4]!==32'd5)  begin errors=errors+1; $display("FAIL $4=%0d exp 5",cpu.rf.RF_data[4]); end
		if(dmem.RAM[0]!==32'd5)        begin errors=errors+1; $display("FAIL MEM[0]=%0d exp 5",dmem.RAM[0]); end
		if(errors==0) $display("PASS tb_cpu_forward");
		$finish;
	end
endmodule
