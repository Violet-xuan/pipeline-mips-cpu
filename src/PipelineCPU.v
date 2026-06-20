module PipelineCPU(
	input  clk,
	input  reset,
	// external memory / peripheral bus (driven from MEM stage)
	output        MemRead,
	output        MemWrite,
	output [31:0] MemAddr,
	output [31:0] MemWriteData,
	input  [31:0] MemReadData
);
	// ---------- hazard/forward control (Phase3/4 wire in; here: no stall/forward/flush) ----------
	wire        stall      = 1'b0;
	wire        flush_IFID = 1'b0;
	wire        flush_IDEX = 1'b0;
	wire [1:0]  ForwardA;
	wire [1:0]  ForwardB;
	wire        redirect_EX;     // from EX branch/jr
	wire [31:0] target_EX;
	wire        redirect_ID;     // from ID j/jal
	wire [31:0] target_ID;

	// forwarding unit (operates on ID/EX rs/rt vs EX/MEM & MEM/WB dests)
	ForwardingUnit fwd(
		.EXMEM_RegWrite(m_RegWrite),.EXMEM_rd(m_waddr),
		.MEMWB_RegWrite(w_RegWrite),.MEMWB_rd(w_waddr),
		.IDEX_rs(x_rs),.IDEX_rt(x_rt),.ForwardA(ForwardA),.ForwardB(ForwardB));

	// ================= IF =================
	reg  [31:0] PC;
	wire [31:0] PC_plus4 = PC + 32'd4;
	wire [31:0] PC_next  = redirect_EX ? target_EX :
	                       redirect_ID ? target_ID : PC_plus4;
	always @(posedge clk or posedge reset)
		if (reset) PC <= 32'd0;
		else if (!stall) PC <= PC_next;

	wire [31:0] IF_inst;
	InstructionMemory imem(.Address(PC), .Instruction(IF_inst));

	// ---------- IF/ID ----------
	reg [31:0] IFID_pc4, IFID_inst;
	always @(posedge clk or posedge reset)
		if (reset) begin IFID_pc4<=0; IFID_inst<=0; end
		else if (!stall) begin
			if (flush_IFID) begin IFID_pc4<=0; IFID_inst<=32'h00000000; end
			else begin IFID_pc4<=PC_plus4; IFID_inst<=IF_inst; end
		end

	// ================= ID =================
	wire [5:0]  ID_op   = IFID_inst[31:26];
	wire [5:0]  ID_funct= IFID_inst[5:0];
	wire [4:0]  ID_rs   = IFID_inst[25:21];
	wire [4:0]  ID_rt   = IFID_inst[20:16];
	wire [4:0]  ID_rd   = IFID_inst[15:11];
	wire [4:0]  ID_shamt= IFID_inst[10:6];
	wire [15:0] ID_imm  = IFID_inst[15:0];

	wire c_RegWrite,c_MemRead,c_MemWrite,c_ALUSrc1,c_ALUSrc2,c_ExtOp,c_LuOp,c_isBranch,c_isJump,c_isJr;
	wire [1:0] c_MemtoReg,c_RegDst;
	wire [3:0] c_ALUOp;
	wire [2:0] c_branchType;
	Control ctrl(.OpCode(ID_op),.Funct(ID_funct),.Rt(ID_rt),
		.RegWrite(c_RegWrite),.MemRead(c_MemRead),.MemWrite(c_MemWrite),
		.MemtoReg(c_MemtoReg),.RegDst(c_RegDst),.ALUSrc1(c_ALUSrc1),.ALUSrc2(c_ALUSrc2),
		.ExtOp(c_ExtOp),.LuOp(c_LuOp),.ALUOp(c_ALUOp),.isBranch(c_isBranch),
		.branchType(c_branchType),.isJump(c_isJump),.isJr(c_isJr));

	// write-back port (produced in WB, see below)
	wire        wb_RegWrite;
	wire [4:0]  wb_waddr;
	wire [31:0] wb_wdata;

	wire [31:0] ID_rdata1, ID_rdata2;
	RegisterFile rf(.reset(reset),.clk(clk),.RegWrite(wb_RegWrite),
		.Read_register1(ID_rs),.Read_register2(ID_rt),.Write_register(wb_waddr),
		.Write_data(wb_wdata),.Read_data1(ID_rdata1),.Read_data2(ID_rdata2));

	wire [31:0] ID_ext = {c_ExtOp?{16{ID_imm[15]}}:16'h0, ID_imm};
	wire [31:0] ID_imm32 = c_LuOp ? {ID_imm,16'h0} : ID_ext;

	// j/jal target (resolved in ID)
	wire [31:0] ID_jtarget = {IFID_pc4[31:28], IFID_inst[25:0], 2'b00};
	assign redirect_ID = c_isJump;
	assign target_ID   = ID_jtarget;

	// ---------- ID/EX ----------
	reg        x_RegWrite,x_MemRead,x_MemWrite,x_ALUSrc1,x_ALUSrc2,x_isBranch,x_isJr;
	reg [1:0]  x_MemtoReg,x_RegDst;
	reg [3:0]  x_ALUOp;
	reg [2:0]  x_branchType;
	reg [31:0] x_pc4,x_rdata1,x_rdata2,x_imm32;
	reg [4:0]  x_rs,x_rt,x_rd,x_shamt;
	reg [5:0]  x_funct;
	// bubble = load-use stall OR branch flush
	wire insert_bubble = stall | flush_IDEX;
	always @(posedge clk or posedge reset)
		if (reset) begin
			{x_RegWrite,x_MemRead,x_MemWrite,x_ALUSrc1,x_ALUSrc2,x_isBranch,x_isJr}<=0;
			{x_MemtoReg,x_RegDst,x_ALUOp,x_branchType}<=0;
			{x_pc4,x_rdata1,x_rdata2,x_imm32}<=0; {x_rs,x_rt,x_rd,x_shamt,x_funct}<=0;
		end else begin
			if (insert_bubble) begin
				x_RegWrite<=0; x_MemRead<=0; x_MemWrite<=0; x_isBranch<=0; x_isJr<=0;
				x_MemtoReg<=0; x_RegDst<=0; x_ALUOp<=0; x_branchType<=0;
				x_pc4<=0; x_rdata1<=0; x_rdata2<=0; x_imm32<=0; x_rs<=0; x_rt<=0; x_rd<=0; x_shamt<=0; x_funct<=0;
			end else begin
				x_RegWrite<=c_RegWrite; x_MemRead<=c_MemRead; x_MemWrite<=c_MemWrite;
				x_ALUSrc1<=c_ALUSrc1; x_ALUSrc2<=c_ALUSrc2; x_isBranch<=c_isBranch; x_isJr<=c_isJr;
				x_MemtoReg<=c_MemtoReg; x_RegDst<=c_RegDst; x_ALUOp<=c_ALUOp; x_branchType<=c_branchType;
				x_pc4<=IFID_pc4; x_rdata1<=ID_rdata1; x_rdata2<=ID_rdata2; x_imm32<=ID_imm32;
				x_rs<=ID_rs; x_rt<=ID_rt; x_rd<=ID_rd; x_shamt<=ID_shamt; x_funct<=ID_funct;
			end
		end

	// ================= EX =================
	// forwarded operands (Phase3 onward ForwardA/B may be nonzero)
	wire [31:0] ex_fwdA = (ForwardA==2'b10)? m_alu :
	                      (ForwardA==2'b01)? wb_wdata : x_rdata1;
	wire [31:0] ex_fwdB = (ForwardB==2'b10)? m_alu :
	                      (ForwardB==2'b01)? wb_wdata : x_rdata2;

	wire [31:0] alu_in1 = x_ALUSrc1 ? {27'd0, x_shamt} : ex_fwdA;
	wire [31:0] alu_in2 = x_ALUSrc2 ? x_imm32 : ex_fwdB;

	wire [4:0]  ALUCtl; wire Sign;
	ALUControl aluc(.ALUOp(x_ALUOp),.Funct(x_funct),.ALUCtl(ALUCtl),.Sign(Sign));
	wire [31:0] EX_alu; wire EX_zero;
	ALU alu(.in1(alu_in1),.in2(alu_in2),.ALUCtl(ALUCtl),.Sign(Sign),.out(EX_alu),.zero(EX_zero));

	// branch decision (uses forwarded rs/rt)
	wire signed [31:0] sA = ex_fwdA;
	reg branch_cond;
	always @(*) case (x_branchType)
		3'b000: branch_cond = (ex_fwdA==ex_fwdB);     // beq
		3'b001: branch_cond = (ex_fwdA!=ex_fwdB);     // bne
		3'b010: branch_cond = (sA<=0);                // blez
		3'b011: branch_cond = (sA>0);                 // bgtz
		3'b100: branch_cond = (sA<0);                 // bltz
		3'b101: branch_cond = (sA>=0);                // bgez
		default: branch_cond = 1'b0;
	endcase
	wire branch_taken = x_isBranch & branch_cond;
	wire [31:0] EX_btarget = x_pc4 + {x_imm32[29:0], 2'b00};
	assign redirect_EX = branch_taken | x_isJr;
	assign target_EX   = x_isJr ? ex_fwdA : EX_btarget;   // jr/jalr use forwarded rs

	wire [4:0] EX_waddr = (x_RegDst==2'b01)? x_rd : (x_RegDst==2'b10)? 5'd31 : x_rt;

	// ---------- EX/MEM ----------
	reg        m_RegWrite,m_MemRead,m_MemWrite; reg [1:0] m_MemtoReg;
	reg [31:0] m_alu,m_wdata,m_pc4; reg [4:0] m_waddr;
	always @(posedge clk or posedge reset)
		if (reset) begin
			{m_RegWrite,m_MemRead,m_MemWrite,m_MemtoReg}<=0;
			{m_alu,m_wdata,m_pc4}<=0; m_waddr<=0;
		end else begin
			m_RegWrite<=x_RegWrite; m_MemRead<=x_MemRead; m_MemWrite<=x_MemWrite; m_MemtoReg<=x_MemtoReg;
			m_alu<=EX_alu; m_wdata<=ex_fwdB; m_pc4<=x_pc4; m_waddr<=EX_waddr;
		end

	// ================= MEM =================
	assign MemRead = m_MemRead; assign MemWrite = m_MemWrite;
	assign MemAddr = m_alu;      assign MemWriteData = m_wdata;
	wire [31:0] MEM_rdata = MemReadData;

	// ---------- MEM/WB ----------
	reg        w_RegWrite; reg [1:0] w_MemtoReg;
	reg [31:0] w_alu,w_mem,w_pc4; reg [4:0] w_waddr;
	always @(posedge clk or posedge reset)
		if (reset) begin {w_RegWrite,w_MemtoReg}<=0; {w_alu,w_mem,w_pc4}<=0; w_waddr<=0; end
		else begin
			w_RegWrite<=m_RegWrite; w_MemtoReg<=m_MemtoReg;
			w_alu<=m_alu; w_mem<=MEM_rdata; w_pc4<=m_pc4; w_waddr<=m_waddr;
		end

	// ================= WB =================
	assign wb_wdata = (w_MemtoReg==2'b01)? w_mem : (w_MemtoReg==2'b10)? w_pc4 : w_alu;
	assign wb_waddr = w_waddr;
	assign wb_RegWrite = w_RegWrite;
endmodule
