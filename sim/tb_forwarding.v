`timescale 1ns/1ps
module tb_forwarding;
	reg exmem_rw, memwb_rw; reg [4:0] exmem_rd, memwb_rd, idex_rs, idex_rt;
	wire [1:0] fa, fb; integer errors=0;
	ForwardingUnit u(.EXMEM_RegWrite(exmem_rw),.EXMEM_rd(exmem_rd),
		.MEMWB_RegWrite(memwb_rw),.MEMWB_rd(memwb_rd),
		.IDEX_rs(idex_rs),.IDEX_rt(idex_rt),.ForwardA(fa),.ForwardB(fb));
	task chk(input [1:0] ga,gb); begin
		if(fa!==ga||fb!==gb) begin errors=errors+1;
			$display("FAIL fa=%b fb=%b exp %b %b",fa,fb,ga,gb); end end
	endtask
	initial begin
		// EX/MEM forward priority
		exmem_rw=1; exmem_rd=5'd3; memwb_rw=0; memwb_rd=0; idex_rs=5'd3; idex_rt=5'd9; #1 chk(2'b10,2'b00);
		// MEM/WB forward
		exmem_rw=0; exmem_rd=0; memwb_rw=1; memwb_rd=5'd9; idex_rs=5'd2; idex_rt=5'd9; #1 chk(2'b00,2'b01);
		// $0 never forwarded
		exmem_rw=1; exmem_rd=5'd0; memwb_rw=0; idex_rs=5'd0; idex_rt=5'd0; #1 chk(2'b00,2'b00);
		// EX/MEM over MEM/WB on same register
		exmem_rw=1; exmem_rd=5'd5; memwb_rw=1; memwb_rd=5'd5; idex_rs=5'd5; idex_rt=5'd1; #1 chk(2'b10,2'b00);
		if(errors==0) $display("PASS tb_forwarding"); $finish;
	end
endmodule
