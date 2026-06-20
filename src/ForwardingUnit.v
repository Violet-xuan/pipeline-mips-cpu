module ForwardingUnit(
	input        EXMEM_RegWrite,
	input  [4:0] EXMEM_rd,
	input        MEMWB_RegWrite,
	input  [4:0] MEMWB_rd,
	input  [4:0] IDEX_rs,
	input  [4:0] IDEX_rt,
	output [1:0] ForwardA,
	output [1:0] ForwardB
);
	assign ForwardA =
		(EXMEM_RegWrite && EXMEM_rd!=5'd0 && EXMEM_rd==IDEX_rs)? 2'b10 :
		(MEMWB_RegWrite && MEMWB_rd!=5'd0 && MEMWB_rd==IDEX_rs)? 2'b01 : 2'b00;
	assign ForwardB =
		(EXMEM_RegWrite && EXMEM_rd!=5'd0 && EXMEM_rd==IDEX_rt)? 2'b10 :
		(MEMWB_RegWrite && MEMWB_rd!=5'd0 && MEMWB_rd==IDEX_rt)? 2'b01 : 2'b00;
endmodule
