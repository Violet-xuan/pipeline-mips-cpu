module Control(
	input  [5:0] OpCode,
	input  [5:0] Funct,
	input  [4:0] Rt,            // distinguishes bltz/bgez
	output reg RegWrite,
	output reg MemRead,
	output reg MemWrite,
	output reg [1:0] MemtoReg,
	output reg [1:0] RegDst,
	output reg ALUSrc1,
	output reg ALUSrc2,
	output reg ExtOp,
	output reg LuOp,
	output reg [3:0] ALUOp,
	output reg isBranch,
	output reg [2:0] branchType,
	output reg isJump,
	output reg isJr
);
	// opcodes
	localparam R=6'h00, MUL=6'h1c, ADDI=6'h08, ADDIU=6'h09, ANDI=6'h0c,
	           ORI=6'h0d, SLTI=6'h0a, SLTIU=6'h0b, LUI=6'h0f, LW=6'h23,
	           SW=6'h2b, BEQ=6'h04, BNE=6'h05, BLEZ=6'h06, BGTZ=6'h07,
	           BZ=6'h01, J=6'h02, JAL=6'h03;
	// R-type funct
	localparam F_SLL=6'h00,F_SRL=6'h02,F_SRA=6'h03,F_JR=6'h08,F_JALR=6'h09;

	always @(*) begin
		// defaults (nop-safe)
		RegWrite=0; MemRead=0; MemWrite=0; MemtoReg=2'b00; RegDst=2'b00;
		ALUSrc1=0; ALUSrc2=0; ExtOp=1; LuOp=0; ALUOp=4'b0000;
		isBranch=0; branchType=3'b000; isJump=0; isJr=0;
		case (OpCode)
		R: begin
			ALUOp=4'b0010;            // R-type, decode funct
			case (Funct)
			F_JR:   begin isJr=1; end
			F_JALR: begin isJr=1; RegWrite=1; RegDst=2'b01; MemtoReg=2'b10; end
			F_SLL,F_SRL,F_SRA: begin RegWrite=1; RegDst=2'b01; ALUSrc1=1; end
			default: begin RegWrite=1; RegDst=2'b01; end // add/sub/and/or/...
			endcase
		end
		MUL:   begin RegWrite=1; RegDst=2'b01; ALUOp=4'b0110; end
		ADDI:  begin RegWrite=1; ALUSrc2=1; ALUOp=4'b0000; end
		ADDIU: begin RegWrite=1; ALUSrc2=1; ALUOp=4'b0000; end
		ANDI:  begin RegWrite=1; ALUSrc2=1; ExtOp=0; ALUOp=4'b0100; end
		ORI:   begin RegWrite=1; ALUSrc2=1; ExtOp=0; ALUOp=4'b0011; end
		SLTI:  begin RegWrite=1; ALUSrc2=1; ALUOp=4'b1101; end // signed slt
		SLTIU: begin RegWrite=1; ALUSrc2=1; ALUOp=4'b0101; end // unsigned slt
		LUI:   begin RegWrite=1; ALUSrc2=1; LuOp=1; ALUOp=4'b0000; end
		LW:    begin RegWrite=1; MemRead=1; MemtoReg=2'b01; ALUSrc2=1; ALUOp=4'b0000; end
		SW:    begin MemWrite=1; ALUSrc2=1; ALUOp=4'b0000; end
		BEQ:   begin isBranch=1; branchType=3'b000; ALUOp=4'b0001; end
		BNE:   begin isBranch=1; branchType=3'b001; ALUOp=4'b0001; end
		BLEZ:  begin isBranch=1; branchType=3'b010; end
		BGTZ:  begin isBranch=1; branchType=3'b011; end
		BZ:    begin isBranch=1; branchType=(Rt==5'd0)?3'b100:3'b101; end // bltz/bgez
		J:     begin isJump=1; end
		JAL:   begin isJump=1; RegWrite=1; RegDst=2'b10; MemtoReg=2'b10; end
		default: ; // nop
		endcase
	end
endmodule
