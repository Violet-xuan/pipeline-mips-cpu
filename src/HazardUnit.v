module HazardUnit(
	input        IDEX_MemRead,
	input  [4:0] IDEX_rt,
	input        EXMEM_MemRead,       // load in MEM stage (needed for registered-DMEM 2-cycle latency)
	input  [4:0] EXMEM_rt,            // load's dest reg while in MEM
	input        dmem_second_cycle,   // high when load data is already in the DMEM output register
	input  [4:0] IFID_rs,
	input  [4:0] IFID_rt,
	input        redirect_EX,         // branch/jr taken (EX)
	input        redirect_ID,         // j/jal (ID)
	output       stall,
	output       flush_IFID,
	output       flush_IDEX
);
	// Classic load-use from EX stage (load result not yet in any forwarding path)
	wire load_use_ex = IDEX_MemRead &&
		((IDEX_rt==IFID_rs)||(IDEX_rt==IFID_rt)) && (IDEX_rt!=5'd0);
	// Load-use from MEM stage — only relevant while the load's data has NOT yet
	// reached the DMEM output register (i.e. during the first MEM cycle).
	// Once dmem_second_cycle is true the data IS available on MemReadData and
	// will be captured into MEM/WB at the end of this cycle → WB forwarding works.
	wire load_use_mem = EXMEM_MemRead && !dmem_second_cycle &&
		((EXMEM_rt==IFID_rs)||(EXMEM_rt==IFID_rt)) && (EXMEM_rt!=5'd0);
	// EX redirect takes priority: when it fires, don't stall (just flush)
	assign stall      = (load_use_ex | load_use_mem) & ~redirect_EX;
	assign flush_IFID = redirect_EX | redirect_ID;
	assign flush_IDEX = redirect_EX;
endmodule
