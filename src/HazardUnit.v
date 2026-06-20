module HazardUnit(
	input        IDEX_MemRead,
	input  [4:0] IDEX_rt,
	input  [4:0] IFID_rs,
	input  [4:0] IFID_rt,
	input        redirect_EX,   // branch/jr taken (EX)
	input        redirect_ID,   // j/jal (ID)
	output       stall,
	output       flush_IFID,
	output       flush_IDEX
);
	wire load_use = IDEX_MemRead &&
		((IDEX_rt==IFID_rs)||(IDEX_rt==IFID_rt)) && (IDEX_rt!=5'd0);
	// EX redirect takes priority: when it fires, don't stall (just flush)
	assign stall      = load_use & ~redirect_EX;
	assign flush_IFID = redirect_EX | redirect_ID;
	assign flush_IDEX = redirect_EX;
endmodule
