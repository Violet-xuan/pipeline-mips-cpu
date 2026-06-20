`timescale 1ns/1ps
module tb_hazard;
	reg idex_memread; reg [4:0] idex_rt, ifid_rs, ifid_rt;
	reg redirect_ex, redirect_id;
	wire stall, flush_ifid, flush_idex; integer errors=0;
	HazardUnit u(.IDEX_MemRead(idex_memread),.IDEX_rt(idex_rt),
		.IFID_rs(ifid_rs),.IFID_rt(ifid_rt),
		.redirect_EX(redirect_ex),.redirect_ID(redirect_id),
		.stall(stall),.flush_IFID(flush_ifid),.flush_IDEX(flush_idex));
	task chk(input s,fi,fx); begin
		if(stall!==s||flush_ifid!==fi||flush_idex!==fx) begin errors=errors+1;
			$display("FAIL s=%b fi=%b fx=%b exp %b %b %b",stall,flush_ifid,flush_idex,s,fi,fx); end end
	endtask
	initial begin
		// load-use: lw dest == following rs -> stall
		idex_memread=1; idex_rt=5'd5; ifid_rs=5'd5; ifid_rt=5'd0; redirect_ex=0; redirect_id=0; #1 chk(1,0,0);
		// unrelated: no stall
		idex_memread=1; idex_rt=5'd5; ifid_rs=5'd6; ifid_rt=5'd7; #1 chk(0,0,0);
		// EX redirect (branch/jr taken) -> flush IF/ID and ID/EX
		idex_memread=0; redirect_ex=1; redirect_id=0; #1 chk(0,1,1);
		// ID redirect (j/jal) -> flush IF/ID only
		redirect_ex=0; redirect_id=1; #1 chk(0,1,0);
		// EX redirect over load-use (don't swallow the redirect)
		idex_memread=1; idex_rt=5'd5; ifid_rs=5'd5; redirect_ex=1; redirect_id=0; #1 chk(0,1,1);
		if(errors==0) $display("PASS tb_hazard"); $finish;
	end
endmodule
